mutable struct EnumerationBudget
    per_call::Int
    total::Int
    reserved::Int
end
EnumerationBudget() = EnumerationBudget(1_000_000, 4_000_000, 0)
function reserve_enumeration!(budget::EnumerationBudget, count)
    0 <= count <= budget.per_call && big(budget.reserved) + count <= budget.total ||
        throw(ArgumentError("Preflight enumeration budget refused; campaign incomplete."))
    budget.reserved += Int(count)
    return count
end

function reconstructed_polynomial(cell::CompiledCell)
    p, maps = cell.polynomial, cell.maps
    nsource, n = length(cell.instance.lower), length(p.g)
    original_B, original_offset = zeros(nsource, n), zeros(nsource)
    for (i, map) in enumerate(maps[1:nsource])
        original_offset[i] = map.offset
        original_B[i, map.positions] = map.weights
    end
    G, g = zeros(n, n), original_B' * cell.instance.costs
    constant = dot(cell.instance.costs, original_offset)
    for penalty in cell.penalty_rows
        penalty["form"] == "removed" && continue
        row, divisor = penalty["row"], penalty["divisor"]
        sigma = cell.instance.relations[row] == "ge" ? -1 : 1
        a = sigma .* (original_B' * cell.instance.rows[row]) ./ divisor
        c = sigma * (dot(cell.instance.rows[row], original_offset) - cell.instance.rhs[row]) / divisor
        if penalty["slack_map"] > 0
            slack = maps[penalty["slack_map"]]
            c += slack.offset
            a[slack.positions] .+= slack.weights
        end
        rho = penalty["coefficient"]
        if penalty["form"] == "square"
            G .+= rho .* (a * a')
            g .+= 2rho * c .* a
            constant += rho * c^2
        elseif penalty["form"] == "linear"
            g .+= rho .* a
            constant += rho * c
        else
            error("Unknown independent penalty reconstruction.")
        end
    end
    return validate_polynomial(Polynomial(G, g, constant, p.lower, p.upper, p.sense))
end

function compare_polynomials(actual::Polynomial, expected::Polynomial)
    a, b = structural_metrics(actual)["canonical"], structural_metrics(expected)["canonical"]
    a["active"] == b["active"] || error("Canonical polynomial domains differ.")
    n = length(a["g"])
    close(x, y) = isapprox(x, y; atol = PROTOCOL["energy_parity_atol"], rtol = PROTOCOL["energy_parity_rtol"])
    close(a["constant"], b["constant"]) || error("Polynomial constant parity failed.")
    all(close(x, y) for (x, y) in zip(a["g"], b["g"])) || error("Polynomial linear parity failed.")
    for i in 1:n
        close(a["G"][i][i], b["G"][i][i]) || error("Polynomial diagonal parity failed.")
        for j in (i + 1):n
            close(a["G"][i][j] + a["G"][j][i], b["G"][i][j] + b["G"][j][i]) ||
                error("Polynomial unique-coupler parity failed.")
        end
    end
    return true
end

function validate_map(cell::CompiledCell, map::CoordinateMap)
    width = big(map.upper) - map.lower
    0 <= width <= 64 || error("Emitted map exceeds width admission.")
    length(map.positions) == length(map.weights) == length(map.digit_lower) == length(map.digit_upper) ||
        error("Invalid emitted map dimensions.")
    all(>(0), map.weights) && all(map.digit_lower .<= map.digit_upper) || error("Invalid digit domain.")
    low = big(map.offset) + sum(big(w) * l for (w, l) in zip(map.weights, map.digit_lower); init = big(0))
    high = big(map.offset) + sum(big(w) * u for (w, u) in zip(map.weights, map.digit_upper); init = big(0))
    low == map.lower && high == map.upper || error("Emitted image endpoints are wrong.")
    if cell.arm == "native"
        map.offset == 0 && map.weights == [1] &&
            map.digit_lower == [map.lower] && map.digit_upper == [map.upper] || error("Not an identity map.")
    else
        levels = startswith(cell.arm, "toqubo") ? 2 : PROTOCOL["levels"]
        cap = cell.weight_cap == 0 ? nothing : cell.weight_cap
        weights, uppers = protocol_layout(Int(width); levels, max_weight = cap)
        map.offset == map.lower && map.weights == weights && map.digit_upper == uppers &&
            all(iszero, map.digit_lower) || error("Emitted map differs from declared strategy.")
    end
    # Independent DP consumes actual emitted digits, never calls the constructor.
    reachable = Set([big(map.offset)])
    for (weight, lower, upper) in zip(map.weights, map.digit_lower, map.digit_upper)
        reachable = Set(value + weight * digit for value in reachable for digit in lower:upper)
        length(reachable) <= 65 || error("Emitted-map DP exceeds its admitted image.")
    end
    reachable == Set(big(map.lower):big(map.upper)) || error("Emitted map has holes or extra values.")
    for value in map.lower:map.upper
        digits = lift_map(map, value)
        map.offset + dot(map.weights, digits) == value || error("Per-coordinate lift failed.")
    end
    return true
end

function layout_identity(cell::CompiledCell)
    return [Dict("kind" => m.kind, "row" => m.row, "lower" => m.lower, "upper" => m.upper,
        "offset" => m.offset + dot(m.weights, m.digit_lower),
        "digits" => sort([[w, u - l] for (w, l, u) in
            zip(m.weights, m.digit_lower, m.digit_upper) if u > l])) for m in cell.maps]
end

function preflight(cell::CompiledCell, reference; budget = EnumerationBudget(), exhaustive = false,
                   reservation_hook = () -> nothing)
    validate_polynomial(cell.polynomial)
    foreach(map -> validate_map(cell, map), cell.maps)
    positions = sort([p for map in cell.maps for p in map.positions])
    positions == collect(eachindex(cell.polynomial.g)) || error("Digits do not partition across emitted maps.")
    compare_polynomials(cell.polynomial, reconstructed_polynomial(cell))
    arm_index = findfirst(==(cell.arm), PROTOCOL["arms"])
    regime_index = findfirst(==(cell.regime), PROTOCOL["regimes"])
    seed = PROTOCOL["preflight"]["random_seed"] + 10_000cell.instance.ordinal +
           100arm_index + 10regime_index + cell.weight_cap
    rng = MersenneTwister(seed)
    state_count = prod(big(u) - l + 1 for (l, u) in
        zip(cell.polynomial.lower, cell.polynomial.upper); init = big(1))
    examined = 0
    function parity(state)
        isapprox(energy(cell.polynomial, state), independent_energy(cell, state);
            atol = PROTOCOL["energy_parity_atol"], rtol = PROTOCOL["energy_parity_rtol"]) ||
            error("Constant/sense-inclusive source-penalty parity failed.")
        examined += 1
    end
    for _ in 1:PROTOCOL["preflight"]["random_digit_states_per_cell"]
        parity([rand(rng, l:u) for (l, u) in zip(cell.polynomial.lower, cell.polynomial.upper)])
    end
    for point in (cell.instance.witness, reference["point"])
        lifted = reference_lift(cell, point)
        decoded_source(cell, lifted) == point || error("Reference lift source roundtrip failed.")
        cell_observer(cell, reference["objective"])(lifted).feasible || error("Lifted reference is infeasible.")
        parity(lifted)
    end
    optimum = nothing
    if exhaustive
        reserve_enumeration!(budget, state_count)
        reservation_hook()
        for state in Iterators.product((l:u for (l, u) in zip(cell.polynomial.lower, cell.polynomial.upper))...)
            x = collect(state)
            parity(x)
            value = energy(cell.polynomial, x)
            if isnothing(optimum) || (cell.polynomial.sense == "min" ? value < optimum : value > optimum)
                optimum = value
            end
        end
        isapprox(optimum, reference["objective"]; atol = PROTOCOL["energy_parity_atol"],
                 rtol = PROTOCOL["energy_parity_rtol"]) || error("Exact encoded/source optimum disagreement.")
    end
    return Dict{String,Any}("status" => "passed", "rng_seed" => seed,
        "random_states" => PROTOCOL["preflight"]["random_digit_states_per_cell"],
        "examined_states" => examined, "target_state_count" => state_count,
        "exhaustive" => exhaustive, "target_optimum" => isnothing(optimum) ? "not-enumerated" : optimum,
        "polynomial_coefficients_verified" => true, "emitted_map_DP_verified" => true,
        "layout_identity" => layout_identity(cell))
end
