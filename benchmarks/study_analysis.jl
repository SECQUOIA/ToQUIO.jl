# Protocol-v1 descriptive comparisons. Instances are the outer sampling unit;
# the same restart IDs are resampled together within a paired instance.
mean_or_missing(values) = isempty(values) ? "missing" : sum(values) / length(values)

function percentile(values, probability)
    isempty(values) && return "missing"
    ordered = sort(values)
    position = 1 + probability * (length(ordered) - 1)
    lower, upper = floor(Int, position), ceil(Int, position)
    return ordered[lower] + (position - lower) * (ordered[upper] - ordered[lower])
end

function sign_flip_sensitivity(differences)
    observed = Float64[d for d in differences if d != "missing"]
    n = length(observed)
    n <= 8 || error("Sign-flip enumeration exceeds the frozen eight-instance scope.")
    n == 0 && return Dict("n" => 0, "assignments" => 0, "p" => "missing")
    actual = abs(sum(observed))
    # Each signed sum has at most n rounding steps. Bound the error of both
    # compared sums conservatively at this data's scale, rather than applying
    # a statistical tolerance that would include genuinely interior outcomes.
    roundoff = 2n * eps(Float64) * sum(abs, observed)
    extreme = 0
    for mask in 0:(2^n - 1)
        flipped = sum([((mask >> (i - 1)) & 1 == 1 ? -1 : 1) * observed[i] for i in 1:n])
        extreme += abs(flipped) >= actual ||
            isapprox(abs(flipped), actual; atol = roundoff, rtol = 0)
    end
    return Dict("n" => n, "assignments" => 2^n, "p" => extreme / 2^n,
                "tie_absolute_tolerance" => roundoff,
                "interpretation" => "exchangeable-sign-sensitivity-not-confirmatory")
end

function run_endpoint(record, endpoint)
    trajectory = record["trajectory"]
    endpoint == "feasibility" && return Float64(trajectory["any_feasible"])
    endpoint == "target_time_score" && return trajectory["target_time_score"]
    endpoint == "target_work_score" && return trajectory["target_work_score"]
    endpoint == "signed_gap" && return get(trajectory, "signed_gap", "missing")
    error("Unknown frozen endpoint.")
end

function pair_differences(left, right, endpoint, restart_indices = 1:5)
    values = Float64[]
    for index in restart_indices
        a, b = left[index], right[index]
        if endpoint == "signed_gap"
            a["trajectory"]["any_feasible"] && b["trajectory"]["any_feasible"] || continue
        end
        x, y = run_endpoint(a, endpoint), run_endpoint(b, endpoint)
        x == "missing" || y == "missing" || push!(values, x - y)
    end
    # Clock data missingness invalidates an all-five time-score comparison.
    endpoint == "target_time_score" && length(values) != length(restart_indices) &&
        return (difference = "missing", paired_restarts = length(values))
    return (difference = mean_or_missing(values), paired_restarts = length(values))
end

function paired_contrast(pairs, endpoint; bootstrap_replicates = 2000, seed = 99001)
    length(pairs) == 8 || error("A complete contrast requires eight held-out instances.")
    all(length(p.left) == length(p.right) == 5 for p in pairs) || error("Missing planned restart.")
    observed = [pair_differences(p.left, p.right, endpoint) for p in pairs]
    differences = [p.difference for p in observed]
    families = sort(unique(p.family for p in pairs))
    strata = [[p for p in pairs if p.family == family] for family in families]
    length(strata) == 4 && all(length(s) == 2 for s in strata) || error("Frozen family strata differ.")
    rng = MersenneTwister(seed)
    draws = Float64[]
    for _ in 1:bootstrap_replicates
        instance_means = Float64[]
        for stratum in strata, _ in 1:length(stratum)
            pair = stratum[rand(rng, 1:length(stratum))]
            restart_indices = rand(rng, 1:5, 5)
            estimate = pair_differences(pair.left, pair.right, endpoint, restart_indices)
            estimate.difference == "missing" || push!(instance_means, estimate.difference)
        end
        isempty(instance_means) || push!(draws, sum(instance_means) / length(instance_means))
    end
    incomplete_time = endpoint == "target_time_score" && any(==("missing"), differences)
    return Dict("endpoint" => endpoint,
        "instance_differences" => [Dict("instance_id" => p.id, "family" => p.family,
            "difference" => o.difference, "paired_restarts" => o.paired_restarts) for (p, o) in zip(pairs, observed)],
        "mean_difference" => incomplete_time ? "missing" : mean_or_missing(filter(!=("missing"), differences)),
        "interval" => incomplete_time ? ["missing", "missing"] :
                      [percentile(draws, 0.025), percentile(draws, 0.975)],
        "bootstrap_replicates" => bootstrap_replicates, "valid_bootstrap_replicates" => length(draws),
        "bootstrap_seed" => seed, "confidence" => 0.95,
        "sign_flip" => incomplete_time ? Dict("p" => "missing", "n" => 0, "assignments" => 0) :
                       sign_flip_sensitivity(differences),
        "incomplete_time_comparison" => incomplete_time,
        "interpretation" => "descriptive-exploratory-nested-instance-bootstrap-no-multiplicity-control")
end

function source_target_predicate(instance, reference)
    # Reuse the actual runner observer, rather than duplicating its tolerance.
    cell = compile_quio(instance, "native", "controlled")
    observe = cell_observer(cell, reference["objective"])
    return point -> observe(reference_lift(cell, point)).target
end

function validate_trajectory_scores(record, reference, instance; target_predicate = nothing)
    t = record["trajectory"]
    cap = record["job"]["reserved_proposals"]
    if record["status"] == "invalid"
        !t["any_feasible"] && !t["timely_target"] && t["target_time_score"] == 2.0 &&
            t["target_work_score"] == cap && get(t, "signed_gap", "missing") == "missing" ||
            error("Invalid run did not retain frozen failure scores.")
        return true
    end
    record["reference_objective"] == reference["objective"] || error("Run reference objective differs.")
    expected_gap = "missing"
    if t["any_feasible"]
        point = t["best_feasible_source"]
        source_feasible(instance, point; atol = 0) || error("Best point violates the source.")
        value = source_value(instance, point)
        value == t["best_feasible_objective"] || error("Best objective differs from source point.")
        sigma = instance.sense == "min" ? 1 : -1
        expected_gap = sigma * (value - reference["objective"]) / max(1, abs(reference["objective"]))
    end
    get(t, "signed_gap", "missing") == expected_gap || error("Signed gap differs from frozen reference.")
    reaches_target = false
    if t["any_feasible"]
        isnothing(target_predicate) && (target_predicate = source_target_predicate(instance, reference))
        reaches_target = target_predicate(t["best_feasible_source"])
    end
    hit = t["first_target_seconds"] != "missing"
    hit == t["timely_target"] || error("Timely-target flag differs from observed hit.")
    if hit
        reaches_target && isfinite(t["first_target_seconds"]) &&
            0 <= t["first_target_seconds"] <= PROTOCOL["metropolis"]["max_seconds_per_run"] &&
            t["first_target_proposal"] isa Integer &&
            0 <= t["first_target_proposal"] <= t["completed_proposals"] || error("Invalid first-hit fields.")
    else
        t["first_target_proposal"] == "missing" || error("Unobserved hit has a proposal index.")
        if reaches_target
            overshoot = get(t, "overshoot_target_proposal", "missing")
            overshoot isa Integer && 0 <= overshoot <= t["completed_proposals"] ||
                error("A best point reaching the target needs a timely hit or recorded overshoot.")
        end
    end
    expected_time = hit ? t["first_target_seconds"] : PROTOCOL["metropolis"]["max_seconds_per_run"]
    expected_work = hit ? t["first_target_proposal"] : cap
    t["target_time_score"] == expected_time && t["target_work_score"] == expected_work ||
        error("Target scores differ from observed hit/failure rule.")
    return true
end

function load_complete_campaign(root)
    manifest, ledger = read_archive(root, "manifest.toml"), read_archive(root, "ledger.toml")
    verify_archive_execution(manifest)
    manifest["campaign_hashes"] == campaign_hashes() || error("Frozen campaign source hashes differ.")
    ledger["manifest_hash"] == bytes2hex(SHA.sha256(read(joinpath(root, "manifest.toml")))) ||
        error("Campaign manifest/ledger binding differs.")
    ledger["status"] == "campaign-complete" && manifest["mode"] == "campaign" ||
        error("Incomplete/smoke evidence cannot produce a completed-campaign report.")
    ledger["sampler_starts_reserved"] == 680 && ledger["proposals_reserved"] == 5_325_120 ||
        error("Campaign reservation totals differ from the frozen plan.")
    length(ledger["jobs"]) == 680 && length(unique(e["key"] for e in ledger["jobs"])) == 680 ||
        error("Missing or duplicate planned job.")
    records = [read_archive(root, e["file"]; expected_hash = e["hash"]) for e in ledger["jobs"]]
    all(r["status"] in ("complete", "invalid") for r in records) || error("Unaccounted job status.")
    selection = read_archive(root, "selection.toml"; expected_hash = ledger["selection_hash"])
    instances = instance_from_record.(manifest["instances"])
    verify_corpus_hashes(instances)
    expected = Dict{String,Any}()
    for stage in ("warmup", "pilot", "tuning", "evaluation")
        order = read_archive(root, "orders/" * stage * ".toml")
        planned = stage_jobs(instances, stage, selection["selected"])
        Dict(j["key"] => j for j in order["jobs"]) == Dict(j["key"] => j for j in planned) ||
            error("Archived stage order differs from the frozen source/seed/work plan.")
        merge!(expected, Dict(j["key"] => j for j in planned))
    end
    Set(keys(expected)) == Set(r["key"] for r in records) || error("Run records differ from archived stage plans.")
    references = Dict{String,Any}()
    freeze = read_archive(root, "reference_freeze.toml"; expected_hash = ledger["reference_freeze_hash"])
    freeze["references"] == ledger["references"] || error("Ledger references differ from frozen references.")
    all(e["status"] == "complete" for e in freeze["references"]) || error("Incomplete frozen reference.")
    for entry in ledger["references"]
        reference = read_archive(root, entry["file"]; expected_hash = entry["hash"])
        reference["source_hash"] == entry["source_hash"] || error("Reference source binding differs.")
        references[entry["source_hash"]] = reference
    end
    predicates = Dict{String,Any}()
    for record in records
        record["job"] == expected[record["key"]] || error("Trajectory job differs from frozen plan.")
        instance = only(filter(i -> i.id == record["job"]["instance_id"], instances))
        if record["status"] == "complete"
            record["reference_freeze_hash"] == ledger["reference_freeze_hash"] || error("Run reference freeze differs.")
        end
        hash = instance_hash(instance)
        predicate = get!(predicates, hash) do
            source_target_predicate(instance, references[hash])
        end
        validate_trajectory_scores(record, references[hash], instance; target_predicate = predicate)
    end
    return (manifest = manifest, ledger = ledger, records = records, selection = selection, instances = instances)
end

function evaluation_pairs(campaign, left_arm, right_arm, regime)
    pairs = NamedTuple[]
    for instance in filter(i -> i.stage == "evaluation", campaign.instances)
        function arm_records(arm)
            records = filter(r -> r["job"]["stage"] == "evaluation" &&
                r["job"]["instance_id"] == instance.id && r["job"]["arm"] == arm &&
                r["job"]["regime"] == regime, campaign.records)
            sort!(records; by = r -> r["job"]["replicate_seed"])
            [r["job"]["replicate_seed"] for r in records] == PROTOCOL["evaluation"]["replicate_seeds"] ||
                error("Evaluation pairing does not contain all five planned restart IDs.")
            return records
        end
        push!(pairs, (id = instance.id, family = instance.family,
                      left = arm_records(left_arm), right = arm_records(right_arm)))
    end
    return pairs
end

function study_statistics(campaign)
    contrasts = Dict{String,Any}[]
    for regime in PROTOCOL["regimes"], (left, right) in
        (("radix", "native"), ("bounded", "native"), ("toqubo_binary", "native"),
         ("toqubo_bounded_shim", "toqubo_binary"))
        pairs = evaluation_pairs(campaign, left, right, regime)
        push!(contrasts, Dict("name" => left * "-" * right, "regime" => regime,
            "primary" => regime == "controlled" && left in ("radix", "bounded"),
            "endpoints" => [paired_contrast(pairs, endpoint;
                bootstrap_replicates = PROTOCOL["statistics"]["bootstrap_replicates"],
                seed = PROTOCOL["statistics"]["bootstrap_seed"]) for endpoint in
                ("feasibility", "signed_gap", "target_time_score", "target_work_score")]))
    end
    return Dict("protocol_id" => PROTOCOL["protocol_id"], "contrasts" => contrasts,
        "evaluation_instances" => 8, "planned_restarts_per_cell" => 5,
        "gap_scope" => "jointly-feasible-paired-restarts-missing-retained",
        "calibration_repeats" => "QUIO-defaults-repeat-controlled-do-not-pool-regimes",
        "source_revision" => campaign.manifest["source_revision"],
        "analysis_sha256" => bytes2hex(SHA.sha256(read(@__FILE__))))
end
