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

function get_objective_matrices(varmap::Function, n::Integer, f::SAF{T}) where {T}
    ℓ = zeros(T, n)
    Q = zeros(T, n, n)
    b = f.constant

    for t in f.terms
        c = t.coefficient
        j = varmap(t.variable)

        ℓ[j] += c
    end

    return (ℓ, Q, b)
end

function get_objective_matrices(varmap::Function, n::Integer, f::SQF{T}) where {T}
    ℓ = zeros(T, n)
    Q = zeros(T, n, n)
    b = f.constant

    for t in f.affine_terms
        c = t.coefficient
        j = varmap(t.variable)

        ℓ[j] += c
    end

    for t in f.quadratic_terms
        c = t.coefficient
        j = varmap(t.variable_1)
        k = varmap(t.variable_2)

        if j == k
            Q[j, k] += c / 2
        else
            Q[j, k] += c
        end
    end

    return (ℓ, Q, b)
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
function to_quio(::Type{T}, varmap::Function, conmap::Function, source::MOI.ModelLike; ϵ = one(T)) where {T}
    # opt f(x)
    #  st A_eq x = b_eq
    #     A_lt x ≤ b_lt
    #     A_gt x ≥ b_gt
    #      l ≤ x ≤ u

    F = MOI.get(source, MOI.ObjectiveFunctionType())
    f = MOI.get(source, MOI.ObjectiveFunction{F}())

    l, u = get_variable_bounds(T, varmap, source)

    n = MOI.get(source, MOI.NumberOfVariables())

    Δ = get_objective_delta(varmap, f, l, u)

    ℓ, Q, β = get_objective_matrices(varmap, n, f)

    A_eq, b_eq = get_eq_matrices(T, varmap, conmap, source)
    A_lt, b_lt = get_lt_matrices(T, varmap, conmap, source)
    A_gt, b_gt = get_gt_matrices(T, varmap, conmap, source)
    A_ie, b_ie = T[A_lt; -A_gt], T[b_lt; -b_gt]
    A   , b    = T[A_eq;  A_ie], T[b_eq;  b_ie]

    θ_eq = get_eq_penalty_hints(T, conmap, source)
    θ_lt = get_lt_penalty_hints(T, conmap, source)
    θ_gt = get_gt_penalty_hints(T, conmap, source)
    θ_ie = Maybe{T}[θ_lt; θ_gt]

    ε_eq = get_sensibility(A_eq, b_eq)
    ε_ie = get_sensibility(A_ie, b_ie)

    # Compute Penalties!
    # TODO: Store penalties for analysis
    # NOTE: This gives priority to user-defined penalties.
    ρ_eq = something.(θ_eq, (Δ ./ ε_eq) .+ ϵ)
    ρ_ie = something.(θ_ie, (Δ ./ ε_ie) .+ ϵ)
    ρ    = T[ρ_eq; ρ_ie]

    target = QUIOModel{T}()

    D, D_eq, D_ie = if MOI.get(source, MOI.ObjectiveSense()) === MOI.MAX_SENSE
        MOI.set(
            target,
            MOI.ObjectiveSense(),
            MOI.MAX_SENSE,
        )

        (diagm(-ρ), diagm(-ρ_eq), diagm(-ρ_ie))
    else # minimization or feasibility
        MOI.set(
            target,
            MOI.ObjectiveSense(),
            MOI.MIN_SENSE,
        )

        (diagm(ρ), diagm(ρ_eq), diagm(ρ_ie))
    end

    cl, cu = get_constraint_bounds(T, A_ie, l, u)
    sb     = b_ie - cl # Calculate slack bounds

    x, _ = MOI.add_constrained_variables(target, MOI.Interval{T}.(l, u))
    MOI.add_constraints(target, x, MOI.Integer())
    
    s, _ = MOI.add_constrained_variables(target, MOI.Interval{T}.(zero(T), sb)) # slack variables 0 ≤ s_i ≤ sb_i
    MOI.add_constraints(target, s, MOI.Integer())

    z = VI[x; s]
    
    # Construct Penalty terms
    # F = (x' Q x + ℓ' x + β) + ρ_eq' * (A_eq x - b_eq)' (A_eq x - b_eq) + ρ_ie' * (A_ie x + s - b_ie)' (A_ie x + s - b_ie)
    #   = (x' Q x + ℓ' x + β)
    #   + [x' A_eq' D_eq A_eq x - 2 A_eq D_eq b_eq x + b_eq D_eq b_eq]
    #   + [x' A_ie' D_ie A_ie x - 2 A_ie D_ie b_ie x + b_ie D_ie b_ie + x' A_ie' D_ie s + s' A_ie D_ie x + s' D_ie s - 2 s' D_ie b_ie]
    # => [x s] G [x s] = 
    #    [x] [Q + A_eq' D_eq A_eq | ] [x]
    #    [s] [                    | ] [s]

    Gxx = Q + A_eq' * D_eq * A_eq + A_ie' * D_ie * A_ie
    Gxs = A_ie' * D_ie
    Gsx = D_ie * A_ie
    Gss = D_ie

    Gx = [Gxx;; Gxs]
    Gs = [Gsx;; Gss]

    G  = [Gx; Gs] 

    g = [
        ℓ - 2 * A' * D * b;
          - 2 * D_ie  * b_ie
    ]

    γ = b' * D * b + β

    # p_eq = A_eq * x - b_eq
    # p_ie = A_ie * x - b_ie + s

    # g = ρ_eq' * (p_eq .* p_eq)
    # h = ρ_ie' * (p_ie .* p_ie)

    obj = z' * G * z + g' * z + γ

    MOI.set(
        target,
        MOI.ObjectiveFunction{SQF{T}}(),
        obj,
    )

    data = Dict{Symbol,Any}(
        :n => length(z), # dimension
        :Q => G, # quadratic terms
        :L => g, # linear terms
        :c => γ, # constant term
        :D => D, #
        :l => T[l; zeros(T, length(s))], # lower
        :u => T[u; sb],                  # upper
    )

    return (target, data)
end

function get_eq_matrices(::Type{T}, varmap::Function, conmap::Function, source) where {T}
    F = SAF{T}
    S = EQ{T}

    m = MOI.get(source, MOI.NumberOfConstraints{F,S}())
    n = MOI.get(source, MOI.NumberOfVariables())

    A = zeros(T, m, n)
    b = zeros(T, m)

    for ci in MOI.get(source, MOI.ListOfConstraintIndices{F,S}())
        f = MOI.get(source, MOI.ConstraintFunction(), ci)
        s = MOI.get(source, MOI.ConstraintSet(), ci)
        i = conmap(ci)

        for t in f.terms
            vi = t.variable::VI
            c  = t.coefficient::T
            j  = varmap(vi)

            A[i, j] = c
        end

        b[i] = s.value - f.constant
    end

    return (A, b)
end

function get_penalty_hints(::Type{T}, ::Type{F}, ::Type{S}, conmap, source) where {T,F,S}
    m = MOI.get(source, MOI.NumberOfConstraints{F,S}())

    θ = fill!(Vector{Maybe{T}}(undef, m), nothing)

    for ci in MOI.get(source, MOI.ListOfConstraintIndices{F,S}())
        i = conmap(ci)

        θ[i] = MOI.get(source, ConstraintPenaltyHint(), ci)
    end

    return θ
end

get_eq_penalty_hints(::Type{T}, conmap, source) where {T} = get_penalty_hints(T, SAF{T}, EQ{T}, conmap, source)
get_lt_penalty_hints(::Type{T}, conmap, source) where {T} = get_penalty_hints(T, SAF{T}, LT{T}, conmap, source)
get_gt_penalty_hints(::Type{T}, conmap, source) where {T} = get_penalty_hints(T, SAF{T}, GT{T}, conmap, source)

function get_lt_matrices(::Type{T}, varmap::Function, conmap::Function, source) where {T}
    F = SAF{T}
    S = LT{T}

    m = MOI.get(source, MOI.NumberOfConstraints{F,S}())
    n = MOI.get(source, MOI.NumberOfVariables())

    A = zeros(T, m, n)
    b = zeros(T, m)

    for ci in MOI.get(source, MOI.ListOfConstraintIndices{F,S}())
        f = MOI.get(source, MOI.ConstraintFunction(), ci)
        s = MOI.get(source, MOI.ConstraintSet(), ci)
        i = conmap(ci)

        for t in f.terms
            vi = t.variable::VI
            c  = t.coefficient::T
            j  = varmap(vi)

            A[i, j] = c
        end

        b[i] = s.upper - f.constant
    end

    return (A, b)
end

function get_gt_matrices(::Type{T}, varmap::Function, conmap::Function, source) where {T}
    F = SAF{T}
    S = GT{T}

    m = MOI.get(source, MOI.NumberOfConstraints{F,S}())
    n = MOI.get(source, MOI.NumberOfVariables())

    A = zeros(T, m, n)
    b = zeros(T, m)

    for ci in MOI.get(source, MOI.ListOfConstraintIndices{F,S}())
        f = MOI.get(source, MOI.ConstraintFunction(), ci)
        s = MOI.get(source, MOI.ConstraintSet(), ci)
        i = conmap(ci)

        for t in f.terms
            vi = t.variable::VI
            c  = t.coefficient::T
            j  = varmap(vi)

            A[i, j] = c
        end

        b[i] = s.upper - f.constant
    end

    return (A, b)
end
