# Read-only analysis of a complete frozen campaign. No optional solver imports.
include("CQTBenchmarks.jl")
Base.include(CQTBenchmarks, joinpath(@__DIR__, "runner.jl"))
Base.include(CQTBenchmarks, joinpath(@__DIR__, "study_analysis.jl"))
const S = CQTBenchmarks

function evaluation_summary(campaign)
    rows = Dict{String,Any}[]
    for regime in S.PROTOCOL["regimes"], arm in S.PROTOCOL["arms"]
        records = filter(r -> r["job"]["stage"] == "evaluation" &&
            r["job"]["arm"] == arm && r["job"]["regime"] == regime, campaign.records)
        length(records) == 40 || error("Evaluation denominator changed.")
        trajectories = [r["trajectory"] for r in records]
        gaps = Any[]
        for instance in filter(i -> i.stage == "evaluation", campaign.instances)
            per_instance = filter(r -> r["job"]["instance_id"] == instance.id, records)
            values = [get(r["trajectory"], "signed_gap", "missing") for r in per_instance]
            push!(gaps, S.mean_or_missing(filter(!=("missing"), values)))
        end
        sampled, feasible_samples, unique_sources = 0, 0, Set{Tuple}()
        for r in records
            trajectory = r["trajectory"]
            instance = only(filter(i -> i.id == r["job"]["instance_id"], campaign.instances))
            if trajectory["any_feasible"]
                source = trajectory["best_feasible_source"]
                S.source_feasible(instance, source; atol = 0) || error("Best point is not source feasible.")
                S.source_value(instance, source) == trajectory["best_feasible_objective"] ||
                    error("Best source objective differs from recorded value.")
            end
            for sample in get(trajectory, "samples", Dict[])
                multiplicity = sample["multiplicity"]
                multiplicity isa Integer && multiplicity >= 1 || error("Invalid sample multiplicity.")
                sample["source_feasible"] == S.source_feasible(instance, sample["source"]; atol = 0) ||
                    error("Snapshot source-feasibility flag differs.")
                sampled += multiplicity
                feasible_samples += multiplicity * sample["source_feasible"]
                push!(unique_sources, (instance.id, Tuple(sample["source"])))
            end
        end
        cap = arm in ("bounded", "toqubo_bounded_shim") ? campaign.selection["selected"][arm] : 0
        push!(rows, Dict("arm" => arm, "regime" => regime, "weight_cap" => cap, "planned_runs" => 40,
            "feasible_runs" => count(t -> t["any_feasible"], trajectories),
            "target_hits" => count(t -> t["timely_target"], trajectories),
            "invalid_runs" => count(r -> r["status"] == "invalid", records),
            "clock_censored_runs" => count(t -> get(t, "clock_censored", false), trajectories),
            "mean_time_score" => S.mean_or_missing([t["target_time_score"] for t in trajectories]),
            "mean_work_score" => S.mean_or_missing([t["target_work_score"] for t in trajectories]),
            "conditional_instance_mean_gap" => S.mean_or_missing(filter(!=("missing"), gaps)),
            "instances_with_gap" => count(!=("missing"), gaps),
            "feasible_snapshot_multiplicity" => feasible_samples, "snapshot_multiplicity" => sampled,
            "snapshot_feasible_fraction" => sampled == 0 ? "missing" : feasible_samples / sampled,
            "distinct_archived_source_snapshots" => length(unique_sources),
            "latency_missing_runs" => count(t -> t["elapsed_seconds"] == "missing", trajectories),
            "observed_target_seconds" => [t["first_target_seconds"] for t in trajectories],
            "actual_completed_proposals" => [t["completed_proposals"] for t in trajectories]))
    end
    return rows
end

function structural_summary(root, campaign)
    result = Dict{String,Any}[]
    for entry in campaign.ledger["cells"]
        data = S.read_archive(root, entry["file"]; expected_hash = entry["hash"])
        data["instance"]["stage"] == "evaluation" || continue
        arm = data["arm"]
        cap = arm in ("bounded", "toqubo_bounded_shim") ? campaign.selection["selected"][arm] : 0
        data["weight_cap"] == cap || continue
        warm = campaign.ledger["warm_timings"][entry["key"]]
        timing = S.read_archive(root, warm["file"]; expected_hash = warm["hash"])["compiler"]
        push!(result, Dict("instance_id" => data["instance"]["id"], "arm" => arm,
            "regime" => data["regime"], "weight_cap" => cap, "structure" => data["structure"],
            "layout_identity" => data["preflight"]["layout_identity"],
            "warm_compiler" => timing))
    end
    length(result) == 80 || error("Missing held-out structural cell.")
    return sort(result; by = r -> (r["regime"], r["arm"], r["instance_id"]))
end

function write_evaluation_csv(output, rows)
    fields = ["regime", "arm", "weight_cap", "planned_runs", "feasible_runs", "target_hits",
        "invalid_runs", "clock_censored_runs", "mean_time_score", "mean_work_score",
        "conditional_instance_mean_gap", "instances_with_gap", "feasible_snapshot_multiplicity",
        "snapshot_multiplicity", "snapshot_feasible_fraction", "distinct_archived_source_snapshots",
        "latency_missing_runs"]
    lines = [join(fields, ',')]
    append!(lines, [join([string(row[field]) for field in fields], ',') for row in rows])
    return S.write_archive_bytes(output, "evaluation.csv", join(lines, '\n') * "\n")
end

function main(args)
    length(args) == 2 || error("Usage: julia --project=. benchmarks/report.jl CAMPAIGN OUTPUT")
    root, output = abspath.(args)
    campaign = S.load_complete_campaign(root)
    statistics = S.study_statistics(campaign)
    statistics["evaluation_summary"] = evaluation_summary(campaign)
    statistics["structure"] = structural_summary(root, campaign)
    statistics["selection"] = campaign.selection
    statistics["resource_ledger"] = Dict(k => campaign.ledger[k] for k in
        ("elapsed_seconds", "process_peak_rss_bytes", "sampler_starts_reserved", "proposals_reserved",
         "enumeration_states_reserved", "invocations"))
    statistics["input_manifest_sha256"] = bytes2hex(S.SHA.sha256(read(joinpath(root, "manifest.toml"))))
    statistics["report_sha256"] = bytes2hex(S.SHA.sha256(read(@__FILE__)))
    mkpath(output)
    hash = S.write_archive(output, "statistics.toml", statistics)
    write_evaluation_csv(output, statistics["evaluation_summary"])
    println("Completed descriptive report: ", joinpath(output, "statistics.toml"), " sha256=", hash)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
