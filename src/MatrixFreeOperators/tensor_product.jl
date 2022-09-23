struct TensorProductMap{T} <: LinearMaps.LinearMap{T}
    A::Operator1D{T}
    B::Operator1D{T}
    σᵢ::Matrix{Int}
    σₒ::Matrix{Int}
end

Base.size(C::TensorProductMap) = (size(C.σₒ,1)*size(C.σₒ,2), 
    size(C.σᵢ,1)*size(C.σᵢ,2))

function LinearAlgebra.mul!(y::AbstractVector, 
    C::TensorProductMap, x::AbstractVector)
    
    LinearMaps.check_dim_mul(y, C, x)
    @unpack A, B, σᵢ, σₒ = C

    return tensor_mul!(y,A,B,σᵢ,σₒ,x)
end

"""
Compute transpose using
(A ⊗ B)ᵀ = Aᵀ ⊗ Bᵀ 
"""
function LinearAlgebra.transpose(C::TensorProductMap)
    return TensorProductMap(transpose(C.A), transpose(C.B), C.σₒ, C.σᵢ)
end

"""
Multiply a vector of length N1*N2 by the M1*M2 x N1*N2 matrix

C[σₒ[α1,α2], σᵢ[β1,β2]] = A[α1,β1] B[α2,β2]

or C = A ⊗ B. The action of this matrix on a vector x is 

(Cx)[σₒ[α1,α2]] = ∑_{β1,β2} A[α1,β1] B[α2,β2] x[σᵢ[β1,β2]] 
                = ∑_{β1} A[α1,β1] (∑_{β2} B[α2,β2] x[σᵢ[β1,β2]]) 
                = ∑_{β1} A[α1,β1] Z[α2,β1] 
"""
function tensor_mul!(y::AbstractVector, 
    A::AbstractMatrix, B::AbstractMatrix,
    σᵢ::Matrix{Int}, σₒ::Matrix{Int},
    x::AbstractVector)

    (M1,M2) = size(σₒ)
    (N1,N2) = size(σᵢ)

    Z = zeros(Float64, M2, N1)
    for α2 in 1:M2, β1 in 1:N1
        @simd for β2 in 1:N2
            Z[α2,β1] += B[α2,β2]*x[σᵢ[β1,β2]]
        end
    end

    for α1 in 1:M1, α2 in 1:M2
        y[σₒ[α1,α2]] = 0.0
        @simd for β1 in 1:N1
            y[σₒ[α1,α2]] += A[α1,β1]*Z[α2,β1]
        end
    end

    return y
end

"""
Multiply a vector of length N1*N2 by the M1*M2 x N1*M2 matrix

C[σₒ[α1,α2], σᵢ[β1,β2]] = A[α1,β1] δ_{α2,β2}

or C = A ⊗ I_{M2}. The action of this matrix on a vector x is 

(Cx)[σₒ[α1,α2]] = ∑_{β1,β2} A[α1,β1] δ_{α2,β2} x[σᵢ[β1,β2]] 
                = ∑_{β1} A[α1,β1] x[σᵢ[β1,α2]] 
"""
function tensor_mul!(y::AbstractVector, 
    A::AbstractMatrix, ::UniformScaling,
    σᵢ::Matrix{Int}, σₒ::Matrix{Int},
    x::AbstractVector)

    (M1,M2) = size(σₒ)
    (N1,N2) = size(σᵢ)

    for α1 in 1:M1, α2 in 1:M2
        y[σₒ[α1,α2]] = 0.0
        @simd for β1 in 1:N1
            y[σₒ[α1,α2]] += A[α1,β1]*x[σᵢ[β1,α2]]
        end
    end
    return y
end

"""
Multiply a vector of length N1*N2 by the M1*M2 x M1*N2 matrix
C[σₒ[α1,α2], σᵢ[β1,β2]] = δ_{α1,β1} B[α2,β2]

or C = I_{M1} ⊗ B. The action of this matrix on a vector x is 

(Cx)[σₒ[α1,α2]] = ∑_{β1,β2} δ_{α1,β1} B[α2,β2] x[σᵢ[β1,β2]] 
                = ∑_{β2} B[α2,β2] x[σᵢ[α1,β2]]) 
"""
function tensor_mul!(y::AbstractVector, 
    ::UniformScaling, B::AbstractMatrix,
    σᵢ::Matrix{Int}, σₒ::Matrix{Int},
    x::AbstractVector)

    (M1,M2) = size(σₒ)
    (N1,N2) = size(σᵢ)

    for α1 in 1:M1, α2 in 1:M2
        y[σₒ[α1,α2]] = 0.0
        @simd for β2 in 1:N2
            y[σₒ[α1,α2]] += B[α2,β2]*x[σᵢ[α1,β2]]
        end
    end
    return y
end
