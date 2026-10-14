# Invoke from the ordinary root environment, independently of CQTExperiment.
using Test
include("CQTBenchmarks.jl")
const R = CQTBenchmarks
root = only(ARGS)
ledger = R.read_archive(root, "ledger.toml")
@test !any(id.name in ("ToQUBO", "HiGHS") for id in keys(Base.loaded_modules))
entry = first(filter(e -> e["status"] == "complete", ledger["jobs"]))
@test R.replay_job(root, entry["key"])["status"] == "verified"
