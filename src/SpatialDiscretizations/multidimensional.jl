function ReferenceApproximation(
    approx_type::ModalMulti, ::Line; 
    mapping_degree::Int=1, N_plot::Int=10,
    volume_quadrature_rule=LGQuadrature(approx_type.p))

    @unpack p = approx_type

    reference_element = RefElemData(Line(), mapping_degree,
        quad_rule_vol=quadrature(Line(),volume_quadrature_rule), Nplot=N_plot)
        
    @unpack rstp, rstq, rstf, wq, wf = reference_element    

    VDM, ∇VDM = basis(Line(), p, rstq[1])     
    ∇V = (LinearMap(∇VDM),)
    Vf = LinearMap(vandermonde(Line(),p,rstf[1]))
    V = LinearMap(VDM)
    V_plot = LinearMap(vandermonde(Line(), p, rstp[1]))
    W = Diagonal(wq)
    B = Diagonal(wf)
    P = inv(VDM' * Diagonal(wq) * VDM) * V' * W
    R = Vf * P
    D = (∇V[1] * P,)

    return ReferenceApproximation(approx_type, p+1, length(wq), 2, 
        reference_element, D, V, Vf, R, W, B, V_plot, NoMapping())
end

function ReferenceApproximation(
    approx_type::ModalMulti, element_type::AbstractElemShape;
    mapping_degree::Int=1, N_plot::Int=10, volume_quadrature_rule=DefaultQuadrature(2*approx_type.p),
    facet_quadrature_rule=DefaultQuadrature(2*approx_type.p))

    @unpack p = approx_type
    d = dim(element_type)
    
    reference_element = RefElemData(element_type, mapping_degree, 
        quad_rule_vol=quadrature(element_type, volume_quadrature_rule),
        quad_rule_face=quadrature(face_type(element_type),
            facet_quadrature_rule), Nplot=N_plot)

    @unpack rstq, rstf, rstp, wq, wf = reference_element
    
    VDM, ∇VDM... = basis(element_type, p, rstq...) 
    ∇V = Tuple(LinearMap(∇VDM[m]) for m in 1:d)
    V = LinearMap(VDM)
    Vf = LinearMap(vandermonde(element_type,p,rstf...))
    V_plot = LinearMap(vandermonde(element_type, p, rstp...))
    W = Diagonal(wq)
    B = Diagonal(wf)
    P = inv(VDM' * Diagonal(wq) * VDM) * V' * W
    R = Vf * P
    D = Tuple(∇V[m] * P for m in 1:d)

    return ReferenceApproximation(approx_type, binomial(p+d, d), length(wq),
        length(wf), reference_element, D, V, Vf, R, W, B, V_plot, NoMapping())
end

function ReferenceApproximation(
    approx_type::NodalMulti, element_type::AbstractElemShape;
    mapping_degree::Int=1, N_plot::Int=10, volume_quadrature_rule=DefaultQuadrature(2*approx_type.p),
    facet_quadrature_rule=DefaultQuadrature(2*approx_type.p))

    @unpack p = approx_type
    d = dim(element_type)

    reference_element = RefElemData(element_type, mapping_degree, 
        quad_rule_vol=quadrature(element_type, volume_quadrature_rule),
        quad_rule_face=quadrature(face_type(element_type),
            facet_quadrature_rule), Nplot=N_plot)

    @unpack rstq, rstf, rstp, wq, wf = reference_element

    N_q = length(wq)
    VDM, ∇VDM... = basis(element_type, p, rstq...) 
    ∇V = Tuple(LinearMap(∇VDM[m]) for m in 1:d)
    V = LinearMap(I, N_q)
    Vf = LinearMap(vandermonde(element_type,p,rstf...))
    V_plot = LinearMap(vandermonde(element_type, p, rstp...))
    W = Diagonal(wq)
    B = Diagonal(wf)
    P = inv(VDM' * Diagonal(wq) * VDM) * VDM' * W
    R = Vf * P
    D = Tuple(∇V[m] * P for m in 1:d)

    return ReferenceApproximation(approx_type, N_q, N_q,
        length(wf), reference_element, D, V, R, R, W, B, V_plot * P, 
        NoMapping())
end