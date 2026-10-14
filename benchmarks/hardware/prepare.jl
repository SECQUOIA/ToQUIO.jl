# Offline only: build deterministic artifacts from the verified public campaign.
include("offline.jl")
const H = CQTOfflineHardware
const S = H.S
using TOML, JSON, SHA
length(ARGS) == 2 || error("Pass extracted campaign and a new output directory.")
campaign, output = abspath.(ARGS)
ispath(output) && error("Refusing to overwrite a readiness packet.")
H.verify_driver()
manifest = S.read_archive(campaign, "manifest.toml")
S.verify_archive_execution(manifest)
ledger = S.read_archive(campaign, "ledger.toml")
bytes2hex(sha256(read(joinpath(campaign, "manifest.toml")))) == ledger["manifest_hash"] ||
    error("Manifest binding differs.")
subset_path = joinpath(@__DIR__, "../results/protocol_v1/hardware_subset.toml")
subset = TOML.parsefile(subset_path)
subset["representative"] == false && subset["predeclared"] == false ||
    error("This packet is restricted to the disclosed post-hoc demonstration.")
mkpath(output)
rows, jobs = Dict{String,Any}[], Dict{String,Any}[]
files = Dict{String,String}()
function save(name, record)
    bytes = S.toml_bytes(S.portable(record))
    write(joinpath(output, name), bytes)
    files[name] = bytes2hex(sha256(bytes))
end
for source in subset["instances"], descriptor in source["arms"]
    entry = only(filter(c -> c["key"] == descriptor["cell_key"], ledger["cells"]))
    entry["hash"] == descriptor["cell_hash"] && entry["source_hash"] == source["source_hash"] ||
        error("Subset cell binding differs.")
    record = S.read_archive(campaign, entry["file"]; expected_hash = entry["hash"])
    cell = S.cell_from_record(record)
    S.instance_hash(cell.instance) == source["source_hash"] || error("Source hash differs.")
    cell.arm == descriptor["arm"] && cell.regime == "controlled" || error("Target arm/regime differs.")
    exported = H.export_request(H.target_model(cell.polynomial))
    readiness = H.readiness(exported.request)
    name = source["instance_id"] * "-" * cell.arm
    state = S.reference_lift(cell, cell.instance.witness)
    shifted = state - cell.polynomial.lower
    response = Dict{String,Any}("status" => "COMPLETED", "job_info" => Dict("job_id" => "mock-" * name),
        "results" => Dict("solutions" => [shifted],
            "energies" => [H.payload_energy(exported.request.file, shifted)], "counts" => [1]))
    sample = H.response_record(exported, response, cell)
    merge!(sample, Dict("cell_key" => entry["key"], "cell_hash" => entry["hash"]))
    save(name * "-payload.toml", exported.request.file)
    save(name * "-sample.toml", sample)
    merge!(readiness, Dict("instance_id" => source["instance_id"], "arm" => cell.arm,
        "source_hash" => source["source_hash"], "cell_hash" => entry["hash"], "cell_key" => entry["key"],
        "payload_file" => name * "-payload.toml", "sample_file" => name * "-sample.toml"))
    push!(rows, readiness)
    for repeat in 1:3
        push!(jobs, Dict("candidate_id" => name * "-r" * string(repeat), "enabled" => false,
            "device" => "dirac-3", "job_type" => "sample-hamiltonian-integer",
            "source_hash" => source["source_hash"], "cell_hash" => entry["hash"],
            "payload_file" => name * "-payload.toml", "num_levels" => exported.request.num_levels,
            "num_samples" => 10, "relaxation_schedule" => 1, "automatic_retries" => 0,
            "payload_screen_pass" => readiness["conservative_payload_pass"]))
    end
end
save("readiness.toml", Dict("schema_version" => 1, "evidence_kind" => "mock",
    "qci_revision" => H.QCI_PIN["revision"], "julia_version" => string(VERSION), "moi_version" => "1.54.0",
    "campaign_source_revision" => manifest["source_revision"],
    "subset_sha256" => bytes2hex(sha256(read(subset_path))), "rows" => rows))
save("candidate_manifest.toml", Dict("schema_version" => 1, "status" => "PROPOSED-NOT-AUTHORIZED",
    "purpose" => "post-hoc-four-family-demonstration-no-comparative-claims", "representative" => false,
    "qci_revision" => H.QCI_PIN["revision"], "jobs" => jobs,
    "caps" => Dict("job_attempts" => 36, "reads" => 360, "reads_per_job" => 10,
        "relaxation_schedule" => 1, "automatic_retries" => 0,
        "proposed_device_usage_seconds" => 2160, "proposed_per_job_device_usage_seconds" => 60,
        "total_level_cap" => 500, "max_levels" => 16),
    "billing" => Dict("currency" => "USD", "price_per_device_second" => "unverified",
        "maximum_charge" => "approval-required", "account_allocation_seconds" => "unverified",
        "access_owner" => "maintainer-must-name-account-owner"),
    "gates" => ["maintainer-accepts-demonstration-subset", "payload-contract-and-precision-confirmed",
        "account-access-and-allocation-verified", "concrete-dollar-or-allocation-budget-approved",
        "approved-manifest-hash-bound-before-submit"],
    "stop_conditions" => ["any-gate-missing", "payload-screen-fails", "provider-contract-changes",
        "allocation-below-reserved-cap", "unexpected-billing", "invalid-sample-or-response",
        "job-failure-no-automatic-retry", "read-job-time-or-spend-cap-reached"],
    "conditional_routes" => Dict("dwave" => "excluded-no-access-owner-approved",
        "ibm" => "excluded-no-adapter-or-access-owner-approved")))
table = IOBuffer()
println(table, "# Offline QCI readiness\n\nGenerated mock evidence only. No jobs submitted. " *
    "Every live eligibility remains unverified. The proposed subset is post hoc and nonrepresentative.\n")
println(table, "| Instance | Arm | Levels (max / total) | Coefficient ratio | Conservative screen | Reasons |")
println(table, "|---|---|---:|---:|---|---|")
for row in rows
    println(table, "| ", join([row["instance_id"], row["arm"],
        string(row["maximum_levels"]) * " / " * string(row["total_levels"]),
        round(row["coefficient_ratio"]; digits = 4), row["conservative_payload_pass"],
        isempty(row["reasons"]) ? "none; account/approval still pending" : join(row["reasons"], ", ")], " | "), " |")
end
write(joinpath(output, "READINESS.md"), take!(table))
files["READINESS.md"] = bytes2hex(sha256(read(joinpath(output, "READINESS.md"))))
write(joinpath(output, "checksums.json"), JSON.json(files, 2) * "\n")
println("Prepared ", length(rows), " offline targets and ", length(jobs), " disabled candidate jobs.")
