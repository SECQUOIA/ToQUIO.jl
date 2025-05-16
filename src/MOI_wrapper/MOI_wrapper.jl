mutable struct Optimizer{T,O<:Maybe{MOI.AbstractOptimizer}} <: MOI.AbstractOptimizer
    inner::O
    model::QUIOModel
end

function Optimizer{T}() where {T}
    return Optimizer{T,Nothing}(optimizer, QUIOModel{T}())
end

function Optimizer{T}(::Type{O}) where {T,O<:MOI.AbstractOptimizer}
    return Optimizer{T,O}(O(), QUIOModel{T}())
end


Optimizer(args...; kws...) = Optimizer{Float64}(args...; kws...)

function MOI.is_empty(solver::Optimizer{T}) where {T}
    return MOI.is_empty(solver.model)
end

function MOI.empty!(solver::Optimizer{T}) where {T}
    MOI.empty!(solver.model)

    return nothing
end

function MOI.optimize!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    solver.model = to_quio(T, vi -> vi.value, model)::QUIOModel

    MOI.optimize!(solver.inner, solver.model)

    return (MOIU.identity_index_map(model), false)
end

MOI.supports(::Optimizer{T}, ::MOI.ObjectiveFunction{F}) where {T,F<:Union{SAF{T},SQF{T}}}= true

MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{<:Union{EQ{T},LT{T},GT{T}}}) where {T} = true
MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{<:Union{MOI.ZeroOne,MOI.Integer}}) where {T} = true

MOI.supports_constraint(::Optimizer{T}, ::Type{<:Union{SAF{T}}}, ::Type{<:Union{EQ{T},LT{T},GT{T}}}) where {T} = true
