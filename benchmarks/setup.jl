# Run once with julia --project=benchmarks benchmarks/setup.jl.
using Pkg, TOML
protocol = TOML.parsefile(joinpath(@__DIR__, "protocol_v1.toml"))
Pkg.develop(PackageSpec(path = dirname(@__DIR__)))
Pkg.add(PackageSpec(url = "https://github.com/JuliaQUBO/ToQUBO.jl",
                    rev = protocol["toqubo_revision"]))
Pkg.instantiate()
