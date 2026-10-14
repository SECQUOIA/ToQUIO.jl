module CQTOfflineHardware
using QCIOpt, JSON, SHA, TOML, Pkg
import MathOptInterface as M
include("../CQTBenchmarks.jl")
const S = CQTBenchmarks
const QCI_PIN = JSON.parsefile(joinpath(@__DIR__, "qci_source_pin.json"))

function verify_driver()
    root = dirname(dirname(pathof(QCIOpt)))
    for (file, digest) in QCI_PIN["files"]
        bytes2hex(sha256(read(joinpath(root, file)))) == digest || error("QCIOpt pin differs: $file")
    end
    normpath(dirname(dirname(pathof(S.ToQUIO)))) == normpath(S.ROOT) || error("Wrong ToQUIO import.")
    return true
end

# Reconstruct the archived x'G*x+g'x+c target using MOI's half diagonal convention.
function target_model(p::S.Polynomial)
    S.validate_polynomial(p)
    model = M.Utilities.Model{Float64}()
    x = M.add_variables(model, length(p.g))
    for (i, xi) in enumerate(x)
        M.add_constraint(model, xi, M.Integer())
        M.add_constraint(model, xi, M.Interval(Float64(p.lower[i]), Float64(p.upper[i])))
    end
    terms = M.ScalarQuadraticTerm{Float64}[]
    for i in eachindex(x), j in i:length(x)
        coefficient = i == j ? 2p.G[i, i] : p.G[i, j] + p.G[j, i]
        iszero(coefficient) || push!(terms, M.ScalarQuadraticTerm(coefficient, x[i], x[j]))
    end
    f = M.ScalarQuadraticFunction(terms,
        [M.ScalarAffineTerm(p.g[i], x[i]) for i in eachindex(x)], p.constant)
    M.set(model, M.ObjectiveFunction{typeof(f)}(), f)
    M.set(model, M.ObjectiveSense(), p.sense == "min" ? M.MIN_SENSE : M.MAX_SENSE)
    return model
end

function export_request(model)
    # The driver's load entry point does not enforce arbitrary source constraints.
    # Refuse them rather than silently exporting a different problem.
    for (F, T) in M.get(model, M.ListOfConstraintTypesPresent())
        F == M.VariableIndex && T <: Union{M.Integer,M.ZeroOne,M.Interval{Float64},
            M.EqualTo{Float64},M.LessThan{Float64},M.GreaterThan{Float64}} ||
            throw(ArgumentError("Export a compiled unconstrained integer target."))
    end
    M.get(model, M.ObjectiveSense()) in (M.MIN_SENSE, M.MAX_SENSE) ||
        throw(ArgumentError("A minimization or maximization objective is required."))
    solver = QCIOpt.Optimizer()
    device = solver.device
    vars = QCIOpt.qci_load!(solver, device, model)
    request = QCIOpt.qci_build_poly_request(solver, device, vars)
    request.job_type == "sample-hamiltonian-integer" || throw(ArgumentError("Integer targets only."))
    terms = request.file["file_config"]["polynomial"]["data"]
    all(t -> isfinite(t["val"]), terms) || throw(ArgumentError("Nonfinite submission coefficient."))
    return (; model, solver, device, vars, request)
end

function payload_energy(file, point)
    config = file["file_config"]["polynomial"]
    length(point) == config["num_variables"] || throw(ArgumentError("Wrong payload dimension."))
    return sum(t["val"] * prod(point[i] for i in t["idx"] if i != 0; init = 1.0)
        for t in config["data"]; init = 0.0)
end

# Conservative campaign admission, distinct from the driver's broader digital API.
# The vendor's v0.0.4 manual is ambiguous about 16 values vs upper bound 16;
# choose at most 16 levels until the account owner confirms the current contract.
function readiness(request; total_level_cap = 500, max_levels = 16, dynamic_range = 200.0)
    total_level_cap > 0 && max_levels >= 2 && isfinite(dynamic_range) && dynamic_range >= 1 ||
        throw(ArgumentError("Invalid conservative contract."))
    levels = request.num_levels
    coefficients = [t["val"] for t in request.file["file_config"]["polynomial"]["data"]]
    magnitudes = sort(unique(abs.(filter(!iszero, coefficients))))
    maximum_coefficient = maximum(magnitudes; init = 0.0)
    ratio = isempty(magnitudes) ? 0.0 : maximum_coefficient / first(magnitudes)
    distinct = sort(unique(coefficients))
    separation = length(distinct) < 2 ? "not-applicable" : minimum(diff(distinct))
    reasons = String[]
    sum(big.(levels); init = big(0)) > total_level_cap && push!(reasons, "total-level-allocation-cap")
    maximum(levels; init = 0) > max_levels && push!(reasons, "per-variable-conservative-level-cap")
    any(==(1), levels) && push!(reasons, "singleton-provider-contract-unconfirmed")
    ratio > dynamic_range && push!(reasons, "coefficient-dynamic-range")
    separation isa Real && separation < maximum_coefficient / dynamic_range &&
        push!(reasons, "coefficient-resolution")
    isempty(coefficients) && push!(reasons, "constant-only-provider-contract-unconfirmed")
    return Dict("offline_export" => "tested", "conservative_payload_pass" => isempty(reasons),
        "live_eligible" => false, "reasons" => reasons, "levels" => levels,
        "total_levels" => sum(big.(levels)), "maximum_levels" => maximum(levels; init = 0),
        "maximum_absolute_coefficient" => maximum_coefficient, "coefficient_ratio" => ratio,
        "minimum_distinct_coefficient_separation" => separation,
        "normalization" => "none", "quantization" => "none",
        "account_contract" => "unverified", "precision_model" => "conservative-manual-screen-not-certificate")
end

function require_conservative_payload(request; kwargs...)
    result = readiness(request; kwargs...)
    result["conservative_payload_pass"] || throw(ArgumentError(join(result["reasons"], ", ")))
    return result
end

function safe_identifier(value)
    isnothing(value) && return "unavailable"
    value isa AbstractString && occursin(r"^[A-Za-z0-9_.-]{1,80}$", value) ||
        throw(ArgumentError("Invalid provider identifier."))
    return String(value)
end

function timing_value(value)
    isnothing(value) && return "unavailable"
    value isa Real && isfinite(value) && value >= 0 || throw(ArgumentError("Invalid provider timing."))
    return Float64(value)
end

function response_record(exported, response, cell; evidence_kind = "mock")
    evidence_kind == "mock" || throw(ArgumentError("This offline reader records mock evidence only."))
    status = get(response, "status", nothing)
    status in ("COMPLETED", "ERRORED", "CANCELLED", "QUEUED", "RUNNING", "SUBMITTED") ||
        throw(ArgumentError("Unknown provider status."))
    if status == "COMPLETED"
        results = QCIOpt.qci_provider_results(response)
        levels = exported.request.num_levels
        read_cap = M.get(exported.solver, M.RawOptimizerAttribute("num_samples"))
        length(results["solutions"]) <= read_cap || throw(ArgumentError("Response exceeds sample cap."))
        for (point, energy, count) in zip(results["solutions"], results["energies"], results["counts"])
            length(point) == length(levels) || throw(ArgumentError("Wrong sample dimension."))
            all(v -> v isa Real && isfinite(v) && isinteger(v), point) ||
                throw(ArgumentError("Noninteger provider sample."))
            all(0 .<= point .< levels) || throw(ArgumentError("Out-of-domain provider sample."))
            count isa Integer && !(count isa Bool) && 0 < count <= read_cap ||
                throw(ArgumentError("Invalid multiplicity."))
            energy isa Real && isfinite(energy) || throw(ArgumentError("Invalid reported energy."))
        end
        sum(big.(results["counts"]); init = big(0)) <= read_cap ||
            throw(ArgumentError("Multiplicity cap exceeded."))
    end
    # The driver's error logger prints a provider diagnostic verbatim. Do not
    # send unknown diagnostic text to it or publish raw response metadata.
    parse_response = status == "ERRORED" ? Dict{String,Any}("status" => status) : response
    solution = QCIOpt.qci_parse_results(Float64, Float64, parse_response)
    solution = QCIOpt.Solution{Float64,Float64}(solution.samples, response)
    QCIOpt.qci_store_results!(exported.solver, exported.device, exported.model, exported.vars, solution)
    metadata = M.get(exported.solver, QCIOpt.ProviderMetadata())
    samples = Dict{String,Any}[]
    for sample in exported.solver.solution.samples
        source = S.decoded_source(cell, sample.point)
        expected = S.energy(cell.polynomial, sample.point)
        isapprox(sample.value, expected; atol = 1e-9, rtol = 1e-12) || error("Target objective mismatch.")
        feasible = S.source_feasible(cell.instance, source; atol = 0)
        oracle = S.ToQUIO.is_feasible(cell.oracle, S.native_source_point(cell.oracle, source); atol = 0)
        feasible == oracle || error("Original feasibility disagreement.")
        push!(samples, Dict("target_point" => sample.point, "target_objective" => sample.value,
            "multiplicity" => sample.reads, "source_point" => source,
            "source_objective" => S.source_value(cell.instance, source), "source_feasible" => feasible))
    end
    return Dict("schema_version" => 1, "evidence_kind" => evidence_kind, "provider_status" => status,
        "job_id" => safe_identifier(metadata["job_id"]),
        "result_file_id" => safe_identifier(metadata["result_file_id"]),
        "problem_file_id" => safe_identifier(metadata["problem_file_id"]),
        "timing" => Dict(key => timing_value(metadata[key]) for key in
            ("queue_time_sec", "run_time_sec", "total_time_sec", "device_usage_sec")),
        "reported_provider_energies" => status == "COMPLETED" ? response["results"]["energies"] : Float64[],
        "device_config" => Dict("device" => "dirac-3", "job_type" => exported.request.job_type,
            "num_levels" => exported.request.num_levels,
            "num_samples_cap" => M.get(exported.solver, M.RawOptimizerAttribute("num_samples")),
            "relaxation_schedule" => M.get(exported.solver, M.RawOptimizerAttribute("relaxation_schedule"))),
        "qci_revision" => QCI_PIN["revision"], "source_hash" => S.instance_hash(cell.instance),
        "target_hash" => S.record_hash(S.polynomial_record(cell.polynomial)),
        "request_hash" => S.record_hash(exported.request.file), "samples" => samples,
        "failure_class" => status == "COMPLETED" ? "none" : "provider-not-completed",
        "optimality_certificate" => false)
end

end
