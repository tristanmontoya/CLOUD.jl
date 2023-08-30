module SpatialDiscretizations

    using StaticArrays: SArray, SMatrix, SVector
    using LinearAlgebra: I, inv, Diagonal, diagm, kron, transpose, det, eigvals, mul!
    using Random: rand, shuffle
    using LinearMaps: LinearMap, ⊗
    using StartUpDG: MeshData, basis, vandermonde, grad_vandermonde, diagE_sbp_nodes, quad_nodes, NodesAndModes.quad_nodes_tri, NodesAndModes.quad_nodes_tet, face_vertices, nodes, num_faces, find_face_nodes, init_face_data, equi_nodes, face_type, Polynomial, jacobiP, match_coordinate_vectors,uniform_mesh, make_periodic, jaskowiec_sukumar_quad_nodes, Hicken, geometric_factors
    
    using Jacobi: zgrjm, wgrjm, zgj, wgj, zglj, wglj

    using ..MatrixFreeOperators: TensorProductMap2D, TensorProductMap3D, WarpedTensorProductMap2D, WarpedTensorProductMap3D, SelectionMap

    using Reexport
    @reexport using StartUpDG: RefElemData, AbstractElemShape, Line, Quad, Tri, Tet, Hex, SBP

    export AbstractApproximationType, NodalTensor, ModalTensor, ModalMulti, NodalMulti, ModalMultiDiagE, NodalMultiDiagE, AbstractReferenceMapping, AbstractMetrics, ExactMetrics, ChanWilcoxMetrics, NoMapping, ReferenceApproximation, GeometricFactors, SpatialDiscretization, apply_reference_mapping, reference_derivative_operators, check_normals, check_facet_nodes, check_sbp_property, centroids, trace_constant, dim, χ, warped_product
    
    abstract type AbstractApproximationType end

    """Nodal approximation using tensor-product operators"""
    struct NodalTensor <: AbstractApproximationType 
        p::Int
    end

    """Modal approximation using tensor-product operators"""
    struct ModalTensor <: AbstractApproximationType
        p::Int
    end

    """Modal approximation using multidimensional operators"""
    struct ModalMulti <: AbstractApproximationType
        p::Int
    end

    """Nodal approximation using multidimensional operators"""
    struct NodalMulti <: AbstractApproximationType
        p::Int
    end

    """Modal approximation using diagonal-E SBP operators"""
    struct ModalMultiDiagE <: AbstractApproximationType
        p::Int
    end

    """Nodal approximation using diagonal-E SBP operators"""
    struct NodalMultiDiagE <: AbstractApproximationType
        p::Int
    end

    """Collapsed coordinate mapping χ: [-1,1]ᵈ → Ωᵣ"""
    abstract type AbstractReferenceMapping end
    struct NoMapping <: AbstractReferenceMapping end
    struct ReferenceMapping <: AbstractReferenceMapping 
        J_ref::Vector{Float64}
        Λ_ref::Array{Float64, 3}
    end

    abstract type AbstractMetrics end
    struct ExactMetrics <: AbstractMetrics end
    struct ChanWilcoxMetrics <: AbstractMetrics end

    """Operators for local approximation on reference element"""
    struct ReferenceApproximation{d, ElemShape, 
        ApproxType, D_type, V_type, Vf_type, R_type, V_plot_type, ReferenceMappingType}
        approx_type::ApproxType
        N_p::Int
        N_q::Int
        N_f::Int
        reference_element::RefElemData{d, ElemShape}
        D::D_type
        V::V_type
        Vf::Vf_type
        R::R_type
        W::Diagonal{Float64, Vector{Float64}}
        B::Diagonal{Float64, Vector{Float64}}
        V_plot::V_plot_type
        reference_mapping::ReferenceMappingType

        function ReferenceApproximation(approx_type::ApproxType,
            reference_element::RefElemData{d,ElemShape},  
            D::D_type, V::V_type, Vf::Vf_type, 
            R::R_type, V_plot::V_plot_type, 
            reference_mapping::ReferenceMappingType = NoMapping()
            ) where {d, ElemShape, 
            ApproxType, D_type, V_type, Vf_type, R_type, V_plot_type, ReferenceMappingType}

            return new{d, ElemShape, 
            ApproxType, D_type, V_type, Vf_type, R_type, V_plot_type, ReferenceMappingType}(approx_type, size(V,2), 
                size(V,1), size(R,1), reference_element, D, V, Vf, R, 
                Diagonal(reference_element.wq), Diagonal(reference_element.wf),
                V_plot, reference_mapping)
        end
    end

    struct GeometricFactors
        # first dimension is node index, second is element
        J_q::Matrix{Float64}
    
        # first dimension is node index, second and third are matrix indices mn,
        # fourth is element
        Λ_q::Array{Float64,4}
    
        # first dimension is node index, second is element
        J_f::Matrix{Float64}
    
        # first dimension is node, second is cartesian component, third is element
        nJf::Array{Float64,3}

        # first dimension is is node, second is vector index n
        # fourth is element
        nJq::Array{Float64,4}
    end
    
    """Data for constructing the global spatial discretization"""
    struct SpatialDiscretization{d}
        mesh::MeshData{d}
        N_e::Int
        reference_approximation::ReferenceApproximation{d}
        geometric_factors::GeometricFactors
        M::Vector{AbstractMatrix}
        x_plot::NTuple{d, Matrix{Float64}}
    end

    function SpatialDiscretization(mesh::MeshData{d},
        reference_approximation::ReferenceApproximation{d},
        metric_type::AbstractMetrics=ExactMetrics();
        project_jacobian::Bool=false) where {d}

        (; reference_element, W, V) = reference_approximation

        N_e = size(mesh.xyz[1])[2]
        (; J_q, Λ_q, J_f, nJf, nJq) = GeometricFactors(mesh,
        reference_element, metric_type)

        # this is used in the SISC paper
        # Chan and Wilcox metrics interpolate on mapping nodes so 
        # this isn't needed in that case.
        if project_jacobian
            J_proj = similar(J_q)
            Minv = inv(Matrix(V'*W*V))
            for k in 1:N_e 
                J_proj[:,k] = V * Minv * V' * W * J_q[:,k]
            end
        else 
            J_proj = J_q
        end

        return SpatialDiscretization{d}(mesh, N_e, reference_approximation, 
            GeometricFactors(J_proj, Λ_q, J_f, nJf, nJq),
            [Matrix(V' * Diagonal(W * J_proj[:,k]) * V) for k in 1:N_e],
            Tuple(reference_element.Vp * mesh.xyz[m] for m in 1:d))
    end

    """Use this when there are no collapsed coordinates"""
    @inline apply_reference_mapping(geometric_factors::GeometricFactors, ::NoMapping) = geometric_factors
    
    """Express all metric terms in terms of collapsed coordinates"""
    function apply_reference_mapping(geometric_factors::GeometricFactors,
        reference_mapping::ReferenceMapping)
        (; J_q, Λ_q, J_f, nJf, nJq) = geometric_factors
        (; J_ref, Λ_ref) = reference_mapping
        (N_q, N_e) = size(J_q)
        d = size(Λ_q, 2)
        Λ_η = similar(Λ_q)

        @inbounds for k in 1:N_e, i in 1:N_q, m in 1:d, n in 1:d
            Λ_η[i,m,n,k] = sum(Λ_ref[i,m,l] * Λ_q[i,l,n,k] ./ J_ref[i] 
                for l in 1:d)
        end
        
        return GeometricFactors(J_q, Λ_η, J_f, nJf, nJq)
    end

    # get derivative operators in reference coordinates from collapsed
    function reference_derivative_operators(D_η::NTuple{d, LinearMap},
        reference_mapping::ReferenceMapping) where {d}
        (; Λ_ref, J_ref) = reference_mapping
        return Tuple(sum(Diagonal(Λ_ref[:,l,m]./J_ref) * D_η[l]
            for l in 1:d) for m in 1:d)
    end

    function reference_derivative_operators(D_η::NTuple{d, LinearMap},    
        ::NoMapping) where {d}
        return D_η
    end

    """
    Check if the normals are equal and opposite under the mapping
    """
    function check_normals(
        spatial_discretization::SpatialDiscretization{d}) where {d}
        (; geometric_factors, mesh, N_e) = spatial_discretization
        return Tuple([maximum(abs.(geometric_factors.nJf[m,:,k] + 
                geometric_factors.nJf[m,:,:][mesh.mapP[:,k]])) for k in 1:N_e]
                for m in 1:d)
    end

    """
    Check if the facet nodes are conforming
    """
    function check_facet_nodes(
        spatial_discretization::SpatialDiscretization{d}) where {d}
        (; mesh, N_e) = spatial_discretization
        return Tuple([maximum(abs.(mesh.xyzf[m][:,k] -
            mesh.xyzf[m][mesh.mapP[:,k]])) for k in 1:N_e] for m in 1:d)
    end

    """
    Check if the SBP property is satisfied on the reference element
    """
    function check_sbp_property(
        reference_approximation::ReferenceApproximation{d}) where {d}       
        (; W, D, R, B) = reference_approximation
        (; reference_mapping) = reference_approximation
        (; nrstJ) = reference_approximation.reference_element

        D_ξ = reference_derivative_operators(D, reference_mapping)

        return Tuple(maximum(abs.(Matrix(W*D_ξ[m] + D_ξ[m]'*W - 
                R'*B*Diagonal(nrstJ[m])*R))) for m in 1:d)
    end

    """
    Check if the SBP property is satisfied on the physical element
    """
    function check_sbp_property(
        spatial_discretization::SpatialDiscretization{d}, k::Int=1) where {d}

        (; W, D, R, B) = spatial_discretization.reference_approximation
        (; Λ_q, nJf) = spatial_discretization.geometric_factors

        S = Tuple((sum( 0.5 * D[m]' * W * Diagonal(Λ_q[:,m,n,k]) -
                        0.5 * Diagonal(Λ_q[:,m,n,k]) * W * D[m] for m in 1:d) + 
                0.5 * R' * B * Diagonal(nJf[n,:,k]) * R) for n in 1:d)

        E = Tuple(R' * B * Diagonal(nJf[n,:,k]) * R for n in 1:d)

        return Tuple(maximum(abs.(convert(Matrix, S[n] + S[n]' - E[n]))) 
            for n in 1:d)
    end

    """
    Average of vertex positions (not necessarily actual centroid).
    Use only for plotting.
    """
    function centroids(
        spatial_discretization::SpatialDiscretization{d}) where {d}
        (; xyz) = spatial_discretization.mesh
        return [Tuple(sum(xyz[m][:,k])/length(xyz[m][:,k]) 
            for m in 1:d) for k in 1:spatial_discretization.N_e]
    end

    """
    Trace inequality constant from Chan et al. (2016)
    """
    function trace_constant(reference_approximation::ReferenceApproximation)
        (; B, Vf, W, V) = reference_approximation
        return maximum(eigvals(Matrix(Vf' * B * Vf), Matrix(V' * W * V)))
    end

    @inline dim(::Line) = 1
    @inline dim(::Union{Tri,Quad}) = 2
    @inline dim(::Union{Tet,Hex}) = 3

    export AbstractQuadratureRule, DefaultQuadrature, LGLQuadrature, LGQuadrature, LGRQuadrature, GaussLobattoQuadrature, GaussRadauQuadrature, GaussQuadrature, XiaoGimbutasQuadrature, JaskowiecSukumarQuadrature, quadrature
    include("quadrature_rules.jl")

    # new constructors for RefElemData from StartUpDG
    include("ref_elem_data.jl")

    include("multidimensional.jl")
    include("tensor_cartesian.jl")

    export reference_geometric_factors, operators_1d
    include("tensor_simplex.jl")

    export GeometricFactors, metrics, uniform_periodic_mesh, warp_mesh, cartesian_mesh, Uniform, ZigZag, DelReyWarping, ChanWarping
    include("mesh.jl")

end