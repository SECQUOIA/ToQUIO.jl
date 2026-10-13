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
    _metadata_integer(version) && version in (REFORMULATION_SCHEMA_VERSION, 2) ||
        throw(ArgumentError("Unsupported ToQUIO reformulation schema version."))
    package = get(data, "package", nothing)
    package isa AbstractDict && get(package, "name", nothing) == "ToQUIO" ||
        throw(ArgumentError("Not a ToQUIO reformulation metadata document."))
    _validate_metadata_values(data)
    if version == REFORMULATION_SCHEMA_VERSION
        _validate_metadata_structure(data)
    else
        _validate_encoded_metadata_structure(data)
    end
    return data
end

_metadata_integer(value) = value isa Integer && !(value isa Bool)

function _metadata_number(value)
    !(value isa Bool) && value isa Union{Integer,AbstractFloat} && isfinite(value) ||
        throw(ArgumentError("Metadata numbers must be finite integers or floating-point values."))
    return value
end

function _metadata_field(data::AbstractDict, key::String, ::Type{T}) where {T}
    haskey(data, key) && data[key] isa T ||
        throw(ArgumentError("Missing or invalid metadata field '$key'."))
    return data[key]
end

function _metadata_ids(data::AbstractDict, key::String)
    ids = _metadata_field(data, key, AbstractVector)
    all(_metadata_integer, ids) && length(unique(ids)) == length(ids) ||
        throw(ArgumentError("Metadata field '$key' must contain unique integer IDs."))
    return ids
end

function _validate_constraint_identity(identity::AbstractDict)
    _metadata_integer(_metadata_field(identity, "id", Integer)) ||
        throw(ArgumentError("A constraint ID must be an integer, not a boolean."))
    _metadata_field(identity, "function_type", String)
    _metadata_field(identity, "set_type", String)
    return nothing
end

function _validate_metadata_structure(data::AbstractDict)
    _metadata_field(data["package"], "version", String)
    source_ids = _metadata_ids(data, "source_variable_order")
    target_ids = _metadata_ids(data, "target_variable_order")
    auxiliary_ids = _metadata_ids(data, "auxiliary_variables")
    target_id_set = Set(target_ids)
    auxiliary_id_set = Set(auxiliary_ids)
    all(id in target_id_set for id in auxiliary_ids) ||
        throw(ArgumentError("Auxiliary IDs must refer to target variables."))
    for key in ("target_lower_bounds", "target_upper_bounds")
        bounds = _metadata_field(data, key, AbstractVector)
        length(bounds) == length(target_ids) ||
            throw(ArgumentError("Target bounds must match the target variable order."))
        foreach(_metadata_number, bounds)
    end
    originals = _metadata_field(data, "original_variables", AbstractVector)
    length(originals) == length(source_ids) ||
        throw(ArgumentError("Source projections must match the source variable order."))
    for (id, entry) in zip(source_ids, originals)
        entry isa AbstractDict || throw(ArgumentError("A source projection must be a dictionary."))
        entry_id = _metadata_field(entry, "id", Integer)
        _metadata_integer(entry_id) && entry_id == id ||
            throw(ArgumentError("Source projection IDs must match source order without duplicates."))
        expansion = _metadata_field(entry, "expansion", AbstractDict)
        _metadata_field(expansion, "kind", String) == "affine" ||
            throw(ArgumentError("Unsupported projection expansion kind."))
        _metadata_number(_metadata_field(expansion, "offset", Real))
        for term in _metadata_field(expansion, "terms", AbstractVector)
            term isa AbstractDict || throw(ArgumentError("A projection term must be a dictionary."))
            position = _metadata_field(term, "target_position", Integer)
            _metadata_integer(position) && 1 <= position <= length(target_ids) ||
                throw(ArgumentError("Projection references an invalid target position."))
            _metadata_number(_metadata_field(term, "coefficient", Real))
        end
    end
    for slack in _metadata_field(data, "slack_variables", AbstractVector)
        slack isa AbstractDict || throw(ArgumentError("A slack entry must be a dictionary."))
        id = _metadata_field(slack, "id", Integer)
        position = _metadata_field(slack, "target_position", Integer)
        _metadata_integer(id) && _metadata_integer(position) &&
            1 <= position <= length(target_ids) && target_ids[position] == id &&
            id in auxiliary_id_set || throw(ArgumentError("Invalid slack target identity or position."))
        _validate_constraint_identity(_metadata_field(slack, "source_constraint", AbstractDict))
    end
    for entry in _metadata_field(data, "constraint_encodings", AbstractVector)
        entry isa AbstractDict || throw(ArgumentError("A constraint entry must be a dictionary."))
        _validate_constraint_identity(_metadata_field(entry, "source_constraint", AbstractDict))
        for key in ("source_relation", "canonical_relation")
            _metadata_field(entry, key, String)
        end
        multiplier = _metadata_field(entry, "row_multiplier", Integer)
        _metadata_integer(multiplier) && multiplier in (-1, 1) ||
            throw(ArgumentError("A canonical row multiplier must be -1 or 1."))
        position = _metadata_field(entry, "slack_target_position", Union{Nothing,Integer})
        isnothing(position) || (_metadata_integer(position) && 1 <= position <= length(target_ids)) ||
            throw(ArgumentError("Invalid constraint slack target position."))
        for key in ("applied_penalty", "automatic_penalty")
            _metadata_number(_metadata_field(entry, key, Real))
        end
        hint = _metadata_field(entry, "penalty_hint", Union{Nothing,Real})
        isnothing(hint) || _metadata_number(hint)
    end
    _metadata_field(data, "guarantees", AbstractDict)
    if haskey(data, "penalty_controls")
        controls = _metadata_field(data, "penalty_controls", AbstractDict)
        for key in ("offset", "scale")
            _metadata_number(_metadata_field(controls, key, Real)) > 0 ||
                throw(ArgumentError("Serialized penalty controls must be positive."))
        end
    end
    return nothing
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
        "function_type" => sprint(show, F; context = :module => nothing),
        "set_type" => sprint(show, S; context = :module => nothing),
    )
end

_source_relation(::CI{F,S}) where {F,S<:EQ} = "="
_source_relation(::CI{F,S}) where {F,S<:LT} = "<="
_source_relation(::CI{F,S}) where {F,S<:GT} = ">="

@doc raw"""
    reformulation_metadata(data_or_optimizer)

Return a fresh, string-keyed metadata snapshot for a completed QUIO
reformulation. Native schema version 1 records source and full target variable ordering,
affine source projections, target bounds, slack ownership, constraint
canonicalization, and automatic/applied penalties. Matrices remain in the raw
`data` dictionary. Numbers retain their integer or floating-point type and must
be finite; use a JSON serializer supporting that numeric type (e.g. BigFloat).
Optional encodings use schema version 2: target order/bounds and source expansions
refer to encoded digits, native_variables records each coordinate's affine map
and slack ownership, and native_reformulation contains the complete version 1
snapshot with the unchanged penalties. The raw legacy keys remain native.

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
    haskey(data, :encoding_metadata) &&
        return deepcopy(_serialized_reformulation(data[:encoding_metadata]))
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
    metadata = Dict{String,Any}(
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
    if haskey(data, :penalty_offset) && haskey(data, :penalty_scale)
        metadata["penalty_controls"] = Dict{String,Any}(
            "offset" => _metadata_number(data[:penalty_offset]),
            "scale" => _metadata_number(data[:penalty_scale]),
        )
    end
    return metadata
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

Return target auxiliaries: native slacks for schema 1, or every encoded digit
owned by a generated slack for schema 2. Fixed slacks need no encoded digit.
Raw data and optimizers return `MOI.VariableIndex` values; serialized metadata
returns integer target IDs. The returned vector is a copy.
"""
function auxiliary_variables(input)
    if input isa AbstractDict && haskey(input, "schema_version")
        return copy(_serialized_reformulation(input)["auxiliary_variables"])
    end
    data = _reformulation_data(input)
    return copy(get(data, :encoded_auxiliary_variables, data[:slack_variables]))
end

@doc raw"""
    project_original_state(data_or_optimizer_or_metadata, state::AbstractVector)

Project a full target state, in `target_variable_order` (native `[x; s]` order
or encoded digit order),
to a dictionary of source values. Keys are `MOI.VariableIndex` for raw data or
an optimizer, and integer source IDs for serialized metadata. The vector length
must match the full target dimension and values must be finite real numbers.
Projection preserves input precision and does not round, check feasibility or
repair slacks. Serialized affine expansion terms use one-based target positions,
not variable IDs. Optional encodings compose native and encoded maps; all fixed
source values are restored. Native coordinates can be read with project_native_state.
"""
function project_original_state(input, state::AbstractVector)
    Base.require_one_based_indexing(state)
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
    return _project_original_native(data, project_native_state(data, state))
end

function _project_original_native(data, state)
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
        _metadata_integer(position) && 1 <= position <= length(state) ||
            throw(ArgumentError("Projection references an invalid target position."))
        value = _affine_add(value, _metadata_number(term["coefficient"]), state[position])
        isfinite(value) || throw(ArgumentError("Decoded value overflowed."))
    end
    return value
end
