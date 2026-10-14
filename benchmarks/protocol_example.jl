# Executable scientific specification, not a public encoding implementation.
using ToQUIO
const protocol_dot = ToQUIO.LinearAlgebra.dot
const PMOI = ToQUIO.MOI

Base.include(@__MODULE__, joinpath(@__DIR__, "protocol_helpers.jl"))

function protocol_affine_substitution(G, g, gamma, offset, expansion)
    result = (
        G = expansion' * G * expansion,
        g = expansion' * (g + (G + G') * offset),
        gamma = protocol_dot(offset, G * offset) + protocol_dot(g, offset) + gamma,
    )
    all(isfinite, result.G) && all(isfinite, result.g) && isfinite(result.gamma) ||
        throw(ArgumentError("Affine substitution produced nonfinite coefficients."))
    return result
end

function protocol_knapsack(; penalty_hint = nothing)
    source = PMOI.Utilities.UniversalFallback(PMOI.Utilities.Model{Float64}())
    x, y = PMOI.add_variables(source, 2)
    for (vi, upper) in ((x, 2.0), (y, 1.0))
        PMOI.add_constraint(source, vi, PMOI.Interval(0.0, upper))
        PMOI.add_constraint(source, vi, PMOI.Integer())
    end
    objective = PMOI.ScalarAffineFunction([
        PMOI.ScalarAffineTerm(3.0, x), PMOI.ScalarAffineTerm(2.0, y),
    ], 0.0)
    PMOI.set(source, PMOI.ObjectiveFunction{typeof(objective)}(), objective)
    PMOI.set(source, PMOI.ObjectiveSense(), PMOI.MAX_SENSE)
    capacity = PMOI.ScalarAffineFunction([
        PMOI.ScalarAffineTerm(2.0, x), PMOI.ScalarAffineTerm(1.0, y),
    ], 0.0)
    ci = PMOI.add_constraint(source, capacity, PMOI.LessThan(3.0))
    optimizer = ToQUIO.Optimizer()
    isnothing(penalty_hint) || PMOI.set(source, ToQUIO.ConstraintPenaltyHint(), ci, penalty_hint)
    PMOI.optimize!(optimizer, source)
    return optimizer
end

function protocol_example()
    optimizer = protocol_knapsack()
    data = optimizer.data
    G, g, gamma = data[:Q], data[:L], data[:c]
    native_value(z) = protocol_dot(z, G * z) + protocol_dot(g, z) + gamma
    # x=d1+d2, y=d3, s=d4+2d5: exact bounded binary maps of widths 2,1,3.
    expansion = Float64[1 1 0 0 0; 0 0 1 0 0; 0 0 0 1 2]
    transformed = protocol_affine_substitution(G, g, gamma, zeros(3), expansion)
    binary_value(d) = protocol_dot(d, transformed.G * d) + protocol_dot(transformed.g, d) + transformed.gamma
    protocol_state_count([2, 1, 3]; limit = 1_000_000)
    protocol_state_count(ones(Int, 5); limit = 1_000_000)
    native_states = [collect(z) for z in Iterators.product(0:2, 0:1, 0:3)]
    binary_states = [collect(d) for d in Iterators.product(ntuple(_ -> 0:1, 5)...)]
    images = [expansion * d for d in binary_states]
    @assert Set(Tuple(z) for z in images) == Set(Tuple(z) for z in native_states)
    @assert all(binary_value(d) == native_value(expansion * d) for d in binary_states)
    source_points = [(x, y) for x in 0:2 for y in 0:1 if 2x + y <= 3]
    reference = maximum(3x + 2y for (x, y) in source_points)
    native_optimum = maximum(native_value(z) for z in native_states)
    binary_optimum = maximum(binary_value(d) for d in binary_states)
    @assert all(ToQUIO.is_feasible(data, z) for z in native_states if native_value(z) == native_optimum)
    # Exercise the actual hint override; retain an independent formula check.
    weak_data = protocol_knapsack(; penalty_hint = 0.25).data
    weak_value(z) = protocol_dot(z, weak_data[:Q] * z) + protocol_dot(weak_data[:L], z) + weak_data[:c]
    @assert only(weak_data[:rho]) == 0.25
    @assert all(weak_value(z) == 3z[1] + 2z[2] - 0.25 * (2z[1] + z[2] + z[3] - 3)^2
                for z in native_states)
    weak_best = native_states[argmax(weak_value.(native_states))]
    return (
        source_optimum = reference, automatic_penalty = only(data[:rho]),
        native_optimum = native_optimum, binary_optimum = binary_optimum,
        native_states = length(native_states), binary_states = length(binary_states),
        decoded_states = length(Set(Tuple(z) for z in images)),
        weak_optimum = weak_value(weak_best), weak_source_feasible = ToQUIO.is_feasible(data, weak_best),
    )
end

let result = protocol_example()
    println(result)
    result
end
