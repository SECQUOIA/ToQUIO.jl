include("CQTBenchmarks.jl")
Base.include(CQTBenchmarks, joinpath(@__DIR__, "toqubo_adapter.jl"))
Base.include(CQTBenchmarks, joinpath(@__DIR__, "reference.jl"))
