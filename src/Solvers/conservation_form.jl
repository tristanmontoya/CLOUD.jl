struct StrongConservationForm{MappingForm,TwoPointFlux} <: AbstractResidualForm{MappingForm,TwoPointFlux}
    mapping_form::MappingForm
    first_order_numerical_flux::AbstractFirstOrderNumericalFlux
    second_order_numerical_flux::AbstractSecondOrderNumericalFlux
    two_point_flux::TwoPointFlux
end

struct WeakConservationForm{MappingForm,TwoPointFlux} <: AbstractResidualForm{MappingForm,TwoPointFlux}
    mapping_form::MappingForm
    first_order_numerical_flux::AbstractFirstOrderNumericalFlux
    second_order_numerical_flux::AbstractSecondOrderNumericalFlux
    two_point_flux::TwoPointFlux
end 

function StrongConservationForm(
    first_order_numerical_flux::AbstractFirstOrderNumericalFlux)
    return StrongConservationForm(StandardMapping(), 
        first_order_numerical_flux, 
        NoSecondOrderFlux(), 
        NoTwoPointFlux())
end

function WeakConservationForm(
    first_order_numerical_flux::AbstractFirstOrderNumericalFlux)
    return WeakConservationForm(StandardMapping(),
    first_order_numerical_flux, 
    NoSecondOrderFlux(),
    NoTwoPointFlux())
end

"""
    Make operators for strong conservation form
"""
function make_operators(spatial_discretization::SpatialDiscretization{d}, 
    ::StrongConservationForm) where {d}

    @unpack N_el, M = spatial_discretization
    @unpack V, Vf, R, P, W, B = spatial_discretization.reference_approximation
    @unpack nrstJ = 
        spatial_discretization.reference_approximation.reference_element
    @unpack J_q, Λ_q, nJf = spatial_discretization.geometric_factors

    operators = Array{PhysicalOperators}(undef, N_el)
    for k in 1:N_el
        if d == 1
            VOL = (-V' * W * D[1] + Diagonal(nrstJ[1]) * R,)
        else
            if form.mapping_form isa SkewSymmetricMapping
                error("StrongConservationForm only implements standard conservative mapping")
            else
                VOL = Tuple(sum(-V' * W * D[m] * Diagonal(Λ_q[:,m,n,k]) + 
                        Diagonal(nrstJ[m]) * R * Diagonal(Λ_q[:,m,n,k]) 
                        for m in 1:d) for n in 1:d)
            end
        end
        FAC = -Vf' * B
        SRC = V' * W * Diagonal(J_q[:,k])
        operators[k] = PhysicalOperators(VOL, FAC, SRC, M[k], V, Vf,
            Tuple(nJf[m][:,k] for m in 1:d))
    end
    return operators
end

"""
    Make operators for weak conservation form
"""
function make_operators(spatial_discretization::SpatialDiscretization{d}, 
    form::WeakConservationForm) where {d}

    @unpack N_el, M, reference_approximation = spatial_discretization
    @unpack ADVw, V, Vf, R, P, W, B, D = reference_approximation
    @unpack nrstJ = reference_approximation.reference_element
    @unpack J_q, Λ_q, nJf = spatial_discretization.geometric_factors

    operators = Array{PhysicalOperators}(undef, N_el)
    for k in 1:N_el
        if d == 1
            VOL = (ADVw[1],)
        else
            if form.mapping_form isa SkewSymmetricMapping
                VOL = Tuple(
                        0.5*(sum(ADVw[m] * Diagonal(Λ_q[:,m,n,k]) -
                            V' * Diagonal(Λ_q[:,m,n,k]) * W * D[m] 
                            for m in 1:d) +
                            Vf' * B * Diagonal(nJf[n][:,k]) * R)
                        for n in 1:d)
            else
                VOL = Tuple(sum(ADVw[m] * Diagonal(Λ_q[:,m,n,k]) for m in 1:d)  
                    for n in 1:d)
            end
        end
        FAC = -Vf' * B
        SRC = V' * W * Diagonal(J_q[:,k])
        operators[k] = PhysicalOperators(VOL, FAC, SRC, M[k], V, Vf,
            Tuple(nJf[m][:,k] for m in 1:d))
    end
    return operators
end

"""
    Evaluate semi-discrete residual for a hyperbolic problem
"""
function rhs!(dudt::AbstractArray{Float64,3}, u::AbstractArray{Float64,3}, 
    solver::Solver{d, N_eq, <:AbstractResidualForm, Hyperbolic},
    t::Float64; print::Bool=false) where {d, N_eq}

    @timeit "rhs!" begin
        @unpack conservation_law, operators, x_q, connectivity, form, strategy = solver
        @unpack first_order_numerical_flux = form

        N_el = size(operators)[1]
        N_f = size(operators[1].Vf)[1]
        u_facet = Array{Float64}(undef, N_f, N_eq, N_el)

        # get all facet state values
        Threads.@threads for k in 1:N_el
            u_facet[:,:,k] = @timeit get_timer(string("thread_timer_", Threads.threadid())) "extrapolate solution" convert(
                Matrix, operators[k].Vf * u[:,:,k])
        end

        # evaluate all local residuals
        Threads.@threads for k in 1:N_el
            to = get_timer(string("thread_timer_", Threads.threadid()))

            @timeit to "gather external state" begin
                # gather external state to element
                u_out = Matrix{Float64}(undef, N_f, N_eq)
                @inbounds for e in 1:N_eq
                    u_out[:,e] = u_facet[:,e,:][connectivity[:,k]]
                end
            end
            
            # evaluate physical and numerical flux
            f = @timeit to "eval flux" physical_flux(
                conservation_law, Matrix(operators[k].V * u[:,:,k]))
            f_star = @timeit to "eval numerical flux" numerical_flux(
                conservation_law, first_order_numerical_flux,
                u_facet[:,:,k], u_out, operators[k].scaled_normal)
            
            # evaluate source term, if there is one
            s = @timeit to "eval source term" evaluate(
                    conservation_law.source_term, 
                    Tuple(x_q[m][:,k] for m in 1:d),t)

            # apply operators to obtain residual as
            # du/dt = M \ (VOL⋅f + FAC⋅f_star + SRC⋅s)
            dudt[:,:,k] = @timeit to "eval residual" apply_operators!(
                dudt[:,:,k], operators[k], f, f_star, strategy, s)
        end
    end
    return dudt
end


"""
    Evaluate semi-discrete residual for a mixed/parabolic problem
"""
function rhs!(dudt::AbstractArray{Float64,3}, u::AbstractArray{Float64,3}, 
    solver::Solver{d, N_eq, <:AbstractResidualForm, <:Union{Mixed,Parabolic}},
    t::Float64; print::Bool=false) where {d, N_eq}

    @timeit "rhs!" begin
        @unpack conservation_law, operators, x_q, connectivity, form, strategy = solver
        @unpack first_order_numerical_flux = form
         
        N_el = size(operators)[1]
        N_f, N_p = size(operators[1].Vf)
        u_facet = Array{Float64}(undef, N_f, N_eq, N_el)

        # auxiliary variable q = ∇u
        q = Array{Float64}(undef, N_p, d, N_eq, N_el ) 
        q_facet = Array{Float64}(undef, N_f, d, N_eq, N_el)

        # get all facet state values
        Threads.@threads for k in 1:N_el
            u_facet[:,:,k] = @timeit get_timer(string("thread_timer_", Threads.threadid())) "extrapolate solution" convert(
                Matrix, operators[k].Vf * u[:,:,k])
        end

        # evaluate auxiliary variable 
        Threads.@threads for k in 1:N_el
            to = get_timer(string("thread_timer_", Threads.threadid()))
            @timeit to "auxiliary variable" begin

                # gather external state to element
                @timeit to "gather external state" begin
                    u_out = Matrix{Float64}(undef, N_f, N_eq)
                    @inbounds for e in 1:N_eq
                        u_out[:,:,e] = u_facet[:,e,:][connectivity[:,k]]
                    end
                end
                
                # evaluate nodal solution
                u = @timeit to "eval solution" physical_flux(
                    conservation_law, Matrix(operators[k].V * u[:,:,k]))

                # d-vector of approximations to u nJf
                u_star = @timeit to "eval numerical flux" numerical_flux(
                    conservation_law, second_order_numerical_flux,
                    u_facet[:,:,k], u_out, operators[k].scaled_normal)
                
                # apply operators
                q[:,:,:,k] = @timeit to "eval aux variable" auxiliary_variable!(
                    q[:,:,:,k], operators[k], u, u_star, strategy)
            end
        end

        # evaluate all local residuals
        Threads.@threads for k in 1:N_el
            to = get_timer(string("thread_timer_", Threads.threadid()))

            # gather external state to element
            @timeit to "gather external state" begin
                u_out = Matrix{Float64}(undef, N_f, N_eq)
                @inbounds for e in 1:N_eq
                    u_out[:,e] = u_facet[:,e,:][connectivity[:,k]]
                end
                q_out = Matrix{Float64}(undef, N_f, d, N_eq)
                @inbounds for e in 1:N_eq, m in 1:d
                    q_out[:,:,m,e] = q_facet[:,m,e,:][connectivity[:,k]]
                end
            end
            
            # evaluate physical flux
            f = @timeit to "eval flux" physical_flux(
                conservation_law, Matrix(operators[k].V * u[:,:,k]), 
                Matrix(operators[k].V * q[:,:,:,k]))
            
            # evaluate inviscid numerical flux 
            f_star = @timeit to "eval inviscid numerical flux" numerical_flux(
                conservation_law, first_order_numerical_flux,  
                u_facet[:,:,k], u_out, operators[k].scaled_normal)
                
            # evaluate viscous numerical flux
            f_star = f_star + 
                @timeit to "eval viscous numerical flux" numerical_flux(
                    conservation_law, second_order_numerical_flux,
                    u_facet[:,:,k], u_out, q_facet[:,:,:, k], q_out,
                    operators[k].scaled_normal)
            
            # evaluate source term, if there is one
            s = @timeit to "eval source term" evaluate(
                conservation_law.source_term, Tuple(x_q[m][:,k] for m in 1:d),t)

            # apply operators
            dudt[:,:,k] = @timeit to "eval residual" apply_operators!(
                dudt[:,:,k], operators[k], f, f_star, strategy, s)
        end
    end
    return dudt
end