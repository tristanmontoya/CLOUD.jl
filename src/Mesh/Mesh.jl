module Mesh

    using StartUpDG: RefElemData, MeshData, uniform_mesh, make_periodic, meshgrid, Line, Tri
    using LinearAlgebra: inv, det

    export GeometricFactors, uniform_periodic_mesh

    struct GeometricFactors{d}

        # first dimension is node index, second is element
        J_q::Matrix{Float64}

        # first dimension is node index, second and third are matrix indices mn,
        # fourth is element
        Jdrdx_q ::Array{Float64,4}

        # d-tuple of matrices, where first is element index,
        nJf::NTuple{d, Matrix{Float64}}

    end
    
    function uniform_periodic_mesh(reference_element::RefElemData{1}, 
        limits::NTuple{2,Float64}, M::Int)

        VX, EtoV = uniform_mesh(reference_element.elementType, M)
        mesh =  MeshData(limits[1] .+ 0.5*(limits[2]-limits[1])*(VX[1] .+ 1.0), EtoV,reference_element)

        return make_periodic(mesh)
    end

    function uniform_periodic_mesh(reference_element::RefElemData{2}, 
        limits::NTuple{2,NTuple{2,Float64}}, M::NTuple{2,Int})

        (VX, VY), EtoV = uniform_mesh(reference_element.elementType, M[1], M[2])

        return make_periodic(
            MeshData(limits[1][1] .+ 
                0.5*(limits[1][2]-limits[1][1])*(VX .+ 1.0),
                limits[2][1] .+ 0.5*(limits[2][2]-limits[2][1])*(VY .+ 1.0),
                EtoV, reference_element))
    end

    function GeometricFactors(mesh::MeshData{d}, 
        reference_element::RefElemData{d}) where {d}

        # note, here we assume that mesh is same N_q, N_f every element
        N_q = size(mesh.xyzq[1],1)
        N_f = size(mesh.xyzf[1],1)
        N_el = size(mesh.xyzq[1],2)

        J_q = Matrix{Float64}(undef, N_q, N_el)
        nJf = Tuple(Matrix{Float64}(undef, N_f, N_el) for m in 1:d)

        # first dimension is node index, 
        # second and third are matrix indices mn,
        # fourth is element index.
        dxdr_q = Array{Float64, 4}(undef, N_q, d, d, N_el)
        Jdrdx_q = Array{Float64, 4}(undef, N_q, d, d, N_el)
        dxdr_f = Array{Float64, 4}(undef, N_f, d, d, N_el)        

        for k in 1:N_el
            for m in 1:d, n in 1:d
                for n in 1:d
                    # evaluate metric at mapping nodes
                    dxdr = reference_element.Drst[n]*mesh.xyz[m][:,k]

                    # use mapping basis to interpolate to quadrature nodes
                    dxdr_q[:,m,n,k] = reference_element.Vq*dxdr
                    dxdr_f[:,m,n,k] = reference_element.Vf*dxdr
                end
            end

            # loops over slower indices
            for i in 1:N_q
                J_q[i,k] = det(dxdr_q[i,:,:,k])
                Jdrdx_q[i,:,:,k] = J_q[i,k]*inv(dxdr_q[i,:,:,k])
            end
        
            # get scaled normal vectors - this includes scaling for ref. quadrature weights on long side of right-angled triangle.
            # don't need actual facet Jacobian for now, probably will.
            for i in 1:N_f
                Jdrdx_f = det(dxdr_f[i,:,:,k]) *
                    inv(dxdr_f[i,:,:,k])
                for m in 1:d
                    nJf[m][i,k] = sum(
                        Jdrdx_f[n,m]*reference_element.nrstJ[n][i] 
                            for n in 1:d)
                end
            end
        end
        return GeometricFactors{d}(J_q, Jdrdx_q, nJf)
    end
end