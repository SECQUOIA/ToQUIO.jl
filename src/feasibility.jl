function _capture_source_constraints(::Type{T}, source::MOI.ModelLike) where {T}
    constraints = Any[]
    for (F, S) in MOI.get(source, MOI.ListOfConstraintTypesPresent())
        supported = (F == VI && S <: Union{EQ{T},LT{T},GT{T},MOI.Interval{T},MOI.Integer,MOI.ZeroOne}) ||
            (F == SAF{T} && S <: Union{EQ{T},LT{T},GT{T}})
        supported || throw(ArgumentError("Unsupported source constraint for QUIO: $F in $S."))
        for ci in MOI.get(source, MOI.ListOfConstraintIndices{F,S}())
            push!(constraints, (
                index = ci,
                func = deepcopy(MOI.get(source, MOI.ConstraintFunction(), ci)),
                set = deepcopy(MOI.get(source, MOI.ConstraintSet(), ci)),
            ))
        end
    end
    return constraints
end

@doc raw"""
    ConstraintViolation

An original source constraint whose distance to its set exceeds the requested
tolerance. Fields are `constraint`, `function_type`, `set_type`, `value`,
`violation`, `raw_residual`, and `source_values` (the involved source variables).
`violation` is a nonnegative distance in the constraint's native units;
`raw_residual` retains its sign where applicable. No values are rounded or repaired.
"""
struct ConstraintViolation
    constraint::MOI.ConstraintIndex
    function_type::Type
    set_type::Type
    value::Real
    violation::Real
    raw_residual::Real
    source_values::Dict{VI,Any}
end

function _feasibility_tolerance(atol)
    atol isa Real && !(atol isa Bool) && isfinite(atol) && atol >= zero(atol) ||
        throw(ArgumentError("Feasibility tolerance must be a finite nonnegative real number."))
    return atol
end

function _source_distance(value::Real, set::Union{EQ,LT,GT})
    bound = set isa EQ ? set.value : set isa LT ? set.upper : set.lower
    point, bound = promote(value, bound)
    promoted_set = set isa EQ ? MOI.EqualTo(bound) :
        set isa LT ? MOI.LessThan(bound) : MOI.GreaterThan(bound)
    residual = set isa GT ? bound - point : point - bound
    return MOIU.distance_to_set(point, promoted_set), residual
end

function _source_distance(value::Real, set::MOI.Interval)
    point, lower, upper = promote(value, set.lower, set.upper)
    residual = max(lower - point, point - upper)
    return MOIU.distance_to_set(point, MOI.Interval(lower, upper)), residual
end

function _source_distance(value::Real, set::MOI.Integer)
    return MOIU.distance_to_set(value, set), value - round(value)
end

function _source_distance(value::Real, set::MOI.ZeroOne)
    nearest = abs(value) <= abs(value - one(value)) ? zero(value) : one(value)
    return MOIU.distance_to_set(value, set), value - nearest
end

_constraint_variables(func::VI) = VI[func]
_constraint_variables(func::SAF) = unique(VI[term.variable for term in func.terms])

function _source_evaluations(input, state::AbstractVector; atol)
    tolerance = _feasibility_tolerance(atol)
    data = _reformulation_data(input)
    haskey(data, :source_constraints) ||
        throw(ArgumentError("Source constraint snapshots are unavailable; reformulate with this version."))
    projected = project_original_state(data, state)
    positions = Dict(vi => i for (i, vi) in enumerate(_quio_variables(data)))
    slack_positions = Dict(
        ci => positions[vi] for (ci, vi) in zip(data[:slack_constraints], data[:slack_variables])
    )
    evaluations = Any[]
    for entry in data[:source_constraints]
        value = entry.func isa VI ? projected[entry.func] :
            MOIU.eval_variables(vi -> projected[vi], entry.func)
        value isa Real && isfinite(value) ||
            throw(ArgumentError("Evaluating a source constraint produced a nonfinite value."))
        distance, residual = _source_distance(value, entry.set)
        isfinite(distance) && isfinite(residual) ||
            throw(ArgumentError("Evaluating a source residual overflowed."))
        involved = Dict{VI,Any}(vi => projected[vi] for vi in _constraint_variables(entry.func))
        target_residual = if haskey(slack_positions, entry.index)
            residual + state[slack_positions[entry.index]]
        elseif entry.func isa SAF && entry.set isa EQ
            residual
        else
            nothing
        end
        push!(evaluations, (
            constraint = entry.index, function_type = typeof(entry.func),
            set_type = typeof(entry.set), value = value, violation = distance,
            raw_residual = residual, source_values = involved,
            target_residual = target_residual, violated = distance > tolerance,
        ))
    end
    return projected, evaluations
end

function _optimizer_state(solver::Optimizer, result)
    data = _reformulation_data(solver)
    count = MOI.get(solver, MOI.ResultCount())
    result isa Integer && !(result isa Bool) ||
        throw(ArgumentError("Result index must be an integer."))
    1 <= result <= count || throw(MOI.ResultIndexBoundsError(MOI.VariablePrimal(result), count))
    return [
        MOI.get(solver.inner, MOI.VariablePrimal(result), _backend_variable(solver, vi))
        for vi in _quio_variables(data)
    ]
end

@doc raw"""
    violations(data_or_optimizer, state::AbstractVector; atol=1e-6)
    violations(optimizer; result=1, atol=1e-6)

Return [`ConstraintViolation`](@ref) entries for original source constraints
whose distance to the set exceeds `atol`. Evaluate the captured source model on
projected original variables, including bounds, integrality and binary domains.
The explicit state is in full target order, including slacks. Optimizer results
are read through the target-to-backend index map at the selected result index.
Fractional samples are not rounded. This is a tolerance-based check, not a
certificate of optimality. Serialized projection metadata alone does not contain
the source functions needed for this analysis.
"""
function violations(input, state::AbstractVector; atol = 1e-6)
    _, evaluations = _source_evaluations(input, state; atol)
    return [
        ConstraintViolation(entry.constraint, entry.function_type, entry.set_type,
            entry.value, entry.violation, entry.raw_residual, entry.source_values)
        for entry in evaluations if entry.violated
    ]
end

violations(solver::Optimizer; result = 1, atol = 1e-6) =
    violations(solver, _optimizer_state(solver, result); atol)

@doc raw"""
    is_feasible(data_or_optimizer, state::AbstractVector; atol=1e-6)
    is_feasible(optimizer; result=1, atol=1e-6)

Return whether [`violations`](@ref) is empty for the source model. Consistency of
generated slacks is independent of original source feasibility and is not used
to classify the point. No repair or rounding is performed.
"""
is_feasible(input, state::AbstractVector; atol = 1e-6) = isempty(violations(input, state; atol))
is_feasible(solver::Optimizer; result = 1, atol = 1e-6) =
    isempty(violations(solver; result, atol))

function _state_feasibility_report(input, state::AbstractVector; atol)
    projected, evaluations = _source_evaluations(input, state; atol)
    rows = [
        Dict{String,Any}(
            "constraint" => _constraint_identity(entry.constraint),
            "value" => entry.value, "violation" => entry.violation,
            "raw_residual" => entry.raw_residual, "violated" => entry.violated,
            "source_values" => Dict(string(vi.value) => value for (vi, value) in entry.source_values),
            "target_residual" => entry.target_residual,
        ) for entry in evaluations
    ]
    magnitudes = [entry.violation for entry in evaluations]
    return Dict{String,Any}(
        "feasible" => all(!entry.violated for entry in evaluations),
        "atol" => atol,
        "violation_count" => count(entry -> entry.violated, evaluations),
        "max_violation" => isempty(magnitudes) ? 0 : maximum(magnitudes),
        "total_violation" => sum(magnitudes; init = 0),
        "projected_source_values" => Dict(string(vi.value) => value for (vi, value) in projected),
        "constraints" => rows,
    )
end

@doc raw"""
    feasibility_report(data_or_optimizer, state::AbstractVector; atol=1e-6)
    feasibility_report(optimizer; result=nothing, atol=1e-6)

Return source feasibility, all per-constraint distances/residuals, projected
values and optional target residuals. Optimizer `result=nothing` (the default)
summarizes every available result; specify an index for one result. The aggregate
counts result records, not read multiplicities, and its `feasible_fraction` is
`nothing` for zero results. Max/sum violation diagnostics use native constraint
units without normalization. Source feasibility does not certify target slack
consistency; target residuals remain separate and can be nonzero at a feasible
source point. The source snapshot remains independent of later model edits.
"""
feasibility_report(input, state::AbstractVector; atol = 1e-6) =
    _state_feasibility_report(input, state; atol)

function feasibility_report(solver::Optimizer; result = nothing, atol = 1e-6)
    _feasibility_tolerance(atol)
    _reformulation_data(solver)
    if !isnothing(result)
        return _state_feasibility_report(solver, _optimizer_state(solver, result); atol)
    end
    count = MOI.get(solver, MOI.ResultCount())
    reports = [
        _state_feasibility_report(solver, _optimizer_state(solver, i); atol)
        for i in 1:count
    ]
    feasible_count = Base.count(report -> report["feasible"], reports)
    return Dict{String,Any}(
        "result_count" => count, "feasible_count" => feasible_count,
        "feasible_fraction" => count == 0 ? nothing : feasible_count / count,
        "max_violation" => isempty(reports) ? nothing : maximum(r["max_violation"] for r in reports),
        "total_violation" => sum((r["total_violation"] for r in reports); init = 0),
        "results" => reports,
    )
end
