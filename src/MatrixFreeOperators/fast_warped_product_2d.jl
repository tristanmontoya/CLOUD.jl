"""
FastWarped tensor-product operator (e.g. for Dubiner-type bases)
"""    

struct FastWarpedTensorProductMap2D{A_type,B_type,σᵢ_type,σₒ_type,N2_type} <: LinearMaps.LinearMap{Float64}
    A::A_type
    B::B_type
    σᵢ::σᵢ_type 
    σₒ::σₒ_type
    N2::N2_type

    function FastWarpedTensorProductMap2D(
        A::A_type,B::B_type, σᵢ::σᵢ_type,σₒ::σₒ_type) where {A_type,B_type,σᵢ_type,σₒ_type}
        N1 = size(A,2)
        return new{A_type,B_type,σᵢ_type,σₒ_type,SVector{N1,Int}}(A,B,σᵢ,σₒ,
            SVector{N1,Int}([count(a -> a>0, σᵢ[β1,:]) for β1 in axes(σᵢ,1)]))
    end
end

function FastWarpedTensorProductMap2D(map::WarpedTensorProductMap2D)
    (M1, N1) = size(map.A)
    (M2, _, N2max) = size(map.B)

    A = SArray{Tuple{M1,N1}}(map.A)
    B = SArray{Tuple{M1,N1,N2max}}(map.B)
    σᵢ = SArray{Tuple{M1,M2}}(map.σᵢ)
    σₒ = SArray{Tuple{N1,N2max}}(map.σₒ)

    return FastWarpedTensorProductMap2D(A, B, σᵢ, σₒ)
end

@inline Base.size(L::FastWarpedTensorProductMap2D) = (count(a->a>0,L.σₒ), 
    count(a->a>0,L.σᵢ))

"""
Evaluate the matrix-vector product

(Lx)[σₒ[α1,α2]] = ∑_{β1,β2} A[α1,β1] B[α2,β1,β2] x[σᵢ[β1,β2]] 
                = ∑_{β1} A[α1,β1] (∑_{β2} B[α2,β1,β2] x[σᵢ[β1,β2]]) 
                = ∑_{β1} A[α1,β1] Z[β1,α2]
"""
function LinearAlgebra.mul!(y::AbstractVector, 
    L::FastWarpedTensorProductMap2D, x::AbstractVector)
    LinearMaps.check_dim_mul(y, L, x)
    @unpack A, B, σᵢ, σₒ, N2 = L
    
    Z = Matrix{Float64}(undef, size(σᵢ,1), size(σₒ,2))

    @inbounds for α2 in axes(σₒ,2), β1 in axes(σᵢ,1)
        temp = 0.0
        @simd for β2 in 1:N2[β1]
            @muladd temp = temp + B[α2,β1,β2] * x[σᵢ[β1,β2]]
        end
        Z[β1,α2] = temp
    end

    @inbounds for α1 in axes(σₒ,1), α2 in axes(σₒ,2)
        temp = 0.0
        @simd for β1 in axes(σᵢ,1)
            @muladd temp = temp + A[α1,β1] * Z[β1,α2]
        end
        y[σₒ[α1,α2]] = temp
    end
    return y
end

"""
Evaluate the matrix-vector product

(Lx)[σᵢ[β1,β2]] = ∑_{α1,α2} B[α2,β1,β2] A[α1,β1] x[σₒ[α1,α2]] 
                = ∑_{α2} B[α2,β1,β2] (∑_{α1} A[α1,β1] x[σₒ[α1,α2]] )
                = ∑_{α2} B[α2,β1,β2] Z[β1,α2])
"""
function LinearMaps._unsafe_mul!(y::AbstractVector, 
    L::LinearMaps.TransposeMap{Float64, <:FastWarpedTensorProductMap2D},
    x::AbstractVector)

    LinearMaps.check_dim_mul(y, L, x)
    @unpack A, B, σᵢ, σₒ, N2 = L.lmap

    Z = Matrix{Float64}(undef, size(σᵢ,1), size(σₒ,2))
    
    @inbounds for β1 in axes(σᵢ,1), α2 in axes(σₒ,2)
        temp = 0.0
        @simd for α1 in axes(σₒ,1)
            @muladd temp = temp + A[α1,β1] * x[σₒ[α1,α2]]
        end
        Z[β1,α2] = temp
    end

    @inbounds for β1 in axes(σᵢ,1)
        for β2 in 1:N2[β1]
            temp = 0.0
            @simd for α2 in axes(σₒ,2)
                @muladd temp = temp + B[α2,β1,β2] * Z[β1,α2]
            end
            y[σᵢ[β1,β2]] = temp
        end
    end

    return y
end