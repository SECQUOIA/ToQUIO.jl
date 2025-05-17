mutable struct Optimizer{T,O<:Maybe{MOI.AbstractOptimizer}} <: MOI.AbstractOptimizer
    inner::O
    source_model::MOI.ModelLike
    target_model::QUIOModel
end

function Optimizer{T}() where {T}
    return Optimizer{T,Nothing}(optimizer, QUIOModel{T}())
end

function Optimizer{T}(callable::Any) where {T}
    optimizer = callable()

    return Optimizer{T,typeof(optimizer)}(optimizer, QUIOModel{T}())
end

Optimizer(args...; kws...) = Optimizer{Float64}(args...; kws...)

function MOI.is_empty(solver::Optimizer{T}) where {T}
    return MOI.is_empty(solver.source_model)
end

function MOI.empty!(solver::Optimizer{T}) where {T}
    MOI.empty!(solver.source_model)

    return nothing
end

function MOI.optimize!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    solver.source_model = model
    solver.target_model = to_quio(T, vi -> vi.value, solver.source_model)::QUIOModel

    MOI.optimize!(solver.inner, solver.target_model)

    return (MOIU.identity_index_map(solver.source_model), false)
end

MOI.supports(::Optimizer{T}, ::MOI.ObjectiveFunction{F}) where {T,F<:Union{SAF{T},SQF{T}}}= true

MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{<:Union{EQ{T},LT{T},GT{T}}}) where {T} = true
MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{<:Union{MOI.ZeroOne,MOI.Integer}}) where {T} = true

MOI.supports_constraint(::Optimizer{T}, ::Type{<:Union{SAF{T}}}, ::Type{<:Union{EQ{T},LT{T},GT{T}}}) where {T} = true

include("attributes/model.jl")
include("attributes/results.jl")
