function MOI.get(solver::Optimizer{T}, attr::MOI.TerminationStatus) where {T}
    if isnothing(solver.inner)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        return MOI.get(solver.inner, attr)
    end
end

@doc raw"""
    PenalizedObjectiveValue(result_index::Int = 1)

Return the objective value reported by the backend on the reformulated QUIO
target model. `MOI.ObjectiveValue` returns the original objective evaluated at
the mapped source-variable primal values.
"""
struct PenalizedObjectiveValue <: MOI.AbstractModelAttribute
    result_index::Int
    PenalizedObjectiveValue(result_index::Int = 1) = new(result_index)
end

function _target_variable(solver::Optimizer, vi::VI)
    source_to_target = get(solver.data, :source_to_target_variables, nothing)
    isnothing(source_to_target) &&
        error("Variable mappings are unavailable; call optimize! before querying primal values.")
    haskey(source_to_target, vi) || throw(MOI.InvalidIndex(vi))
    return source_to_target[vi]
end

function _backend_variable(solver::Optimizer, vi::VI)
    target_to_backend = get(solver.data, :target_to_backend_variables, nothing)
    isnothing(target_to_backend) && return vi
    haskey(target_to_backend, vi) || throw(MOI.InvalidIndex(vi))
    return target_to_backend[vi]
end

function MOI.get(solver::Optimizer{T}, attr::MOI.VariablePrimal, vi::VI) where {T}
    @assert !isnothing(solver.inner)

    return MOI.get(solver.inner, attr, _backend_variable(solver, _target_variable(solver, vi)))
end

function MOI.supports(solver::Optimizer{T}, attr::MOI.TerminationStatus) where {T}
    return isnothing(solver.inner) || MOI.supports(solver.inner, attr)
end

function MOI.get(solver::Optimizer{T}, attr::MOI.ObjectiveValue) where {T}
    @assert !isnothing(solver.inner)
    @assert !isnothing(solver.source_model)

    F = MOI.get(solver.source_model, MOI.ObjectiveFunctionType())
    f = MOI.get(solver.source_model, MOI.ObjectiveFunction{F}())

    return MOIU.eval_variables(solver.source_model, f) do vi
        return MOI.get(solver, MOI.VariablePrimal(attr.result_index), vi)
    end
end

function MOI.get(solver::Optimizer{T}, attr::PenalizedObjectiveValue) where {T}
    @assert !isnothing(solver.inner)

    return MOI.get(solver.inner, MOI.ObjectiveValue(attr.result_index))
end

function MOI.get(solver::Optimizer{T}, attr::MOI.ResultCount) where {T}
    if isnothing(solver.inner)
        return 0
    else
        MOI.get(solver.inner, attr)
    end
end

function MOI.supports(solver::Optimizer{T}, attr::MOI.ResultCount) where {T}
    return isnothing(solver.inner) || MOI.supports(solver.inner, attr)
end
