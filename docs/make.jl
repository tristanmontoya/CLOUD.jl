import Pkg
Pkg.add("Documenter")
using Documenter
using StableSpectralElements

push!(LOAD_PATH, "../src/")

makedocs(
    sitename = "StableSpectralElements.jl",
    authors = "Tristan Montoya",
    pages = [
        "Home" => "index.md",
        "Reference" => [
            "`ConservationLaws`" => "ConservationLaws.md",
            "`SpatialDiscretizations`" => "SpatialDiscretizations.md",
        ],
    ],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        assets = ["assets/favicon.ico"],
        ansicolor = true,
    ),
)
deploydocs(repo = "github.com/tristanmontoya/StableSpectralElements.jl.git")
