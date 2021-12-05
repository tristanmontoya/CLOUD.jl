module InitialConditions

    using ..ConservationLaws: ConservationLaw
    using ..SpatialDiscretizations: SpatialDiscretization

    export AbstractInitialData, InitialDataSine, InitialDataHeaviside, initial_condition
    
    abstract type AbstractInitialData end

    struct InitialDataSine{d} <: AbstractInitialData
        A::Float64  # amplitude
        k::NTuple{d,Float64}  # wave number in each direction
    end

    function InitialDataSine(A::Float64, k::Float64)
        return InitialDataSine{1}(A,(k,))
    end

    function initial_condition(initial_data::InitialDataSine{d},
        conservation_law::ConservationLaw{d,N_eq}) where {d, N_eq}
        return x -> Tuple(initial_data.A*prod(Tuple(sin.(initial_data.k[m]*x[m])
            for m in 1:d)) 
            for e in 1:N_eq)
    end

    struct InitialDataHeaviside <: AbstractInitialData end

    function initial_condition(::InitialDataHeaviside,
        ::ConservationLaw{d,N_eq}) where {d, N_eq}
        return x -> Tuple(0.5 .* (sign.(x[1] .- 0.5) .+ 1) for e in 1:N_eq)
    end

end