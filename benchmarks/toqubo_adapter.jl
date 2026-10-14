# Included only by the optional experiment entry point. No vendor source patch.
using ToQUBO, Pkg

struct ExactBoundedShim <: ToQUBO.Encoding.IntervalVariableEncodingMethod
    max_weight::Int
    max_digits::Int
end

function ToQUBO.Encoding.encode(var::Function, e::ExactBoundedShim, interval::Tuple{T,T};
                                tol::Union{T,Nothing} = nothing) where {T}
    isnothing(tol) || throw(ArgumentError("The experiment shim refuses real discretization."))
    lower, upper = ceil(BigInt, interval[1]), floor(BigInt, interval[2])
    lower <= upper || throw(ArgumentError("Empty shim interval."))
    upper - lower <= 64 || throw(ArgumentError("Shim width exceeds protocol admission."))
    weights, uppers = protocol_layout(upper - lower; levels = 2, max_weight = e.max_weight,
                                      max_digits = e.max_digits)
    all(isone, uppers) || error("Shim emitted a nonbinary digit.")
    variables = var(length(weights))
    expansion = ToQUBO.PBO.PBF{M.VariableIndex,T}(
        [T(lower); [variables[i] => T(weights[i]) for i in eachindex(weights)]])
    return variables, expansion, nothing
end

function verify_dependency_pins()
    dependencies = Pkg.dependencies()
    toqubo = dependencies[Base.PkgId(ToQUBO).uuid]
    toqubo.version == v"0.7.1" && toqubo.git_revision == PROTOCOL["toqubo_revision"] ||
        error("ToQUBO does not match the frozen source pin.")
    return true
end

function affine_map(entry, positions, polynomial, kind, row, lower, upper)
    offset, weights, indices = 0, Int[], Int[]
    for term in entry["expansion_terms"]
        coefficient = term["coefficient"]
        isfinite(coefficient) && isinteger(coefficient) || error("Noninteger emitted map coefficient.")
        variables = term["variables"]
        length(variables) <= 1 || error("Non-affine emitted encoding.")
        if isempty(variables)
            offset += Int(coefficient)
        else
            coefficient > 0 || error("Nonpositive emitted encoding weight.")
            push!(indices, positions[M.VariableIndex(only(variables))])
            push!(weights, Int(coefficient))
        end
    end
    expected_positions = sort([positions[M.VariableIndex(i)] for i in entry["target_variables"]])
    sort(indices) == expected_positions || error("Emitted map lost an allocated target digit.")
    order = sortperm(indices)
    indices, weights = indices[order], weights[order]
    return CoordinateMap(kind, row, lower, upper, offset, indices, weights,
                          polynomial.lower[indices], polynomial.upper[indices])
end

function row_from_reference(instance, ref)
    occursin("ScalarAffineFunction", ref["function_type"]) || error("Unexpected penalty constraint type.")
    set = ref["set_type"]
    relation = occursin("LessThan", set) ? "le" : occursin("GreaterThan", set) ? "ge" :
               occursin("EqualTo", set) ? "eq" : error("Unexpected penalty set.")
    candidates = findall(==(relation), instance.relations)
    1 <= ref["id"] <= length(candidates) || error("Unknown original constraint identity.")
    return candidates[ref["id"]]
end

function residual_domain(instance, row, maps; discretize)
    coefficients = instance.rows[row]
    constant = sum(a * map.offset for (a, map) in zip(coefficients, maps)) - instance.rhs[row]
    divisor = big(abs(constant))
    for (a, map) in zip(coefficients, maps), weight in map.weights
        divisor = gcd(divisor, big(a) * weight)
    end
    divisor = !discretize || iszero(divisor) ? 1 : Int(divisor)
    sign = instance.relations[row] == "ge" ? -1 : 1
    oriented = sign .* coefficients
    rhs = sign * instance.rhs[row]
    lower = sum(a * (a >= 0 ? l : u) for (a, l, u) in
        zip(oriented, instance.lower, instance.upper)) - rhs
    upper = sum(a * (a >= 0 ? u : l) for (a, l, u) in
        zip(oriented, instance.lower, instance.upper)) - rhs
    lower % divisor == upper % divisor == 0 || error("Nonintegral normalized residual endpoints.")
    return lower ÷ divisor, upper ÷ divisor, divisor
end

function compile_toqubo(instance::Instance, arm, regime; cap = 2, oracle = native_optimizer(instance))
    verify_dependency_pins()
    arm in ("toqubo_binary", "toqubo_bounded_shim") || throw(ArgumentError("Unknown ToQUBO arm."))
    regime in PROTOCOL["regimes"] || throw(ArgumentError("Unknown regime."))
    source_guard(instance)
    controlled = regime == "controlled"
    built = @timed (controlled ? oracle.target_model : source_model(instance))
    input = built.value
    method = arm == "toqubo_binary" ? ToQUBO.Encoding.Binary() : ExactBoundedShim(cap, 256)
    timed = @timed begin
        optimizer = ToQUBO.Optimizer{Float64}()
        M.set(optimizer, ToQUBO.Attributes.DefaultVariableEncodingMethod(), method)
        M.set(optimizer, ToQUBO.Attributes.Discretize(), !controlled)
        M.set(optimizer, ToQUBO.Attributes.MaxPenaltyUpdates(), 0)
        source_copy = @timed M.copy_to(optimizer, input)
        compiled = @timed M.optimize!(optimizer)
        optimizer
    end
    optimizer = timed.value
    target = M.get(optimizer, ToQUBO.Attributes.TargetModel())
    target_copy = @timed polynomial_from_moi(target)
    polynomial, positions = target_copy.value
    captured = @timed ToQUBO.reformulation_metadata(optimizer)
    metadata = captured.value
    polynomial.sense == instance.sense || error("Pinned target sense changed; reconstruction requires audit.")
    isempty(metadata["applied_penalties"]["variables"]) &&
        isempty(metadata["applied_penalties"]["slack_variables"]) ||
        error("Comparator introduced digit-enforcement penalties.")
    nsource = length(instance.lower)
    maps = CoordinateMap[]
    original_entries = sort(metadata["original_variables"]; by = e -> e["id"])
    expected_original_count = controlled ? length(oracle.data[:l]) : nsource
    length(original_entries) == expected_original_count || error("Missing original emitted map.")
    slack_rows = controlled ? [row_indices(instance)[ci] for ci in oracle.data[:slack_constraints]] : Int[]
    for (i, entry) in enumerate(original_entries)
        entry["id"] == i && entry["encoded"] || error("Unexpected copied variable order.")
        isnothing(entry["penalty_terms"]) || error("Variable encoding requires an extra penalty.")
        lower = controlled ? ceil(Int, oracle.data[:l][i]) : instance.lower[i]
        upper = controlled ? floor(Int, oracle.data[:u][i]) : instance.upper[i]
        kind, row = i <= nsource ? ("original", 0) : ("slack", slack_rows[i - nsource])
        push!(maps, affine_map(entry, positions, polynomial, kind, row, lower, upper))
    end
    penalties = Dict{String,Any}[]
    if controlled
        isempty(metadata["constraint_encodings"]) && isempty(metadata["slack_variables"]) ||
            error("Controlled comparator added a constraint penalty or slack.")
        for (ci, rho) in zip(oracle.data[:penalty_constraints], oracle.data[:rho])
            row = row_indices(instance)[ci]
            slack = findfirst(m -> m.kind == "slack" && m.row == row, maps)
            push!(penalties, Dict("row" => row, "divisor" => 1, "form" => "square",
                "coefficient" => (instance.sense == "min" ? rho : -rho),
                "slack_map" => isnothing(slack) ? 0 : slack))
        end
    else
        for entry in metadata["slack_variables"]
            isnothing(entry["penalty_terms"]) || error("Slack encoding requires an extra penalty.")
            row = row_from_reference(instance, entry["constraint"])
            lower, _, _ = residual_domain(instance, row, maps[1:nsource]; discretize = true)
            push!(maps, affine_map(entry, positions, polynomial, "slack", row, 0, abs(lower)))
        end
        encoded_rows = Int[]
        for entry in metadata["constraint_encodings"]
            entry["method"]["type"] == "QuadraticPenalty" || error("Unexpected default penalty method.")
            row = row_from_reference(instance, entry["constraint"])
            push!(encoded_rows, row)
            lower, _, divisor = residual_domain(instance, row, maps[1:nsource]; discretize = true)
            slack = findfirst(m -> m.kind == "slack" && m.row == row, maps)
            # Pinned QuadraticPenalty also leaves a nonnegative equality
            # residual unsquared (e.g. terminal inventory stock == 0).
            linear = lower >= 0 && isnothing(slack)
            push!(penalties, Dict("row" => row, "divisor" => divisor,
                "form" => linear ? "linear" : "square", "coefficient" => entry["penalty"],
                "slack_map" => isnothing(slack) ? 0 : slack))
        end
        for row in setdiff(eachindex(instance.rows), encoded_rows)
            lower, upper, divisor = residual_domain(instance, row, maps[1:nsource]; discretize = true)
            valid = instance.relations[row] == "eq" ? lower == upper == 0 : upper <= 0
            valid || error("Compiler removed a nonredundant source row.")
            push!(penalties, Dict("row" => row, "divisor" => divisor, "form" => "removed",
                                  "coefficient" => 0.0, "slack_map" => 0))
        end
    end
    record = Dict{String,Any}("compiler" => "ToQUBO", "compiler_version" => "0.7.1",
        "compiler_revision" => PROTOCOL["toqubo_revision"], "upstream_metadata" => metadata,
        "strategy" => Dict("name" => arm, "levels" => 2, "max_weight" => arm == "toqubo_binary" ? 0 : cap,
            "construction" => arm == "toqubo_binary" ? "pinned-upstream-binary" : "exact-bounded-tail-v1"),
        "shim_hash" => bytes2hex(SHA.sha256(read(@__FILE__))),
        "build_seconds" => built.time + timed.time + target_copy.time + captured.time,
        "construction_seconds" => built.time, "compiler_source_copy_seconds" => source_copy.time,
        "compiler_reformulation_and_encoding_seconds" => compiled.time,
        "target_polynomial_copy_seconds" => target_copy.time, "metadata_capture_seconds" => captured.time,
        "shared_native_timing" => oracle.data[:benchmark_native_timing],
        "build_allocated_bytes" => built.bytes + timed.bytes + target_copy.bytes + captured.bytes,
        "numeric_type" => "Float64", "discretize" => !controlled,
        "penalty_updates" => 0, "penalty_policy" => metadata["penalty_policy"],
        "applied_penalties" => penalties, "source_hash" => instance_hash(instance),
        "slack_rule" => controlled ? "preserve-native" : "pinned-integer-gcd-and-redundant-row-removal",
        "regime" => regime, "arm" => arm)
    return CompiledCell(instance, arm, regime, arm == "toqubo_binary" ? 0 : cap,
                        polynomial, maps, penalties, oracle, record)
end
