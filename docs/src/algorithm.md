# Algorithm Documentation

This document describes the mathematical formulation and algorithmic details of the QUIO reformulation implemented in ToQUIO.jl.

## Table of Contents

- [Problem Formulation](#problem-formulation)
- [Penalty Method](#penalty-method)
- [Slack Variables](#slack-variables)
- [Penalty Coefficient Computation](#penalty-coefficient-computation)
- [Reformulation Steps](#reformulation-steps)
- [Mathematical Derivation](#mathematical-derivation)

## Problem Formulation

### Original Problem (P)

ToQUIO handles integer programming problems of the form:

```
minimize    f(x) = x'Qx + ℓ'x + β
subject to  A_eq x = b_eq       (m_eq equality constraints)
            A_le x ≤ b_le       (m_le inequality constraints)
            A_ge x ≥ b_ge       (m_ge inequality constraints)
            l ≤ x ≤ u           (variable bounds)
            x ∈ ℤⁿ              (integer variables)
```

Where:
- `x ∈ ℤⁿ`: Decision variables
- `Q ∈ ℝⁿˣⁿ`: Quadratic cost matrix (can be zero for linear problems)
- `ℓ ∈ ℝⁿ`: Linear cost vector
- `β ∈ ℝ`: Constant term
- `A_eq, A_le, A_ge`: Constraint matrices
- `b_eq, b_le, b_ge`: Right-hand side vectors
- `l, u ∈ ℝⁿ`: Variable lower and upper bounds

### Target Problem (QUIO)

The reformulated problem is:

```
minimize    z'Gz + g'z + γ
subject to  l̃ ≤ z ≤ ũ
            z ∈ ℤᵐ
```

Where:
- `z = [x; s]`: Extended variable vector (original + slack variables)
- `G ∈ ℝᵐˣᵐ`: Reformulated quadratic matrix
- `g ∈ ℝᵐ`: Reformulated linear vector
- `γ ∈ ℝ`: Reformulated constant
- `m = n + m_le + m_ge`: Total variables (original + slacks)

## Penalty Method

The core idea is to incorporate constraints into the objective using quadratic penalties.

### Equality Constraints

For each equality constraint `a'x = b`, we add a penalty term:

```
P_eq(x) = ρ_eq * (a'x - b)²
```

Where `ρ_eq > 0` is the penalty coefficient. As `ρ_eq → ∞`, minimizing the penalized objective forces the constraint to be satisfied.

### Inequality Constraints

For inequality constraints `a'x ≤ b`, we introduce a slack variable `s ≥ 0` and rewrite as:

```
a'x + s = b,  s ≥ 0
```

Then apply the equality penalty:

```
P_le(x, s) = ρ_le * (a'x + s - b)²
```

Similarly for `a'x ≥ b`, we write `a'x - s = b` with `s ≥ 0`.

## Slack Variables

### Slack Bounds Computation

For inequality constraint `a'x ≤ b` with `l ≤ x ≤ u`, the slack variable `s` must satisfy:

```
s = b - a'x
```

Given variable bounds `l ≤ x ≤ u`, we compute:

```
δ_l = min{a'x : l ≤ x ≤ u}
δ_u = max{a'x : l ≤ x ≤ u}
```

For linear constraints with bounded variables:

```
δ_l = Σᵢ min(aᵢlᵢ, aᵢuᵢ)
δ_u = Σᵢ max(aᵢlᵢ, aᵢuᵢ)
```

Then the slack variable bound is:

```
0 ≤ s ≤ b - δ_l
```

This ensures that when `a'x` is at its minimum value `δ_l`, the slack is at its maximum `b - δ_l`, and when `a'x = b`, the slack is zero.

## Penalty Coefficient Computation

The penalty coefficients must be large enough to enforce constraints but not so large that they cause numerical issues.

### Objective Range

First, compute an objective range bound over the region defined by variable bounds:

```
Δ_bound ≥ max{f(x) : l ≤ x ≤ u} - min{f(x) : l ≤ x ≤ u}
```

For linear objectives `f(x) = ℓ'x + β`, this bound is exact:

```
Δ_bound = Σᵢ |ℓᵢ|(uᵢ - lᵢ)
```

For quadratic objectives, ToQUIO computes a conservative termwise interval
bound by summing the minimum and maximum contribution of each affine and
quadratic objective term over the variable bounds. This can overestimate the
exact objective range because each term is bounded independently.

### Sensibility Factor

For constraint `Ax ⊙ b` (where ⊙ is =, ≤, or ≥), the sensibility factor `ε`
represents the minimum nonzero violation magnitude. The current implementation
requires integer-valued constraint coefficients and right-hand sides, so:

```
ε = 1
```

This ensures that any violation is at least 1 in magnitude.

### Penalty Formula

The automatic penalty coefficient for each constraint is computed as:

```
ρ_auto = Δ_bound/ε² + ϵ
```

Where:
- `Δ_bound`: Exact objective range for affine objectives, or a conservative
  objective range bound for quadratic objectives
- `ε`: Minimum nonzero violation magnitude
- `ϵ`: User-specified adjustment (default: 1.0)

Because the penalty term is quadratic, a minimum nonzero violation contributes
`ρ_auto * ε²`. With positive `ϵ`, the automatic coefficient makes that
contribution larger than the objective range bound, strongly incentivizing
feasibility.

### User-Specified Penalties

Users can override automatic penalties using the `ConstraintPenaltyHint` attribute:

```julia
MOI.set(model, ConstraintPenaltyHint(), constraint, custom_penalty)
```

Custom penalty hints must be finite and positive. They override the automatic
sufficient coefficient and are treated as user-chosen heuristic values; if a
hint is lower than `ρ_auto`, ToQUIO uses it but equivalence to the constrained
problem is not guaranteed. The reformulation metadata stores the selected
penalties, automatic penalties, and user hints for inspection.

## Reformulation Steps

### Step 1: Extract Problem Data

1. Extract objective function `f(x) = x'Qx + ℓ'x + β`
2. Extract variable bounds `l, u`
3. Extract equality constraints `A_eq x = b_eq`
4. Extract inequality constraints `A_le x ≤ b_le` and `A_ge x ≥ b_ge`
5. Combine inequalities: `A_ie = [A_le; -A_ge]`, `b_ie = [b_le; -b_ge]`

### Step 2: Compute Penalties

1. Compute objective range bound `Δ_bound`
2. Compute sensibility factors `ε_eq`, `ε_ie`
3. Compute penalty coefficients:
   - `ρ_auto_eq = Δ_bound/ε_eq² + ϵ` for equalities
   - `ρ_auto_ie = Δ_bound/ε_ie² + ϵ` for inequalities
4. Apply user hints if provided

### Step 3: Add Slack Variables

1. Compute slack bounds for inequalities
2. Create slack variables `s` with bounds `0 ≤ s ≤ sb`
3. Form extended variable vector `z = [x; s]`

### Step 4: Build QUIO Matrices

Construct the penalized objective:

```
F(z) = f(x) + Σᵢ ρ_eq,i (aᵢ'x - bᵢ)² + Σⱼ ρ_ie,j (cⱼ'x + sⱼ - dⱼ)²
```

Expand to standard form `z'Gz + g'z + γ`.

## Mathematical Derivation

### Equality Penalty Expansion

For equality constraints with diagonal penalty matrix `D_eq = diag(ρ_eq)`:

```
P_eq(x) = (A_eq x - b_eq)' D_eq (A_eq x - b_eq)
        = x'(A_eq' D_eq A_eq)x - 2(A_eq' D_eq b_eq)'x + b_eq' D_eq b_eq
```

### Inequality Penalty Expansion

For inequality constraints with slacks and penalty matrix `D_ie = diag(ρ_ie)`:

```
P_ie(x,s) = (A_ie x + s - b_ie)' D_ie (A_ie x + s - b_ie)
          = x'(A_ie' D_ie A_ie)x + s'D_ie s + x'(A_ie' D_ie)s 
            + s'(D_ie A_ie)x - 2(A_ie' D_ie b_ie)'x - 2(D_ie b_ie)'s 
            + b_ie' D_ie b_ie
```

### Combined Objective

The full reformulated objective is:

```
F(z) = x'Qx + ℓ'x + β
     + x'(A_eq' D_eq A_eq)x - 2(A_eq' D_eq b_eq)'x + b_eq' D_eq b_eq
     + x'(A_ie' D_ie A_ie)x + s'D_ie s + x'(A_ie' D_ie)s + s'(D_ie A_ie)x
     - 2(A_ie' D_ie b_ie)'x - 2(D_ie b_ie)'s + b_ie' D_ie b_ie
```

Collecting terms with `D = diag([ρ_eq; ρ_ie])`, `A = [A_eq; A_ie]`, `b = [b_eq; b_ie]`:

```
G = [ Q + A_eq' D_eq A_eq + A_ie' D_ie A_ie ,  A_ie' D_ie ]
    [        D_ie A_ie                       ,     D_ie    ]

g = [    ℓ - 2A' D b    ]
    [ -2 D_ie b_ie      ]

γ = β + b' D b
```

### Block Matrix Structure

The quadratic matrix `G` has blocks:

```
G = [ G_xx  G_xs ]
    [ G_sx  G_ss ]
```

Where:
- `G_xx = Q + A_eq' D_eq A_eq + A_ie' D_ie A_ie`: Original + penalty quadratic terms
- `G_xs = A_ie' D_ie`: Coupling between original and slack variables
- `G_sx = D_ie A_ie`: Symmetric coupling
- `G_ss = D_ie`: Slack variable quadratic terms

This structure ensures:
1. The original objective is preserved in `G_xx`
2. Penalties on equalities are added to `G_xx`
3. Inequalities couple original and slack variables
4. Slack variables have simple quadratic penalties

## Implementation Notes

### Numerical Stability

1. **Penalty magnitude**: Automatically computed to balance constraint enforcement and numerical stability
2. **Matrix symmetry**: Care is taken to maintain symmetry in quadratic matrices
3. **Sparse storage**: Could be improved for large-scale problems (future work)

### Optimality

The reformulated problem is equivalent to the original if:
1. Penalties are sufficiently large
2. Slack bounds are correctly computed
3. Numeric precision is adequate

In practice, finite penalties may result in small constraint violations that are acceptable in many applications.

### Extensions

Possible extensions include:
1. **Adaptive penalties**: Adjust penalties during optimization
2. **Warm starting**: Use solutions to guide penalty selection
3. **Nonlinear objectives**: Extend to nonlinear QUIO formulations
4. **SOS constraints**: Special handling for special ordered sets
