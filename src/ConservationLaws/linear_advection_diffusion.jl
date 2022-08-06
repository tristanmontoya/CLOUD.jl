
struct LinearAdvectionEquation{d} <: AbstractConservationLaw{d,1,Hyperbolic}
    a::NTuple{d,Float64} 
    source_term::AbstractParametrizedFunction{d}
end

struct LinearAdvectionDiffusionEquation{d} <: AbstractConservationLaw{d,1,Mixed}
    a::NTuple{d,Float64}
    b::Float64
    source_term::AbstractParametrizedFunction{d}
end

struct DiffusionSolution{InitialData} <: AbstractParametrizedFunction{1}
    conservation_law::LinearAdvectionDiffusionEquation
    initial_data::InitialData
    N_eq::Int 
end

function LinearAdvectionEquation(a::NTuple{d,Float64}) where {d}
    return LinearAdvectionEquation{d}(a,NoSourceTerm{d}())
end

function LinearAdvectionEquation(a::Float64)
    return LinearAdvectionEquation{1}((a,),NoSourceTerm{1}())
end

function LinearAdvectionDiffusionEquation(a::NTuple{d,Float64}, 
    b::Float64) where {d}
    return LinearAdvectionDiffusionEquation{d}(a,b,NoSourceTerm{d}())
end

function LinearAdvectionDiffusionEquation(a::Float64, b::Float64)
    return LinearAdvectionDiffusionEquation{1}((a,),b,NoSourceTerm{1}())
end

function DiffusionSolution(conservation_law::LinearAdvectionDiffusionEquation, initial_data::AbstractParametrizedFunction)
    return DiffusionSolution(conservation_law,initial_data,1)
end

"""
    function physical_flux(conservation_law::LinearAdvectionEquation{d}, u::Matrix{Float64})

Evaluate the flux for 1D linear advection-diffusion equation 1D linear advection equation

F(U) = aU
"""
function physical_flux(conservation_law::LinearAdvectionEquation{d}, 
    u::Matrix{Float64}) where {d}
    # returns d-tuple of matrices of size N_q x N_eq
    return Tuple(conservation_law.a[m] * u for m in 1:d)
end

"""
    function physical_flux(conservation_law::LinearAdvectionDiffusionEquation{d}u::Matrix{Float64}, q::Tuple{d,Matrix{Float64}})

Evaluate the flux for 1D linear advection-diffusion equation

F(U,Q) = aU - bQ
"""
function physical_flux(conservation_law::LinearAdvectionDiffusionEquation{d},
    u::Matrix{Float64}, q::NTuple{d,Matrix{Float64}}) where {d}
    @unpack a, b = conservation_law
    # returns d-tuple of matrices of size N_q x N_eq
    return Tuple(a[m]*u - b*q[m] for m in 1:d)
end

struct LinearAdvectionNumericalFlux <: AbstractFirstOrderNumericalFlux
    λ::Float64
end

struct BR1 <: AbstractSecondOrderNumericalFlux end

"""
    numerical_flux(conservation_law::LinearAdvectionEquation{d},numerical_flux::LinearAdvectionNumericalFlux, u_in::Matrix{Float64}, u_out::Matrix{Float64}, n::NTuple{d, Vector{Float64}})

Evaluate the standard advective numerical flux

F*(U⁻, U⁺, n) = 1/2 a⋅n(U⁻ + U⁺) + λ/2 |a⋅n|(U⁺ - U⁻)
"""
function numerical_flux(conservation_law::Union{LinearAdvectionEquation{d},LinearAdvectionDiffusionEquation{d}},
    numerical_flux::LinearAdvectionNumericalFlux,
    u_in::Matrix{Float64}, u_out::Matrix{Float64}, 
    n::NTuple{d, Vector{Float64}}) where {d}

    # Note that if you give it scaled normal nJf, 
    # the flux will be appropriately scaled by Jacobian too 
    a_n = sum(conservation_law.a[m].*n[m] for m in 1:d)
    
    # returns vector of length N_f
    return 0.5*a_n.*(u_in + u_out) - 
        0.5*numerical_flux.λ*abs.(a_n).*(u_out - u_in)
end

"""
    function numerical_flux(::LinearAdvectionDiffusionEquation{d}, ::BR1,u_in::Matrix{Float64}, u_out::Matrix{Float64}, n::NTuple{d, Vector{Float64}}

Evaluate the interface normal solution for the (advection-)diffusion equation using the BR1 approach

U*(U⁻, U⁺, n) = 1/2 (U⁻ + U⁺)n
"""

function numerical_flux(::LinearAdvectionDiffusionEquation{d},
    ::BR1,u_in::Matrix{Float64}, u_out::Matrix{Float64}, 
    n::NTuple{d, Vector{Float64}}) where {d}

    # average both sides
    u_avg = 0.5*(u_in + u_out)

    # Note that if you give it scaled normal nJf, 
    # the flux will be appropriately scaled by Jacobian too
    # returns tuple of vectors of length N_f 
    return Tuple(u_avg.*n[m] for m in 1:d)
end

"""
    function numerical_flux(::LinearAdvectionDiffusionEquation{d}, ::BR1,u_in::Matrix{Float64}, u_out::Matrix{Float64}, n::NTuple{d, Vector{Float64}}

Evaluate the numerical flux for the (advection-)diffusion equation using the BR1 approach

F*(U⁻, U⁺, Q⁻, Q⁺, n) = 1/2 (F²``(U⁻, Q⁻) + F²(U⁺, Q⁺))⋅n
"""

function numerical_flux(conservation_law::LinearAdvectionDiffusionEquation{d},
    ::BR1, u_in::Matrix{Float64}, u_out::Matrix{Float64}, 
    q_in::NTuple{d,Matrix{Float64}}, q_out::NTuple{d,Matrix{Float64}}, 
    n::NTuple{d, Vector{Float64}}) where {d}

    @unpack b = conservation_law

    # average both sides
    q_avg = Tuple(0.5*(q_in[m] + q_out[m]) for m in 1:d)

    # Note that if you give it scaled normal nJf, 
    # the flux will be appropriately scaled by Jacobian too
    # returns vector of length N_f 
    return -1.0*sum(b*q_avg[m] .* n[m] for m in 1:d)
end

function evaluate(s::DiffusionSolution{InitialDataGaussian{d}}, 
    x::NTuple{d,Float64},t::Float64=0.0) where {d}
    @unpack A, k, x_0 = s.initial_data
    @unpack b = s.conservation_law
    # this seems to be right but maybe plug into equation to check
    r² = sum((x[m] - x_0[m]).^2 for m in 1:d)
    t_0 = k^2/(2.0*b)
    C = A*(t_0/(t+t_0))^(0.5*d)
    return [C*exp.(-r²/(4.0*b*(t_0 + t)))]
end
