const REFORMULATION_SCHEMA_VERSION = 1

function _reformulation_data(data::AbstractDict)
    haskey(data, :source_variables) ||
        throw(ArgumentError("No ToQUIO reformulation data; reformulate the model first."))
    return data
end

_reformulation_data(solver::Optimizer) = _reformulation_data(solver.data)

function _quio_variables(data::AbstractDict)
    return get(data, :quio_variables) do
        return vcat(data[:target_variables], data[:slack_variables])
    end
end

function _serialized_reformulation(data::AbstractDict)
    version = get(data, "schema_version", nothing)
    version isa Integer && version == REFORMULATION_SCHEMA_VERSION ||
        throw(ArgumentError("Unsupported ToQUIO reformulation schema version."))
    package = get(data, "package", nothing)
    package isa AbstractDict && get(package, "name", nothing) == "ToQUIO" ||
        throw(ArgumentError("Not a ToQUIO reformulation metadata document."))
    return _validate_metadata_values(data)
end

function _metadata_number(value)
    value isa Union{Integer,AbstractFloat} && isfinite(value) ||
        throw(ArgumentError("Metadata numbers must be finite integers or floating-point values."))
    return value
end

function _validate_metadata_values(value)
    if value isa AbstractDict
        all(key isa String for key in keys(value)) ||
            throw(ArgumentError("Metadata dictionary keys must be strings."))
        foreach(_validate_metadata_values, values(value))
    elseif value isa AbstractVector
        foreach(_validate_metadata_values, value)
    elseif !(value isa Union{Nothing,String,Bool})
        _metadata_number(value)
    end
    return value
end

function _constraint_identity(ci::CI{F,S}) where {F,S}
    return Dict{String,Any}(
        "id" => ci.value,
        "function_type" => string(F),
        "set_type" => string(S),
    )
end

_source_relation(::CI{F,S}) where {F,S<:EQ} = "="
_source_relation(::CI{F,S}) where {F,S<:LT} = "<="
_source_relation(::CI{F,S}) where {F,S<:GT} = ">="

@doc raw"""
    reformulation_metadata(data_or_optimizer)

Return a fresh, string-keyed metadata snapshot for a completed native QUIO
reformulation. Schema version 1 records source and full target variable ordering,
affine source projections, target bounds, slack ownership, constraint
canonicalization, and automatic/applied penalties. Matrices remain in the raw
`data` dictionary. Numbers retain their integer or floating-point type and must
be finite; use a JSON serializer supporting that numeric type (e.g. BigFloat).

The returned snapshot can be passed to [`project_original_state`](@ref),
[`original_variables`](@ref), and [`auxiliary_variables`](@ref). Projection does
not check feasibility, validate slack consistency, round values, or repair a
sample. An optimizer must have been reformulated with `optimize!` first.
"""
function reformulation_metadata(input)
    if input isa AbstractDict && haskey(input, "schema_version")
        return deepcopy(_serialized_reformulation(input))
    end
    data = _reformulation_data(input)
    variables = _quio_variables(data)
    positions = Dict(vi => i for (i, vi) in enumerate(variables))
    original = [
        Dict{String,Any}(
            "id" => vi.value,
            "expansion" => Dict{String,Any}(
                "kind" => "affine",
                "offset" => 0,
                "terms" => [Dict{String,Any}(
                    "target_position" => positions[data[:source_to_target_variables][vi]],
                    "coefficient" => 1,
                )],
            ),
        ) for vi in data[:source_variables]
    ]
    slacks = [
        Dict{String,Any}(
            "id" => vi.value,
            "target_position" => positions[vi],
            "source_constraint" => _constraint_identity(ci),
        ) for (vi, ci) in zip(data[:slack_variables], data[:slack_constraints])
    ]
    slack_positions = Dict(
        ci => positions[vi] for (vi, ci) in zip(
            data[:slack_variables], data[:slack_constraints],
        )
    )
    constraints = [
        Dict{String,Any}(
            "source_constraint" => _constraint_identity(ci),
            "source_relation" => _source_relation(ci),
            "canonical_relation" => _source_relation(ci) == "=" ? "=" : "<=",
            "row_multiplier" => _source_relation(ci) == ">=" ? -1 : 1,
            "slack_target_position" => get(slack_positions, ci, nothing),
            "applied_penalty" => _metadata_number(data[:rho][i]),
            "automatic_penalty" => _metadata_number(data[:rho_auto][i]),
            "penalty_hint" => isnothing(data[:penalty_hints][i]) ? nothing :
                _metadata_number(data[:penalty_hints][i]),
        ) for (i, ci) in enumerate(data[:penalty_constraints])
    ]
    return Dict{String,Any}(
        "schema_version" => REFORMULATION_SCHEMA_VERSION,
        "package" => Dict{String,Any}(
            "name" => "ToQUIO", "version" => string(pkgversion(@__MODULE__)),
        ),
        "source_variable_order" => [vi.value for vi in data[:source_variables]],
        "target_variable_order" => [vi.value for vi in variables],
        "target_lower_bounds" => _metadata_number.(data[:l]),
        "target_upper_bounds" => _metadata_number.(data[:u]),
        "original_variables" => original,
        "auxiliary_variables" => [vi.value for vi in data[:slack_variables]],
        "slack_variables" => slacks,
        "constraint_encodings" => constraints,
        "guarantees" => Dict{String,Any}(
            "projection" => "affine, without rounding",
            "source_feasibility_check" => false,
            "auxiliary_consistency_check" => false,
            "auxiliary_repair" => false,
        ),
    )
end

@doc raw"""
    original_variables(data_or_optimizer_or_metadata)

Return source variables in source-model order. Raw data and optimizers return
`MOI.VariableIndex` values; serialized metadata returns integer source IDs.
The returned vector is a copy.
"""
function original_variables(input)
    if input isa AbstractDict && haskey(input, "schema_version")
        return copy(_serialized_reformulation(input)["source_variable_order"])
    end
    return copy(_reformulation_data(input)[:source_variables])
end

@doc raw"""
    auxiliary_variables(data_or_optimizer_or_metadata)

Return the target slack variables introduced by native reformulation. Raw data
and optimizers return `MOI.VariableIndex` values; serialized metadata returns
integer target IDs. The returned vector is a copy.
"""
function auxiliary_variables(input)
    if input isa AbstractDict && haskey(input, "schema_version")
        return copy(_serialized_reformulation(input)["auxiliary_variables"])
    end
    return copy(_reformulation_data(input)[:slack_variables])
end

@doc raw"""
    project_original_state(data_or_optimizer_or_metadata, state::AbstractVector)

Project a full target state, in `target_variable_order` (native `[x; s]` order),
to a dictionary of source values. Keys are `MOI.VariableIndex` for raw data or
an optimizer, and integer source IDs for serialized metadata. The vector length
must match the full target dimension and values must be finite real numbers.
Projection preserves input precision and does not round, check feasibility or
repair slacks. Serialized affine expansion terms use one-based target positions,
not variable IDs, allowing future schema extensions to multiple target digits.
"""
function project_original_state(input, state::AbstractVector)
    all(x -> x isa Real && isfinite(x), state) ||
        throw(ArgumentError("Target state values must be finite real numbers."))
    if input isa AbstractDict && haskey(input, "schema_version")
        metadata = _serialized_reformulation(input)
        length(state) == length(metadata["target_variable_order"]) ||
            throw(DimensionMismatch("Expected a full target state including auxiliary variables."))
        return Dict(
            entry["id"] => _project_expansion(entry["expansion"], state)
            for entry in metadata["original_variables"]
        )
    end
    data = _reformulation_data(input)
    variables = _quio_variables(data)
    length(state) == length(variables) ||
        throw(DimensionMismatch("Expected a full target state including auxiliary variables."))
    positions = Dict(vi => i for (i, vi) in enumerate(variables))
    return Dict(
        vi => state[positions[data[:source_to_target_variables][vi]]]
        for vi in data[:source_variables]
    )
end

function _project_expansion(expansion::AbstractDict, state::AbstractVector)
    expansion["kind"] == "affine" ||
        throw(ArgumentError("Unsupported projection expansion kind."))
    value = _metadata_number(expansion["offset"])
    for term in expansion["terms"]
        position = term["target_position"]
        position isa Integer && 1 <= position <= length(state) ||
            throw(ArgumentError("Projection references an invalid target position."))
        value += _metadata_number(term["coefficient"]) * state[position]
    end
    return value
end
