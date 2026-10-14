include("CQTExperiment.jl")
Base.include(CQTBenchmarks, joinpath(@__DIR__, "runner.jl"))
length(ARGS) == 2 || error("Usage: julia --project=benchmarks benchmarks/run.jl smoke|preflight|campaign OUTPUT")
CQTBenchmarks.run_campaign(abspath(ARGS[2]); mode = ARGS[1])
