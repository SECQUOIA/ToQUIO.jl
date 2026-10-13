# Executable scientific specification, not a public encoding implementation.
using ToQUIO
const protocol_dot = ToQUIO.LinearAlgebra.dot
const PMOI = ToQUIO.MOI

function protocol_layout(width::Integer; levels::Integer, max_weight = nothing, max_digits = 128)
    width >= 0 && levels >= 2 || throw(ArgumentError("Invalid interval/level limit."))
    isnothing(max_weight) || (max_weight isa Integer && max_weight >= 1) ||
        throw(ArgumentError("Invalid weight cap."))
    max_digits >= 1 || throw(ArgumentError("Invalid digit allocation limit."))
    weights, uppers = BigInt[], BigInt[]
    covered = big(0)
    while covered < width
        remaining = big(width) - covered
        weight = min(covered + 1, remaining)
        isnothing(max_weight) || (weight = min(weight, max_weight))
        upper = min(big(levels) - 1, remaining ÷ weight)
        length(weights) < max_digits || throw(ArgumentError("Digit allocation exceeds its limit."))
        push!(weights, weight)
        push!(uppers, upper)
        covered += weight * upper
    end
    return weights, uppers
end

function protocol_canonical_lift(value::Integer, weights, uppers)
    0 <= value <= sum(weights .* uppers; init = big(0)) ||
        throw(ArgumentError("Value outside the encoded interval."))
    digits = zeros(BigInt, length(weights))
    remainder = big(value)
    for i in reverse(eachindex(weights))
        digits[i] = min(uppers[i], remainder ÷ weights[i])
        remainder -= weights[i] * digits[i]
    end
    iszero(remainder) || error("Invalid coverage construction.")
    return digits
end

function protocol_state_count(uppers; limit::Integer)
    limit >= 1 || throw(ArgumentError("Enumeration budget must be positive."))
    count = big(1)
    for upper in uppers
        upper >= 0 || throw(ArgumentError("Negative digit bound."))
        count *= big(upper) + 1
        count <= limit || throw(ArgumentError("Enumeration exceeds its predeclared limit."))
    end
    return count
end

function protocol_affine_substitution(G, g, gamma, offset, expansion)
    result = (
        G = expansion' * G * expansion,
        g = expansion' * (g + (G + G') * offset),
        gamma = protocol_dot(offset, G * offset) + protocol_dot(g, offset) + gamma,
    )
    all(isfinite, result.G) && all(isfinite, result.g) && isfinite(result.gamma) ||
        throw(ArgumentError("Affine substitution produced nonfinite coefficients."))
    return result
end

function protocol_knapsack()
    source = PMOI.Utilities.Model{Float64}()
    x, y = PMOI.add_variables(source, 2)
    for (vi, upper) in ((x, 2.0), (y, 1.0))
        PMOI.add_constraint(source, vi, PMOI.Interval(0.0, upper))
        PMOI.add_constraint(source, vi, PMOI.Integer())
    end
    objective = PMOI.ScalarAffineFunction([
        PMOI.ScalarAffineTerm(3.0, x), PMOI.ScalarAffineTerm(2.0, y),
    ], 0.0)
    PMOI.set(source, PMOI.ObjectiveFunction{typeof(objective)}(), objective)
    PMOI.set(source, PMOI.ObjectiveSense(), PMOI.MAX_SENSE)
    capacity = PMOI.ScalarAffineFunction([
        PMOI.ScalarAffineTerm(2.0, x), PMOI.ScalarAffineTerm(1.0, y),
    ], 0.0)
    PMOI.add_constraint(source, capacity, PMOI.LessThan(3.0))
    optimizer = ToQUIO.Optimizer()
    PMOI.optimize!(optimizer, source)
    return optimizer
end

function protocol_example()
    optimizer = protocol_knapsack()
    data = optimizer.data
    G, g, gamma = data[:Q], data[:L], data[:c]
    native_value(z) = protocol_dot(z, G * z) + protocol_dot(g, z) + gamma
    # x=d1+d2, y=d3, s=d4+2d5: exact bounded binary maps of widths 2,1,3.
    expansion = Float64[1 1 0 0 0; 0 0 1 0 0; 0 0 0 1 2]
    transformed = protocol_affine_substitution(G, g, gamma, zeros(3), expansion)
    binary_value(d) = protocol_dot(d, transformed.G * d) + protocol_dot(transformed.g, d) + transformed.gamma
    protocol_state_count([2, 1, 3]; limit = 1_000_000)
    protocol_state_count(ones(Int, 5); limit = 1_000_000)
    native_states = [collect(z) for z in Iterators.product(0:2, 0:1, 0:3)]
    binary_states = [collect(d) for d in Iterators.product(ntuple(_ -> 0:1, 5)...)]
    images = [expansion * d for d in binary_states]
    @assert Set(Tuple(z) for z in images) == Set(Tuple(z) for z in native_states)
    @assert all(binary_value(d) == native_value(expansion * d) for d in binary_states)
    source_points = [(x, y) for x in 0:2 for y in 0:1 if 2x + y <= 3]
    reference = maximum(3x + 2y for (x, y) in source_points)
    native_optimum = maximum(native_value(z) for z in native_states)
    binary_optimum = maximum(binary_value(d) for d in binary_states)
    @assert all(ToQUIO.is_feasible(data, z) for z in native_states if native_value(z) == native_optimum)
    # Independent low-penalty failure illustration; no automatic penalty claim.
    weak_value(z) = 3z[1] + 2z[2] - 0.25 * (2z[1] + z[2] + z[3] - 3)^2
    weak_best = native_states[argmax(weak_value.(native_states))]
    return (
        source_optimum = reference, automatic_penalty = only(data[:rho]),
        native_optimum = native_optimum, binary_optimum = binary_optimum,
        native_states = length(native_states), binary_states = length(binary_states),
        decoded_states = length(Set(Tuple(z) for z in images)),
        weak_optimum = weak_value(weak_best), weak_source_feasible = ToQUIO.is_feasible(data, weak_best),
    )
end

let result = protocol_example()
    println(result)
    result
end
