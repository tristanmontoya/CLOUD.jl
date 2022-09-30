function Solver(conservation_law::AbstractConservationLaw,     
    spatial_discretization::SpatialDiscretization,
    form::AbstractResidualForm,
    strategy::ReferenceOperator)

    operators = make_operators(spatial_discretization, form)
    return Solver(conservation_law, 
        operators,
        spatial_discretization.mesh.xyzq,
        spatial_discretization.mesh.mapP, form, strategy)
end

function apply_operators!(residual::Matrix{Float64},
    operators::DiscretizationOperators{d},
    f::NTuple{d,Matrix{Float64}}, 
    f_fac::Matrix{Float64}, 
    ::ReferenceOperator,
    s::Union{Matrix{Float64},Nothing}) where {d}

    @unpack VOL, FAC, SRC, M = operators
    
    rhs = zero(residual) # only allocation

    @CLOUD_timeit "volume terms" begin
        @inbounds for m in 1:d
            rhs += mul!(residual, VOL[m], f[m])
        end
    end

    @CLOUD_timeit "facet terms" begin
        rhs += mul!(residual, FAC, f_fac)
    end

    if !isnothing(s)
        @CLOUD_timeit "source terms" begin
            rhs += mul!(residual, SRC, s)
        end
    end

    @CLOUD_timeit "mass matrix solve" begin
        residual = M \ rhs
    end
    
    return residual
end

function auxiliary_variable!(m::Int, 
    q::Matrix{Float64},
    operators::DiscretizationOperators{d},
    u::Matrix{Float64},
    u_fac::Matrix{Float64}, 
    ::ReferenceOperator) where {d}

    @unpack VOL, FAC, M = operators
    
    rhs = similar(q) # only allocation

    @CLOUD_timeit "volume terms" begin
        mul!(rhs, -VOL[m], u)
    end

    @CLOUD_timeit "facet terms" begin
        rhs += mul!(q, -FAC, u_fac)
    end
    
    @CLOUD_timeit "mass matrix solve" begin
        q = M \ rhs
    end

    return q
end