# TOML archives are portable inputs, not executable Julia serialization.
function portable(value)
    isnothing(value) && return Dict("__cqt_none__" => true)
    value isa AbstractString && return String(value)
    value isa BigInt && return typemin(Int) <= value <= typemax(Int) ? Int(value) :
                             Dict("__cqt_bigint__" => string(value))
    value isa AbstractDict && return Dict(string(k) => portable(v) for (k, v) in value)
    value isa AbstractVector && return [portable(v) for v in value]
    value isa Tuple && return [portable(v) for v in value]
    value isa Union{String,Bool,Integer,AbstractFloat} && return value
    throw(ArgumentError("Unsupported archive value type: $(typeof(value))."))
end

function restore_portable(value)
    if value isa AbstractDict
        length(value) == 1 && get(value, "__cqt_none__", false) === true && return nothing
        length(value) == 1 && haskey(value, "__cqt_bigint__") && return parse(BigInt, value["__cqt_bigint__"])
        return Dict{String,Any}(string(k) => restore_portable(v) for (k, v) in value)
    end
    value isa AbstractVector && return [restore_portable(v) for v in value]
    return value
end

function safe_artifact_path(root, relative)
    isabspath(relative) && throw(ArgumentError("Absolute archive member path."))
    any(==(".."), splitpath(relative)) && throw(ArgumentError("Archive path traversal."))
    current = abspath(root)
    islink(current) && throw(ArgumentError("Symlink artifact directory."))
    for part in splitpath(relative)
        current = joinpath(current, part)
        islink(current) && throw(ArgumentError("Symlink archive member."))
    end
    return current
end

function artifact_bytes(root)
    total = 0
    for (directory, _, files) in walkdir(root)
        for file in files
            path = joinpath(directory, file)
            islink(path) && throw(ArgumentError("Symlink in artifact tree."))
            total += filesize(path)
        end
    end
    return total
end

function write_archive(root, relative, value; replace = false)
    return write_archive_bytes(root, relative, toml_bytes(portable(value)); replace)
end

function write_archive_bytes(root, relative, bytes; replace = false)
    path = safe_artifact_path(root, relative)
    if isfile(path) && !replace
        read(path) == bytes || error("Immutable archive member differs: $relative.")
        return bytes2hex(SHA.sha256(bytes))
    end
    previous = isfile(path) ? filesize(path) : 0
    artifact_bytes(root) - previous + length(bytes) <= PROTOCOL["resources"]["artifact_bytes"] ||
        error("Artifact allowance exhausted; campaign incomplete.")
    mkpath(dirname(path))
    temporary, io = mktemp(dirname(path); cleanup = false)
    try
        write(io, bytes)
        flush(io)
    finally
        close(io)
    end
    mv(temporary, path; force = replace)
    return bytes2hex(SHA.sha256(bytes))
end

function read_archive(root, relative; expected_hash = nothing)
    path = safe_artifact_path(root, relative)
    filesize(path) <= PROTOCOL["resources"]["artifact_bytes"] || error("Oversized archive member.")
    bytes = read(path)
    isnothing(expected_hash) || bytes2hex(SHA.sha256(bytes)) == expected_hash || error("Archive hash mismatch.")
    return restore_portable(TOML.parse(String(bytes)))
end

function execution_hashes()
    files = ["benchmarks/CQTBenchmarks.jl", "benchmarks/protocol_helpers.jl", "benchmarks/corpus.jl",
        "benchmarks/metropolis.jl", "benchmarks/corpus_hashes_v1.toml",
        "benchmarks/compilers.jl", "benchmarks/preflight.jl", "benchmarks/artifacts.jl"]
    for (directory, _, entries) in walkdir(joinpath(ROOT, "src")), file in entries
        endswith(file, ".jl") && push!(files, relpath(joinpath(directory, file), ROOT))
    end
    return Dict(file => bytes2hex(SHA.sha256(read(joinpath(ROOT, file)))) for file in sort(files))
end

function verify_archive_execution(manifest)
    manifest["julia_version"] == string(VERSION) || error("Replay requires the archived Julia version.")
    manifest["execution_hashes"] == execution_hashes() || error("Replay executable source hashes differ.")
    manifest["protocol_hash"] == bytes2hex(SHA.sha256(read(joinpath(@__DIR__, "protocol_v1.toml")))) ||
        error("Frozen protocol hash differs.")
    manifest["replay_moi_version"] == string(Pkg.dependencies()[Base.PkgId(M).uuid].version) ||
        error("Replay requires the archived MathOptInterface version.")
    return true
end

function cell_record(cell::CompiledCell, gate)
    structure = structural_metrics(cell.polynomial)
    merge!(structure, Dict("source_variables" => length(cell.instance.lower),
        "native_coordinates" => length(cell.maps),
        "target_original_digits" => sum(length(m.positions) for m in cell.maps if m.kind == "original"),
        "target_auxiliaries" => sum(length(m.positions) for m in cell.maps if m.kind == "slack"; init = 0),
        "max_encoding_weight" => maximum((w for m in cell.maps for w in m.weights); init = 0),
        "fixed_variables" => count(==(0), cell.polynomial.upper - cell.polynomial.lower)))
    return Dict{String,Any}("schema_version" => 1, "instance" => instance_record(cell.instance),
        "arm" => cell.arm, "regime" => cell.regime, "weight_cap" => cell.weight_cap,
        "maps" => map_record.(cell.maps), "penalty_rows" => cell.penalty_rows,
        "polynomial" => polynomial_record(cell.polynomial), "compiler" => cell.record,
        "structure" => structure, "preflight" => gate)
end

function cell_from_record(record)
    instance = instance_from_record(record["instance"])
    maps = [CoordinateMap(m["kind"], m["row"], m["lower"], m["upper"], m["offset"],
        Int.(m["positions"]), Int.(m["weights"]), Int.(m["digit_lower"]), Int.(m["digit_upper"]))
        for m in record["maps"]]
    cell = CompiledCell(instance, record["arm"], record["regime"], record["weight_cap"],
        polynomial_from_record(record["polynomial"]), maps,
        Dict{String,Any}[Dict{String,Any}(r) for r in record["penalty_rows"]], native_optimizer(instance),
        Dict{String,Any}(record["compiler"]))
    record["preflight"]["status"] == "passed" || error("Archived cell did not pass preflight.")
    foreach(map -> validate_map(cell, map), cell.maps)
    compare_polynomials(cell.polynomial, reconstructed_polynomial(cell))
    return cell
end

function initial_native(cell::CompiledCell, rng)
    return [rand(rng, ceil(Int, l):floor(Int, u)) for (l, u) in
            zip(cell.oracle.data[:l], cell.oracle.data[:u])]
end

function initializer(cell::CompiledCell)
    if startswith(cell.arm, "toqubo") && cell.regime == "compiler_defaults"
        return rng -> [rand(rng, l:u) for (l, u) in zip(cell.polynomial.lower, cell.polynomial.upper)]
    end
    return rng -> lift_cell(cell, initial_native(cell, rng))
end

function replay_job(root, key)
    occursin(r"^[0-9a-f]{64}$", key) || throw(ArgumentError("Invalid job key."))
    manifest = read_archive(root, "manifest.toml")
    verify_archive_execution(manifest)
    ledger = read_archive(root, "ledger.toml")
    ledger["manifest_hash"] == bytes2hex(SHA.sha256(read(joinpath(root, "manifest.toml")))) ||
        error("Manifest and ledger binding mismatch.")
    entry = only(filter(e -> e["key"] == key, ledger["jobs"]))
    entry["status"] == "complete" || error("Job has no valid replayable trajectory.")
    record = read_archive(root, entry["file"]; expected_hash = entry["hash"])
    cell_data = read_archive(root, record["cell_file"]; expected_hash = record["cell_hash"])
    cell = cell_from_record(cell_data)
    trajectory = record["trajectory"]
    verify_replay_binding(key, record, cell, ledger, root)
    reference = record["reference_objective"]
    replay = metropolis(cell.polynomial, initializer(cell), cell_observer(cell, reference);
        seed = trajectory["seed"], reserved_proposals = trajectory["reserved_proposals"],
        completed_limit = trajectory["completed_proposals"], max_sweeps = trajectory["max_sweeps"],
        max_seconds = Inf, temperature_start = trajectory["temperature_start"],
        temperature_end = trajectory["temperature_end"], energy_scale = trajectory["energy_scale"],
        check_deltas = true)
    for field in ("initial", "final", "samples", "move_counts", "completed_proposals",
                  "source_observations", "best_feasible_objective", "best_feasible_source", "any_feasible",
                  "first_feasible_proposal")
        replay[field] == trajectory[field] || error("Replayed trajectory differs at $field.")
    end
    target_index = trajectory["first_target_proposal"] == "missing" ?
                   trajectory["overshoot_target_proposal"] : trajectory["first_target_proposal"]
    replay["first_target_proposal"] == target_index || error("First target work endpoint differs.")
    # Clock durations/censoring are archived observations, never regenerated from seeds.
    return Dict("key" => key, "status" => "verified", "completed_proposals" => replay["completed_proposals"],
        "source_feasibility_checked" => true, "clock_reproduced" => false)
end

function verify_replay_binding(key, record, cell, ledger, root)
    job, trajectory = record["job"], record["trajectory"]
    unhashed = copy(job)
    pop!(unhashed, "key") == key && record_hash(unhashed) == key || error("Job key binding differs.")
    stage = job["stage"]
    configuration = PROTOCOL[stage]
    job["effective_seed"] == job["replicate_seed"] + 10_000cell.instance.ordinal ||
        error("Effective seed binding differs.")
    job["replicate_seed"] in configuration["replicate_seeds"] || error("Unplanned replicate seed.")
    for field in ("reserved_proposals", "max_sweeps")
        expected = configuration[field == "reserved_proposals" ? "max_proposals" : field]
        trajectory[field] == job[field] == expected || error("Work plan binding differs.")
    end
    trajectory["seed"] == job["effective_seed"] || error("Trajectory seed differs from plan.")
    for field in ("temperature_start", "temperature_end")
        trajectory[field] == PROTOCOL["metropolis"][field] || error("Temperature differs from protocol.")
    end
    scale = max(1, sum(abs(c) * (big(u) - l) for (c, l, u) in
        zip(cell.instance.costs, cell.instance.lower, cell.instance.upper)))
    trajectory["energy_scale"] == Float64(scale) || error("Source-box energy scale differs.")
    job["instance_id"] == cell.instance.id && job["ordinal"] == cell.instance.ordinal &&
        job["arm"] == cell.arm && job["regime"] == cell.regime && job["cap"] == cell.weight_cap ||
        error("Trajectory cell differs from plan.")
    expected = record_hash(Dict("source_hash" => instance_hash(cell.instance),
        "arm" => cell.arm, "regime" => cell.regime, "cap" => cell.weight_cap))
    job["cell_key"] == expected || error("Cell key differs from source/arm binding.")
    binding = only(filter(e -> e["key"] == expected, ledger["cells"]))
    record["cell_file"] == binding["file"] == "cells/" * expected * ".toml" &&
        record["cell_hash"] == binding["hash"] || error("Cell archive binding differs.")
    record["reference_freeze_hash"] == ledger["reference_freeze_hash"] || error("Reference freeze differs.")
    read_archive(root, "reference_freeze.toml"; expected_hash = ledger["reference_freeze_hash"])
    return true
end
