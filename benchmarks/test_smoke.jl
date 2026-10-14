using Test
include("CQTExperiment.jl")
Base.include(CQTBenchmarks, joinpath(@__DIR__, "runner.jl"))
const S = CQTBenchmarks
const OUTPUT = joinpath(@__DIR__, "ci-smoke")

@testset "Credential-free smoke, replay and resume" begin
    ledger = S.run_campaign(OUTPUT; mode = "smoke")
    @test ledger["status"] == "smoke-only-complete-no-performance-conclusion"
    @test ledger["sampler_starts_reserved"] == 40
    @test ledger["proposals_reserved"] == 5120
    @test length(ledger["cells"]) == 40
    @test length(ledger["jobs"]) == 40
    @test length(ledger["warm_timings"]) == 40
    @test all(entry["status"] == "complete" for entry in ledger["jobs"])
    for entry in ledger["jobs"]
        @test S.replay_job(OUTPUT, entry["key"])["status"] == "verified"
    end
    again = S.run_campaign(OUTPUT; mode = "smoke")
    @test again["sampler_starts_reserved"] == ledger["sampler_starts_reserved"]
    @test again["proposals_reserved"] == ledger["proposals_reserved"]
    @test [j["key"] for j in again["jobs"]] == [j["key"] for j in ledger["jobs"]]
    @test S.artifact_bytes(OUTPUT) <= S.PROTOCOL["resources"]["artifact_bytes"]
end
