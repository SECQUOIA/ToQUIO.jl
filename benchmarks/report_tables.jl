# Derived disclosure tables and the explicitly post-hoc software hardware subset.
format_value(value; digits = 6) = value == "missing" ? "missing" : string(round(value; digits))

function contrast_identities(cells, left, right, regime)
    identities = Dict{String,Any}[]
    for id in sort(unique(c["instance_id"] for c in cells))
        a = only(filter(c -> c["instance_id"] == id && c["arm"] == left && c["regime"] == regime, cells))
        b = only(filter(c -> c["instance_id"] == id && c["arm"] == right && c["regime"] == regime, cells))
        push!(identities, Dict("instance_id" => id,
            "layout_distinct" => a["layout_identity"] != b["layout_identity"],
            "exact_target_distinct" => a["target_signature"] != b["target_signature"]))
    end
    return identities
end

function identity_counts(identities)
    return Dict("instance_identities" => identities,
        "layout_distinct_instances" => count(i -> i["layout_distinct"], identities),
        "exact_target_distinct_instances" => count(i -> i["exact_target_distinct"], identities))
end

function annotate_distinctness!(statistics)
    cells = statistics["structure"]
    for contrast in statistics["contrasts"]
        left, right = split(contrast["name"], '-'; limit = 2)
        merge!(contrast, identity_counts(contrast_identities(cells, left, right, contrast["regime"])))
    end
    statistics["encoding_alias_diagnostics"] = [merge(Dict("regime" => regime,
        "contrast" => "radix-bounded", "scope" => "structural-diagnostic-no-new-inference"),
        identity_counts(contrast_identities(cells, "radix", "bounded", regime))) for regime in S.PROTOCOL["regimes"]]
end

function hardware_subset(campaign, statistics)
    instances = Dict{String,Any}[]
    for family in sort(unique(i.family for i in campaign.instances))
        instance = first(sort(filter(i -> i.family == family && i.stage == "evaluation", campaign.instances);
                              by = i -> i.ordinal))
        cells = filter(c -> c["instance_id"] == instance.id && c["regime"] == "controlled" &&
            c["arm"] in ("native", "radix", "bounded"), statistics["structure"])
        descriptors = [Dict("arm" => c["arm"], "cell_key" => c["cell_key"], "cell_hash" => c["cell_hash"],
            "weight_cap" => c["weight_cap"], "encoding_level_parameter" => c["arm"] == "native" ?
                "not-applicable-native-domains" : S.PROTOCOL["levels"],
            "maximum_domain_levels" => maximum(c["structure"]["domain_levels"]),
            "total_domain_levels" => sum(c["structure"]["domain_levels"]),
            "exceeds_hypothetical_four_level_cap" => maximum(c["structure"]["domain_levels"]) > 4,
            "provider_eligibility" => "unverified-until-issue52-contract-and-issue53-account-check") for c in cells]
        a = only(filter(c -> c["arm"] == "radix", cells))
        b = only(filter(c -> c["arm"] == "bounded", cells))
        push!(instances, Dict("family" => family, "instance_id" => instance.id,
            "source_hash" => S.instance_hash(instance), "regime" => "controlled",
            "radix_bounded_target_identity" => a["target_signature"] == b["target_signature"],
            "arms" => descriptors))
    end
    selected_ids = Set(i["instance_id"] for i in instances)
    composition = Dict{String,Any}[]
    for contrast in filter(c -> c["primary"], statistics["contrasts"]), endpoint in contrast["endpoints"]
        differences = endpoint["instance_differences"]
        groups = Dict{String,Any}[]
        for (name, selected) in (("selected", true), ("excluded", false))
            rows = filter(d -> (d["instance_id"] in selected_ids) == selected, differences)
            values = [d["difference"] for d in rows if d["difference"] != "missing"]
            push!(groups, Dict("group" => name, "instance_differences" => rows,
                "observed_instances" => length(values), "mean_difference" => S.mean_or_missing(values)))
        end
        push!(composition, Dict("contrast" => contrast["name"], "endpoint" => endpoint["endpoint"],
                                "groups" => groups))
    end
    adverse_selected = Set{String}()
    adverse_excluded = Set{String}()
    for c in composition
        c["endpoint"] in ("feasibility", "target_time_score") || continue
        for group in c["groups"], d in group["instance_differences"]
            value = d["difference"]
            value == "missing" && continue
            adverse = c["endpoint"] == "feasibility" ? value < 0 : value > 0
            adverse || continue
            push!(group["group"] == "selected" ? adverse_selected : adverse_excluded, d["instance_id"])
        end
    end
    warning = "Adverse feasibility/time-score instances: selected=" * string(length(adverse_selected)) *
              ", excluded=" * string(length(adverse_excluded)) * "; post-hoc packet is not representative."
    return Dict("schema_version" => 1, "status" => "software-subset-no-live-approval",
        "campaign_source_revision" => campaign.manifest["source_revision"],
        "selection_rule" => "lowest-ordinal-held-out-source-per-family", "predeclared" => false,
        "selection_timing" => "post-campaign", "representative" => false,
        "composition_warning" => warning,
        "adverse_selected_instances" => sort(collect(adverse_selected)),
        "adverse_excluded_instances" => sort(collect(adverse_excluded)),
        "purpose" => "four-family-demo-packet-subject-to-maintainer-review-in-issue52",
        "instances" => instances, "composition" => composition)
end

function derived_tables(statistics, subset)
    io = IOBuffer()
    println(io, "# Reproduced study values\n\nGenerated by `benchmarks/report.jl` from the immutable raw archive.\n")
    println(io, "All intervals and sign-flip sensitivities are descriptive/exploratory; " *
                "there is no multiplicity control or confirmatory inference. " *
                "QUIO compiler-default contrasts repeat controlled policies and must not be pooled.\n")
    println(io, "## Evaluation summaries\n\nUnpaired gaps use each arm's own feasible-instance set.\n")
    println(io, "| Regime | Arm | F / 40 | Target / 40 | Censored | Time score | Work score | " *
                "Unpaired gap | Instances with gap / 8 |")
    println(io, "|---|---|---:|---:|---:|---:|---:|---:|---:|")
    for r in statistics["evaluation_summary"]
        values = [r["regime"], r["arm"], r["feasible_runs"], r["target_hits"], r["clock_censored_runs"],
            format_value(r["mean_time_score"]), format_value(r["mean_work_score"]),
            format_value(r["conditional_instance_mean_gap"]), r["instances_with_gap"]]
        println(io, "| ", join(values, " | "), " |")
    end
    println(io, "\n## Contrast identity and all endpoints\n")
    println(io, "| Regime | Contrast | Layout-distinct / 8 | Exact-target-distinct / 8 | " *
                "Endpoint | Difference | 95% descriptive interval | n | Sensitivity p |")
    println(io, "|---|---|---:|---:|---|---:|---|---:|---:|")
    for c in statistics["contrasts"], e in c["endpoints"]
        name = c["name"]
        c["regime"] == "compiler_defaults" && name in ("radix-native", "bounded-native") &&
            (name *= " (calibration repeat)")
        values = [c["regime"], name, c["layout_distinct_instances"], c["exact_target_distinct_instances"],
            e["endpoint"], format_value(e["mean_difference"]),
            "[" * join(format_value.(e["interval"]), ", ") * "]", e["sign_flip"]["n"],
            format_value(e["sign_flip"]["p"])]
        println(io, "| ", join(values, " | "), " |")
    end
    println(io, "\n## Radix/bounded alias diagnostic\n")
    println(io, "| Regime | Layout-distinct / 8 | Exact-target-distinct / 8 |")
    println(io, "|---|---:|---:|")
    for c in statistics["encoding_alias_diagnostics"]
        println(io, "| ", join([c["regime"], c["layout_distinct_instances"],
            c["exact_target_distinct_instances"]], " | "), " |")
    end
    for c in statistics["encoding_alias_diagnostics"]
        distinct = [i["instance_id"] for i in c["instance_identities"] if i["exact_target_distinct"]]
        aliases = [i["instance_id"] for i in c["instance_identities"] if !i["exact_target_distinct"]]
        println(io, "\n", c["regime"], ": distinct targets: ", join(distinct, ", "),
                "; aliases: ", join(aliases, ", "), ". Aliases are not independent method evidence.\n")
    end
    println(io, "\n## All primary paired gap differences\n")
    println(io, "| Contrast | Instance | Gap difference | Jointly feasible paired restarts / 5 |")
    println(io, "|---|---|---:|---:|")
    for c in filter(c -> c["primary"], statistics["contrasts"])
        gap = only(filter(e -> e["endpoint"] == "signed_gap", c["endpoints"]))
        for d in gap["instance_differences"]
            println(io, "| ", join([c["name"], d["instance_id"], format_value(d["difference"]),
                                    d["paired_restarts"]], " | "), " |")
        end
    end
    println(io, "\n## Reproduced structural means\n")
    println(io, "Means over eight held-out cells; coefficient extrema/ratios use canonical polynomials.\n")
    println(io, "| Regime | Arm | Variables | Couplers | Own build ms | Allocations MiB | " *
                "Mean minimum nonzero coefficient | Mean maximum coefficient | Mean ratio |")
    println(io, "|---|---|---:|---:|---:|---:|---:|---:|---:|")
    for regime in S.PROTOCOL["regimes"], arm in S.PROTOCOL["arms"]
        cells = filter(c -> c["regime"] == regime && c["arm"] == arm, statistics["structure"])
        meanfield(key) = S.mean_or_missing([c["structure"][key] for c in cells if c["structure"][key] != "missing"])
        values = [meanfield("logical_variables"), meanfield("unique_couplers"),
            1000S.mean_or_missing([c["warm_compiler"]["build_seconds"] for c in cells]),
            S.mean_or_missing([c["warm_compiler"]["build_allocated_bytes"] for c in cells]) / 2^20,
            meanfield("coefficient_min_nonzero"), meanfield("coefficient_max"), meanfield("coefficient_ratio")]
        println(io, "| ", join([regime, arm, format_value.(values)...], " | "), " |")
    end
    println(io, "\n## Post-hoc subset composition\n\nSelected minus native and excluded minus native; " *
                "not a representative sample.\n")
    println(io, "| Contrast | Endpoint | Selected mean | Selected n | Excluded mean | Excluded n |")
    println(io, "|---|---|---:|---:|---:|---:|")
    for c in subset["composition"]
        a, b = c["groups"]
        println(io, "| ", join([c["contrast"], c["endpoint"], format_value(a["mean_difference"]),
            a["observed_instances"], format_value(b["mean_difference"]), b["observed_instances"]], " | "), " |")
    end
    println(io, "\n## Native versus encoder domain limits\n\n" *
                "Four is an encoder parameter, not a verified provider cap.\n")
    println(io, "| Instance | Arm | Actual maximum levels | Actual total levels | " *
                "Exceeds hypothetical 4-level cap |")
    println(io, "|---|---|---:|---:|---|")
    for i in subset["instances"], arm in i["arms"]
        println(io, "| ", join([i["instance_id"], arm["arm"], arm["maximum_domain_levels"],
            arm["total_domain_levels"], arm["exceeds_hypothetical_four_level_cap"]], " | "), " |")
    end
    return String(take!(io))
end
