module ParametrizedFunctions

    export AbstractParametrizedFunction, InitialDataSine, InitialDataGassner, BurgersSolution, SourceTermGassner, evaluate
    
    abstract type AbstractParametrizedFunction{d} end

    struct InitialDataSine{d} <: AbstractParametrizedFunction{d}
        A::Float64  # amplitude
        k::NTuple{d,Float64}  # wave number in each direction
        N_eq::Int
    end

    struct InitialDataGassner <: AbstractParametrizedFunction{1} 
        N_eq::Int
    end

    struct BurgersSolution{InitialData,SourceTerm} <: AbstractParametrizedFunction{1}
        initial_data::InitialData
        source_term::SourceTerm
        N_eq::Int
    end

    struct SourceTermGassner <: AbstractParametrizedFunction{1} 
        N_eq::Int
    end

    function InitialDataSine(A::Float64, k::Float64; N_eq::Int=1)
        return InitialDataSine(A,(k,),N_eq)
    end

    function InitialDataSine(A::Float64, k::NTuple{d,Float64}; 
        N_eq::Int=1) where {d}
        return InitialDataSine(A,k,N_eq)
    end

    function InitialDataGassner()
        return InitialDataGassner(1)
    end

    function BurgersSolution(initial_data::AbstractParametrizedFunction{1},
        source_term::AbstractParametrizedFunction{1})
        return BurgersSolution(initial_data, source_term, 1)
    end

    function SourceTermGassner()
        return SourceTermGassner(1)
    end

    function evaluate(f::InitialDataSine{d}, 
        x::NTuple{d,Float64},t::Float64=0.0) where {d}
        return fill(f.A*prod(Tuple(sin(f.k[m]*x[m]) for m in 1:d)), f.N_eq)
    end

    function evaluate(::InitialDataGassner, 
        x::NTuple{1,Float64},t::Float64=0.0)
        return [sin(π*x[1])+0.01]
    end

    function evaluate(::SourceTermGassner, 
        x::NTuple{1,Float64},t::Float64=0.0)
        return [π.*cos(π*(x[1]-t))*(-0.99 + sin(π*(x[1]-t)))]
    end

    function evaluate(::BurgersSolution{InitialDataGassner,SourceTermGassner}, 
        x::NTuple{1,Float64},t::Float64=0.0)
        return [sin(π*(x[1]-t))+0.01]
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
end