function process_peak_rss_bytes()
    for line in eachline("/proc/self/status")
        startswith(line, "VmHWM:") && return 1024parse(Int, split(line)[2])
    end
    return "not-available"
end

function resource_enforcement()
    Threads.nthreads() == 1 && LinearAlgebra.BLAS.get_num_threads() == 1 ||
        error("The frozen experiment requires one Julia/BLAS thread.")
    line = only(filter(l -> startswith(l, "0::"), readlines("/proc/self/cgroup")))
    relative = split(line, ':'; limit = 3)[3]
    path = joinpath("/sys/fs/cgroup", lstrip(relative, '/'))
    memory, swap = big(typemax(Int)), big(typemax(Int))
    while startswith(path, "/sys/fs/cgroup")
        for (file, kind) in (("memory.max", "memory"), ("memory.swap.max", "swap"))
            full = joinpath(path, file)
            isfile(full) || continue
            value = strip(read(full, String))
            value == "max" && continue
            kind == "memory" ? (memory = min(memory, parse(BigInt, value))) :
                               (swap = min(swap, parse(BigInt, value)))
        end
        path == "/sys/fs/cgroup" && break
        path = dirname(path)
    end
    memory <= PROTOCOL["resources"]["memory_bytes"] && swap == 0 ||
        error("Run under an OS scope with MemoryMax=4G and MemorySwapMax=0.")
    return Dict("resident_memory_limit_bytes" => Int(memory), "swap_limit_bytes" => 0,
                "julia_threads" => Threads.nthreads(), "blas_threads" => LinearAlgebra.BLAS.get_num_threads())
end

boot_fingerprint() = bytes2hex(SHA.sha256(read("/proc/sys/kernel/random/boot_id")))
function campaign_hashes()
    files = ["CQTExperiment.jl", "toqubo_adapter.jl", "reference.jl", "runner.jl", "run.jl"]
    return Dict(file => bytes2hex(SHA.sha256(read(joinpath(@__DIR__, file)))) for file in files)
end

function dependency_record()
    return [Dict("name" => p.name, "uuid" => string(uuid),
        "version" => isnothing(p.version) ? "stdlib" : string(p.version),
        "tree_hash" => isnothing(p.tree_hash) ? "not-recorded" : string(p.tree_hash),
        "git_revision" => isnothing(p.git_revision) ? "registry-or-stdlib" : p.git_revision)
        for (uuid, p) in sort(collect(Pkg.dependencies()); by = pair -> last(pair).name)]
end

function checkpoint!(root, ledger)
    elapsed = (time_ns() - ledger["started_monotonic_ns"]) / 1.0e9
    elapsed <= PROTOCOL["resources"]["campaign_wall_seconds"] ||
        error("Campaign wall allowance exhausted; retain incomplete evidence.")
    ledger["elapsed_seconds"] = elapsed
    peak = process_peak_rss_bytes()
    ledger["process_peak_rss_bytes"] = max(get(ledger, "process_peak_rss_bytes", 0), peak)
    ledger["invocations"][end]["peak_rss_bytes"] = peak
    return write_archive(root, "ledger.toml", ledger; replace = true)
end

function open_campaign(root, mode)
    opened_ns = Int(time_ns())
    mode in ("smoke", "preflight", "campaign") || throw(ArgumentError("Unknown runner mode."))
    enforcement = resource_enforcement()
    verify_dependency_pins()
    Base.pathof(ToQUIO) == joinpath(ROOT, "src", "ToQUIO.jl") || error("Benchmark loaded another ToQUIO checkout.")
    isdir(root) || mkpath(root)
    manifest_path = safe_artifact_path(root, "manifest.toml")
    if isfile(manifest_path)
        manifest = read_archive(root, "manifest.toml")
        manifest["owner"] == "cqt-y4-runner-v1" && manifest["mode"] == mode || error("Different artifact owner/mode.")
        verify_archive_execution(manifest)
        manifest["campaign_hashes"] == campaign_hashes() || error("Campaign executable hashes differ.")
        ledger = read_archive(root, "ledger.toml")
        haskey(ledger, "correctness_failure") && error("Prior correctness failure; campaign cannot resume.")
        manifest["dependencies"] == dependency_record() || error("Resolved dependencies changed on resume.")
        for name in ("Project.toml", "Manifest.toml")
            read(joinpath(root, name)) == read(joinpath(@__DIR__, name)) ||
                error("Experiment environment bytes changed on resume.")
        end
        push!(ledger["invocations"], Dict("enforcement" => enforcement, "peak_rss_bytes" => 0))
        ledger["manifest_hash"] == bytes2hex(SHA.sha256(read(manifest_path))) || error("Manifest binding mismatch.")
        ledger["boot_fingerprint"] == boot_fingerprint() || error("Cannot resume accounting across clock origins.")
        checkpoint!(root, ledger)
        return manifest, ledger, instance_from_record.(manifest["instances"])
    end
    isempty(readdir(root)) || error("Refusing to overwrite a nonempty foreign artifact directory.")
    instances = corpus(PROTOCOL)
    verify_corpus_hashes(instances)
    manifest = Dict{String,Any}("schema_version" => 1, "owner" => "cqt-y4-runner-v1", "mode" => mode,
        "julia_version" => string(VERSION), "machine" => Sys.MACHINE,
        "replay_moi_version" => string(Pkg.dependencies()[Base.PkgId(M).uuid].version),
        "source_revision" => readchomp(Cmd(["git", "-C", ROOT, "rev-parse", "HEAD"])),
        "source_status" => readchomp(Cmd(["git", "-C", ROOT, "status", "--porcelain", "--", "src", "benchmarks"])),
        "execution_hashes" => execution_hashes(), "campaign_hashes" => campaign_hashes(),
        "protocol_hash" => bytes2hex(SHA.sha256(read(joinpath(@__DIR__, "protocol_v1.toml")))),
        "study_hash" => bytes2hex(SHA.sha256(read(joinpath(ROOT, "docs", "src", "study.md")))),
        "instances" => instance_record.(instances), "instance_hashes" => instance_hash.(instances),
        "dependencies" => dependency_record(), "enforcement" => enforcement,
        "planned_starts" => mode == "campaign" ? 680 : mode == "smoke" ? 40 : 0,
        "planned_reserved_proposals" => mode == "campaign" ? 5_325_120 : mode == "smoke" ? 5120 : 0,
        "resources" => PROTOCOL["resources"], "statistics" => PROTOCOL["statistics"],
        "physical_device_model" => false)
    manifest_hash = write_archive(root, "manifest.toml", manifest)
    # Freeze concrete generators and hashes before compilation or reference solving.
    write_archive(root, "protocol.toml", PROTOCOL)
    write_archive_bytes(root, "Manifest.toml", read(joinpath(@__DIR__, "Manifest.toml")))
    write_archive_bytes(root, "Project.toml", read(joinpath(@__DIR__, "Project.toml")))
    ledger = Dict{String,Any}("schema_version" => 1, "manifest_hash" => manifest_hash,
        "boot_fingerprint" => boot_fingerprint(), "started_monotonic_ns" => opened_ns,
        "status" => "prepared", "sampler_starts_reserved" => 0, "proposals_reserved" => 0,
        "enumeration_states_reserved" => 0, "jobs" => Dict{String,Any}[],
        "references" => Dict{String,Any}[], "cells" => Dict{String,Any}[],
        "elapsed_seconds" => 0.0, "errors" => String[],
        "invocations" => [Dict("enforcement" => enforcement, "peak_rss_bytes" => 0)])
    checkpoint!(root, ledger)
    return manifest, ledger, instances
end

function freeze_references!(root, ledger, instances, mode)
    selected = mode == "smoke" ? filter(i -> i.stage == "pilot", instances) : instances
    results = Dict{String,Any}()
    for instance in selected
        found = findfirst(e -> e["source_hash"] == instance_hash(instance), ledger["references"])
        if !isnothing(found)
            entry = ledger["references"][found]
            entry["status"] == "complete" || error("Prior incomplete reference attempt cannot be retried.")
            reference = read_archive(root, entry["file"]; expected_hash = entry["hash"])
        else
            entry = Dict{String,Any}("source_hash" => instance_hash(instance), "status" => "reserved")
            push!(ledger["references"], entry)
            checkpoint!(root, ledger) # One reference attempt per source; crashes remain visible.
            if instance.stage == "pilot"
                count = prod(big(u) - l + 1 for (l, u) in zip(instance.lower, instance.upper); init = big(1))
                budget = EnumerationBudget(1_000_000, 4_000_000, ledger["enumeration_states_reserved"])
                reserve_enumeration!(budget, count)
                ledger["enumeration_states_reserved"] = budget.reserved
                checkpoint!(root, ledger)
                reference = exact_reference(instance)
            else
                reference = try
                    highs_reference(instance)
                catch exception
                    Dict{String,Any}("status" => "ERROR", "error" => sprint(showerror, exception),
                        "source_hash" => instance_hash(instance), "source_feasible" => false,
                        "point" => Float64[], "objective" => "missing", "objective_bound" => "missing")
                end
            end
            file = "references/" * instance_hash(instance) * ".toml"
            entry["hash"] = write_archive(root, file, reference)
            valid = !isempty(reference["point"]) && get(reference, "source_feasible", true)
            entry["file"], entry["status"] = file, valid ? "complete" : "failed"
            checkpoint!(root, ledger)
            valid || error("Missing valid bounded reference; failed evidence retained, campaign incomplete.")
        end
        reference["source_hash"] == instance_hash(instance) || error("Reference source binding mismatch.")
        source_feasible(instance, reference["point"]; atol = PROTOCOL["source_feasibility_atol"]) ||
            error("Frozen reference point is not source feasible.")
        results[instance.id] = reference
    end
    freeze = Dict("references" => deepcopy(ledger["references"]), "status" => "frozen-before-tuning")
    ledger["reference_freeze_hash"] = write_archive(root, "reference_freeze.toml", freeze)
    checkpoint!(root, ledger)
    return results
end

cell_key(instance, arm, regime, cap) = record_hash(Dict("source_hash" => instance_hash(instance),
    "arm" => arm, "regime" => regime, "cap" => cap))

function prepare_cells!(root, ledger, instances, references, mode)
    selected = mode == "smoke" ? filter(i -> i.stage == "pilot", instances) : instances
    cells = Dict{String,CompiledCell}()
    for instance in selected
        oracle = native_optimizer(instance)
        for arm in PROTOCOL["arms"], regime in PROTOCOL["regimes"]
            caps = instance.stage == "pilot" ? [arm in ("bounded", "toqubo_bounded_shim") ? 2 : 0] :
                   arm in ("bounded", "toqubo_bounded_shim") ? PROTOCOL["bounded_weight_candidates"] : [0]
            for cap in caps
                key = cell_key(instance, arm, regime, cap)
                found = findfirst(e -> e["key"] == key, ledger["cells"])
                if !isnothing(found)
                    entry = ledger["cells"][found]
                    entry["status"] == "passed" || error("Prior failed/interrupted preflight cannot be retried.")
                    cell = cell_from_record(read_archive(root, entry["file"]; expected_hash = entry["hash"]))
                else
                    entry = Dict{String,Any}("key" => key, "status" => "reserved",
                        "source_hash" => instance_hash(instance), "arm" => arm, "regime" => regime, "cap" => cap)
                    push!(ledger["cells"], entry)
                    checkpoint!(root, ledger)
                    try
                        cell = startswith(arm, "toqubo") ? compile_toqubo(instance, arm, regime; cap, oracle) :
                               compile_quio(instance, arm, regime; cap, oracle)
                        budget = EnumerationBudget(1_000_000, 4_000_000, ledger["enumeration_states_reserved"])
                        function reserve_hook()
                            ledger["enumeration_states_reserved"] = budget.reserved
                            checkpoint!(root, ledger)
                        end
                        gate = preflight(cell, references[instance.id]; budget,
                            exhaustive = instance.stage == "pilot", reservation_hook = reserve_hook)
                        file = "cells/" * key * ".toml"
                        entry["hash"] = write_archive(root, file, cell_record(cell, gate))
                        entry["file"], entry["status"] = file, "passed"
                        checkpoint!(root, ledger)
                    catch exception
                        entry["status"] = "failed"
                        entry["error"] = sprint(showerror, exception)
                        checkpoint!(root, ledger)
                        rethrow()
                    end
                end
                cells[key] = cell
                println("preflight passed: ", instance.id, " / ", arm, " / ", regime, " / cap=", cap)
            end
        end
    end
    ledger["status"] = "preflight-complete"
    checkpoint!(root, ledger)
    return cells
end

function stage_jobs(instances, stage, selected_caps)
    configuration = PROTOCOL[stage]
    sources = filter(i -> i.stage == (stage in ("warmup", "pilot") ? "pilot" : stage), instances)
    arms = stage == "tuning" ? configuration["arms"] : PROTOCOL["arms"]
    regimes = stage == "tuning" ? [configuration["regime"]] : PROTOCOL["regimes"]
    jobs = Dict{String,Any}[]
    for instance in sources, arm in arms, regime in regimes
        bounded = arm in ("bounded", "toqubo_bounded_shim")
        caps = stage == "tuning" ? PROTOCOL["bounded_weight_candidates"] :
               [bounded ? (stage == "evaluation" ? selected_caps[arm] : 2) : 0]
        for cap in caps, replicate in configuration["replicate_seeds"]
            seed = replicate + 10_000instance.ordinal
            job = Dict{String,Any}("instance_id" => instance.id, "source_hash" => instance_hash(instance),
                "family" => instance.family, "ordinal" => instance.ordinal, "stage" => stage,
                "arm" => arm, "regime" => regime, "cap" => cap, "replicate_seed" => replicate,
                "effective_seed" => seed, "reserved_proposals" => configuration["max_proposals"],
                "max_sweeps" => configuration["max_sweeps"],
                "cell_key" => cell_key(instance, arm, regime, cap))
            job["key"] = record_hash(job)
            push!(jobs, job)
        end
    end
    length(jobs) == configuration["starts"] || error("Frozen stage plan count changed.")
    return jobs
end

function warm_build_timings!(root, ledger, cells, instances)
    bindings = get!(ledger, "warm_timings", Dict{String,Any}())
    for instance in instances
        relevant = sort([key for (key, cell) in cells if cell.instance.id == instance.id])
        isempty(relevant) && continue
        oracle = native_optimizer(instance)
        for key in relevant
            if haskey(bindings, key)
                read_archive(root, bindings[key]["file"]; expected_hash = bindings[key]["hash"])
                continue
            end
            original = cells[key]
            rebuilt = startswith(original.arm, "toqubo") ?
                compile_toqubo(instance, original.arm, original.regime; cap = original.weight_cap, oracle) :
                compile_quio(instance, original.arm, original.regime; cap = original.weight_cap, oracle)
            compare_polynomials(original.polynomial, rebuilt.polynomial)
            map_record.(original.maps) == map_record.(rebuilt.maps) || error("Warm compilation changed emitted maps.")
            file = "warm_timings/" * key * ".toml"
            data = Dict("phase" => "after-all-pilot-sampler-warmups", "compiler" => rebuilt.record,
                        "compiled_cell_key" => key, "shared_setup_is_additive" => false)
            bindings[key] = Dict("file" => file, "hash" => write_archive(root, file, data))
            checkpoint!(root, ledger)
        end
    end
    return bindings
end

function invalid_trajectory(job, reason)
    return Dict{String,Any}("invalid_run" => true, "reason" => reason, "any_feasible" => false,
        "timely_target" => false, "best_feasible_objective" => "missing", "best_feasible_source" => Int[],
        "first_target_seconds" => "missing", "first_target_proposal" => "missing",
        "elapsed_seconds" => "missing", "completed_proposals" => "unknown",
        "target_time_score" => PROTOCOL["metropolis"]["max_seconds_per_run"],
        "target_work_score" => job["reserved_proposals"], "termination" => "invalid-planned-run")
end

function store_invalid!(root, ledger, entry, job, reason)
    record = Dict("status" => "invalid", "job" => job, "key" => job["key"],
        "trajectory" => invalid_trajectory(job, reason), "retained_prior_file" => get(entry, "file", "missing"),
        "retained_prior_hash" => get(entry, "hash", "missing"))
    file = "jobs/" * job["key"] * ".invalid.toml"
    hash = write_archive(root, file, record)
    entry["status"], entry["file"], entry["hash"] = "invalid", file, hash
    checkpoint!(root, ledger)
    return record
end

function execute_job!(root, ledger, job, cells, references)
    found = findfirst(e -> e["key"] == job["key"], ledger["jobs"])
    if !isnothing(found)
        entry = ledger["jobs"][found]
        if entry["status"] == "reserved"
            return store_invalid!(root, ledger, entry, job, "interrupted-after-reservation-no-rerun")
        end
        try
            return read_archive(root, entry["file"]; expected_hash = entry["hash"])
        catch exception
            entry["status"] == "invalid" && rethrow()
            reason = "corrupted-or-missing-trajectory: " * sprint(showerror, exception)
            return store_invalid!(root, ledger, entry, job, reason)
        end
    end
    ledger["sampler_starts_reserved"] + 1 <= PROTOCOL["resources"]["max_sampler_starts"] ||
        error("Sampler start allowance exhausted; campaign incomplete.")
    big(ledger["proposals_reserved"]) + job["reserved_proposals"] <=
        PROTOCOL["resources"]["max_reserved_proposals"] || error("Proposal allowance exhausted; campaign incomplete.")
    ledger["sampler_starts_reserved"] += 1
    ledger["proposals_reserved"] += job["reserved_proposals"]
    entry = Dict{String,Any}("key" => job["key"], "status" => "reserved", "stage" => job["stage"],
        "reserved_proposals" => job["reserved_proposals"])
    push!(ledger["jobs"], entry)
    checkpoint!(root, ledger) # Reserve before any sampler dispatch; never replenish on resume.
    cell = cells[job["cell_key"]]
    cell_entry = only(filter(e -> e["key"] == job["cell_key"], ledger["cells"]))
    reference = Float64(references[cell.instance.id]["objective"])
    scale = max(1, sum(abs(c) * (big(u) - l) for (c, l, u) in
        zip(cell.instance.costs, cell.instance.lower, cell.instance.upper)))
    trajectory = try
        metropolis(cell.polynomial, initializer(cell), cell_observer(cell, reference);
            seed = job["effective_seed"], reserved_proposals = job["reserved_proposals"],
            max_sweeps = job["max_sweeps"], max_seconds = PROTOCOL["metropolis"]["max_seconds_per_run"],
            temperature_start = PROTOCOL["metropolis"]["temperature_start"],
            temperature_end = PROTOCOL["metropolis"]["temperature_end"], energy_scale = Float64(scale))
    catch exception
        exception isa InterruptException && rethrow()
        if exception isa VerificationError || exception isa AssertionError || exception isa ArgumentError
            ledger["correctness_failure"] = sprint(showerror, exception)
            checkpoint!(root, ledger)
            rethrow()
        end
        return store_invalid!(root, ledger, entry, job, sprint(showerror, exception))
    end
    # Archive and quota failures propagate as incomplete campaigns. They must
    # not manufacture a sampler failure or discard a completed trajectory.
    trajectory["invalid_run"] = false
    if trajectory["any_feasible"]
        sigma = cell.instance.sense == "min" ? 1 : -1
        trajectory["signed_gap"] = sigma * (trajectory["best_feasible_objective"] - reference) /
                                   max(1, abs(reference))
    else
        trajectory["signed_gap"] = "missing"
    end
    timing = cell.record
    timing_phase = "preflight-build-warmup-only"
    if haskey(get(ledger, "warm_timings", Dict()), job["cell_key"])
        binding = ledger["warm_timings"][job["cell_key"]]
        timing = read_archive(root, binding["file"]; expected_hash = binding["hash"])["compiler"]
        timing_phase = "warm-build"
    end
    shared = timing["shared_native_timing"]
    shared_seconds = startswith(cell.arm, "toqubo") && cell.regime == "compiler_defaults" ? 0.0 :
                     shared["construction_seconds"] + shared["native_reformulation_seconds"]
    record = Dict{String,Any}("schema_version" => 1, "status" => "complete", "key" => job["key"],
        "job" => job, "trajectory" => trajectory, "cell_file" => cell_entry["file"],
        "cell_hash" => cell_entry["hash"], "reference_objective" => reference,
        "reference_freeze_hash" => ledger["reference_freeze_hash"],
        "calibration_repeat" => !startswith(cell.arm, "toqubo") && cell.regime == "compiler_defaults",
        "calibration_repeat_of_regime" => !startswith(cell.arm, "toqubo") ? "controlled" : "not-applicable",
        "timing_phase" => timing_phase, "shared_native_setup_seconds" => shared_seconds,
        "own_build_seconds" => timing["build_seconds"],
        "end_to_end_seconds" => shared_seconds + timing["build_seconds"] + trajectory["elapsed_seconds"],
        "shared_setup_scope" => "once-per-instance-not-additive-across-arms")
    file = "jobs/" * job["key"] * ".toml"
    hash = write_archive(root, file, record)
    entry["file"], entry["hash"], entry["status"] = file, hash, "complete"
    checkpoint!(root, ledger)
    return record
end

function select_caps(root, ledger, instances)
    selected, scores = Dict{String,Int}(), Dict{String,Any}[]
    for arm in PROTOCOL["tuning"]["arms"]
        choices = Tuple{Float64,Float64,Int}[]
        for cap in PROTOCOL["bounded_weight_candidates"]
            planned = filter(j -> j["arm"] == arm && j["cap"] == cap,
                stage_jobs(instances, "tuning", Dict{String,Int}()))
            success, times = 0, 0.0
            for job in planned
                entry = only(filter(e -> e["key"] == job["key"], ledger["jobs"]))
                entry["status"] in ("complete", "invalid") || error("Incomplete tuning; no cap selection.")
                result = read_archive(root, entry["file"]; expected_hash = entry["hash"])["trajectory"]
                success += result["timely_target"]
                times += result["target_time_score"]
            end
            length(planned) == 20 || error("Tuning must retain all five planned replicates per instance.")
            push!(choices, (-success / 20, times / 20, cap))
            push!(scores, Dict("arm" => arm, "cap" => cap, "success_fraction" => success / 20,
                               "mean_capped_target_time" => times / 20, "planned_runs" => 20))
        end
        selected[arm] = last(minimum(choices))
    end
    return Dict("selected" => selected, "scores" => scores,
        "policy" => PROTOCOL["tuning"]["selection"], "status" => "frozen-before-evaluation")
end

function process_identity(pid)
    pid isa Integer && pid > 0 || error("Invalid lock process identity.")
    file = "/proc/$pid/stat"
    isfile(file) || return nothing
    text = read(file, String)
    return split(text[(findlast(')', text) + 2):end])[20]
end

function acquire_campaign_lock(root)
    lock = root * ".running"
    if isdir(lock)
        readdir(lock) == ["owner.toml"] || error("Unrecognized lock contents retained.")
        owner = TOML.parsefile(joinpath(lock, "owner.toml"))
        owner["owner"] == "cqt-y4-runner-v1" || error("Foreign lock retained.")
        process_identity(owner["pid"]) == owner["process_start"] && error("Campaign process is still live.")
        rm(joinpath(lock, "owner.toml"))
        rm(lock)
    end
    mkdir(lock) # Atomic exclusion: a second invocation must not duplicate dispatch.
    open(joinpath(lock, "owner.toml"), "w") do io
        TOML.print(io, Dict("owner" => "cqt-y4-runner-v1", "pid" => getpid(),
                            "process_start" => process_identity(getpid())))
    end
    return lock
end

function run_campaign(root; mode = "smoke")
    root = abspath(root)
    mkpath(dirname(root))
    lock = acquire_campaign_lock(root)
    ledger = nothing
    try
        manifest, ledger, instances = open_campaign(root, mode)
        references = freeze_references!(root, ledger, instances, mode)
        cells = prepare_cells!(root, ledger, instances, references, mode)
        if mode == "preflight"
            ledger["status"] = "preflight-only-complete-no-sampler-results"
            checkpoint!(root, ledger)
            return ledger
        end
        stages = mode == "smoke" ? ["warmup"] : ["warmup", "pilot", "tuning", "evaluation"]
        order_rng = MersenneTwister(PROTOCOL["metropolis"]["run_order_seed"])
        selected_caps = Dict{String,Int}()
        for stage in stages
            jobs = stage_jobs(instances, stage, selected_caps)
            shuffle!(order_rng, jobs)
            order_file = "orders/" * stage * ".toml"
            write_archive(root, order_file, Dict("seed" => PROTOCOL["metropolis"]["run_order_seed"],
                "stage" => stage, "jobs" => jobs))
            for job in jobs
                result = execute_job!(root, ledger, job, cells, references)
                println("job ", stage, " ", job["instance_id"], " / ", job["arm"], " / ",
                    job["regime"], " / cap=", job["cap"], ": ", result["status"])
            end
            stage == "warmup" && warm_build_timings!(root, ledger, cells, instances)
            if stage == "tuning"
                selection = select_caps(root, ledger, instances)
                selected_caps = selection["selected"]
                ledger["selection_hash"] = write_archive(root, "selection.toml", selection)
                checkpoint!(root, ledger)
            end
        end
        ledger["sampler_starts_reserved"] == manifest["planned_starts"] &&
            ledger["proposals_reserved"] == manifest["planned_reserved_proposals"] ||
            error("Incomplete planned campaign ledger; no completed-campaign aggregate.")
        all(e["status"] in ("complete", "invalid") for e in ledger["jobs"]) || error("Unaccounted planned job.")
        ledger["status"] = mode == "smoke" ? "smoke-only-complete-no-performance-conclusion" : "campaign-complete"
        checkpoint!(root, ledger)
        return ledger
    catch exception
        if !isnothing(ledger)
            ledger["status"] = "incomplete"
            push!(ledger["errors"], sprint(showerror, exception))
            # This final checkpoint preserves failure even after the wall limit.
            write_archive(root, "ledger.toml", ledger; replace = true)
        end
        rethrow()
    finally
        rm(joinpath(lock, "owner.toml"))
        rm(lock)
    end
end
