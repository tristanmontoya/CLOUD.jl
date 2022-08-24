abstract type AbstractDynamicalAnalysis{d} <: AbstractAnalysis end

abstract type AbstractKoopmanAlgorithm end

struct DynamicalAnalysisResults <: AbstractAnalysisResults
    σ::Vector{ComplexF64}
    λ::Vector{ComplexF64}
    Z::Matrix{ComplexF64}
    conjugate_pairs::Union{Vector{Int},Nothing}
    c::Union{Matrix{ComplexF64},Nothing}
    projection::Union{Matrix{ComplexF64},Nothing}
    E::Union{Matrix{Float64},Nothing}
end

struct LinearAnalysis{d} <: AbstractDynamicalAnalysis{d}
    results_path::String
    analysis_path::String
    r::Int
    tol::Float64
    N_p::Int
    N_eq::Int
    N_el::Int
    M::AbstractMatrix
    plotter::Plotter{d}
    L::LinearMap
    use_data::Bool
end

struct KoopmanAnalysis{d} <: AbstractDynamicalAnalysis{d}
    results_path::String
    analysis_path::String
    basis::Vector{<:Function}
    basis_derivatives::Vector{<:Function}
    r::Int
    svd_tol::Float64
    proj_tol::Float64
    N_p::Int
    N_eq::Int
    N_el::Int
    M::AbstractMatrix
    plotter::Plotter{d}
end

"""Tu et al. (2014) or Kutz et al. (2018)"""
struct StandardDMD <: AbstractKoopmanAlgorithm end

"""Williams et al. (2015)"""
struct ExtendedDMD <: AbstractKoopmanAlgorithm
    ϵ::Float64
end

"""Rosenfeld's algorithm (see youtube video)"""
struct KernelDMD <: AbstractKoopmanAlgorithm 
    k::Function
end

function LinearAnalysis(results_path::String,
    conservation_law::AbstractConservationLaw, 
    spatial_discretization::SpatialDiscretization, 
    L::Union{LinearMap{Float64},AbstractMatrix{Float64}};
    r=4, tol=1.0e-12, name="linear_analysis", 
    use_data=true)

    analysis_path = new_path(string(results_path, name, "/"))
    N_p, N_eq, N_el = get_dof(spatial_discretization, conservation_law)

    # define mass matrix for the state space as a Hilbert space 
    M = blockdiag((kron(Diagonal(ones(N_eq)),
        sparse(spatial_discretization.M[k])) for k in 1:N_el)...)
            
    return LinearAnalysis(results_path, analysis_path, 
        r, tol, N_p, N_eq, N_el, M, Plotter(spatial_discretization, analysis_path), L, use_data)
end

"""Linear observables"""
function KoopmanAnalysis(results_path::String, 
    conservation_law::AbstractConservationLaw,spatial_discretization::SpatialDiscretization; 
    r=4, svd_tol=1.0e-12, proj_tol=1.0e-12, 
    name="koopman_analysis")
    
    # create path and get discretization information
    analysis_path = new_path(string(results_path, name, "/"))

    N_p, N_eq, N_el = get_dof(spatial_discretization, conservation_law)

    # define mass matrix for the state space as a Hilbert space 
    M = blockdiag((kron(Diagonal(ones(N_eq)),
        sparse(spatial_discretization.M[k])) for k in 1:N_el)...)

    return KoopmanAnalysis(results_path, analysis_path, 
        [identity], [x->zeros(size(x))],
        r, svd_tol, proj_tol, N_p, N_eq, N_el, M, 
        Plotter(spatial_discretization, analysis_path))
end

"""Nonlinear observables"""
function KoopmanAnalysis(results_path::String, 
    conservation_law::AbstractConservationLaw,spatial_discretization::SpatialDiscretization,
    basis::Vector{<:Function}; 
    basis_derivatives::Vector{<:Function}=[x->ones(size(x))],
    r=4, svd_tol=1.0e-12, proj_tol=1.0e-12, 
    name="koopman")
    
    # create path and get discretization information
    analysis_path = new_path(string(results_path, name, "/"))

    N_p, N_eq, N_el = get_dof(spatial_discretization, conservation_law)
 
    M = Diagonal(ones(N_p*N_eq*N_el*length(basis)))

    return KoopmanAnalysis(results_path, analysis_path, basis, basis_derivatives, 
        r, svd_tol, proj_tol, N_p, N_eq, N_el, M, 
        Plotter(spatial_discretization, analysis_path))
end

"""Linear eigensolution analysis"""
function analyze(analysis::LinearAnalysis)

    @unpack M, L, r, tol, use_data, results_path = analysis
    eigenvalues, eigenvectors = eigs(L, nev=r, which=:SI)

    # normalize eigenvectors
    Z = eigenvectors/Diagonal([eigenvectors[:,i]'*M*eigenvectors[:,i] 
        for i in 1:r])

    if use_data
        #load snapshot data
        X, t_s = load_snapshots(results_path, load_time_steps(results_path))

        # project data onto eigenvectors to determine coeffients
        c = (Z'*M*Z) \ Z'*M*X

        # calculate energy in each mode
        E = real([dot(c[i,j]*Z[:,i], M * (c[i,j]*Z[:,i]))
            for i in 1:r, j in 1:size(c,2)])
        
        # sort modes by decreasing energy in initial data
        inds_no_cutoff = sortperm(-E[:,1])
        inds = inds_no_cutoff[E[inds_no_cutoff,1] .> tol]
        
        return DynamicalAnalysisResults(exp.(eigenvalues[inds]*t_s), 
            eigenvalues[inds], Z[:,inds],
            find_conjugate_pairs(eigenvalues[inds]), 
            c[inds,:], Z*c, E[inds,:]) 
    else 
        dt = 1.0
        return DynamicalAnalysisResults(exp.(dt.*values), values, Z,    
            find_conjugate_pairs(values), nothing, nothing, nothing)
    end

end

"""Approximate the Koopman operator"""
analyze(analysis::KoopmanAnalysis, range=nothing) = analyze(analysis, StandardDMD(), range)
function analyze(analysis::KoopmanAnalysis, 
    ::StandardDMD, range=nothing)

    @unpack basis, basis_derivatives, r, svd_tol, proj_tol, M, results_path = analysis

    # load time step and ensure rank is suitable
    time_steps = load_time_steps(results_path)
    if !isnothing(range)
        time_steps = time_steps[range[1]:range[2]]
    end
    if r >= length(time_steps)
        r = length(time_steps)-1
    end

    # set up data matrices
    U, t_s = load_snapshots(results_path, time_steps)
    observables = vcat([ψ.(U) for ψ ∈ basis]...)
    X = observables[:,1:end-1]
    Y = observables[:,2:end]

    eigenvectors, eigenvalues, r = dmd(X,Y,r,svd_tol)

    # normalize Koopman modes for the observable basis
    Z = eigenvectors/Diagonal([eigenvectors[:,i]'*M*eigenvectors[:,i]
        for i in 1:r])
    
    # project observable data onto Koopman modes
    c = (Z'*M*Z) \ Z'*M*observables
    # calculate energy in each mode 
    E = real([dot(c[i,j]*Z[:,i], M * (c[i,j]*Z[:,i]))
        for i in 1:r, j in 1:size(observables,2)])

    # sort modes by decreasing energy in initial data
    inds_no_cutoff = sortperm(-E[:,1])
    inds = inds_no_cutoff[E[inds_no_cutoff,1] .> proj_tol]

    return DynamicalAnalysisResults(eigenvalues[inds], 
        log.(Complex.(eigenvalues[inds]))./t_s, Z[:,inds], 
        find_conjugate_pairs(eigenvalues[inds]), c[inds,:],
        Z*c, E[inds,:])
end

function analyze(analysis::KoopmanAnalysis, 
    algorithm::ExtendedDMD, range=nothing)

    @unpack basis, basis_derivatives, r, N_p, N_eq, N_el, svd_tol, proj_tol, results_path = analysis

    # load time step and ensure rank is suitable
    time_steps = load_time_steps(results_path)
    if !isnothing(range)
        time_steps = time_steps[range[1]:range[2]]
    end
    if r >= length(time_steps)
        r = length(time_steps)-1
    end
    N_s = length(time_steps) - 1

    # set up data matrices
    U, t_s = load_snapshots(results_path, time_steps)
    observables = vcat([ψ.(U) for ψ ∈ basis]...)
    X = (observables[:,1:end-1])'
    Y = (observables[:,2:end])'

    # perform the extended DMD
    Ψ, σ, r = dmd(X,Y,algorithm,r,svd_tol)
    
    # Get Koopman modes by projecting observable onto eigenfunctions
    Z = transpose(pinv(Ψ'*Ψ) * Ψ' * X)
    c = transpose(Ψ)
    r = size(Ψ,2)

    # calculate energy in each mode 
    E = real.([dot(c[i,j]*Z[:,i], (c[i,j]*Z[:,i]))
        for i in 1:r, j in 1:N_s])

    # sort modes by decreasing energy in initial data
    inds_no_cutoff = sortperm(-E[:,1])
    inds = inds_no_cutoff[E[inds_no_cutoff,1] .> proj_tol]

    return DynamicalAnalysisResults(σ[inds], 
        log.(σ[inds])./t_s, Z[:,inds], 
        find_conjugate_pairs(σ[inds]), c[inds,:],
        Z*c, E[inds,:])
end

"""Approximate the Koopman generator (requires known dynamics)"""
analyze(analysis::KoopmanAnalysis, f::Function, range=nothing) = analyze(analysis, f, StandardDMD(), range)

function analyze(analysis::KoopmanAnalysis, f::Function, 
    ::StandardDMD, range=nothing)

    @unpack basis, basis_derivatives, r, svd_tol, proj_tol, M, results_path = analysis

    # load time step and ensure rank is suitable
    time_steps = load_time_steps(results_path)
    if !isnothing(range)
        time_steps = time_steps[range[1]:range[2]]
    end
    if r >= length(time_steps)
        r = length(time_steps)-1
    end

    # set up data matrices
    U, t_s = load_snapshots(results_path, time_steps)
    X = vcat([ψ.(U) for ψ ∈ basis]...)
    dUdt = hcat([f(U[:,i]) for i in 1:size(X,2)]...)
    Y = vcat([dψdu.(U) .* dUdt for dψdu ∈ basis_derivatives]...)

    # perform (reduced) DMD    
    eigenvectors, eigenvalues, r = dmd(X,Y,r,svd_tol)

    # normalize eigenvectors (although not orthogonal - this isn't POD)
    Z = eigenvectors/Diagonal([eigenvectors[:,i]'*M*eigenvectors[:,i] 
    for i in 1:r])

    # project onto eigenvectors with respect to the inner product of the scheme
    c = (Z'*M*Z) \ Z'*M*X

    # calculate energy
    E = real([dot(c[i,j]*Z[:,i], M * (c[i,j]*Z[:,i]))
    for i in 1:r, j in 1:size(X,2)])

    # sort modes by decreasing energy in initial data
    inds_no_cutoff = sortperm(-E[:,1])
    inds = inds_no_cutoff[E[inds_no_cutoff,1] .> proj_tol]

    return DynamicalAnalysisResults(exp.(eigenvalues[inds].*t_s), 
        eigenvalues[inds], Z[:,inds], find_conjugate_pairs(eigenvalues[inds]), 
        c[inds,:], Z*c, E[inds,:])
end

function forecast(results::DynamicalAnalysisResults, Δt::Float64; starting_step::Int=0)
    @unpack c, λ, Z = results
    n_modes = size(Z,2)
    if starting_step == 0
        c0 = c[:,end]
    else
        c0 = c[:,starting_step]
    end
    return sum(Z[:,j]*exp(λ[j]*Δt)*c0[j] for j in 1:n_modes)
end

function forecast(results::DynamicalAnalysisResults, Δt::Float64, c0::Vector{ComplexF64})
    @unpack λ, Z = results
    n_modes = size(Z,2)
    return sum(Z[:,j]*exp(λ[j]*Δt)*c0[j] for j in 1:n_modes)
end

function forecast(analysis::KoopmanAnalysis, Δt::Float64, 
    range::NTuple{2,Int64}, forecast_name::String="forecast"; window_size=nothing, algorithm::AbstractKoopmanAlgorithm=StandardDMD(), koopman_generator=false, new_projection=false)
    
    @unpack analysis_path, results_path, N_p, N_eq, N_el = analysis
    time_steps = load_time_steps(results_path)
    forecast_path = new_path(string(analysis_path, forecast_name, "/"),
        true,true)
    save_object(string(forecast_path, "time_steps.jld2"), time_steps)
    if koopman_generator
        solver = load_solver(results_path)
        f(u::Vector{Float64}) = vec(rhs!(similar(reshape(u,(N_p,N_eq,N_el))),
            reshape(u,(N_p,N_eq,N_el)),solver,0.0))  # assume time invariant
    end

    u = Array{Float64,3}[]
    t = Float64[]
    model = DynamicalAnalysisResults[]
    for i in (range[1]+1):range[2]
        if isnothing(window_size) || (i - range[1]) < window_size
            window_size_new = i-range[1]
        else
            window_size_new = window_size
        end
        if koopman_generator
            push!(model,analyze(analysis,algorithm,f,(i-window_size_new,i)))
        else
            push!(model,analyze(analysis, algorithm, (i-window_size_new,i)))
        end
        u0, t0 = load_solution(results_path, time_steps[i-1])
        if new_projection
            push!(u,reshape(real.(forecast(last(model), Δt, last(model).c[:,end]))[1:N_p*N_eq*N_el], (N_p,N_eq,N_el)))
        else
            c = project_onto_modes(analysis,last(model),vec(u0))
            push!(u,reshape(real.(forecast(last(model), Δt, c)[1:N_p*N_eq*N_el]), (N_p,N_eq,N_el)))
        end
        push!(t, t0 + Δt)
        save(string(forecast_path, "res_", time_steps[i], ".jld2"),
            Dict("u" => last(u), "t" => last(t)))
    end
    return forecast_path, model
end

#function linear_extrapolate()



function project_onto_modes(analysis::KoopmanAnalysis, results::DynamicalAnalysisResults, u0::Vector{Float64})
    @unpack M, basis = analysis
    @unpack Z = results
    return (Z'*M*Z) \ Z' *M* vcat([ψ.(u0) for ψ ∈ basis]...)
end


function monomial_basis(p::Int)
    return [u->u.^k for k in 1:p]
end

function monomial_derivatives(p::Int)
    return [u->k.*u.^(k-1) for k in 1:p]
end

function find_conjugate_pairs(σ::Vector{ComplexF64}; tol=1.0e-8)

    N = size(σ,1)
    conjugate_pairs = zeros(Int64,N)
    for i in 1:N
        if conjugate_pairs[i] == 0
            for j in (i+1):N
                if abs(σ[j] - conj(σ[i])) < tol
                    conjugate_pairs[i] = j
                    conjugate_pairs[j] = i
                    break
                end
            end
        end
    end
    return conjugate_pairs

end

find_conjugate_pairs(σ::Vector{Float64}; tol=1.0e-8) = nothing

function dmd(X::Matrix{Float64},Y::Matrix{Float64}, r::Int, svd_tol=1.0e-10)

    if r > 0
        # SVD (i.e. POD) of initial states
        U_full, S_full, V_full = svd(X)

        U = U_full[:,1:r][:,S_full[1:r] .> svd_tol]
        S = S_full[1:r][S_full[1:r] .> svd_tol]
        V = V_full[:,1:r][:,S_full[1:r] .> svd_tol]

        # eigendecomposition of reduced DMD matrix 
        # (projected onto singular vectors)
        F = eigen((U') * Y * V * inv(Diagonal(S)))

        # map eigenvectors back up into full space
        Z = Y*V*inv(Diagonal(S))*F.vectors
        Λ = F.values
        r = length(S)
    else
        A = Y*pinv(X)
        F = eigen(A)

        Z = F.vectors
        Λ = F.values
        r = size(F.vectors,2)
    end

    return Z, Λ, r
end

function dmd(X::AbstractMatrix{Float64},Y::AbstractMatrix{Float64}, algorithm::ExtendedDMD, r::Int, svd_tol=1.0e-10)

    if r > 0
        # SVD (i.e. POD) of initial states
        U_full, S_full, Z_full = svd(X)

        U = U_full[:,1:r][:,S_full[1:r] .> svd_tol]
        S = S_full[1:r][S_full[1:r] .> svd_tol]
        Z = Z_full[:,1:r][:,S_full[1:r] .> svd_tol]

        # eigendecomposition of reduced DMD matrix 
        # (projected onto singular vectors)
        F = eigen((inv(Diagonal(S))*U') * Y * X' * U * inv(Diagonal(S)))

        # map eigenvectors back up into full space
        V = Z*F.vectors
        σ = F.values
        r = length(S)
    else
        F = eigen(pinv(X'*X)*X'*Y)
        V = F.vectors
        σ = F.values
        r = size(F.vectors,2)
    end

    # calculate residuals
    G = X'*X
    A = X'*Y
    B = Y'*Y
    res = sqrt.(abs.([ 
        (V[:,i]' * (B - σ[i]*A' - conj(σ[i])*A + abs2(σ[i])*G) * V[:,i]) /
        (V[:,i]' * G * V[:,i])
            for i in 1:r]))

    return X*(V[:, res .< algorithm.ϵ]), σ[res .< algorithm.ϵ], r
end

function plot_analysis(analysis::AbstractDynamicalAnalysis,
    results::DynamicalAnalysisResults; e=1, i=1, modes = 0,
    scale=true, title="spectrum.pdf", xlims=nothing, ylims=nothing)
    l = @layout [a{0.5w} b; c]
    if scale
        coeffs=results.c[:,i]
    else
        coeffs=ones(length(results.c[:,i]))
    end

    if modes == 0
        modes = 1:length(results.λ)
        conjugate_pairs = results.conjugate_pairs
    elseif modes isa Int
        modes = [modes]
        conjugate_pairs=nothing
    else
        conjugate_pairs = find_conjugate_pairs(results.σ[modes])
    end

    if isnothing(xlims)
        xlims=(minimum(real.(results.λ[modes]))*1.05,
            maximum(real.(results.λ[modes]))*1.05)
    end

    if isnothing(ylims)
        ylims=(minimum(imag.(results.λ[modes]))*1.05,
            maximum(imag.(results.λ[modes]))*1.1)
    end

    p = plot(plot_spectrum(analysis,results.λ[modes], 
            label="\\tilde{\\lambda}", unit_circle=false, 
            xlims=xlims,
            ylims=ylims,
            title="continuous_time.pdf", xscale=-0.03, yscale=0.03), 
        plot_spectrum(analysis,results.σ[modes], 
            label="\\exp(\\tilde{\\lambda} t_s)",
            unit_circle=true, xlims=(-1.5,1.5), ylims=(-1.5,1.5),
            title="discrete_time.pdf"),
        plot_modes(analysis,results.Z[:,modes]::Matrix{ComplexF64}; e=e, 
            coeffs=coeffs[modes], conjugate_pairs=conjugate_pairs),
            layout=l, framestyle=:box)
    
    savefig(p, string(analysis.analysis_path, title))
    return p
end

function plot_spectrum(eigs::Vector{Vector{ComplexF64}}, plots_path::String; 
    ylabel="\\lambda", xlims=nothing, ylims=nothing, title="spectra.pdf", 
    labels=["Upwind", "Central"])
    p = plot(legendfontsize=10, xlabelfontsize=13, ylabelfontsize=13, xtickfontsize=10, ytickfontsize=10)
    max_real = @sprintf "%.2e" maximum(real.(eigs[1]))
    for i in 1:length(eigs)
        max_real = @sprintf "%.2e" maximum(real.(eigs[i]))
        sr = @sprintf "%.2f" maximum(abs.(eigs[i]))
        plot!(p, eigs[i], 
        xlabel= latexstring(string("\\mathrm{Re}\\,(", ylabel, ")")), 
        ylabel= latexstring(string("\\mathrm{Im}\\,(", ylabel, ")")), 
        legend=:topleft,
        label=string(labels[i]," (max Re(λ): ", max_real,")"),  
        markershape=:star, seriestype=:scatter,
        markersize=5,
        markerstrokewidth=0, 
        size=(400,400)
        )
    end
    savefig(p, string(plots_path, title))
    return p
end

function plot_spectrum(analysis::AbstractDynamicalAnalysis, 
    eigs::Vector{ComplexF64}; label="\\exp(\\tilde{\\lambda} t_s)",unit_circle=true, xlims=nothing, ylims=nothing,
    xscale=0.02, yscale=0.07, title="spectrum.pdf", numbering=true)

    if unit_circle
        t=collect(LinRange(0.0, 2.0*π,100))
        p = plot(cos.(t), sin.(t), aspect_ratio=:equal, 
            linecolor="black",xticks=-1.0:1.0:1.0, yticks=-1.0:1.0:1.0)
    else
        p = plot()
    end

    plot!(p, eigs, xlabel=latexstring(string("\\mathrm{Re}\\,(", label, ")")), 
        ylabel=latexstring(string("\\mathrm{Im}\\,(", label, ")")), 
        xlims=xlims, ylims=ylims,legend=false,
        seriestype=:scatter)

    if !unit_circle && numbering
        annotate!(real(eigs) .+ xscale*(xlims[2]-xlims[1]), 
            imag(eigs)+sign.(imag(eigs) .+ 1.0e-15)*yscale*(ylims[2]-ylims[1]),
            text.(1:length(eigs), :right, 8))
    end

    savefig(p, string(analysis.analysis_path, title))

    return p
end

function plot_modes(analysis::AbstractDynamicalAnalysis, 
    Z::Matrix{ComplexF64}; e=1, 
    coeffs=nothing, projection=nothing,
    conjugate_pairs=nothing)
    #println("conj pairs: ", conjugate_pairs)
    @unpack N_p, N_eq, N_el, plotter = analysis
    @unpack x_plot, V_plot = plotter

    n_modes = size(Z,2)
    p = plot()

    if isnothing(coeffs)
        coeffs = ones(n_modes)
    end

    if isnothing(conjugate_pairs)
        conjugate_pairs = zeros(Int64,n_modes)
    end

    skip = fill(false, n_modes)
    for j in 1:n_modes

        if skip[j]
            continue
        end

        sol = reshape(Z[:,j][1:N_p*N_eq*N_el],(N_p, N_eq, N_el))
        u = convert(Matrix, V_plot * real(coeffs[j]*sol[:,e,:]))

        if conjugate_pairs[j] == 0
            linelabel = string(j)
            scale_factor = 1.0
        else
            linelabel = string(j, ",", conjugate_pairs[j])
            scale_factor = 2.0
            skip[conjugate_pairs[j]] = true
        end

        plot!(p,vec(vcat(x_plot[1],fill(NaN,1,N_el))), 
            vec(vcat(scale_factor*u,fill(NaN,1,N_el))), 
            label=latexstring(linelabel),
            ylabel="Koopman Modes",
            legendfontsize=6)
    end

    if !isnothing(projection)
        sol = reshape(projection,(N_p, N_eq, N_el))
        linelabel = string("\\mathrm{Projection}")
        u = convert(Matrix, V_plot * real(sol[:,e,:]))
        plot!(p,vec(vcat(x_plot[1],fill(NaN,1,N_el))), 
            vec(vcat(u,fill(NaN,1,N_el))), 
            label=latexstring(linelabel), xlabel=latexstring("x"), 
            linestyle=:dash, linecolor="black")
    end

    savefig(p, string(analysis.analysis_path, "modes.pdf")) 
    return p
end