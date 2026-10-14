# Frozen protocol helpers shared by the worked example and experiment adapters.
function protocol_layout(width::Integer; levels::Integer, max_weight = nothing, max_digits = 256)
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
    # Match the package's authoritative lift: decreasing weight, stable ties.
    for i in sortperm(weights; rev = true)
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
