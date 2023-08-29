@views @timeit "semi-disc. residual" function rhs_benchmark!(
    dudt::AbstractArray{Float64,3}, u::AbstractArray{Float64,3}, 
    solver::Solver{d,ResidualForm,FirstOrder, ConservationLaw,Operators,
    MassSolver,Parallelism,N_p,N_q,N_f,N_c,N_e}, t::Float64=0.0) where {d,
    ResidualForm<:StandardForm,ConservationLaw, Operators<:ReferenceOperators,
    MassSolver,Parallelism,N_p,N_q,N_f,N_c,N_e}

    @timeit "unpack" begin
        (; conservation_law, connectivity, form) = solver
        (; inviscid_numerical_flux) = form
        (; f_q, f_f, f_n, u_q, r_q, u_f, temp, CI) = solver.preallocated_arrays
        (; D, V, R, halfWΛ, halfN, BJf, n_f) = solver.operators
    end
    
    k = 1  #just one element
    
    @timeit "vandermonde" mul!(u_q[:,:,k], V, u[:,:,k])
    
    @timeit "extrap solution" mul!(u_f[:,k,:], R, u_q[:,:,k])

    @timeit "phys flux" physical_flux!(f_q[:,:,:,k],
        conservation_law, u_q[:,:,k])

    @timeit "num flux" numerical_flux!(f_f[:,:,k],
        conservation_law,
        inviscid_numerical_flux, u_f[:,k,:], 
        u_f[CI[connectivity[:,k]],:], n_f[k])

    @timeit "fill w zeros" fill!(r_q[:,:,k],0.0)

    @inbounds for n in 1:d
        @inbounds @timeit "volume operators" for m in 1:d
            mul!(temp[:,:,k],halfWΛ[m,n,k],f_q[:,:,n,k])
            mul!(u_q[:,:,k],D[m]',temp[:,:,k])
            r_q[:,:,k] .+= u_q[:,:,k] 
            mul!(u_q[:,:,k],D[m],f_q[:,:,n,k])
            lmul!(halfWΛ[m,n,k],u_q[:,:,k])
            r_q[:,:,k] .-= u_q[:,:,k] 
        end
        
        # difference facet flux
        @timeit "diff flux" begin
            mul!(f_n[:,:,k], R, f_q[:,:,n,k])
            lmul!(halfN[n,k], f_n[:,:,k])
            f_f[:,:,k] .-= f_n[:,:,k]
        end
    end

    # apply facet operators
    @timeit "facet operators" begin
        lmul!(BJf[k], f_f[:,:,k])
        mul!(u_q[:,:,k], R', f_f[:,:,k])
        r_q[:,:,k] .-= u_q[:,:,k]
    end

    # solve for time derivative
    @timeit "trans. VDM" mul!(dudt[:,:,k], V', r_q[:,:,k])
    @timeit "mass solve" mass_matrix_solve!(
        solver.mass_solver, k, dudt[:,:,k], u_q[:,:,k])
    return dudt
end

@views @timeit "semi-disc. residual" function rhs_benchmark!(
    dudt::AbstractArray{Float64,3}, u::AbstractArray{Float64,3}, 
    solver::Solver{d,ResidualForm,FirstOrder, ConservationLaw,Operators,
    MassSolver,Parallelism,N_p,N_q,N_f,N_c,N_e}, t::Float64=0.0) where {d,
    ResidualForm<:StandardForm,ConservationLaw, Operators<:PhysicalOperators,
    MassSolver,Parallelism,N_p,N_q,N_f,N_c,N_e}

    @timeit "unpack" begin
        (; conservation_law, operators, connectivity, form) = solver
        (; inviscid_numerical_flux) = form
        (; f_q, f_f, u_q, u_f, temp, CI) = solver.preallocated_arrays
    end
    
    k = 1  # just one element
    
    @timeit "vandermonde" mul!(u_q[:,:,k], operators.V[k], u[:,:,k])
    @timeit "extrap solution" mul!(u_f[:,k,:], operators.R[k], u_q[:,:,k])

    @timeit "phys flux" physical_flux!(f_q[:,:,:,k],
        conservation_law, u_q[:,:,k])

    @timeit "num flux" numerical_flux!(f_f[:,:,k],
        conservation_law, inviscid_numerical_flux, u_f[:,k,:], 
        u_f[CI[connectivity[:,k]],:], operators.n_f[k])
    
    @timeit "fill w zeros" fill!(view(dudt,:,:,k),0.0)
    
    @inbounds for m in 1:d
        @timeit "volume operators" begin
            mul!(view(temp,:,:,k),operators.VOL[k][m],f_q[:,:,m,k])
            dudt[:,:,k] .+= temp[:,:,k] 
        end
    end
    
    mul!(view(temp,:,:,k), operators.FAC[k], f_f[:,:,k])
    dudt[:,:,k] .+= temp[:,:,k]

    return dudt
end