@doc raw"""
    RadixEncoding(; levels = 4, max_digits = 256)

Exact bounded-tail radix encoding of native integer variables and generated
slacks. Each digit has at most `levels` values, including zero. The integer level
cap must be at least two. Fixed variables need no digit; a domain already fitting
the cap uses one weight-one digit and its original integer lower endpoint.

For width W and previously covered endpoint C, append weight
w = min(C + 1, W - C), upper bound m = min(levels - 1, (W - C) ÷ w),
and increase C by w*m until C = W. Coverage is contiguous because w ≤ C_old + 1;
the endpoint equals W exactly. A bounded tail can create duplicate representations.
Levels two gives the bounded-tail binary special case, without a performance claim.

`max_digits` bounds layout construction per native coordinate before allocation
can grow without limit. `MaxEncodedVariables()` separately bounds the total
compiled digit count. Both default to 256 and can be configured independently.
Construction uses checked arbitrary-precision integer arithmetic; the compiler
rejects integers not exactly representable in its coefficient type.
"""
struct RadixEncoding{I<:Integer} <: AbstractIntegerEncoding
    levels::I
    max_digits::Int

    function RadixEncoding(; levels = 4, max_digits = 256)
        levels isa Integer && !(levels isa Bool) && levels >= 2 ||
            throw(ArgumentError("Radix levels must be an integer of at least two."))
        max_digits isa Integer && !(max_digits isa Bool) && 1 <= max_digits <= typemax(Int) ||
            throw(ArgumentError("max_digits must be a positive machine-sized integer."))
        I = levels <= typemax(Int) ? Int : BigInt
        return new{I}(I(levels), Int(max_digits))
    end
end

function variable_encoding(strategy::RadixEncoding, lower::Integer, upper::Integer; context)
    return _bounded_tail_encoding(lower, upper, strategy.levels, strategy.max_digits)
end

function _bounded_tail_digit_count(width, levels, max_weight)
    remaining, power, count = big(width), big(1), big(0)
    cap = isnothing(max_weight) ? remaining + 1 : big(max_weight)
    radix_upper = big(levels) - 1
    # Full radix digits have weights 1, levels, levels^2, ... . Once the
    # weight cap binds, count repeated full digits by division, not allocation.
    while power <= cap && power * radix_upper <= remaining
        remaining -= power * radix_upper
        power *= levels
        count += 1
    end
    iszero(remaining) && return count
    weight = min(power, cap, remaining)
    repetitions, tail = divrem(remaining, weight * radix_upper)
    count += repetitions
    if !iszero(tail)
        count += 1
        tail >= weight && !iszero(tail % weight) && (count += 1)
    end
    return count
end

function _bounded_tail_encoding(lower::Integer, upper::Integer, levels, max_digits;
                                max_weight = nothing, strategy_name = "Radix")
    !(lower isa Bool || upper isa Bool) && lower <= upper ||
        throw(ArgumentError("Integer encoding requires a nonempty integer interval."))
    width, covered = big(upper) - lower, big(0)
    required = _bounded_tail_digit_count(width, levels, max_weight)
    if required > max_digits
        cap_text = isnothing(max_weight) ? "uncapped" : string(max_weight)
        suggestion = isnothing(max_weight) ? "max_digits or levels" : "max_digits, max_weight or levels"
        throw(ArgumentError("$strategy_name width=$width with levels=$levels and " *
                            "max_weight=$cap_text requires $required digits; " *
                            "max_digits=$max_digits. Increase $suggestion."))
    end
    weights, uppers = BigInt[], BigInt[]
    while covered < width
        remaining = width - covered
        weight = min(covered + 1, remaining)
        isnothing(max_weight) || (weight = min(weight, max_weight))
        bound = min(big(levels) - 1, remaining ÷ weight)
        push!(weights, weight)
        push!(uppers, bound)
        covered += weight * bound
    end
    return IntegerVariableEncoding(lower, weights, uppers)
end

encoding_descriptor(strategy::RadixEncoding) = Dict{String,Any}(
    "name" => "radix", "construction" => "exact-bounded-tail-v1",
    "levels" => strategy.levels, "max_digits" => strategy.max_digits,
)
