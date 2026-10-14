include("CQTBenchmarks.jl")
length(ARGS) == 2 || error("Usage: julia --project=. benchmarks/replay.jl ARTIFACT_DIRECTORY JOB_KEY")
println(CQTBenchmarks.replay_job(abspath(ARGS[1]), ARGS[2]))
