# A bounded experiment kernel, not an MOI optimizer or a hardware model.
struct Polynomial
    G::Matrix{Float64}
    g::Vector{Float64}
    constant::Float64
    lower::Vector{Int}
    upper::Vector{Int}
    sense::String
end

function validate_polynomial(p::Polynomial; max_variables = 256)
    n = length(p.g)
    n <= max_variables || throw(ArgumentError("Target dimension exceeds the compiler budget."))
    size(p.G) == (n, n) && length(p.lower) == length(p.upper) == n ||
        throw(ArgumentError("Invalid polynomial dimensions."))
    all(isfinite, p.G) && all(isfinite, p.g) && isfinite(p.constant) ||
        throw(ArgumentError("Nonfinite target coefficient."))
    all(p.lower .<= p.upper) || throw(ArgumentError("Empty target interval."))
    p.sense in ("min", "max") || throw(ArgumentError("Unknown target sense."))
    return p
end
energy(p::Polynomial, x) = dot(x, p.G * x) + dot(p.g, x) + p.constant

function delta_energy(p::Polynomial, state, site, step)
    return step * (dot(view(p.G, site, :) + view(p.G, :, site), state) + p.g[site]) +
           p.G[site, site] * step^2
end

function polynomial_record(p::Polynomial)
    return Dict{String,Any}("G" => [collect(row) for row in eachrow(p.G)], "g" => p.g,
        "constant" => p.constant, "lower" => p.lower, "upper" => p.upper, "sense" => p.sense,
        "matrix_convention" => "x'G*x+g'x+c")
end

function polynomial_from_record(r)
    n = length(r["g"])
    n <= 256 || throw(ArgumentError("Archived target exceeds allocation admission."))
    G = zeros(Float64, n, n)
    for i in 1:n
        G[i, :] = r["G"][i]
    end
    return validate_polynomial(Polynomial(G, Float64.(r["g"]), r["constant"],
        Int.(r["lower"]), Int.(r["upper"]), r["sense"]))
end

function structural_metrics(p::Polynomial)
    validate_polynomial(p)
    active = findall(p.lower .< p.upper)
    offset = Float64.(p.lower)
    G = p.G[active, active]
    g = (p.g + (p.G + p.G') * offset)[active]
    constant = energy(p, offset)
    widths = (p.upper - p.lower)[active]
    for i in eachindex(widths)
        if widths[i] == 1
            g[i] += G[i, i]
            G[i, i] = 0.0
        end
    end
    n = length(active)
    squares = [G[i, i] for i in 1:n if !iszero(G[i, i])]
    linear = filter(!iszero, g)
    couplers = [G[i, j] + G[j, i] for i in 1:n for j in (i + 1):n if !iszero(G[i, j] + G[j, i])]
    magnitudes = abs.([squares; linear; couplers])
    lo, hi = isempty(magnitudes) ? ("missing", "missing") : extrema(magnitudes)
    return Dict{String,Any}("logical_variables" => length(p.g), "active_variables" => n,
        "domain_levels" => big.(p.upper) - p.lower .+ 1,
        "binary_variables" => count(==(1), p.upper - p.lower),
        "integer_variables" => count(>(1), p.upper - p.lower),
        "nonbinary_square_terms" => length(squares), "linear_terms" => length(linear),
        "unique_couplers" => length(couplers), "density_denominator" => n * (n - 1) ÷ 2,
        "density" => n < 2 ? 0.0 : 2length(couplers) / (n * (n - 1)),
        "coefficient_min_nonzero" => lo, "coefficient_max" => hi,
        "coefficient_ratio" => isempty(magnitudes) ? "missing" : hi / lo,
        "storage" => "dense", "physical_resources" => "not-measured",
        "raw_polynomial" => polynomial_record(p),
        "canonical" => Dict("G" => [collect(row) for row in eachrow(G)], "g" => g,
                            "constant" => constant, "offset" => offset, "active" => active))
end

function temperature(index, reserved, start, finish)
    reserved >= 1 && 1 <= index <= reserved || throw(ArgumentError("Invalid schedule index."))
    isfinite(start) && isfinite(finish) && start > 0 && finish > 0 ||
        throw(ArgumentError("Temperatures must be finite and positive."))
    return reserved == 1 ? Float64(start) : start * (finish / start)^((index - 1) / (reserved - 1))
end

function metropolis(p::Polynomial, initialize, observe; seed, reserved_proposals,
                    completed_limit = reserved_proposals, max_sweeps = reserved_proposals,
                    max_seconds = 2.0, temperature_start = 2.0, temperature_end = 0.01,
                    energy_scale = 1.0, clock = time_ns, check_deltas = false)
    validate_polynomial(p)
    for value in (seed, reserved_proposals, completed_limit, max_sweeps)
        value isa Integer && !(value isa Bool) && 0 <= value <= typemax(Int) ||
            throw(ArgumentError("Seeds and work limits must be nonnegative machine integers."))
    end
    seed <= typemax(Int) - 1_000_000_000 || throw(ArgumentError("Proposal seed would overflow."))
    reserved_proposals <= 10_000 || throw(ArgumentError("Per-run work exceeds the frozen stage cap."))
    0 <= completed_limit <= reserved_proposals || throw(ArgumentError("Invalid completed-work limit."))
    reserved_proposals >= 0 && max_sweeps >= 0 || throw(ArgumentError("Negative work allowance."))
    isfinite(energy_scale) && energy_scale >= 1 || throw(ArgumentError("Invalid energy scale."))
    max_seconds > 0 || throw(ArgumentError("Nonpositive clock allowance."))
    initial_rng = MersenneTwister(seed)
    proposal_rng = MersenneTwister(seed + 1_000_000_000)
    active = findall(p.lower .< p.upper)
    sigma = p.sense == "min" ? 1 : -1
    samples = Dict{String,Any}[]
    counts = Dict("boundary" => 0, "accepted" => 0, "energy_rejected" => 0, "in_domain" => 0)
    best, best_point = nothing, Int[]
    first_feasible, first_target = nothing, nothing
    first_feasible_index, first_target_index, overshoot_target_index = nothing, nothing, nothing
    completed, observations = 0, 0
    started = clock() # Includes initialization, canonical lifting and source observations.
    elapsed() = Float64(clock() - started) / 1.0e9
    state = Int.(initialize(initial_rng))
    length(state) == length(p.g) && all(p.lower .<= state .<= p.upper) ||
        throw(VerificationError("Initializer returned an invalid target state."))
    initial = copy(state)
    function visit(index)
        outcome = observe(state)
        observations += 1
        spent = elapsed() # A target is timely only when its observation has finished.
        if outcome.feasible
            value = outcome.objective
            isfinite(value) || throw(VerificationError("Nonfinite decoded source objective."))
            if isnothing(best) || (outcome.sense == "min" ? value < best : value > best)
                best, best_point = value, copy(outcome.source)
            end
            if isnothing(first_feasible)
                first_feasible, first_feasible_index = spent, index
            end
            if outcome.target && isnothing(first_target)
                if spent <= max_seconds
                    first_target, first_target_index = spent, index
                elseif isnothing(overshoot_target_index)
                    overshoot_target_index = index
                end
            end
        end
        return outcome
    end
    function sample(index, outcome)
        if !isempty(samples) && samples[end]["state"] == state
            samples[end]["multiplicity"] += 1
            samples[end]["last_proposal"] = index
        else
            push!(samples, Dict{String,Any}("state" => copy(state), "multiplicity" => 1,
                "first_proposal" => index, "last_proposal" => index,
                "source" => copy(outcome.source), "source_feasible" => outcome.feasible,
                "source_objective" => outcome.objective))
        end
    end
    outcome = visit(0)
    sample(0, outcome)
    proposal_limit = isempty(active) ? 0 : Int(min(big(completed_limit), big(max_sweeps) * length(active)))
    termination = isempty(active) ? "fixed-target" : "proposal-cap"
    for index in 1:proposal_limit
        if elapsed() >= max_seconds
            termination = "clock-censored"
            break
        end
        # Fixed draw sequence: site, sign, acceptance uniform, even on boundary rejection.
        site = active[rand(proposal_rng, 1:length(active))]
        step = rand(proposal_rng, Bool) ? 1 : -1
        draw = rand(proposal_rng)
        candidate = state[site] + step
        if candidate < p.lower[site] || candidate > p.upper[site]
            counts["boundary"] += 1
        else
            counts["in_domain"] += 1
            delta = delta_energy(p, state, site, step)
            if check_deltas
                proposed = copy(state)
                proposed[site] = candidate
                isapprox(delta, energy(p, proposed) - energy(p, state); atol = 1e-9, rtol = 1e-12) ||
                    throw(VerificationError("Incremental/full energy disagreement."))
            end
            normalized = sigma * delta / energy_scale
            T = temperature(index, reserved_proposals, temperature_start, temperature_end)
            if normalized <= 0 || draw < exp(-normalized / T)
                state[site] = candidate
                counts["accepted"] += 1
            else
                counts["energy_rejected"] += 1
            end
        end
        completed = index
        outcome = visit(index) # Observe chain state after every decision, including rejects.
        index % length(active) == 0 && sample(index, outcome)
    end
    completed > 0 && completed % max(1, length(active)) != 0 && sample(completed, outcome)
    spent = elapsed()
    spent > max_seconds && termination in ("proposal-cap", "fixed-target") && (termination = "clock-censored")
    counts["boundary"] + counts["accepted"] + counts["energy_rejected"] == completed ||
        throw(VerificationError("Move-count total disagrees with completed work."))
    counts["in_domain"] == counts["accepted"] + counts["energy_rejected"] ||
        throw(VerificationError("In-domain move counts disagree."))
    missing_value(x) = isnothing(x) ? "missing" : x
    return Dict{String,Any}("seed" => seed, "initialization_seed" => seed,
        "proposal_seed" => seed + 1_000_000_000, "reserved_proposals" => reserved_proposals,
        "completed_proposals" => completed, "max_sweeps" => max_sweeps,
        "max_seconds" => max_seconds, "temperature_start" => temperature_start,
        "temperature_end" => temperature_end, "energy_scale" => energy_scale,
        "initial" => initial, "final" => state, "samples" => samples, "move_counts" => counts,
        "source_observations" => observations, "best_feasible_objective" => missing_value(best),
        "best_feasible_source" => best_point, "any_feasible" => !isnothing(best),
        "first_feasible_seconds" => missing_value(first_feasible),
        "first_feasible_proposal" => missing_value(first_feasible_index),
        "first_target_seconds" => missing_value(first_target),
        "first_target_proposal" => missing_value(first_target_index),
        "overshoot_target_proposal" => missing_value(overshoot_target_index),
        "timely_target" => !isnothing(first_target), "elapsed_seconds" => spent,
        "termination" => termination, "clock_censored" => termination == "clock-censored",
        "target_time_score" => isnothing(first_target) ? max_seconds : first_target,
        "target_work_score" => isnothing(first_target_index) ? reserved_proposals : first_target_index,
        "rng_draw_contract" => "active-site/sign/acceptance-uniform-even-on-rejection",
        "samples_scope" => "initial-complete-sweeps-and-final-partial-sweep-ordered-RLE")
end
