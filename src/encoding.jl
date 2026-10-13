@doc raw"""
    AbstractIntegerEncoding

Extension point for an exact, independent affine map of each native QUIO integer
variable, including generated slacks. Implement variable_encoding for a strategy.
The native polynomial and its already chosen penalties are transformed once;
strategies cannot add constraints or enforcement penalties.
"""
abstract type AbstractIntegerEncoding end

@doc raw"""
    NativeEncoding()

Keep the native reformulation unchanged, including fixed variables, legacy data
keys, result access and schema version 1. This is the default.
"""
struct NativeEncoding <: AbstractIntegerEncoding end

@doc raw"""
    IntegerVariableEncoding(offset, weights, upper_bounds)

An exact local map z = offset + sum(weights .* digits), with integer digits in
0:upper_bounds. Weights and active upper bounds must be positive integers;
empty vectors represent a fixed variable. Inputs are copied. Checked BigInt
arithmetic verifies that sorted weights cover every integer from zero to the
endpoint sum without gaps. The compiler also checks that this image equals the
native interval. Representations may be nonunique.
"""
struct IntegerVariableEncoding{I<:Integer}
    offset::I
    weights::Vector{I}
    upper_bounds::Vector{I}

    function IntegerVariableEncoding(offset, weights::AbstractVector, uppers::AbstractVector)
        Base.require_one_based_indexing(weights, uppers)
        offset isa Integer && !(offset isa Bool) ||
            throw(ArgumentError("An encoding offset must be an integer."))
        length(weights) == length(uppers) ||
            throw(DimensionMismatch("Encoding weights and digit bounds must match."))
        all(x -> x isa Integer && !(x isa Bool) && x > 0, weights) &&
            all(x -> x isa Integer && !(x isa Bool) && x > 0, uppers) ||
            throw(ArgumentError("Active weights and digit upper bounds must be positive integers."))
        w, m = BigInt.(weights), BigInt.(uppers)
        covered = big(0)
        for i in sortperm(w)
            w[i] <= covered + 1 || throw(ArgumentError("Encoding weights leave an interval gap."))
            covered += w[i] * m[i]
        end
        values = [big(offset); w; m]
        I = all(typemin(Int) <= x <= typemax(Int) for x in values) ? Int : BigInt
        return new{I}(I(offset), I.(w), I.(m))
    end
end

@doc raw"""
    variable_encoding(strategy, lower::Integer, upper::Integer; context)

Return an IntegerVariableEncoding for one native coordinate in lower:upper.
Context is a named tuple with native_position, native_variable, role
(:original or :slack), source_variable and source_constraint. A global strategy
is applied to all coordinates; its method may choose layouts by this context.
There are no separate per-variable/slack MOI settings. Strategy parameters belong
to the strategy object. Returned digits always have zero lower bounds.
"""
function variable_encoding(strategy::AbstractIntegerEncoding, lower, upper; context)
    throw(ArgumentError("No variable_encoding method for $(typeof(strategy))."))
end

function variable_encoding(::NativeEncoding, lower::Integer, upper::Integer; context)
    return lower == upper ? IntegerVariableEncoding(lower, Int[], Int[]) :
        IntegerVariableEncoding(lower, [1], [big(upper) - lower])
end

@doc raw"""
    encoding_descriptor(strategy)

Return string-keyed JSON-friendly provenance for a strategy. The default records
its type name. Parameterized extensions should override this method to record
their parameters. Actual offsets, weights and digit bounds are always recorded
independently in the compiled metadata.
"""
encoding_descriptor(strategy::AbstractIntegerEncoding) =
    Dict{String,Any}("name" => string(typeof(strategy)))

function _encoding_options(strategy, limit)
    strategy isa AbstractIntegerEncoding ||
        throw(ArgumentError("encoding must be an AbstractIntegerEncoding instance."))
    limit isa Integer && !(limit isa Bool) && 1 <= limit <= typemax(Int) ||
        throw(ArgumentError("max_encoded_variables must be a positive machine-sized integer."))
    return strategy, Int(limit)
end

function _exact_encoding_number(::Type{T}, value::Integer) where {T}
    converted = try
        convert(T, value)
    catch error
        error isa Union{InexactError,OverflowError,MethodError} || rethrow()
        throw(ArgumentError("Encoding integer cannot be represented by $T."))
    end
    isfinite(converted) && isinteger(converted) && BigInt(converted) == value ||
        throw(ArgumentError("Encoding integer loses precision in $T."))
    return converted
end

_encoding_width(layout::IntegerVariableEncoding) =
    sum(big(w) * m for (w, m) in zip(layout.weights, layout.upper_bounds); init = big(0))

function _decode_layout(layout::IntegerVariableEncoding, digits::AbstractVector)
    length(digits) == length(layout.weights) ||
        throw(DimensionMismatch("A local digit state has the wrong length."))
    value = layout.offset
    for (w, d) in zip(layout.weights, digits)
        d isa Real && isfinite(d) || throw(ArgumentError("Digits must be finite real numbers."))
        # Integer samples must not silently overflow machine arithmetic.
        value = _affine_add(value, w, d)
        isfinite(value) || throw(ArgumentError("Decoded value overflowed."))
    end
    return _finish_affine_decode(value)
end

struct _ExactFloatSum
    value::Rational{BigInt}
end
Base.isfinite(value::_ExactFloatSum) = isfinite(value.value)

function _affine_add(value, coefficient, sample)
    hardware = Union{Float16,Float32,Float64}
    if value isa _ExactFloatSum
        if coefficient isa Integer && sample isa Union{Integer,Rational,hardware}
            return _ExactFloatSum(value.value + big(coefficient) * Rational{BigInt}(sample))
        end
        return value.value + coefficient * sample
    end
    if value isa Integer && coefficient isa Integer && sample isa Integer
        result = big(value) + big(coefficient) * sample
        I = promote_type(typeof(value), typeof(coefficient), typeof(sample))
        if isbitstype(I) && typemin(I) <= result <= typemax(I)
            return convert(I, result)
        end
        return result
    end
    if value isa Union{Integer,hardware} && coefficient isa Integer &&
       sample isa Union{Integer,hardware}
        floating = sample isa hardware ? typeof(sample) :
                   value isa hardware ? typeof(value) : Float64
        limit = maxintfloat(floating)
        product = coefficient * sample
        rounded = value + product
        magnitude = value isa Integer ? abs(big(value)) : abs(value)
        if value isa BigInt || coefficient isa BigInt || magnitude >= limit || abs(big(coefficient)) >= limit ||
           !isfinite(product) || abs(product) >= limit || !isfinite(rounded) || abs(rounded) >= limit
            # Hardware floats are exact dyadic rationals. Retain this accumulator
            # until decoding finishes, rather than rounding between digit terms.
            exact = Rational{BigInt}(value) + big(coefficient) * Rational{BigInt}(sample)
            if rounded isa hardware && isfinite(rounded) && Rational{BigInt}(rounded) == exact
                return rounded
            end
            return _ExactFloatSum(exact)
        end
        return rounded
    end
    return value + coefficient * sample
end

function _finish_affine_decode(accumulator::_ExactFloatSum)
    value = accumulator.value
    ispow2(denominator(value)) || return value
    # A dyadic denominator needs no extra significand bits. This is per-value
    # precision and does not change the process-wide BigFloat precision.
    bits = max(precision(BigFloat), ndigits(abs(numerator(value)); base = 2))
    exponent = ndigits(denominator(value); base = 2) - 1
    sign = value < 0 ? "-" : ""
    binary = sign * "0b" * string(abs(numerator(value)); base = 2) * "p-" * string(exponent)
    # The string constructor initializes MPFR storage at the requested precision;
    # unlike the Julia 1.10 rational constructor, it does not set global defaults.
    return BigFloat(binary; precision = bits)
end
_finish_affine_decode(value) = value

function _canonical_digits(layout::IntegerVariableEncoding, value)
    value isa Real && isfinite(value) && isinteger(value) ||
        throw(ArgumentError("Canonical lifting requires finite integer native values."))
    remainder = BigInt(value) - layout.offset
    0 <= remainder <= _encoding_width(layout) ||
        throw(ArgumentError("Native value is outside its encoding interval."))
    digits = zeros(BigInt, length(layout.weights))
    for i in sortperm(layout.weights; rev = true)
        digits[i] = min(big(layout.upper_bounds[i]), remainder ÷ layout.weights[i])
        remainder -= digits[i] * layout.weights[i]
    end
    iszero(remainder) || throw(ArgumentError("Encoding has no canonical lift for this value."))
    return digits
end

function _emit_quadratic(G::AbstractMatrix{T}, g::AbstractVector{T}, constant::T, variables) where {T}
    quadratic, affine = MOI.ScalarQuadraticTerm{T}[], MOI.ScalarAffineTerm{T}[]
    for i in eachindex(variables)
        diagonal = 2 * G[i, i]
        isfinite(diagonal) || throw(ArgumentError("MOI diagonal coefficient overflowed."))
        iszero(diagonal) || push!(quadratic, MOI.ScalarQuadraticTerm(diagonal, variables[i], variables[i]))
        iszero(g[i]) || push!(affine, MOI.ScalarAffineTerm(g[i], variables[i]))
        for j in (i + 1):length(variables)
            coefficient = G[i, j] + G[j, i]
            isfinite(coefficient) || throw(ArgumentError("MOI off-diagonal coefficient overflowed."))
            iszero(coefficient) ||
                push!(quadratic, MOI.ScalarQuadraticTerm(coefficient, variables[i], variables[j]))
        end
    end
    return MOI.ScalarQuadraticFunction(quadratic, affine, constant)
end

function _encode_native_quio(::Type{T}, native, data, strategy, limit) where {T}
    strategy, limit = _encoding_options(strategy, limit)
    strategy isa NativeEncoding && return native, data
    native_metadata = reformulation_metadata(data)
    variables = _quio_variables(data)
    source_owner = Dict(target => source for (source, target) in data[:source_to_target_variables])
    slack_owner = Dict(zip(data[:slack_variables], data[:slack_constraints]))
    layouts, positions = IntegerVariableEncoding[], Vector{Int}[]
    total = 0
    for (i, variable) in enumerate(variables)
        lower, upper = ceil(BigInt, data[:l][i]), floor(BigInt, data[:u][i])
        lower <= upper || throw(ArgumentError("A native integer interval is empty."))
        context = (
            native_position = i, native_variable = variable,
            role = haskey(slack_owner, variable) ? :slack : :original,
            source_variable = get(source_owner, variable, nothing),
            source_constraint = get(slack_owner, variable, nothing),
        )
        layout = variable_encoding(strategy, lower, upper; context)
        layout isa IntegerVariableEncoding ||
            throw(ArgumentError("variable_encoding must return an IntegerVariableEncoding."))
        length(layout.weights) <= limit - total ||
            throw(ArgumentError("Encoded variable allocation exceeds max_encoded_variables."))
        # Revalidate/copy extension-owned vectors before using them.
        layout = IntegerVariableEncoding(layout.offset, layout.weights, layout.upper_bounds)
        layout.offset == lower && lower + _encoding_width(layout) == upper ||
            throw(ArgumentError("An encoding must cover exactly its native integer interval."))
        push!(positions, collect((total + 1):(total + length(layout.weights))))
        total += length(layout.weights)
        push!(layouts, layout)
    end
    # Check the complete dimension before allocating dense expansion matrices.
    offset, expansion = zeros(T, length(variables)), zeros(T, length(variables), total)
    upper_bounds = zeros(T, total)
    for (i, layout) in enumerate(layouts)
        offset[i] = _exact_encoding_number(T, layout.offset)
        for (j, position) in enumerate(positions[i])
            expansion[i, position] = _exact_encoding_number(T, layout.weights[j])
            upper_bounds[position] = _exact_encoding_number(T, layout.upper_bounds[j])
        end
    end
    G, g, constant = data[:Q], data[:L], data[:c]
    encoded_G = expansion' * G * expansion
    encoded_g = expansion' * (g + (G + G') * offset)
    encoded_constant = dot(offset, G * offset) + dot(g, offset) + constant
    all(isfinite, encoded_G) && all(isfinite, encoded_g) && isfinite(encoded_constant) ||
        throw(ArgumentError("Encoded polynomial coefficients overflowed."))
    target = QUIOModel{T}()
    digits, _ = MOI.add_constrained_variables(target, MOI.Interval{T}.(zeros(T, total), upper_bounds))
    MOI.add_constraints(target, digits, MOI.Integer())
    objective = _emit_quadratic(encoded_G, encoded_g, encoded_constant, digits)
    MOI.set(target, MOI.ObjectiveFunction{typeof(objective)}(), objective)
    MOI.set(target, MOI.ObjectiveSense(), MOI.get(native, MOI.ObjectiveSense()))
    encoded = copy(data) # Legacy keys and selected rho retain native meaning.
    merge!(encoded, Dict{Symbol,Any}(
        :native_model => native, :encoding_layouts => layouts,
        :encoding_digit_positions => positions,
        :encoding_native_positions => Dict(vi => i for (i, vi) in enumerate(variables)),
        :encoded_variables => digits, :encoded_n => total,
        :encoded_Q => encoded_G, :encoded_L => encoded_g, :encoded_c => encoded_constant,
        :encoded_l => zeros(T, total), :encoded_u => upper_bounds,
        :encoded_auxiliary_variables => VI[
            digits[p] for (i, vi) in enumerate(variables) if haskey(slack_owner, vi) for p in positions[i]
        ],
    ))
    encoded[:encoding_metadata] = _encoded_metadata(native_metadata, encoded, strategy, limit)
    return target, encoded
end

_sample_variables(data) = get(data, :encoded_variables, _quio_variables(data))

@doc raw"""
    project_native_state(data_or_optimizer_or_metadata, state)

Decode a full target state into native QUIO order, including original variables
and generated slacks. Native reformulations return a copy. Values must be finite
and the dimension must match; bounds/integrality are not checked and no repair or
rounding occurs. Integer arithmetic is widened to avoid silent overflow.
"""
function project_native_state(input, state::AbstractVector)
    Base.require_one_based_indexing(state)
    all(x -> x isa Real && isfinite(x), state) ||
        throw(ArgumentError("Target state values must be finite real numbers."))
    if input isa AbstractDict && haskey(input, "schema_version")
        metadata = _serialized_reformulation(input)
        length(state) == length(metadata["target_variable_order"]) ||
            throw(DimensionMismatch("Expected a full target state."))
        metadata["schema_version"] == 1 && return copy(state)
        return [_project_expansion(e["expansion"], state) for e in metadata["native_variables"]]
    end
    data = _reformulation_data(input)
    length(state) == length(_sample_variables(data)) || throw(DimensionMismatch("Expected a full target state."))
    haskey(data, :encoding_layouts) || return copy(state)
    return [
        _decode_layout(layout, state[positions])
        for (layout, positions) in zip(data[:encoding_layouts], data[:encoding_digit_positions])
    ]
end

@doc raw"""
    lift_native_state(data_or_optimizer_or_metadata, native_state)

Return a deterministic target preimage of a finite integer native state. Require
native bounds; reject fractional or out-of-domain values. This is a right inverse,
not a repair of invalid samples. Nonunique maps choose digits in decreasing
weight order, with stable ordering for tied weights.
"""
function lift_native_state(input, state::AbstractVector)
    Base.require_one_based_indexing(state)
    metadata = reformulation_metadata(input)
    native = metadata["schema_version"] == 1 ? metadata : metadata["native_reformulation"]
    length(state) == length(native["target_variable_order"]) ||
        throw(DimensionMismatch("Expected a full native QUIO state."))
    for (value, lower, upper) in zip(state, native["target_lower_bounds"], native["target_upper_bounds"])
        value isa Real && isfinite(value) && isinteger(value) && lower <= value <= upper ||
            throw(ArgumentError("Canonical lifting requires native integer values within their bounds."))
    end
    metadata["schema_version"] == 1 && return copy(state)
    digits = zeros(BigInt, length(metadata["target_variable_order"]))
    for (value, entry) in zip(state, metadata["native_variables"])
        layout, positions = _metadata_layout(metadata, entry)
        digits[positions] = _canonical_digits(layout, value)
    end
    return digits
end
