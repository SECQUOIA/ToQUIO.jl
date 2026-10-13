@doc raw"""
    BoundedEncoding(; max_weight = 2, levels = 4, max_digits = 256)

Exact bounded-weight integer encoding for original variables and generated
slacks. `max_weight` must be a positive integer and `levels` an integer of at
least two. The default optimizer remains NativeEncoding(); select this strategy
explicitly. Parameters and actual maps are recorded in the encoding metadata.

For width W and coverage C, append w = min(C + 1, W - C, max_weight),
m = min(levels - 1, (W - C) ÷ w), then increase C by w*m. This covers exactly
the original integer interval without enforcement penalties. Fixed coordinates
need no digit; negative/shifted offsets and nonunique representations are allowed.
Levels two is a bounded-weight binary special case. Lower caps can increase the
digit count and change sampling multiplicities and neighborhoods.

The cap bounds encoding weights, not the final quadratic/linear coefficients:
source coefficients, offsets and unchanged native penalties can amplify them.
It does not certify hardware admissibility. BigInt construction and the existing
coefficient-type checks reject lossy or overflowing arithmetic. `max_digits`
limits each coordinate's construction; MaxEncodedVariables() separately limits
the complete target. Neither is a verified device capability.
"""
struct BoundedEncoding{I<:Integer,J<:Integer} <: AbstractIntegerEncoding
    levels::I
    max_weight::J
    max_digits::Int

    function BoundedEncoding(; max_weight = 2, levels = 4, max_digits = 256)
        max_weight isa Integer && !(max_weight isa Bool) && max_weight >= 1 ||
            throw(ArgumentError("max_weight must be a positive integer."))
        # Reuse the radix level/allocation contract; no backend is constructed.
        radix = RadixEncoding(; levels, max_digits)
        J = max_weight <= typemax(Int) ? Int : BigInt
        return new{typeof(radix.levels),J}(radix.levels, J(max_weight), radix.max_digits)
    end
end

function variable_encoding(strategy::BoundedEncoding, lower::Integer, upper::Integer; context)
    return _bounded_tail_encoding(lower, upper, strategy.levels, strategy.max_digits;
                                  max_weight = strategy.max_weight)
end

encoding_descriptor(strategy::BoundedEncoding) = Dict{String,Any}(
    "name" => "bounded", "construction" => "exact-bounded-tail-v1",
    "levels" => strategy.levels, "max_weight" => strategy.max_weight,
    "max_digits" => strategy.max_digits,
)
