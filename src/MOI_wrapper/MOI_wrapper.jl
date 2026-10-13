mutable struct Optimizer{T,O<:Maybe{MOI.AbstractOptimizer}} <: MOI.AbstractOptimizer
    inner::O
    source_model::Maybe{MOI.ModelLike}
    target_model::Maybe{QUIOModel}
    data::Dict{Symbol,Any}
    settings::Dict{Symbol,Any}
end

function Optimizer{T}(::Nothing = nothing; penalty_offset = one(T), penalty_scale = one(T)) where {T}
    settings = _penalty_settings(T, penalty_offset, penalty_scale)
    return Optimizer{T,Nothing}(nothing, nothing, nothing, Dict{Symbol,Any}(), settings)
end

function Optimizer{T}(callable::Any; penalty_offset = one(T), penalty_scale = one(T)) where {T}
    settings = _penalty_settings(T, penalty_offset, penalty_scale)
    optimizer = callable()

    return Optimizer{T,typeof(optimizer)}(optimizer, nothing, nothing, Dict{Symbol,Any}(), settings)
end

# Preserve the previous positional constructor for callers holding raw data.
Optimizer{T,O}(inner, source, target, data) where {T,O} =
    Optimizer{T,O}(inner, source, target, data, Dict{Symbol,Any}())

Optimizer(args...; kws...) = Optimizer{Float64}(args...; kws...)

function MOI.is_empty(solver::Optimizer{T}) where {T}
    return isnothing(solver.source_model) || MOI.is_empty(solver.source_model)
end

function MOI.empty!(solver::Optimizer{T}) where {T}
    isnothing(solver.inner) || MOI.empty!(solver.inner)
    isnothing(solver.source_model) || MOI.empty!(solver.source_model)
    isnothing(solver.target_model) || MOI.empty!(solver.target_model)
    empty!(solver.data)

    return nothing
end

include("attributes/model.jl")
include("attributes/results.jl")
include("attributes/reformulation.jl")

function _source_variable_positions(source::MOI.ModelLike)
    return Dict(vi => i for (i, vi) in enumerate(MOI.get(source, MOI.ListOfVariableIndices())))
end

function _source_constraint_positions(::Type{T}, source::MOI.ModelLike) where {T}
    constraints = Dict{Any,Int}()
    for (F, S) in ((SAF{T}, EQ{T}), (SAF{T}, LT{T}), (SAF{T}, GT{T}))
        for (i, ci) in enumerate(MOI.get(source, MOI.ListOfConstraintIndices{F,S}()))
            constraints[ci] = i
        end
    end
    return constraints
end

function MOI.optimize!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    # A failed new reformulation must not expose the previous model's mappings.
    # Replace the dictionary so externally retained raw data remains usable.
    solver.data = Dict{Symbol,Any}()
    solver.target_model = nothing
    solver.source_model = model
    variable_positions = _source_variable_positions(solver.source_model)
    constraint_positions = _source_constraint_positions(T, solver.source_model)

    solver.target_model, solver.data = to_quio(
        T,
        vi -> variable_positions[vi], # varmap : VI -> Int
        ci -> constraint_positions[ci], # conmap : CI{F,S} -> Int
        solver.source_model,
        ϵ = MOI.get(solver, PenaltyOffset()),
        penalty_scale = MOI.get(solver, PenaltyScale()),
    )

    if !isnothing(solver.inner)
        index_map, _ = MOI.optimize!(solver.inner, solver.target_model)
        target_variables = MOI.get(solver.target_model, MOI.ListOfVariableIndices())
        solver.data[:target_to_backend_variables] = Dict{VI,VI}(
            vi => index_map[vi] for vi in target_variables
        )
    end

    return (MOIU.identity_index_map(solver.source_model), false)
end

MOI.supports(::Optimizer{T}, ::MOI.ObjectiveFunction{F}) where {T,F<:Union{SAF{T},SQF{T}}}= true

MOI.supports_constraint(
    ::Optimizer{T},
    ::Type{VI},
    ::Type{<:Union{EQ{T},LT{T},GT{T},MOI.Interval{T}}},
) where {T} = true
MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{<:Union{MOI.ZeroOne,MOI.Integer}}) where {T} = true

MOI.supports_constraint(::Optimizer{T}, ::Type{<:Union{SAF{T}}}, ::Type{<:Union{EQ{T},LT{T},GT{T}}}) where {T} = true
