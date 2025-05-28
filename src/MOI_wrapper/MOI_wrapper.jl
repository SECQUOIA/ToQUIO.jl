mutable struct Optimizer{T,O<:Maybe{MOI.AbstractOptimizer}} <: MOI.AbstractOptimizer
    inner::O
    source_model::Maybe{MOI.ModelLike}
    target_model::Maybe{QUIOModel}
    data::Dict{Symbol,Any}
end

function Optimizer{T}(::Nothing = nothing) where {T}
    return Optimizer{T,Nothing}(nothing, nothing, nothing, Dict{Symbol,Any}())
end

function Optimizer{T}(callable::Any) where {T}
    optimizer = callable()

    return Optimizer{T,typeof(optimizer)}(optimizer, nothing, nothing, Dict{Symbol,Any}())
end

Optimizer(args...; kws...) = Optimizer{Float64}(args...; kws...)

function MOI.is_empty(solver::Optimizer{T}) where {T}
    return isnothing(solver.source_model) || MOI.is_empty(solver.source_model)
end

function MOI.empty!(solver::Optimizer{T}) where {T}
    isnothing(solver.inner) || MOI.empty!(solver.inner)
    isnothing(solver.source_model) || MOI.empty!(solver.source_model)
    isnothing(solver.target_model) || MOI.empty!(solver.target_model)

    return nothing
end

include("attributes/model.jl")
include("attributes/results.jl")
include("attributes/reformulation.jl")

function MOI.optimize!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    solver.source_model = model

    solver.target_model, solver.data = to_quio(
        T,
        vi -> vi.value, # varmap : VI -> Int
        ci -> ci.value, # conmap : CI{F,S} -> Int
        solver.source_model,
    )

    if !isnothing(solver.inner)
        MOI.optimize!(solver.inner, solver.target_model)
    end

    return (MOIU.identity_index_map(solver.source_model), false)
end

MOI.supports(::Optimizer{T}, ::MOI.ObjectiveFunction{F}) where {T,F<:Union{SAF{T},SQF{T}}}= true

MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{<:Union{EQ{T},LT{T},GT{T}}}) where {T} = true
MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{<:Union{MOI.ZeroOne,MOI.Integer}}) where {T} = true

MOI.supports_constraint(::Optimizer{T}, ::Type{<:Union{SAF{T}}}, ::Type{<:Union{EQ{T},LT{T},GT{T}}}) where {T} = true
