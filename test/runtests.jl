push!(LOAD_PATH,"../")
using Test, StableSpectralElements, OrdinaryDiffEq, TimerOutputs

include("test_driver.jl")
include("burgers_fluxdiff_1d.jl")
include("euler_1d_gauss.jl")
include("euler_vortex_2d_nodal_diage.jl")
include("euler_vortex_2d_modal.jl")

const tol = 1.0e-10
const p = 4
@testset "Advection-Diffusion 1D ModalMulti" begin
    (l2, conservation, _) = test_driver(
        ReferenceApproximation(ModalMulti(p), Line()), 
        LinearAdvectionDiffusionEquation(1.0,5.0e-2),
        InitialDataSine(1.0,2π),
        StandardForm(
            mapping_form=StandardMapping(),
            inviscid_numerical_flux=LaxFriedrichsNumericalFlux(),
            viscous_numerical_flux=BR1()),
        PhysicalOperator(), DefaultOperatorAlgorithm(),
        1.0, 4, 1.0, 1.0/100.0, 0.1,
        "test_advection_diffusion_1d_dgmulti")
        
    @test l2 ≈ 6.988216111882884e-6 atol=tol
    @test conservation ≈ 0.0 atol=tol
end

@testset "Advection 2D Energy-Conservative ModalTensor Tri" begin
    (l2, conservation, energy) = test_driver(
        ReferenceApproximation(ModalTensor(p), Tri(),mapping_degree=p), 
        LinearAdvectionEquation((1.0,1.0)),
        InitialDataSine(1.0,(2*π, 2*π)),
        StandardForm(mapping_form=SkewSymmetricMapping(),
            inviscid_numerical_flux=LaxFriedrichsNumericalFlux(0.0)),
        ReferenceOperator(), BLASAlgorithm(), 1.0, 2, 1.0, 1.0/100.0, 0.1,
        "test_advection_2d_collapsed_econ")

    @test l2 ≈ 0.2660013939427627 atol=tol
    @test conservation ≈ 0.0 atol=tol
    @test energy ≈ 0.0 atol=tol
end

@testset "Advection 2D FluxDiff NodalTensor Quad" begin
    (l2, conservation, _) = test_driver(
        ReferenceApproximation(NodalTensor(p), Quad(), mapping_degree=p), 
        LinearAdvectionEquation((1.0,1.0)),
        InitialDataSine(1.0,(2*π, 2*π)),
        FluxDifferencingForm(),
        ReferenceOperator(), DefaultOperatorAlgorithm(),
        1.0, 2, 1.0, 1.0/100.0, 0.1,
        "test_advection_2d_dgsem_fluxdiff")
    
    @test l2 ≈ 0.04790536605026519 atol=tol
    @test conservation ≈ 0.0 atol=tol
end

@testset "Inviscid Burgers NodalTensor FluxDiff 1D" begin
    (conservation, energy) = burgers_fluxdiff_1d()

    @test conservation ≈ 0.0 atol=tol
    @test energy ≈ 0.0 atol=tol
end

@testset "Euler 1D Gauss collocation 1D" begin
    (l2, conservation, entropy) = euler_1d_gauss()

    @test l2 ≈ [3.5808560177567635e-5, 5.2129828619609155e-5, 0.00012637647535378534] atol=tol
    @test conservation ≈ [0.0, 0.0, 0.0] atol=tol
    @test entropy ≈ 0.0 atol=tol
end

@testset "Isentropic Euler vortex FluxDiff NodalMultiDiagE Tri 2D" begin
    (l2, conservation, entropy) = euler_vortex_2d_diage()

    @test l2 ≈ [0.03590766990615721, 0.06742249914084399, 
        0.06824665400591982, 0.08389828379848713] atol=tol
    @test conservation ≈ [0.0, 0.0, 0.0, 0.0] atol=tol
    @test entropy ≈ 0.0 atol=tol
end

@testset "Isentropic Euler vortex FluxDiff ModalTensor Tri 2D" begin
    (l2, conservation, entropy) = euler_vortex_2d_modal()

    @test l2 ≈ [0.03734599714012373, 0.075883163090583, 0.06103456983950774, 0.07065687750221998] atol=tol
    @test conservation ≈ [0.0, 0.0, 0.0, 0.0] atol=tol
    @test entropy ≈ 0.0 atol=tol
end

@testset "Advection 3D Energy-Conservative ModalTensor Tet" begin
    (l2, conservation, energy) = test_driver(
        ReferenceApproximation(ModalTensor(p), Tet(), 
            mapping_degree=3, sum_factorize_vandermonde=false),
        LinearAdvectionEquation((1.0,1.0,1.0)),
        InitialDataSine(1.0,(2*π, 2*π, 2*π)),
        StandardForm(mapping_form=SkewSymmetricMapping(),
            inviscid_numerical_flux=LaxFriedrichsNumericalFlux(0.0)),
        ReferenceOperator(), BLASAlgorithm(), 1.0, 2, 1.0, 1.0/50.0, 0.1,
        "test_advection_3d_collapsed_econ")
    
    @test l2 ≈ 0.18604185425549752 atol=tol
    @test conservation ≈ 0.0 atol=tol
    @test energy ≈ 0.0 atol=tol
end