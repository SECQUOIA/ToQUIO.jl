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
    entry = first(ledger["jobs"])
    record = S.read_archive(OUTPUT, entry["file"]; expected_hash = entry["hash"])
    cell_data = S.read_archive(OUTPUT, record["cell_file"]; expected_hash = record["cell_hash"])
    cell = S.cell_from_record(cell_data)
    broken = deepcopy(record)
    broken["trajectory"]["seed"] += 1
    @test_throws ErrorException S.verify_replay_binding(entry["key"], broken, cell, ledger, OUTPUT)
    broken = deepcopy(record)
    broken["trajectory"]["energy_scale"] += 1
    @test_throws ErrorException S.verify_replay_binding(entry["key"], broken, cell, ledger, OUTPUT)
    original = read(joinpath(OUTPUT, "Project.toml"))
    S.write_archive_bytes(OUTPUT, "Project.toml", [original; UInt8(10)]; replace = true)
    @test_throws ErrorException S.open_campaign(OUTPUT, "smoke")
    S.write_archive_bytes(OUTPUT, "Project.toml", original; replace = true)
    previous_peak = ledger["process_peak_rss_bytes"]
    again = S.run_campaign(OUTPUT; mode = "smoke")
    @test again["sampler_starts_reserved"] == ledger["sampler_starts_reserved"]
    @test again["proposals_reserved"] == ledger["proposals_reserved"]
    @test [j["key"] for j in again["jobs"]] == [j["key"] for j in ledger["jobs"]]
    @test again["process_peak_rss_bytes"] >= previous_peak
    @test length(again["invocations"]) == 2
    @test S.artifact_bytes(OUTPUT) <= S.PROTOCOL["resources"]["artifact_bytes"]
end
