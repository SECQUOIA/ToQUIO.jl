function MOI.get(solver::Optimizer{T}, attr::MOI.TerminationStatus) where {T}
    if isnothing(solver.inner)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        return MOI.get(solver.inner, attr)
    end
end

function MOI.get(solver::Optimizer{T}, attr::MOI.VariablePrimal, vi::VI) where {T}
    @assert !isnothing(solver.inner)

    return MOI.get(solver.inner, attr, vi) # TODO: Variable mapping
end

function MOI.supports(solver::Optimizer{T}, attr::MOI.TerminationStatus) where {T}
    return isnothing(solver.inner) || MOI.supports(solver.inner, attr)
end

function MOI.get(solver::Optimizer{T}, attr::MOI.ObjectiveValue) where {T}
    @assert !isnothing(solver.inner)

    # TODO: Decide what to report: Penalized objective value or Original objective value

    return MOI.get(solver.inner, attr) # This is the penalized one, as passed to the solver
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