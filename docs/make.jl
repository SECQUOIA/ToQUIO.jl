using Documenter
using ToQUIO

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const SKIP_DEPLOY = "--skip-deploy" in ARGS

makedocs(;
    sitename = "ToQUIO.jl",
    authors = "Pedro Maciel Xavier and Albert Lee",
    doctest = false,
    clean = true,
    root = @__DIR__,
    source = "src",
    build = "build",
    workdir = REPOSITORY_ROOT,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
    ),
    pages = [
        "Home" => "index.md",
        "Quick Start" => "QUICKSTART.md",
        "Examples" => "examples.md",
        "API Reference" => "api.md",
        "Algorithm" => "algorithm.md",
    ],
)

if SKIP_DEPLOY
    @info "Skipping documentation deployment"
else
    deploydocs(;
        repo = "github.com/SECQUOIA/ToQUIO.jl.git",
        devbranch = "main",
        push_preview = false,
    )
end
