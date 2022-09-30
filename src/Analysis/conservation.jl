abstract type ConservationAnalysis <: AbstractAnalysis end

"""
Evaluate change in ∫udx  
"""
struct PrimaryConservationAnalysis <: ConservationAnalysis
    WJ::Vector{<:AbstractMatrix}
    N_eq::Int
    N_el::Int
    V::LinearMap
    results_path::String
    analysis_path::String
    dict_name::String
end

"""
Evaluate change in  ∫½u²dx  
"""
struct EnergyConservationAnalysis <: ConservationAnalysis
    WJ::Vector{<:AbstractMatrix}
    N_eq::Int
    N_el::Int
    V::LinearMap
    results_path::String
    analysis_path::String
    dict_name::String
end

struct ConservationAnalysisResults <:AbstractAnalysisResults
    t::Vector{Float64}
    E::Matrix{Float64}
end

function PrimaryConservationAnalysis(results_path::String,
    conservation_law::AbstractConservationLaw, 
    spatial_discretization::SpatialDiscretization{d}, name="primary_conservation_analysis") where {d}

    analysis_path = new_path(string(results_path, name, "/"))
    _, N_eq, N_el = get_dof(spatial_discretization, conservation_law)
  
    @unpack W, V =  spatial_discretization.reference_approximation
    @unpack geometric_factors, mesh, N_el = spatial_discretization
    
    WJ = [Matrix(W) * Diagonal(geometric_factors.J_q[:,k]) for k in 1:N_el]

    return PrimaryConservationAnalysis(
        WJ, N_eq, N_el, V, results_path, analysis_path, "conservation.jld2")
end

function EnergyConservationAnalysis(results_path::String,
    conservation_law::AbstractConservationLaw,
    spatial_discretization::SpatialDiscretization{d},
    name="energy_conservation_analysis") where {d}

    analysis_path = new_path(string(results_path, name, "/"))
    _, N_eq, N_el = get_dof(spatial_discretization, conservation_law)

    @unpack W, V =  spatial_discretization.reference_approximation
    @unpack geometric_factors, mesh, N_el = spatial_discretization
    
    WJ = [Matrix(W) * Diagonal(geometric_factors.J_q[:,k]) for k in 1:N_el]

    return EnergyConservationAnalysis(
        WJ, N_eq, N_el, V ,results_path, analysis_path, "energy.jld2")
end

function evaluate_conservation(
    analysis::PrimaryConservationAnalysis, 
    sol::Array{Float64,3})
    @unpack WJ, N_eq, N_el, V = analysis 

    return [sum(sum(WJ[k]*V*sol[:,e,k]) 
        for k in 1:N_el) for e in 1:N_eq]
end

function evaluate_conservation(
    analysis::EnergyConservationAnalysis, 
    sol::Array{Float64,3})
    @unpack WJ, N_eq, N_el, V = analysis 

    return [0.5*sum(sol[:,e,k]'*V'*WJ[k]*V*sol[:,e,k] 
        for k in 1:N_el) for e in 1:N_eq]
end

function analyze(analysis::ConservationAnalysis, 
    initial_time_step::Union{Int,String}=0, 
    final_time_step::Union{Int,String}="final")
    
    @unpack results_path, analysis_path, dict_name = analysis

    u_0, t_0 = load_solution(results_path, initial_time_step)
    u_f, t_f = load_solution(results_path, final_time_step)

    initial = evaluate_conservation(analysis,u_0)
    final = evaluate_conservation(analysis,u_f)
    difference = final .- initial

    save(string(analysis_path, dict_name), 
        Dict("analysis" => analysis,
            "initial" => initial,
            "final" => final,
            "difference" => difference,
            "t_0" => t_0,
            "t_f" => t_f))

    return initial, final, difference
end

function analyze(analysis::ConservationAnalysis,
    time_steps::Vector{Int})

    @unpack results_path, N_eq, dict_name = analysis
    N_t = length(time_steps)
    t = Vector{Float64}(undef,N_t)
    E = Matrix{Float64}(undef,N_t, N_eq)
    for i in 1:N_t
        u, t[i] = load_solution(results_path, time_steps[i])
        E[i,:] = evaluate_conservation(analysis, u)
    end

    results = ConservationAnalysisResults(t,E)

    save(string(results_path, dict_name), 
    Dict("conservation_analysis" => analysis,
        "conservation_results" => results))

    return ConservationAnalysisResults(t,E)
end

function analyze(analysis::ConservationAnalysis,    
    model::DynamicalAnalysisResults,
    time_steps::Vector{Int}, Δt::Float64, start::Int=1,
    resolution=100;  n=1, window_size=nothing, new_projection=false)

    @unpack results_path, N_eq, dict_name = analysis
    N_t = length(time_steps)
    t = Vector{Float64}(undef,N_t)
    E = Matrix{Float64}(undef,N_t, N_eq)
    
    t_modeled = Vector{Float64}(undef,resolution+1)
    E_modeled = Matrix{Float64}(undef,resolution+1, N_eq)

    u0, t0 = load_solution(results_path, time_steps[start])
    for i in 1:N_t
        u, t[i] = load_solution(results_path, time_steps[i])
        E[i,:] = evaluate_conservation(analysis, u)
    end

    (N_p,N_eq,N_el) = size(u0)
    N = N_p*N_eq*N_el

    dt = Δt/resolution
    if new_projection
        c = pinv(model.Z[1:N,:]) * vec(u0)
    elseif !isnothing(window_size)
        c = model.c[:,1]
        t0 = t[max(start-window_size+1,1)]
    else
        c = model.c[:, (start-1)*n+1]
    end

    for i in 0:resolution
        u = reshape(real.(forecast(model, dt*i, c)[1:N]),(N_p,N_eq,N_el))
        
        t_modeled[i+1] = t0+dt*i
        E_modeled[i+1,:] = evaluate_conservation(analysis, u)
    end

    results = ConservationAnalysisResults(t,E)
    modeled_results = ConservationAnalysisResults(t_modeled, E_modeled)

    save(string(results_path, dict_name), 
    Dict("conservation_analysis" => analysis,
        "conservation_results" => results,
        "modeled_conservation_results" => modeled_results))  

    return results, modeled_results
end

    
function plot_evolution(analysis::ConservationAnalysis, 
    results::ConservationAnalysisResults, title::String; legend::Bool=false,
    ylabel::String="Energy", e::Int=1)
    p = plot(results.t, results.E[:,e], 
        legend=legend, xlabel="\$t\$", ylabel=ylabel)
    savefig(p, string(analysis.analysis_path, title))
    return p
end

function plot_evolution(analysis::ConservationAnalysis, 
    results::Vector{ConservationAnalysisResults}, title::String; 
    labels::Vector{String}=["Actual", "Predicted"],
    ylabel::String="Energy", e::Int=1, t=nothing, xlims=nothing, ylims=nothing)

    p = plot(results[1].t, results[1].E[:,e], xlabel="\$t\$",   
    ylabel=ylabel, labels=labels[1], xlims=xlims, ylims=ylims, linewidth=2.0)
    N = length(results)
    for i in 2:N
        plot!(p, results[i].t, results[i].E[:,e], labels=labels[i], linestyle=:dash, linewidth=3.0, legend=:topright)
    end
    if !isnothing(t)
       vline!(p,[t], labels=nothing)
    end

    savefig(p, string(analysis.analysis_path, title))
    return p
end