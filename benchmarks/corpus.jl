# Repository-authored MPL-2.0 instances, integer quantities and cost units.
# This file is included inside CQTBenchmarks, never by the package runtime.
struct Instance
    id::String
    family::String
    ordinal::Int
    stage::String
    seed::Int
    parameters::Dict{String,Any}
    lower::Vector{Int}
    upper::Vector{Int}
    costs::Vector{Int}
    sense::String
    rows::Vector{Vector{Int}}
    relations::Vector{String}
    rhs::Vector{Int}
    witness::Vector{Int}
end

function instance_record(instance::Instance)
    return Dict{String,Any}(
        "id" => instance.id, "family" => instance.family, "ordinal" => instance.ordinal,
        "stage" => instance.stage, "seed" => instance.seed,
        "seed_kind" => instance.stage == "pilot" ? "fixed-parameters" : "MersenneTwister",
        "license" => "MPL-2.0", "provenance" => "repository-authored-protocol-v1",
        "units" => "integer-quantity-and-integer-cost", "parameters" => instance.parameters,
        "lower" => instance.lower, "upper" => instance.upper, "costs" => instance.costs,
        "sense" => instance.sense, "rows" => instance.rows,
        "relations" => instance.relations, "rhs" => instance.rhs, "witness" => instance.witness,
    )
end

function toml_bytes(record)
    io = IOBuffer()
    TOML.print(io, record; sorted = true)
    return take!(io)
end
record_hash(record) = bytes2hex(SHA.sha256(toml_bytes(record)))
instance_hash(instance::Instance) = record_hash(instance_record(instance))

function instance_from_record(r)
    return Instance(r["id"], r["family"], r["ordinal"], r["stage"], r["seed"],
        Dict{String,Any}(r["parameters"]), Int.(r["lower"]), Int.(r["upper"]), Int.(r["costs"]),
        r["sense"], [Int.(row) for row in r["rows"]], String.(r["relations"]),
        Int.(r["rhs"]), Int.(r["witness"]))
end

function source_model(instance::Instance)
    n = length(instance.lower)
    n == length(instance.upper) == length(instance.costs) || error("Invalid source dimensions.")
    all(instance.lower .<= instance.upper) || error("Empty source interval.")
    length(instance.rows) == length(instance.rhs) == length(instance.relations) ||
        error("Invalid source row dimensions.")
    source = M.Utilities.Model{Float64}()
    variables = M.add_variables(source, n)
    for (x, lower, upper) in zip(variables, instance.lower, instance.upper)
        M.add_constraint(source, x, M.Interval(Float64(lower), Float64(upper)))
        M.add_constraint(source, x, M.Integer())
    end
    objective = M.ScalarAffineFunction([M.ScalarAffineTerm(Float64(c), x)
        for (c, x) in zip(instance.costs, variables)], 0.0)
    M.set(source, M.ObjectiveFunction{typeof(objective)}(), objective)
    M.set(source, M.ObjectiveSense(), instance.sense == "min" ? M.MIN_SENSE : M.MAX_SENSE)
    for (row, relation, rhs) in zip(instance.rows, instance.relations, instance.rhs)
        length(row) == n || error("Invalid source row width.")
        f = M.ScalarAffineFunction([M.ScalarAffineTerm(Float64(a), x)
            for (a, x) in zip(row, variables) if !iszero(a)], 0.0)
        set = relation == "eq" ? M.EqualTo(Float64(rhs)) :
              relation == "le" ? M.LessThan(Float64(rhs)) :
              relation == "ge" ? M.GreaterThan(Float64(rhs)) : error("Unknown relation.")
        M.add_constraint(source, f, set)
    end
    return source
end

function source_feasible(instance::Instance, x; atol = 0.0)
    length(x) == length(instance.lower) || return false
    all(isfinite, x) || return false
    all(abs(v - round(v)) <= atol for v in x) || return false
    all(instance.lower .- atol .<= x .<= instance.upper .+ atol) || return false
    for (row, relation, rhs) in zip(instance.rows, instance.relations, instance.rhs)
        value = dot(row, x)
        valid = relation == "eq" ? abs(value - rhs) <= atol :
                relation == "le" ? value <= rhs + atol : value >= rhs - atol
        valid || return false
    end
    return true
end
source_value(instance::Instance, x) = dot(instance.costs, x)

function make_instance(family, stage, ordinal; seed = 0)
    name = family["name"]
    pilot = stage == "pilot"
    rng = MersenneTwister(seed)
    size = family[pilot ? "pilot_size" : "campaign_size"]
    rows, relations, rhs = Vector{Int}[], String[], Int[]
    addrow(row, relation, bound) = (push!(rows, row); push!(relations, relation); push!(rhs, bound))
    parameters = Dict{String,Any}()
    if name == "knapsack"
        n = only(size)
        # Draw order: all weights, then all profits, both in item order.
        weights = pilot ? [2, 1] : rand(rng, 1:family["weight_max"], n)
        profits = pilot ? [3, 2] : rand(rng, 1:9, n)
        lower, upper = zeros(Int, n), pilot ? [2, 1] : fill(family["quantity_upper"], n)
        capacity = pilot ? 3 : fld(45sum(weights .* upper), 100)
        costs, sense, witness = profits, "max", zeros(Int, n)
        addrow(weights, "le", capacity)
        merge!(parameters, Dict("weights" => weights, "profits" => profits, "capacity" => capacity))
    elseif name == "facility"
        facilities, clients = size
        # Draw order: client demands, facility fixed costs, shipping in row-major order.
        demands = pilot ? [1, 1] : rand(rng, 1:family["demand_max"], clients)
        fixed = pilot ? [4, 3] : rand(rng, 1:9, facilities)
        shipping = pilot ? [[2, 1], [1, 2]] :
                   [[rand(rng, 1:5) for _ in 1:clients] for _ in 1:facilities]
        assignments = [mod1(k, facilities) for k in 1:clients]
        capacities = pilot ? [2, 2] : [sum(demands[k] for k in 1:clients if assignments[k] == j;
            init = 0) + family["capacity_witness_margin"] for j in 1:facilities]
        n = facilities + facilities * clients
        lower, upper, witness = zeros(Int, n), ones(Int, n), zeros(Int, n)
        position(j, k) = facilities + (j - 1) * clients + k
        # Shipments q_jk=demands[k]*assignment_jk are exact integer quantities.
        costs = [fixed; [shipping[j][k] * demands[k] for j in 1:facilities for k in 1:clients]]
        sense = "min"
        for k in 1:clients
            row = zeros(Int, n)
            for j in 1:facilities
                row[position(j, k)] = 1
            end
            addrow(row, "eq", 1)
            witness[assignments[k]] = witness[position(assignments[k], k)] = 1
        end
        for j in 1:facilities, k in 1:clients
            row = zeros(Int, n)
            row[position(j, k)], row[j] = 1, -1
            addrow(row, "le", 0)
        end
        for j in 1:facilities
            row = zeros(Int, n)
            row[j] = -capacities[j]
            for k in 1:clients
                row[position(j, k)] = demands[k]
            end
            addrow(row, "le", 0)
        end
        merge!(parameters, Dict("demands" => demands, "capacities" => capacities,
            "fixed" => fixed, "shipping" => shipping, "shipment_rule" => "integer-demand-times-assignment"))
    elseif name == "inventory"
        periods = only(size)
        # Draw order: demands, setup costs, production costs, each in period order.
        demands = pilot ? [1, 1] : rand(rng, 1:3, periods)
        setups = pilot ? [2, 2] : rand(rng, 1:5, periods)
        production = pilot ? [1, 1] : rand(rng, 1:3, periods)
        quantity_upper = pilot ? 2 : family["quantity_upper"]
        stock_upper = pilot ? 2 : family["stock_upper"]
        n = 3periods
        lower = zeros(Int, n)
        upper = [fill(quantity_upper, periods); fill(stock_upper, periods); ones(Int, periods)]
        costs, sense = [production; ones(Int, periods); setups], "min"
        witness = [demands; zeros(Int, periods); ones(Int, periods)]
        for t in 1:periods
            row = zeros(Int, n)
            row[t], row[periods + t] = 1, -1
            t > 1 && (row[periods + t - 1] = 1)
            addrow(row, "eq", demands[t])
            row = zeros(Int, n)
            row[t], row[2periods + t] = 1, -quantity_upper
            addrow(row, "le", 0)
        end
        row = zeros(Int, n)
        row[2periods] = 1
        addrow(row, "eq", 0)
        merge!(parameters, Dict("demands" => demands, "setup" => setups,
            "production" => production, "holding" => ones(Int, periods),
            "initial_stock" => 0, "terminal_stock" => 0))
    elseif name == "cvrp"
        customers, vehicles, capacity = size
        # Draw order: customer demands, then each customer's x/y coordinates.
        demands = pilot ? [1, 1] : rand(rng, family["demand_min"]:family["demand_max"], customers)
        points = pilot ? [[0, 0], [1, 0], [0, 1]] :
                 vcat([[0, 0]], [Int[rand(rng, 0:5), rand(rng, 0:5)] for _ in 1:customers])
        arcs = [[i, j] for i in 0:customers for j in 0:customers if i != j]
        na, n = length(arcs), length(arcs) + customers
        lower, upper = [zeros(Int, na); demands], [ones(Int, na); fill(capacity, customers)]
        costs = [sum(abs.(points[i + 1] - points[j + 1])) for (i, j) in arcs]
        append!(costs, zeros(Int, customers))
        sense, witness = "min", zeros(Int, n)
        for node in 0:customers, direction in ("in", "out")
            row = zeros(Int, n)
            for (a, (i, j)) in enumerate(arcs)
                (direction == "in" ? j : i) == node && (row[a] = 1)
            end
            addrow(row, "eq", node == 0 ? vehicles : 1)
        end
        for i in 1:customers, j in 1:customers
            i == j && continue
            row = zeros(Int, n)
            row[na + i], row[na + j] = 1, -1
            row[findfirst(==([i, j]), arcs)] = capacity
            addrow(row, "le", capacity - demands[j])
        end
        for vehicle in 1:vehicles
            route = collect(vehicle:vehicles:customers)
            path = [0; route; 0]
            for k in 1:(length(path) - 1)
                witness[findfirst(==([path[k], path[k + 1]]), arcs)] = 1
            end
            load = 0
            for node in route
                load += demands[node]
                witness[na + node] = load
            end
        end
        merge!(parameters, Dict("demands" => demands, "points" => points,
            "arcs" => arcs, "vehicles" => vehicles, "capacity" => capacity))
    else
        throw(ArgumentError("Unknown corpus family: $name"))
    end
    id = pilot ? family["pilot_id"] : "$name-$stage-$seed"
    instance = Instance(id, name, ordinal, stage, seed, parameters, lower, upper, costs,
                        sense, rows, relations, rhs, witness)
    source_feasible(instance, witness) || error("Generator emitted an invalid witness for $id.")
    return instance
end

function corpus(protocol)
    instances = Instance[]
    for family in protocol["families"]
        ordinals = family["instance_ordinals"]
        push!(instances, make_instance(family, "pilot", ordinals[1]))
        push!(instances, make_instance(family, "tuning", ordinals[2]; seed = family["tuning_seed"]))
        for (i, seed) in enumerate(family["evaluation_seeds"])
            push!(instances, make_instance(family, "evaluation", ordinals[i + 2]; seed))
        end
    end
    return instances
end

function exact_reference(instance::Instance; max_states = 1_000_000)
    count = prod(big(u) - l + 1 for (l, u) in zip(instance.lower, instance.upper); init = big(1))
    count <= max_states || throw(ArgumentError("Exact source enumeration exceeds its reserved budget."))
    best, point, feasible = nothing, Int[], 0
    for state in Iterators.product((l:u for (l, u) in zip(instance.lower, instance.upper))...)
        x = collect(state)
        source_feasible(instance, x) || continue
        feasible += 1
        value = source_value(instance, x)
        if isnothing(best) || (instance.sense == "min" ? value < best : value > best)
            best, point = value, x
        end
    end
    return Dict{String,Any}("status" => feasible == 0 ? "EXACT_INFEASIBLE" : "EXACT_OPTIMAL",
        "objective" => isnothing(best) ? "missing" : best, "point" => point,
        "objective_bound" => isnothing(best) ? "missing" : best,
        "enumerated_states" => count, "feasible_states" => feasible,
        "certificate" => "exhaustive-original-integer-box", "source_hash" => instance_hash(instance))
end

function integral_reference_point(instance::Instance, raw_point)
    source_feasible(instance, raw_point; atol = PROTOCOL["source_feasibility_atol"]) ||
        throw(ArgumentError("Reference point violates source tolerance."))
    point = round.(Int, raw_point)
    source_feasible(instance, point; atol = 0) ||
        throw(VerificationError("Rounded reference is not exactly source feasible."))
    return point
end

function verify_corpus_hashes(instances)
    expected = TOML.parsefile(joinpath(@__DIR__, "corpus_hashes_v1.toml"))["hashes"]
    Dict(i.id => instance_hash(i) for i in instances) == expected ||
        error("Concrete corpus drifted from the published protocol-v1 hashes.")
    return true
end
