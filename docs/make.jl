#push!(LOAD_PATH,"../src/")
using Documenter, GENeSYSMOD

#makedocs(sitename="GENeSYSMOD")

# Copy the NEWS.md file
news = "docs/src/manual/NEWS.md"
if isfile(news)
    rm(news)
end
cp("NEWS.md", news)
#cp(joinpath(@__DIR__,"..","NEWS.md"), joinpath(@__DIR__,"src/manual/NEWS.md"), force=true)

DocMeta.setdocmeta!(GENeSYSMOD, :DocTestSetup, :(using GENeSYSMOD); recursive=true)

makedocs(
    sitename = "GENeSYSMOD.jl",
    format = Documenter.HTML(;
    prettyurls=get(ENV, "CI", "false") == "true",
    edit_link="main",
    assets=String[],
    ),
    modules = [GENeSYSMOD],
    pages = [
        "Home" => "index.md",
        "Manual" => Any[
            "Quick Start" => "manual/quick-start.md",
            "Example" => "manual/simple-example.md",
            "Release notes" => "manual/NEWS.md",
        ],
        "Library" => Any[
            "Public" => "library/public.md",
            "Internals" => "library/internals.md"
        ]
    ]
)

deploydocs(
    repo = "github.com/GENeSYS-MOD/GENeSYSMOD.jl.git",
)
