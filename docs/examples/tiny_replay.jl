# Portable 32-proposal smoke replay, not another statistical campaign.
module TinyReplayExample
using ToQUIO, Pkg, SHA, TOML
include("../../benchmarks/CQTBenchmarks.jl")
const S = CQTBenchmarks

function trajectory(cell, reference, seed)
    return S.metropolis(cell.polynomial, S.initializer(cell), S.cell_observer(cell, reference);
        seed, reserved_proposals = 32, max_seconds = Inf, check_deltas = true)
end

function create(root)
    ispath(root) && error("Use a new directory; existing replay evidence is preserved.")
    instance = first(S.corpus(S.PROTOCOL))
    cell = S.compile_quio(instance, "native", "controlled")
    reference = Dict("point" => instance.witness, "objective" => S.source_value(instance, instance.witness))
    gate = S.preflight(cell, reference)
    mkpath(root)
    cell_hash = S.write_archive(root, "cell.toml", S.cell_record(cell, gate))
    run_hash = S.write_archive(root, "trajectory.toml", trajectory(cell, reference["objective"], 741))
    manifest = Dict("julia_version" => string(VERSION), "execution_hashes" => S.execution_hashes(),
        "protocol_hash" => bytes2hex(sha256(read(joinpath(S.ROOT, "benchmarks/protocol_v1.toml")))),
        "replay_moi_version" => string(Pkg.dependencies()[Base.PkgId(S.M).uuid].version),
        "kind" => "32-proposal-smoke-not-campaign", "seed" => 741, "reference" => reference,
        "cell_hash" => cell_hash, "trajectory_hash" => run_hash,
        "example_hash" => bytes2hex(sha256(read(@__FILE__))))
    S.write_archive(root, "manifest.toml", manifest)
    return manifest
end

function replay(root)
    manifest = S.read_archive(root, "manifest.toml")
    S.verify_archive_execution(manifest)
    manifest["example_hash"] == bytes2hex(sha256(read(@__FILE__))) || error("Replay script differs.")
    cell = S.cell_from_record(S.read_archive(root, "cell.toml"; expected_hash = manifest["cell_hash"]))
    original = S.read_archive(root, "trajectory.toml"; expected_hash = manifest["trajectory_hash"])
    result = trajectory(cell, manifest["reference"]["objective"], manifest["seed"])
    for field in ("initial", "final", "samples", "move_counts", "completed_proposals",
                  "source_observations", "best_feasible_objective", "best_feasible_source",
                  "any_feasible", "first_feasible_proposal", "first_target_proposal")
        result[field] == original[field] || error("Replay differs at $field.")
    end
    result["completed_proposals"] == 32 || error("Smoke work count differs.")
    return true
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Use: tiny_replay.jl create|replay DIRECTORY")
    mode, root = ARGS
    mode == "create" ? TinyReplayExample.create(root) :
        mode == "replay" ? TinyReplayExample.replay(root) : error("Unknown mode.")
    println("Tiny smoke ", mode, " complete; timing is not replayed.")
end
