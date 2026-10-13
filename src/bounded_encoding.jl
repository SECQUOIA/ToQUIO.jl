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
It does not certify hardware admissibility. Construction uses BigInt arithmetic;
integer map entries must be exactly representable in the coefficient type and
nonfinite transformed coefficients are rejected. Floating products retain that
type's precision and finite rounding is not detected. `max_digits`
limits each coordinate's construction; MaxEncodedVariables() separately limits
the complete target. Neither is a verified device capability.
"""
struct BoundedEncoding{I<:Integer,J<:Integer} <: AbstractIntegerEncoding
    levels::I
    max_weight::J
    max_digits::Int

    function BoundedEncoding(; max_weight = 2, levels = 4, max_digits = 256)
        max_weight isa Integer && !(max_weight isa Bool) && max_weight >= 1 ||
            throw(ArgumentError("Bounded max_weight must be a positive integer."))
        levels isa Integer && !(levels isa Bool) && levels >= 2 ||
            throw(ArgumentError("Bounded levels must be an integer of at least two."))
        max_digits isa Integer && !(max_digits isa Bool) && 1 <= max_digits <= typemax(Int) ||
            throw(ArgumentError("Bounded max_digits must be a positive machine-sized integer."))
        I = levels <= typemax(Int) ? Int : BigInt
        J = max_weight <= typemax(Int) ? Int : BigInt
        return new{I,J}(I(levels), J(max_weight), Int(max_digits))
    end
end

function variable_encoding(strategy::BoundedEncoding, lower::Integer, upper::Integer; context)
    return _bounded_tail_encoding(lower, upper, strategy.levels, strategy.max_digits;
                                  max_weight = strategy.max_weight, strategy_name = "Bounded")
end

encoding_descriptor(strategy::BoundedEncoding) = Dict{String,Any}(
    "name" => "bounded", "construction" => "exact-bounded-tail-v1",
    "levels" => strategy.levels, "max_weight" => strategy.max_weight,
    "max_digits" => strategy.max_digits,
)
