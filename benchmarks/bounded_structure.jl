# Credential-free structural evidence; no solver, campaign or device calls.
module BoundedStructureExample
using ToQUIO
const M = ToQUIO.MOI
const dot = ToQUIO.LinearAlgebra.dot

function integer_variable(model, lower, upper)
    x = M.add_variable(model)
    M.add_constraint(model, x, M.Interval(Float64(lower), Float64(upper)))
    M.add_constraint(model, x, M.Integer())
    return x
end

function structural_source(name)
    source = M.Utilities.Model{Float64}()
    x = integer_variable(source, name == "scalar" ? -2 : 0, name == "scalar" ? 8 : 3)
    if name == "scalar"
        f = M.ScalarQuadraticFunction([M.ScalarQuadraticTerm(2.0, x, x)],
                                     [M.ScalarAffineTerm(3.0, x)], 5.0)
        original, slacks, expected = [-1], Dict{Any,Int}(), 3
    elseif name == "slack-heavy"
        y = integer_variable(source, 0, 2)
        f = M.ScalarQuadraticFunction([
            M.ScalarQuadraticTerm(2.0, x, x), M.ScalarQuadraticTerm(3.0, x, y),
            M.ScalarQuadraticTerm(4.0, y, y),
        ], [M.ScalarAffineTerm(-5.0, x), M.ScalarAffineTerm(4.0, y)], 7.0)
        row(a, b) = M.ScalarAffineFunction([M.ScalarAffineTerm(Float64(a), x),
                                            M.ScalarAffineTerm(Float64(b), y)], 0.0)
        c1 = M.add_constraint(source, row(1, 1), M.LessThan(3.0))
        c2 = M.add_constraint(source, row(1, -1), M.GreaterThan(0.0))
        c3 = M.add_constraint(source, row(2, 1), M.LessThan(6.0))
        c4 = M.add_constraint(source, row(1, -2), M.GreaterThan(-2.0))
        # Independent residual values at x=1,y=0; use IDs only to order slacks.
        original, slacks, expected = [1, 0], Dict{Any,Int}(c1 => 2, c2 => 1, c3 => 4, c4 => 3), 3
    else
        throw(ArgumentError("Unknown structural case."))
    end
    M.set(source, M.ObjectiveSense(), M.MIN_SENSE)
    M.set(source, M.ObjectiveFunction{typeof(f)}(), f)
    return source, original, slacks, expected
end

function target_polynomial(optimizer)
    data = optimizer.data
    if haskey(data, :encoded_Q)
        return data[:encoded_Q], data[:encoded_L], data[:encoded_c], data[:encoded_l], data[:encoded_u]
    end
    return data[:Q], data[:L], data[:c], data[:l], data[:u]
end

function canonical_polynomial(optimizer)
    G, g, constant, lower, upper = target_polynomial(optimizer)
    L, U = ceil.(Int, lower), floor.(Int, upper)
    active = findall(L .< U)
    offset = Float64.(L)
    expansion = zeros(Float64, length(L), length(active))
    for (j, i) in enumerate(active)
        expansion[i, j] = 1.0
    end
    shifted_G = expansion' * G * expansion
    shifted_g = expansion' * (g + (G + G') * offset)
    shifted_c = dot(offset, G * offset) + dot(g, offset) + constant
    widths = (U - L)[active]
    for i in eachindex(widths)
        if widths[i] == 1
            shifted_g[i] += shifted_G[i, i]
            shifted_G[i, i] = 0.0
        end
    end
    return (G = shifted_G, g = shifted_g, constant = shifted_c,
            active = active, offset = offset, widths = widths)
end

function multiplicity_statistics(optimizer; max_native_states = 10_000)
    lower, upper = ceil.(BigInt, optimizer.data[:l]), floor.(BigInt, optimizer.data[:u])
    native_states = prod(u - l + 1 for (l, u) in zip(lower, upper); init = big(1))
    native_states <= max_native_states ||
        throw(ArgumentError("Multiplicity DP exceeds the native-state budget."))
    target_states, smallest, largest = big(1), big(1), big(1)
    if haskey(optimizer.data, :encoding_layouts)
        for (layout, l, u) in zip(optimizer.data[:encoding_layouts], lower, upper)
            counts = BigInt[1]
            assignments = big(1)
            for (weight, bound) in zip(layout.weights, layout.upper_bounds)
                next_counts = zeros(BigInt, length(counts) + Int(weight * bound))
                for i in eachindex(counts), digit in 0:Int(bound)
                    next_counts[i + Int(weight) * digit] += counts[i]
                end
                counts = next_counts
                assignments *= bound + 1
            end
            @assert all(>(0), counts)
            @assert length(counts) == u - l + 1
            @assert sum(counts) == assignments
            target_states *= assignments
            smallest *= minimum(counts)
            largest *= maximum(counts)
        end
    else
        target_states = native_states
    end
    return (target_states = target_states, native_states = native_states,
            preimages_min = smallest, preimages_max = largest)
end

function structure_statistics(optimizer)
    G, g, _, lower, upper = target_polynomial(optimizer)
    canonical = canonical_polynomial(optimizer)
    n = length(canonical.active)
    squares = [canonical.G[i, i] for i in 1:n if !iszero(canonical.G[i, i])]
    linear = filter(!iszero, canonical.g)
    couplers = [canonical.G[i, j] + canonical.G[j, i] for i in 1:n for j in (i + 1):n
                if !iszero(canonical.G[i, j] + canonical.G[j, i])]
    coefficients = abs.([squares; linear; couplers])
    lo = isempty(coefficients) ? nothing : minimum(coefficients)
    hi = isempty(coefficients) ? nothing : maximum(coefficients)
    max_weight = if haskey(optimizer.data, :encoding_layouts)
        maximum((w for layout in optimizer.data[:encoding_layouts] for w in layout.weights); init = 0)
    else
        isempty(canonical.active) ? 0 : 1
    end
    return merge((
        variables = length(lower), active = n,
        auxiliaries = length(auxiliary_variables(optimizer)),
        max_levels = maximum(floor.(Int, upper) - ceil.(Int, lower) .+ 1; init = 0),
        max_weight = max_weight,
        raw_Q_max = maximum(abs, G; init = 0.0), raw_L_max = maximum(abs, g; init = 0.0),
        nonbinary_squares = length(squares), linear_terms = length(linear), couplers = length(couplers),
        density = n < 2 ? 0.0 : 2length(couplers) / (n * (n - 1)),
        coefficient_min = lo, coefficient_max = hi,
        coefficient_ratio = isnothing(lo) ? nothing : hi / lo,
    ), multiplicity_statistics(optimizer))
end

function bounded_structural_comparison()
    rows = NamedTuple[]
    strategies = (("native", NativeEncoding()), ("radix", RadixEncoding(; levels = 4)),
                  ("bounded", BoundedEncoding(; levels = 4, max_weight = 2)))
    for name in ("scalar", "slack-heavy")
        source, original, slack_values, expected = structural_source(name)
        native_rho = nothing
        for (arm, strategy) in strategies
            optimizer = ToQUIO.Optimizer(; encoding = strategy)
            M.optimize!(optimizer, source)
            point = [original; [slack_values[ci] for ci in optimizer.data[:slack_constraints]]]
            digits = lift_native_state(optimizer, point)
            @assert project_native_state(optimizer, digits) == point
            @assert is_feasible(optimizer, digits)
            isnothing(native_rho) && (native_rho = copy(optimizer.data[:rho]))
            @assert optimizer.data[:rho] == native_rho
            variables = M.get(optimizer.target_model, M.ListOfVariableIndices())
            positions = Dict(v => i for (i, v) in enumerate(variables))
            F = M.get(optimizer.target_model, M.ObjectiveFunctionType())
            f = M.get(optimizer.target_model, M.ObjectiveFunction{F}())
            energy = M.Utilities.eval_variables(v -> digits[positions[v]], f)
            @assert energy == expected
            canonical = canonical_polynomial(optimizer)
            shifted = (digits - canonical.offset)[canonical.active]
            @assert dot(shifted, canonical.G * shifted) + dot(canonical.g, shifted) +
                    canonical.constant == expected
            push!(rows, merge((case = name, arm = arm, weight_cap = arm == "bounded" ? 2 : nothing,
                               level_cap = arm == "native" ? nothing : 4,
                               rho = copy(optimizer.data[:rho]), energy = energy),
                              structure_statistics(optimizer)))
        end
    end
    return rows
end

const RESULTS = bounded_structural_comparison()
end

foreach(println, BoundedStructureExample.RESULTS)
BoundedStructureExample.RESULTS
