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

@doc raw"""
    VariableReformulationAttribute
"""
abstract type VariableReformulationAttribute <: MOI.AbstractConstraintAttribute end

MOI.supports(solver::Optimizer{T}, ::A, ::Type{VI}) where {T,A<:VariableReformulationAttribute} = true
