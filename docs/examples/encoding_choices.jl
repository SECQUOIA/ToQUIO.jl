# Run with --project=docs/examples after setup.jl; no optimizer backend is used.
module EncodingChoicesExample
using JuMP, ToQUIO
const M = ToQUIO.MOI

function example(encoding)
    optimizer = ToQUIO.Optimizer(; encoding, penalty_offset = 1.0, penalty_scale = 1.0)
    model = Model(() -> optimizer)
    @variable(model, -2 <= x <= 8, Int)
    @variable(model, y, Bin)
    @variable(model, fixed == 2, Int)
    @constraint(model, x + y <= 6)
    @objective(model, Min, x^2 + 3x + 5 + 2y - fixed)
    optimize!(model) # Compile only, without sampling or a provider.
    return optimizer
end

function compare()
    rows = NamedTuple[]
    native = example(NativeEncoding())
    strategies = (("native", NativeEncoding()), ("radix4", RadixEncoding(; levels = 4)),
        ("bounded4-cap2", BoundedEncoding(; levels = 4, max_weight = 2)),
        ("radix2", RadixEncoding(; levels = 2)))
    for (name, strategy) in strategies
        optimizer = name == "native" ? native : example(strategy)
        snapshot = reformulation_metadata(optimizer)
        native_point = [-1, 0, 2, 7] # x, y, fixed and inequality residual slack.
        digits = lift_native_state(optimizer, native_point)
        @assert project_native_state(optimizer, digits) == native_point
        original = Dict(v => value for (v, value) in
            zip(original_variables(optimizer), native_point[1:3]))
        @assert project_original_state(optimizer, digits) == original
        @assert project_original_state(snapshot, digits) == Dict(v.value => value for (v, value) in original)
        @assert is_feasible(optimizer, digits)
        @assert optimizer.data[:rho] == native.data[:rho]
        variables = M.get(optimizer.target_model, M.ListOfVariableIndices())
        positions = Dict(v => i for (i, v) in enumerate(variables))
        F = M.get(optimizer.target_model, M.ObjectiveFunctionType())
        f = M.get(optimizer.target_model, M.ObjectiveFunction{F}())
        energy = M.Utilities.eval_variables(v -> digits[positions[v]], f)
        @assert energy == 1 # Independent source equation at (-1,0,2).
        quadratic = [abs(t.coefficient / (t.variable_1 == t.variable_2 ? 2 : 1))
                     for t in f.quadratic_terms if !iszero(t.coefficient)]
        linear = [abs(t.coefficient) for t in f.affine_terms if !iszero(t.coefficient)]
        coefficients = [quadratic; linear]
        levels = snapshot["target_upper_bounds"] - snapshot["target_lower_bounds"] .+ 1
        push!(rows, (arm = name, variables = length(variables), max_levels = maximum(levels),
            max_coefficient = maximum(coefficients), min_coefficient = minimum(coefficients),
            ratio = maximum(coefficients) / minimum(coefficients), checked_energy = energy))
    end
    @assert [r.variables for r in rows] == [4, 7, 7, 9]
    @assert [r.max_levels for r in rows] == [11, 4, 4, 2]
    # Golden measurements published in the guide: the selected native penalty
    # is 193, so the slack linear term has magnitude 12*193. After shifting
    # x by -2, the digit linear magnitude is weight*(16*193+1).
    @assert only(native.data[:rho]) == 193
    @assert [r.max_coefficient for r in rows] == [2316, 12356, 6178, 12356]
    @assert [r.min_coefficient for r in rows] == [1, 193, 193, 193]
    # Source feasibility remains independent of whether a target sample was returned.
    @assert !is_feasible(native, [8, 1, 2, 0])
    return rows
end
const RESULTS = compare()
end
foreach(println, EncodingChoicesExample.RESULTS)
