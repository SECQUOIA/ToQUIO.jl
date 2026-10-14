struct CoordinateMap
    kind::String
    row::Int
    lower::Int
    upper::Int
    offset::Int
    positions::Vector{Int}
    weights::Vector{Int}
    digit_lower::Vector{Int}
    digit_upper::Vector{Int}
end

map_value(map::CoordinateMap, state) = map.offset + dot(map.weights, state[map.positions])
function map_record(map::CoordinateMap)
    return Dict{String,Any}("kind" => map.kind, "row" => map.row, "lower" => map.lower,
        "upper" => map.upper, "offset" => map.offset, "positions" => map.positions,
        "weights" => map.weights, "digit_lower" => map.digit_lower, "digit_upper" => map.digit_upper)
end

struct CompiledCell
    instance::Instance
    arm::String
    regime::String
    weight_cap::Int
    polynomial::Polynomial
    maps::Vector{CoordinateMap}
    penalty_rows::Vector{Dict{String,Any}}
    oracle::Any
    record::Dict{String,Any}
end

function row_indices(instance::Instance)
    counters = Dict("eq" => 0, "le" => 0, "ge" => 0)
    result = Dict{Any,Int}()
    for (i, relation) in enumerate(instance.relations)
        counters[relation] += 1
        set = relation == "eq" ? M.EqualTo{Float64} :
              relation == "le" ? M.LessThan{Float64} : M.GreaterThan{Float64}
        result[M.ConstraintIndex{M.ScalarAffineFunction{Float64},set}(counters[relation])] = i
    end
    return result
end

function source_guard(instance::Instance; max_variables = 256, max_width = 64)
    for value in Iterators.flatten((instance.lower, instance.upper, instance.costs, instance.rhs,
                                    Iterators.flatten(instance.rows)))
        converted = Float64(value)
        isfinite(converted) && BigInt(converted) == big(value) ||
            throw(ArgumentError("Source integer is not exactly representable in Float64."))
    end
    widths = big.(instance.upper) - instance.lower
    all(0 .<= widths .<= max_width) || throw(ArgumentError("Source width exceeds protocol admission."))
    for (row, relation, rhs) in zip(instance.rows, instance.relations, instance.rhs)
        relation == "eq" && continue
        oriented = relation == "le" ? big.(row) : -big.(row)
        bound = relation == "le" ? big(rhs) : -big(rhs)
        minimum_value = sum(a * (a >= 0 ? l : u)
            for (a, l, u) in zip(oriented, instance.lower, instance.upper); init = big(0))
        push!(widths, bound - minimum_value)
    end
    all(0 .<= widths .<= max_width) || throw(ArgumentError("Slack width exceeds protocol admission."))
    # Unary binary digits bound every frozen strategy/cap. Default residual
    # GCD reduction can only reduce widths. Check before compiler allocations.
    sum(max(1, w) for w in widths; init = big(0)) <= max_variables ||
        throw(ArgumentError("Conservative target dimension exceeds protocol admission."))
    return widths
end

function polynomial_from_moi(target; max_variables = 256)
    variables = M.get(target, M.ListOfVariableIndices())
    n = length(variables)
    n <= max_variables || throw(ArgumentError("Compiled dimension exceeds protocol admission."))
    positions = Dict(v => i for (i, v) in enumerate(variables))
    G, g, lower, upper = zeros(n, n), zeros(n), fill(0, n), fill(1, n)
    for (F, S) in M.get(target, M.ListOfConstraintTypesPresent())
        if F == M.VariableIndex && S <: M.Interval
            for ci in M.get(target, M.ListOfConstraintIndices{F,S}())
                v = M.get(target, M.ConstraintFunction(), ci)
                set = M.get(target, M.ConstraintSet(), ci)
                lower[positions[v]], upper[positions[v]] = ceil(Int, set.lower), floor(Int, set.upper)
            end
        end
    end
    F = M.get(target, M.ObjectiveFunctionType())
    f = M.get(target, M.ObjectiveFunction{F}())
    for term in f.affine_terms
        g[positions[term.variable]] += term.coefficient
    end
    for term in f.quadratic_terms
        i, j = positions[term.variable_1], positions[term.variable_2]
        G[i, j] += term.coefficient / (i == j ? 2 : 1)
    end
    sense = M.get(target, M.ObjectiveSense()) == M.MIN_SENSE ? "min" : "max"
    return validate_polynomial(Polynomial(G, g, f.constant, lower, upper, sense)), positions
end

function native_optimizer(instance::Instance)
    source_guard(instance)
    built = @timed source_model(instance)
    oracle = ToQUIO.Optimizer()
    compiled = @timed M.optimize!(oracle, built.value)
    oracle.data[:benchmark_native_timing] = Dict(
        "construction_seconds" => built.time, "native_reformulation_seconds" => compiled.time,
        "allocated_bytes" => built.bytes + compiled.bytes,
        "scope" => "shared-once-per-instance-not-additive-across-arms")
    variables = oracle.data[:source_variables]
    variables == [M.VariableIndex(i) for i in eachindex(instance.lower)] ||
        error("Unexpected source variable order.")
    for (i, v) in enumerate(variables)
        oracle.data[:source_to_target_variables][v] == oracle.data[:quio_variables][i] ||
            error("Unexpected native original-variable projection.")
    end
    return oracle
end

function native_source_point(oracle, source; fill_slacks = false)
    state = zeros(Float64, length(oracle.data[:l]))
    state[1:length(source)] = source
    if fill_slacks
        positions = Dict(v => i for (i, v) in enumerate(oracle.data[:quio_variables]))
        constraints = Dict(c.index => c for c in oracle.data[:source_constraints])
        for (ci, v) in zip(oracle.data[:slack_constraints], oracle.data[:slack_variables])
            c = constraints[ci]
            value = M.Utilities.eval_variables(x -> source[x.value], c.func)
            state[positions[v]] = c.set isa M.LessThan ? c.set.upper - value : value - c.set.lower
        end
    end
    return state
end

function compile_quio(instance::Instance, arm, regime; cap = 2, oracle = nothing)
    strategy = arm == "native" ? ToQUIO.NativeEncoding() :
               arm == "radix" ? ToQUIO.RadixEncoding(; levels = PROTOCOL["levels"]) :
               arm == "bounded" ? ToQUIO.BoundedEncoding(; levels = PROTOCOL["levels"], max_weight = cap) :
               throw(ArgumentError("Unknown QUIO arm."))
    source_guard(instance)
    isnothing(oracle) && (oracle = native_optimizer(instance))
    native_optimizer_result = oracle
    native_timing = oracle.data[:benchmark_native_timing]
    # Source-pinned experiment hook separates the same post-native transform
    # used by public MOI.optimize!. Integration tests compare both routes.
    encoded = @timed ToQUIO._encode_native_quio(Float64, native_optimizer_result.target_model,
        deepcopy(native_optimizer_result.data), strategy, 256)
    target, data = encoded.value
    copied = @timed polynomial_from_moi(target)
    polynomial, _ = copied.value
    captured = @timed ToQUIO.reformulation_metadata(data)
    metadata = captured.value
    native = haskey(metadata, "native_reformulation") ? metadata["native_reformulation"] : metadata
    row_ids = row_indices(instance)
    slack_rows = [row_ids[ci] for ci in data[:slack_constraints]]
    nsource = length(instance.lower)
    maps = CoordinateMap[]
    for i in eachindex(data[:l])
        lower, upper = ceil(Int, data[:l][i]), floor(Int, data[:u][i])
        kind, row = i <= nsource ? ("original", 0) : ("slack", slack_rows[i - nsource])
        if arm == "native"
            map = CoordinateMap(kind, row, lower, upper, 0, [i], [1], [lower], [upper])
        else
            expansion = metadata["native_variables"][i]["expansion"]
            positions = Int[t["target_position"] for t in expansion["terms"]]
            weights = Int[t["coefficient"] for t in expansion["terms"]]
            map = CoordinateMap(kind, row, lower, upper, Int(expansion["offset"]), positions, weights,
                polynomial.lower[positions], polynomial.upper[positions])
        end
        push!(maps, map)
    end
    penalties = Dict{String,Any}[]
    for (ci, rho) in zip(data[:penalty_constraints], data[:rho])
        row = row_ids[ci]
        slack = findfirst(m -> m.kind == "slack" && m.row == row, maps)
        push!(penalties, Dict("row" => row, "divisor" => 1, "form" => "square",
            "coefficient" => (instance.sense == "min" ? rho : -rho),
            "slack_map" => isnothing(slack) ? 0 : slack))
    end
    record = Dict{String,Any}("compiler" => "ToQUIO", "compiler_version" => "0.1.0",
        "strategy" => ToQUIO.encoding_descriptor(strategy), "metadata" => metadata,
        "native_metadata" => native,
        "build_seconds" => encoded.time + copied.time + captured.time,
        "build_allocated_bytes" => encoded.bytes + copied.bytes + captured.bytes,
        "shared_native_timing" => native_timing,
        "compiler_revision" => readchomp(Cmd(["git", "-C", ROOT, "rev-parse", "HEAD"])),
        "encoding_and_copy_seconds" => encoded.time, "target_polynomial_copy_seconds" => copied.time,
        "metadata_capture_seconds" => captured.time,
        "penalty_offset" => 1.0, "penalty_scale" => 1.0, "numeric_type" => "Float64",
        "regime" => regime, "arm" => arm, "applied_penalties" => penalties,
        "slack_rule" => "native-integer-residual-preserved", "source_hash" => instance_hash(instance))
    data[:rho] == oracle.data[:rho] || error("QUIO arm changed native penalties.")
    return CompiledCell(instance, arm, regime, arm == "bounded" ? cap : 0,
                        polynomial, maps, penalties, oracle, record)
end

decoded_native(cell::CompiledCell, state) = [map_value(map, state) for map in cell.maps]
decoded_source(cell::CompiledCell, state) = decoded_native(cell, state)[1:length(cell.instance.lower)]

function independent_energy(cell::CompiledCell, state)
    native = decoded_native(cell, state)
    x = native[1:length(cell.instance.lower)]
    result = Float64(source_value(cell.instance, x))
    for penalty in cell.penalty_rows
        row = penalty["row"]
        residual = (dot(cell.instance.rows[row], x) - cell.instance.rhs[row]) / penalty["divisor"]
        cell.instance.relations[row] == "ge" && (residual = -residual)
        penalty["slack_map"] > 0 && (residual += native[penalty["slack_map"]])
        term = penalty["form"] == "square" ? residual^2 : residual
        result += penalty["coefficient"] * term
    end
    return result
end

function cell_observer(cell::CompiledCell, reference)
    function observe(state)
        x = decoded_source(cell, state)
        oracle_state = native_source_point(cell.oracle, x)
        feasible = ToQUIO.is_feasible(cell.oracle, oracle_state; atol = PROTOCOL["source_feasibility_atol"])
        feasible == source_feasible(cell.instance, x; atol = PROTOCOL["source_feasibility_atol"]) ||
            error("Independent/source API feasibility disagreement.")
        value = source_value(cell.instance, x)
        target = false
        if feasible
            sigma = cell.instance.sense == "min" ? 1 : -1
            allowance = cell.instance.stage == "pilot" ? 0.0 :
                        PROTOCOL["reference"]["target_relative_gap"] * max(1, abs(reference))
            target = sigma * (value - reference) <= allowance + PROTOCOL["reference"]["target_absolute_tolerance"]
        end
        return (source = x, feasible = feasible, objective = Float64(value),
                sense = cell.instance.sense, target = target)
    end
    return observe
end

function lift_map(map::CoordinateMap, value)
    map.lower <= value <= map.upper && isinteger(value) || error("Native point outside declared map.")
    if !isempty(map.digit_lower) && any(!iszero, map.digit_lower)
        length(map.weights) == 1 && map.weights == [1] && map.offset == 0 || error("Invalid identity map.")
        return [Int(value)]
    end
    return Int.(protocol_canonical_lift(Int(value) - map.offset, map.weights, map.digit_upper))
end

function lift_cell(cell::CompiledCell, native)
    length(native) == length(cell.maps) || error("Wrong native initialization dimension.")
    state = zeros(Int, length(cell.polynomial.g))
    for (map, value) in zip(cell.maps, native)
        state[map.positions] = lift_map(map, value)
    end
    decoded_native(cell, state) == native || error("Canonical lift roundtrip failed.")
    return state
end

function reference_lift(cell::CompiledCell, x)
    native = Float64.(x)
    for map in cell.maps[(length(x) + 1):end]
        row = map.row
        divisor = first(p["divisor"] for p in cell.penalty_rows if p["row"] == row)
        residual = (dot(cell.instance.rows[row], x) - cell.instance.rhs[row]) / divisor
        cell.instance.relations[row] == "ge" && (residual = -residual)
        push!(native, -residual)
    end
    return lift_cell(cell, native)
end
