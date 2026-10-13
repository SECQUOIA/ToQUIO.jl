# Credential-free example: run in an environment containing JuMP and ToQUIO.
using JuMP, ToQUIO
const RM = ToQUIO.MOI

function radix_example(encoding)
    optimizer = ToQUIO.Optimizer(; encoding)
    model = Model(() -> optimizer)
    @variable(model, -2 <= x <= 5, Int)
    @variable(model, y, Bin)
    @variable(model, fixed == 2, Int)
    @constraint(model, capacity, x + y <= 3)
    @objective(model, Max, 3x + 2y + fixed)
    optimize!(model) # Reformulate only; no solver or hardware is invoked.
    return optimizer
end

function radix_structural_comparison()
    native = radix_example(NativeEncoding())
    radix = radix_example(RadixEncoding(; levels = 4))
    binary = radix_example(RadixEncoding(; levels = 2))
    native_point = [1, 1, 2, 1] # Source x,y,fixed and the capacity slack.
    rows = NamedTuple[]
    for (name, optimizer) in (("native", native), ("radix4", radix), ("radix2", binary))
        metadata = reformulation_metadata(optimizer)
        digits = lift_native_state(optimizer, native_point)
        @assert project_native_state(optimizer, digits) == native_point
        @assert is_feasible(optimizer, digits)
        @assert optimizer.data[:rho] == native.data[:rho]
        target_variables = RM.get(optimizer.target_model, RM.ListOfVariableIndices())
        positions = Dict(v => i for (i, v) in enumerate(target_variables))
        F = RM.get(optimizer.target_model, RM.ObjectiveFunctionType())
        f = RM.get(optimizer.target_model, RM.ObjectiveFunction{F}())
        energy = RM.Utilities.eval_variables(v -> digits[positions[v]], f)
        @assert energy == 7
        bounds = metadata["target_upper_bounds"] .- metadata["target_lower_bounds"] .+ 1
        push!(rows, (arm = name, variables = length(target_variables),
                     digit_levels = bounds, energy = energy))
    end
    @assert [r.variables for r in rows] == [4, 5, 7]
    @assert maximum(rows[2].digit_levels) <= 4
    @assert maximum(rows[3].digit_levels) == 2
    return rows
end

foreach(println, radix_structural_comparison())
