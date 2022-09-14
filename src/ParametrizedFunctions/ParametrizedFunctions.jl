module ParametrizedFunctions

    using UnPack
    
    export AbstractParametrizedFunction, SumOfFunctions, ConstantFunction, InitialDataSine, InitialDataGaussian, InitialDataGassner, BurgersSolution, SourceTermGassner, GaussianNoise, NoSourceTerm, evaluate
    
    abstract type AbstractParametrizedFunction{d} end

    struct SumOfFunctions{d} <: AbstractParametrizedFunction{d}
        f::AbstractParametrizedFunction{d}
        g::AbstractParametrizedFunction{d}
        N_eq::Int

        function SumOfFunctions(f::AbstractParametrizedFunction{d},
            g::AbstractParametrizedFunction{d}) where {d}
            return new{d}(f,g,f.N_eq)
        end
    end

    struct ConstantFunction{d} <: AbstractParametrizedFunction{d}
        c::Float64
        N_eq::Int

        function ConstantFunction{d}(c) where {d}
            return new{d}(c,1)
        end
    end

    struct InitialDataSine{d} <: AbstractParametrizedFunction{d}
        A::Float64  # amplitude
        k::NTuple{d,Float64}  # wave number in each direction
        N_eq::Int

        function InitialDataSine(A::Float64,
            k::NTuple{d,Float64}) where {d} 
            return new{d}(A,k,1)
        end
    end

    struct InitialDataGaussian{d} <: AbstractParametrizedFunction{d}
        A::Float64  # amplitude
        σ::Float64 # width
        x₀::NTuple{d,Float64}
        N_eq::Int 
        function InitialDataGaussian(A::Float64,σ::Float64,
            x₀::NTuple{d,Float64}) where {d}
            return new{d}(A,σ,x₀,1)
        end
    end

    struct InitialDataGassner <: AbstractParametrizedFunction{1} 
        k::Float64
        ϵ::Float64
        N_eq::Int

        function InitialDataGassner(k,ϵ)
            return new(k,ϵ,1)
        end
    end

    struct SourceTermGassner <: AbstractParametrizedFunction{1} 
        k::Float64
        ϵ::Float64
        N_eq::Int
       
        function SourceTermGassner(k,ϵ)
            return new(k,ϵ,1)
        end
    end
    struct GaussianNoise{d} <: AbstractParametrizedFunction{d}
        σ::Float64
        N_eq::Int
    end

    struct NoSourceTerm{d} <: AbstractParametrizedFunction{d} end

    function Base.:+(f::AbstractParametrizedFunction{d},
        g::AbstractParametrizedFunction{d}) where {d}
        return SumOfFunctions(f,g)
    end

    function InitialDataSine(A::Float64, k::Float64)
        return InitialDataSine(A,(k,))
    end

    function InitialDataGaussian(A::Float64, σ::Float64, x₀::Float64)
        return InitialDataGaussian(A,σ,(x₀,))
    end

    function evaluate(func::SumOfFunctions{d}, 
        x::NTuple{d,Float64},t::Float64=0.0) where {d}
        return evaluate(func.f,x,t) .+ evaluate(func.g,x,t)
    end

    function evaluate(f::ConstantFunction{d},
        x::NTuple{d,Float64},t::Float64=0.0) where {d}
        return fill(f.c, f.N_eq)
    end

    function evaluate(f::InitialDataSine{d}, 
        x::NTuple{d,Float64},t::Float64=0.0) where {d}
        return fill(f.A*prod(Tuple(sin(f.k[m]*x[m]) for m in 1:d)), f.N_eq)
    end

    function evaluate(f::InitialDataGaussian{d}, 
        x::NTuple{d,Float64},t::Float64=0.0) where {d}
        @unpack A, σ, x₀, N_eq = f
        r² = sum((x[m] - x₀[m]).^2 for m in 1:d)
        return fill(A*exp.(-r²/(2.0*σ^2)),N_eq)
    end

    function evaluate(f::InitialDataGassner, 
        x::NTuple{1,Float64},t::Float64=0.0)
        return [sin(f.k*x[1])+f.ϵ]
    end

    function evaluate(f::SourceTermGassner, 
        x::NTuple{1,Float64},t::Float64=0.0)
        return [f.k .* cos(f.k*(x[1]-t))*(-1.0 + f.ϵ + sin(f.k*(x[1]-t)))]
    end

    function evaluate(f::GaussianNoise{d},
        x::NTuple{d,Float64},t::Float64=0.0) where {d}
        return [f.σ*randn() for e in 1:f.N_eq]
    end

    function evaluate(f::AbstractParametrizedFunction{d},
        x::NTuple{d,Vector{Float64}}, t::Float64=0.0) where {d}
        N = length(x[1])
        u0 = Matrix{Float64}(undef, N, f.N_eq)
        for i in 1:N
            u0[i,:] = evaluate(f, Tuple(x[m][i] for m in 1:d),t)
        end
        return u0
    end

    function evaluate(f::AbstractParametrizedFunction{d},
        x::NTuple{d,Matrix{Float64}},t::Float64=0.0) where {d}
        N, N_el = size(x[1])
        u0 = Array{Float64}(undef, N, f.N_eq, N_el)
        for k in 1:N_el
            u0[:,:,k] = evaluate(f, Tuple(x[m][:,k] for m in 1:d),t)
        end
        return u0
    end

    function evaluate(::NoSourceTerm{d}, ::NTuple{d,Vector{Float64}}, ::Float64) where {d}
        return nothing
    end
end