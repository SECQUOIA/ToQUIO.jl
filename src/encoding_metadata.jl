const ENCODED_SCHEMA_VERSION = 2

function _encoded_expansion(layout, positions)
    return Dict{String,Any}(
        "kind" => "affine", "offset" => layout.offset,
        "terms" => [Dict{String,Any}("target_position" => p, "coefficient" => w)
                    for (p, w) in zip(positions, layout.weights)],
    )
end

function _compose_encoded_expansion(expansion, native_entries)
    offset = expansion["offset"]
    coefficients = Dict{Int,Any}()
    for term in expansion["terms"]
        entry = native_entries[term["target_position"]]["expansion"]
        offset = _affine_add(offset, term["coefficient"], entry["offset"])
        for digit in entry["terms"]
            p = digit["target_position"]
            coefficients[p] = _affine_add(get(coefficients, p, 0),
                                          term["coefficient"], digit["coefficient"])
        end
    end
    offset = _finish_affine_decode(offset)
    for position in keys(coefficients)
        coefficients[position] = _finish_affine_decode(coefficients[position])
    end
    return Dict{String,Any}(
        "kind" => "affine", "offset" => offset,
        "terms" => [Dict{String,Any}("target_position" => p, "coefficient" => coefficients[p])
                    for p in sort!(collect(keys(coefficients))) if !iszero(coefficients[p])],
    )
end

function _encoded_originals(native, entries)
    return [Dict{String,Any}(
        "id" => entry["id"],
        "expansion" => _compose_encoded_expansion(entry["expansion"], entries),
    ) for entry in native["original_variables"]]
end

function _encoded_auxiliary_ids(native, entries, target_ids)
    auxiliary_ids = Set(native["auxiliary_variables"])
    return [target_ids[t["target_position"]] for entry in entries if entry["id"] in auxiliary_ids
            for t in entry["expansion"]["terms"]]
end

function _encoded_metadata(native, data, strategy, limit)
    owners = Dict(s["id"] => s["source_constraint"] for s in native["slack_variables"])
    entries = [Dict{String,Any}(
        "id" => id, "native_position" => i,
        "role" => haskey(owners, id) ? "slack" : "original",
        "source_constraint" => get(owners, id, nothing),
        "expansion" => _encoded_expansion(data[:encoding_layouts][i],
                                         data[:encoding_digit_positions][i]),
    ) for (i, id) in enumerate(native["target_variable_order"])]
    target_ids = [vi.value for vi in data[:encoded_variables]]
    descriptor = encoding_descriptor(strategy)
    descriptor isa AbstractDict || throw(ArgumentError("encoding_descriptor must return a dictionary."))
    metadata = Dict{String,Any}(
        "schema_version" => ENCODED_SCHEMA_VERSION, "package" => deepcopy(native["package"]),
        "source_variable_order" => copy(native["source_variable_order"]),
        "target_variable_order" => target_ids,
        "target_lower_bounds" => copy(data[:encoded_l]), "target_upper_bounds" => copy(data[:encoded_u]),
        "original_variables" => _encoded_originals(native, entries),
        "auxiliary_variables" => _encoded_auxiliary_ids(native, entries, target_ids),
        "native_reformulation" => deepcopy(native), "native_variables" => entries,
        "encoding" => Dict{String,Any}(
            "strategy" => deepcopy(descriptor), "max_target_variables" => limit,
            "penalty_policy" => "preserve-native",
        ),
        "guarantees" => deepcopy(native["guarantees"]),
    )
    return _serialized_reformulation(metadata)
end

function _metadata_layout(metadata, entry)
    expansion = _metadata_field(entry, "expansion", AbstractDict)
    _metadata_field(expansion, "kind", String) == "affine" ||
        throw(ArgumentError("Unsupported encoded expansion kind."))
    offset = _metadata_number(_metadata_field(expansion, "offset", Real))
    isinteger(offset) || throw(ArgumentError("Encoded offsets must be integers."))
    positions, weights, uppers = Int[], BigInt[], BigInt[]
    for term in _metadata_field(expansion, "terms", AbstractVector)
        term isa AbstractDict || throw(ArgumentError("Encoded terms must be dictionaries."))
        p = _metadata_field(term, "target_position", Integer)
        _metadata_integer(p) && 1 <= p <= length(metadata["target_variable_order"]) ||
            throw(ArgumentError("Invalid encoded target position."))
        coefficient = _metadata_number(_metadata_field(term, "coefficient", Real))
        isinteger(coefficient) || throw(ArgumentError("Encoded weights must be integers."))
        push!(positions, p)
        push!(weights, BigInt(coefficient))
        push!(uppers, BigInt(metadata["target_upper_bounds"][p]))
    end
    length(unique(positions)) == length(positions) ||
        throw(ArgumentError("A digit cannot occur twice in one native expansion."))
    return IntegerVariableEncoding(BigInt(offset), weights, uppers), positions
end

function _validate_encoded_metadata_structure(data)
    native = _metadata_field(data, "native_reformulation", AbstractDict)
    get(native, "schema_version", nothing) == REFORMULATION_SCHEMA_VERSION ||
        throw(ArgumentError("Encoded metadata must contain a native schema version 1 snapshot."))
    _serialized_reformulation(native)
    data["package"] == native["package"] ||
        throw(ArgumentError("Encoded and native package identities must agree."))
    _metadata_ids(data, "source_variable_order") == native["source_variable_order"] ||
        throw(ArgumentError("Encoded source order must match the native snapshot."))
    target_ids = _metadata_ids(data, "target_variable_order")
    lower = _metadata_field(data, "target_lower_bounds", AbstractVector)
    upper = _metadata_field(data, "target_upper_bounds", AbstractVector)
    length(lower) == length(upper) == length(target_ids) ||
        throw(ArgumentError("Encoded bounds must match target order."))
    foreach(_metadata_number, lower)
    foreach(_metadata_number, upper)
    all(iszero, lower) && all(x -> isinteger(x) && x > 0, upper) ||
        throw(ArgumentError("Active encoded digits require zero lower and positive integer upper bounds."))
    encoding = _metadata_field(data, "encoding", AbstractDict)
    _metadata_field(encoding, "strategy", AbstractDict)
    limit = _metadata_field(encoding, "max_target_variables", Integer)
    _metadata_integer(limit) && 1 <= limit <= typemax(Int) && length(target_ids) <= limit ||
        throw(ArgumentError("Invalid encoded allocation limit."))
    _metadata_field(encoding, "penalty_policy", String) == "preserve-native" ||
        throw(ArgumentError("An exact encoding must preserve native penalties."))
    entries = _metadata_field(data, "native_variables", AbstractVector)
    length(entries) == length(native["target_variable_order"]) ||
        throw(ArgumentError("Every native variable needs one encoded expansion."))
    owners = Dict(s["id"] => s["source_constraint"] for s in native["slack_variables"])
    seen = Int[]
    for (i, (id, entry)) in enumerate(zip(native["target_variable_order"], entries))
        entry isa AbstractDict || throw(ArgumentError("Native expansions must be dictionaries."))
        entry_id, position = _metadata_field(entry, "id", Integer),
                             _metadata_field(entry, "native_position", Integer)
        _metadata_integer(entry_id) && _metadata_integer(position) && entry_id == id && position == i ||
            throw(ArgumentError("Native expansion identities must match native ordering."))
        role = haskey(owners, id) ? "slack" : "original"
        _metadata_field(entry, "role", String) == role ||
            throw(ArgumentError("Encoded variable ownership is inconsistent."))
        haskey(entry, "source_constraint") && entry["source_constraint"] == get(owners, id, nothing) ||
            throw(ArgumentError("Encoded slack ownership must match the native constraint."))
        layout, positions = _metadata_layout(data, entry)
        lower_i, upper_i = ceil(BigInt, native["target_lower_bounds"][i]),
                           floor(BigInt, native["target_upper_bounds"][i])
        layout.offset == lower_i && lower_i + _encoding_width(layout) == upper_i ||
            throw(ArgumentError("Encoded expansion must cover its native interval exactly."))
        append!(seen, positions)
    end
    sort(seen) == collect(eachindex(target_ids)) ||
        throw(ArgumentError("Every encoded digit must belong to exactly one native variable."))
    _metadata_field(data, "original_variables", AbstractVector) == _encoded_originals(native, entries) ||
        throw(ArgumentError("Source decoding must compose the native and encoded maps."))
    _metadata_ids(data, "auxiliary_variables") == _encoded_auxiliary_ids(native, entries, target_ids) ||
        throw(ArgumentError("Encoded auxiliary IDs must match slack-owned digits."))
    _metadata_field(data, "guarantees", AbstractDict) == native["guarantees"] ||
        throw(ArgumentError("Encoding cannot replace the native feasibility guarantees."))
    return nothing
end
