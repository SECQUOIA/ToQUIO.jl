function get_variable_bounds(::Type{T}, varmap::Function, source::MOI.ModelLike) where {T}
    n = MOI.get(source, MOI.NumberOfVariables())

    l = fill!(Vector{Maybe{T}}(undef, n), nothing) 
    u = fill!(Vector{Maybe{T}}(undef, n), nothing)

    for ci in MOI.get(source, MOI.ListOfConstraintIndices{VI,GT{T}}())
        vi = MOI.get(source, MOI.ConstraintFunction(), ci)
        li = MOI.get(source, MOI.ConstraintSet(), ci).lower
        i  = varmap(vi)

        l[i] = li
    end

    for ci in MOI.get(source, MOI.ListOfConstraintIndices{VI,LT{T}}())
        vi = MOI.get(source, MOI.ConstraintFunction(), ci)
        ui = MOI.get(source, MOI.ConstraintSet(), ci).upper
        i  = varmap(vi)

        u[i] = ui
    end

    for ci in MOI.get(source, MOI.ListOfConstraintIndices{VI,MOI.Interval{T}}())
        vi = MOI.get(source, MOI.ConstraintFunction(), ci)
        li = MOI.get(source, MOI.ConstraintSet(), ci).lower
        ui = MOI.get(source, MOI.ConstraintSet(), ci).upper
        i  = varmap(vi)

        l[i] = li
        u[i] = ui
    end

    for ci in MOI.get(source, MOI.ListOfConstraintIndices{VI,EQ{T}}())
        vi = MOI.get(source, MOI.ConstraintFunction(), ci)
        li = MOI.get(source, MOI.ConstraintSet(), ci).value
        ui = MOI.get(source, MOI.ConstraintSet(), ci).value
        i  = varmap(vi)

        l[i] = li
        u[i] = ui
    end

    @assert all(!isnothing, l) && all(!isnothing, u) "The model contains unbounded variables."

    return (collect(T, l), collect(T, u))
end

function get_objective_bounds(varmap::Function, f::SAF{T}, l::AbstractVector{T}, u::AbstractVector{T}) where {T}
    δl = zero(T)
    δu = zero(T)

    for t in f.terms
        c = t.coefficient
        j = varmap(t.variable)

        lj = c * l[j]
        uj = c * u[j]

        δl += min(lj, uj)
        δu += max(lj, uj)
    end

    return (δl, δu)
end

function get_objective_bounds(varmap::Function, f::SQF{T}, l::AbstractVector{T}, u::AbstractVector{T}) where {T}
    δl = zero(T)
    δu = zero(T)

    for t in f.affine_terms
        c = t.coefficient
        j = varmap(t.variable)

        lj = c * l[j]
        uj = c * u[j]

        δl += min(lj, uj)
        δu += max(lj, uj)
    end

    for t in f.quadratic_terms
        c = t.coefficient
        j = varmap(t.variable_1)
        k = varmap(t.variable_2)

        lljk = c * l[j] * l[k]
        lujk = c * l[j] * u[k]
        uljk = c * u[j] * l[k]
        uujk = c * u[j] * u[k]

        δl += min(lljk, lujk, uljk, uujk)
        δu += max(lljk, lujk, uljk, uujk)
    end

    return (δl, δu)
end

"""
    get_objective_delta(varmap::Function, f::SAF{T}, l::AbstractVector{T}, u::AbstractVector{T}) where {T}
"""
function get_objective_delta(varmap::Function, f, l::AbstractVector{T}, u::AbstractVector{T}) where {T}
    δl, δu = get_objective_bounds(varmap, f, l, u)

    return δu - δl
end

"""
    get_constraint_bounds(T, A, l, u)
"""
function get_constraint_bounds(T, A, l, u)
    m, n = size(A)

    δl = zeros(T, m)
    δu = zeros(T, m)

    for i = 1:m, j = 1:n
        δl[i] += min(A[i, j] * l[j], A[i, j] * u[j])
        δu[i] += max(A[i, j] * l[j], A[i, j] * u[j])
    end

    return (δl, δu)
end

function get_sensibility(A::AbstractMatrix{T}, b::AbstractVector{T}) where {T}
    if all(isinteger, A) && all(isinteger, b)
        return ones(T, length(b))
    else
        error("Constraint coefficients must be integer")
    end
end

@doc raw"""
    varmap : VI -> Int
"""
function to_quio(::Type{T}, varmap::Function, source::MOI.ModelLike; ϵ = one(T)) where {T}
    # opt f(x)
    #  st A_eq x = b_eq
    #     A_lt x ≤ b_lt
    #     A_gt x ≥ b_gt
    #      l ≤ x ≤ u

    F = MOI.get(source, MOI.ObjectiveFunctionType())
    f = MOI.get(source, MOI.ObjectiveFunction{F}())

    l, u = get_variable_bounds(T, varmap, source)

    Δ = get_objective_delta(varmap, f, l, u)

    A_eq, b_eq = get_eq_matrices(T, varmap, source)
    A_lt, b_lt = get_lt_matrices(T, varmap, source)
    A_gt, b_gt = get_gt_matrices(T, varmap, source)
    A_ie, b_ie = [A_lt; -A_gt], [b_lt; -b_gt]

    ε_eq = get_sensibility(A_eq, b_eq)
    ε_ie = get_sensibility(A_ie, b_ie)

    # Compute Penalties!
    # TODO: Store penalties for analysis
    ρ_eq = (Δ ./ ε_eq) .+ ϵ
    ρ_ie = (Δ ./ ε_ie) .+ ϵ

    target = QUIOModel{T}()

    cl, cu = get_constraint_bounds(T, A_ie, l, u)
    sb     = b_ie - cl # Calculate slack bounds

    x, _ = MOI.add_constrained_variables(target, MOI.Interval{T}.(l, u))
    MOI.add_constraints(target, x, MOI.Integer())
    
    s, _ = MOI.add_constrained_variables(target, MOI.Interval{T}.(zero(T), sb)) # slack variables 0 ≤ s_i ≤ sb_i
    MOI.add_constraints(target, s, MOI.Integer())

    p_eq = A_eq * x - b_eq
    p_ie = A_ie * x - b_ie + s

    g = ρ_eq' * (p_eq .* p_eq)
    h = ρ_ie' * (p_ie .* p_ie)

    if MOI.get(source, MOI.ObjectiveSense()) === MOI.MAX_SENSE
        MOI.set(
            target,
            MOI.ObjectiveSense(),
            MOI.MAX_SENSE,
        )

        obj = f - (g + h)
    else # minimization or feasibility
        MOI.set(
            target,
            MOI.ObjectiveSense(),
            MOI.MIN_SENSE,
        )

        obj = f + (g + h)
    end

    MOI.set(
        target,
        MOI.ObjectiveFunction{SQF{T}}(),
        obj,
    )

    return target
end

function get_eq_matrices(::Type{T}, varmap, source) where {T}
    F = SAF{T}
    S = EQ{T}

    m = MOI.get(source, MOI.NumberOfConstraints{F,S}())
    n = MOI.get(source, MOI.NumberOfVariables())

    A = zeros(T, m, n)
    b = zeros(T, m)

    for (i, ci) in enumerate(MOI.get(source, MOI.ListOfConstraintIndices{F,S}()))
        fi = MOI.get(source, MOI.ConstraintFunction(), ci)
        si = MOI.get(source, MOI.ConstraintSet(), ci)

        for t in fi.terms
            v = t.variable::VI
            c = t.coefficient::T
            j = varmap(v)

            A[i, j] = c
        end

        b[i] = si.value - fi.constant
    end

    return (A, b)
end

function get_lt_matrices(::Type{T}, varmap, source) where {T}
    F = SAF{T}
    S = LT{T}

    m = MOI.get(source, MOI.NumberOfConstraints{F,S}())
    n = MOI.get(source, MOI.NumberOfVariables())

    A = zeros(T, m, n)
    b = zeros(T, m)

    for (i, ci) in enumerate(MOI.get(source, MOI.ListOfConstraintIndices{F,S}()))
        fi = MOI.get(source, MOI.ConstraintFunction(), ci)
        si = MOI.get(source, MOI.ConstraintSet(), ci)

        for t in fi.terms
            v = t.variable::VI
            c = t.coefficient::T
            j = varmap(v)

            A[i, j] = c
        end

        b[i] = si.upper - fi.constant
    end

    return (A, b)
end

function get_gt_matrices(::Type{T}, varmap, source) where {T}
    F = SAF{T}
    S = GT{T}

    m = MOI.get(source, MOI.NumberOfConstraints{F,S}())
    n = MOI.get(source, MOI.NumberOfVariables())

    A = zeros(T, m, n)
    b = zeros(T, m)

    for (i, ci) in enumerate(MOI.get(source, MOI.ListOfConstraintIndices{F,S}()))
        fi = MOI.get(source, MOI.ConstraintFunction(), ci)
        si = MOI.get(source, MOI.ConstraintSet(), ci)

        for t in fi.terms
            v = t.variable::VI
            c = t.coefficient::T
            j = varmap(v)

            A[i, j] = c
        end

        b[i] = si.upper - fi.constant
    end

    return (A, b)
end
