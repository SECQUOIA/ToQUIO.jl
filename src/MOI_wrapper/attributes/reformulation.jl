@doc raw"""
    OptimizerReformulationAttribute
"""
abstract type OptimizerReformulationAttribute <: MOI.AbstractOptimizerAttribute end

MOI.supports(solver::Optimizer{T}, ::A) where {T,A<:OptimizerReformulationAttribute} = true

@doc raw"""
    ModelReformulationAttribute
"""
abstract type ModelReformulationAttribute <: MOI.AbstractModelAttribute end

MOI.supports(solver::Optimizer{T}, ::A) where {T,A<:ModelReformulationAttribute} = true

@doc raw"""
    ConstraintReformulationAttribute
"""
abstract type ConstraintReformulationAttribute <: MOI.AbstractConstraintAttribute end

MOI.supports(solver::Optimizer{T}, ::A, ::Type{<:CI{F,S}}) where {T,F,S,A<:ConstraintReformulationAttribute} = true

@doc raw"""
    ConstraintPenaltyHint
"""
struct ConstraintPenaltyHint <: ConstraintReformulationAttribute end

function _positive_penalty_control(::Type{T}, value, name::String) where {T}
    value isa Real && !(value isa Bool) && isfinite(value) && value > zero(value) ||
        throw(ArgumentError("$name must be a finite positive real number."))
    converted = try
        convert(T, value)
    catch error
        error isa Union{InexactError,MethodError,OverflowError} || rethrow()
        throw(ArgumentError("$name cannot be represented by numeric type $T."))
    end
    isfinite(converted) && converted > zero(T) ||
        throw(ArgumentError("$name must remain finite and positive in numeric type $T."))
    return converted
end

function _penalty_settings(::Type{T}, offset, scale) where {T}
    return Dict{Symbol,Any}(
        :penalty_offset => _positive_penalty_control(T, offset, "Penalty offset"),
        :penalty_scale => _positive_penalty_control(T, scale, "Penalty scale"),
    )
end

@doc raw"""
    PenaltyOffset()

Global positive additive margin for automatic penalties, default `one(T)`.
For an unhinted constraint, the applied magnitude is
`PenaltyScale() * (Δ_bound / ε^2 + PenaltyOffset())`.
Exact `ConstraintPenaltyHint` values bypass both controls. Set through `MOI.set`
or the `Optimizer(; penalty_offset=...)` keyword. Direct `to_quio` calls use the
existing `ϵ` keyword for this margin. Controls persist across `MOI.empty!` and
affect the next reformulation; they do not rewrite a previous result.
"""
struct PenaltyOffset <: OptimizerReformulationAttribute end

@doc raw"""
    PenaltyScale()

Global finite positive multiplier for automatic penalties, default `one(T)`.
Set with `MOI.set(optimizer, PenaltyScale(), scale)`, the optimizer's
`penalty_scale` keyword, or `to_quio(...; penalty_scale=scale)`.
Explicit per-constraint `ConstraintPenaltyHint` values remain exact and unscaled.
Values below 1 may lose constrained-problem equivalence and emit a warning when
the applied penalty is below the unscaled sufficient value.
"""
struct PenaltyScale <: OptimizerReformulationAttribute end

MOI.get(solver::Optimizer{T}, ::PenaltyOffset) where {T} =
    get(solver.settings, :penalty_offset, one(T))
MOI.get(solver::Optimizer{T}, ::PenaltyScale) where {T} =
    get(solver.settings, :penalty_scale, one(T))

function MOI.set(solver::Optimizer{T}, ::PenaltyOffset, value) where {T}
    solver.settings[:penalty_offset] = _positive_penalty_control(T, value, "Penalty offset")
    return nothing
end

function MOI.set(solver::Optimizer{T}, ::PenaltyScale, value) where {T}
    solver.settings[:penalty_scale] = _positive_penalty_control(T, value, "Penalty scale")
    return nothing
end

function MOI.set(solver::Optimizer, ::PenaltyOffset, ::Nothing)
    delete!(solver.settings, :penalty_offset)
    return nothing
end

function MOI.set(solver::Optimizer, ::PenaltyScale, ::Nothing)
    delete!(solver.settings, :penalty_scale)
    return nothing
end

@doc raw"""
    AppliedPenalty()

Read the positive penalty magnitude used for a source scalar affine equality or
inequality in the most recent reformulation, if it succeeded. A failed later
reformulation invalidates this query. Available without a solver backend through
raw `MOI.get`; JuMP's high-level result getter checks solver termination status,
so use `MOI.get(backend(model), AppliedPenalty(), index(con))` in reformulation-only
mode. Maximization subtracts this magnitude in the objective. Changing controls
affects the next reformulation, not this query's recorded value.
"""
struct AppliedPenalty <: ConstraintReformulationAttribute end

MOI.is_set_by_optimize(::AppliedPenalty) = true

MOI.supports(::Optimizer{T}, ::AppliedPenalty, ::Type{CI{F,S}}) where {T,F,S} =
    F <: SAF{T} && S <: Union{EQ{T},LT{T},GT{T}}

function MOI.get(solver::Optimizer, attr::AppliedPenalty, ci::CI)
    haskey(solver.data, :penalty_constraints) ||
        throw(MOI.GetAttributeNotAllowed(attr, "Call optimize! to reformulate the model first."))
    MOI.supports(solver, attr, typeof(ci)) ||
        throw(MOI.GetAttributeNotAllowed(attr, "Only penalized scalar affine constraints are supported."))
    position = findfirst(==(ci), solver.data[:penalty_constraints])
    isnothing(position) && throw(MOI.InvalidIndex(ci))
    return solver.data[:rho][position]
end

@doc raw"""
    VariableReformulationAttribute
"""
abstract type VariableReformulationAttribute <: MOI.AbstractConstraintAttribute end

MOI.supports(solver::Optimizer{T}, ::A, ::Type{VI}) where {T,A<:VariableReformulationAttribute} = true
