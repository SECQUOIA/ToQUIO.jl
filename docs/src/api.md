# API Reference

Complete API reference for ToQUIO.jl.

## Table of Contents

- [Optimizer](#optimizer)
- [Reformulation Functions](#reformulation-functions)
- [MOI Attributes](#moi-attributes)
- [Internal Functions](#internal-functions)

## Optimizer

### `ToQUIO.Optimizer`

```julia
Optimizer{T,O<:Maybe{MOI.AbstractOptimizer}} <: MOI.AbstractOptimizer
```

Main optimizer type that handles reformulation and optional solving.

**Type Parameters:**
- `T`: Numeric type for the optimization (e.g., `Float64`, `BigFloat`)
- `O`: Type of the inner optimizer (or `Nothing`)

**Constructors:**

```julia
Optimizer{T}(inner = nothing) where {T}
```

Creates an optimizer with specified numeric type.

**Arguments:**
- `inner`: Optional callable that returns a MOI-compatible optimizer for solving the QUIO problem

**Default Constructor:**

```julia
Optimizer(args...; kws...) = Optimizer{Float64}(args...; kws...)
```

Uses `Float64` as the default numeric type.

**Examples:**

```julia
# Reformulation only
opt = ToQUIO.Optimizer()

# With Float64 (explicit)
opt = ToQUIO.Optimizer{Float64}()

# With a backend solver
opt = ToQUIO.Optimizer(() -> SomeSolver.Optimizer())

# With BigFloat for high precision
opt = ToQUIO.Optimizer{BigFloat}()
```

**Fields:**

- `inner::O`: The inner optimizer instance (or `nothing`)
- `source_model::Maybe{MOI.ModelLike}`: The original problem model
- `target_model::Maybe{QUIOModel}`: The reformulated QUIO model
- `data::Dict{Symbol,Any}`: Reformulation metadata

## Reformulation Functions

### `to_quio`

```julia
to_quio(::Type{T}, varmap::Function, conmap::Function, source::MOI.ModelLike; ϵ = one(T)) where {T}
```

Core function that performs the QUIO reformulation.

**Arguments:**
- `T`: Numeric type for the reformulation
- `varmap`: Function mapping `VariableIndex` to `Int` (variable position)
- `conmap`: Function mapping `ConstraintIndex` to `Int` (constraint position)
- `source`: Source MOI model to reformulate
- `ϵ`: Penalty coefficient adjustment (default: `1.0`)

**Returns:**
- `target::QUIOModel{T}`: Reformulated QUIO model
- `data::Dict{Symbol,Any}`: Dictionary containing:
  - `:n`: Problem dimension (number of variables including slacks)
  - `:Q`: Quadratic term matrix
  - `:L`: Linear term vector
  - `:c`: Constant term
  - `:D`: Diagonal penalty matrix
  - `:l`: Lower bounds vector
  - `:u`: Upper bounds vector

**Input validation:**
- Every source variable must have finite lower and upper bounds and be marked
  `MOI.Integer` or `MOI.ZeroOne`.
- Affine constraint coefficients and right-hand sides must be integer-valued.
- Equality and inequality rows must be feasible within the variable bounds.
- Equality rows must also pass the integer divisibility check for integer
  assignments.
- Custom `ConstraintPenaltyHint` values must be positive.

**Mathematical Formulation:**

The reformulation converts:
```
minimize    f(x)
subject to  A_eq x = b_eq
            A_le x ≤ b_le
            A_ge x ≥ b_ge
            l ≤ x ≤ u
            x ∈ ℤⁿ
```

Into:
```
minimize    z' Q z + L' z + c
subject to  l ≤ z ≤ u
            z ∈ ℤᵐ
```

Where `z = [x; s]` includes original variables `x` and slack variables `s`.

**Example:**

```julia
using MathOptInterface
const MOI = MathOptInterface

# Create a simple model
model = MOI.Utilities.Model{Float64}()
x = MOI.add_variable(model)
MOI.add_constraint(model, x, MOI.Interval(0.0, 10.0))
MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
        MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0))
MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

# Reformulate
target, data = ToQUIO.to_quio(Float64, vi -> vi.value, ci -> ci.value, model)

# Access reformulation data
Q = data[:Q]  # Quadratic terms
L = data[:L]  # Linear terms
c = data[:c]  # Constant
```

### Helper Functions

#### `get_variable_bounds`

```julia
get_variable_bounds(::Type{T}, varmap::Function, source::MOI.ModelLike) where {T}
```

Extracts variable bounds from the source model.

**Returns:**
- `(l, u)`: Tuple of lower and upper bound vectors

**Throws:**
- Error if any variable is unbounded

#### `get_objective_matrices`

```julia
get_objective_matrices(varmap::Function, n::Integer, f::Union{SAF{T}, SQF{T}}) where {T}
```

Extracts objective function as matrix form.

**Arguments:**
- `varmap`: Variable mapping function
- `n`: Number of variables
- `f`: Objective function (affine or quadratic)

**Returns:**
- `(ℓ, Q, β)`: Linear coefficients, quadratic matrix, and constant

#### `get_constraint_matrices`

```julia
# For equality constraints
get_eq_matrices(::Type{T}, varmap::Function, conmap::Function, source) where {T}

# For less-than constraints
get_lt_matrices(::Type{T}, varmap::Function, conmap::Function, source) where {T}

# For greater-than constraints
get_gt_matrices(::Type{T}, varmap::Function, conmap::Function, source) where {T}
```

Extract constraint matrices in standard form `Ax ⊙ b`.

**Returns:**
- `(A, b)`: Constraint matrix and right-hand side vector

## MOI Attributes

### Solver Information

#### `MOI.SolverName`

```julia
MOI.get(optimizer::Optimizer, ::MOI.SolverName)
```

Returns the solver name.

**Returns:**
- If no inner solver: `"ToQUIO Optimizer (reformulation mode)"`
- With inner solver: `"ToQUIO Optimizer (SolverName)"`

#### `MOI.SolverVersion`

```julia
MOI.get(optimizer::Optimizer, ::MOI.SolverVersion)
```

Returns the package version.

#### `MOI.RawSolver`

```julia
MOI.get(optimizer::Optimizer, ::MOI.RawSolver)
```

Returns the inner solver instance (or `nothing`).

### Results

#### `MOI.TerminationStatus`

```julia
MOI.get(optimizer::Optimizer, ::MOI.TerminationStatus)
```

Returns the termination status from the inner solver, or `OPTIMIZE_NOT_CALLED` if no solver is set.

#### `MOI.ObjectiveValue`

```julia
MOI.get(optimizer::Optimizer, ::MOI.ObjectiveValue)
```

Returns the objective value from the inner solver.

#### `MOI.VariablePrimal`

```julia
MOI.get(optimizer::Optimizer, ::MOI.VariablePrimal, vi::VariableIndex)
```

Returns the primal value for a variable.

### Custom Attributes

#### `ConstraintPenaltyHint`

```julia
struct ConstraintPenaltyHint <: MOI.AbstractConstraintAttribute end
```

Allows users to specify custom penalty coefficients for constraints.

**Usage:**

```julia
using JuMP, ToQUIO
using MathOptInterface
const MOI = MathOptInterface

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)
@variable(model, 0 <= x <= 10, Int)
@constraint(model, con, x >= 1)

# Set custom penalty
MOI.set(backend(model), ToQUIO.ConstraintPenaltyHint(), index(con), 100.0)
```

## Internal Functions

These functions are used internally and are not part of the public API, but may be useful for understanding or extending the package.

### Penalty Computation

```julia
get_objective_delta(varmap::Function, f, l::AbstractVector{T}, u::AbstractVector{T}) where {T}
```

Computes the objective value range based on variable bounds.

**Returns:**
- `Δ = δ_max - δ_min`: Objective range

### Constraint Bounds

```julia
get_constraint_bounds(T, A, l, u)
```

Computes bounds on constraint values `Ax` given variable bounds.

**Returns:**
- `(δl, δu)`: Lower and upper bounds on `Ax`

### Sensibility

```julia
get_sensibility(A::AbstractMatrix{T}, b::AbstractVector{T}) where {T}
```

Computes sensibility factors for penalty computation.

**Returns:**
- `ε`: Vector of sensibility factors

**Requirements:**
- Currently requires integer coefficients

## Type Aliases

For convenience and readability, ToQUIO defines several type aliases to shorten commonly-used MathOptInterface types. These aliases make the code more concise while maintaining type safety and enable type-generic programming across different numeric types.

```julia
const MOIU    = MOI.Utilities              # MOI utility functions
const VI      = MOI.VariableIndex          # Variable index type
const CI{F,S} = MOI.ConstraintIndex{F,S}   # Constraint index (function F in set S)
const EQ{T}   = MOI.EqualTo{T}             # Equality constraint set
const LT{T}   = MOI.LessThan{T}            # Less-than constraint set
const GT{T}   = MOI.GreaterThan{T}         # Greater-than constraint set
const SAF{T}  = MOI.ScalarAffineFunction{T}   # Affine (linear) function
const SQF{T}  = MOI.ScalarQuadraticFunction{T} # Quadratic function
const Maybe{T} = Union{T,Nothing}          # Optional type (value or nothing)
```

These aliases are particularly useful when writing type signatures for functions that handle different constraint and function types, reducing verbosity while maintaining full type information for Julia's type system and multiple dispatch.

## QUIOModel

```julia
QUIOModel{T}
```

A MOI model type specifically for QUIO problems, created using `MOI.Utilities.@model`.

**Supported Features:**
- Scalar sets: `EqualTo`, `LessThan`, `GreaterThan`, `Interval`
- Vector sets: `Zeros`, `Nonnegatives`, `Nonpositives`
- Scalar functions: `ScalarAffineFunction`, `ScalarQuadraticFunction`
- Vector functions: `VectorOfVariables`, `VectorAffineFunction`
- Variable constraints: `Integer`, `ZeroOne`

**Usage:**

```julia
model = QUIOModel{Float64}()
x = MOI.add_variable(model)
MOI.add_constraint(model, x, MOI.Interval(0.0, 10.0))
MOI.add_constraint(model, x, MOI.Integer())
# ... set objective, etc.
```

## Supported Constraint Types

The `Optimizer` supports the following constraint types:

**Variable Constraints:**
- `VariableIndex-in-EqualTo{T}`
- `VariableIndex-in-LessThan{T}`
- `VariableIndex-in-GreaterThan{T}`
- `VariableIndex-in-Interval{T}`
- `VariableIndex-in-Integer`
- `VariableIndex-in-ZeroOne`

**Affine Constraints:**
- `ScalarAffineFunction{T}-in-EqualTo{T}`
- `ScalarAffineFunction{T}-in-LessThan{T}`
- `ScalarAffineFunction{T}-in-GreaterThan{T}`

## Supported Objective Types

- `ScalarAffineFunction{T}` (linear objectives)
- `ScalarQuadraticFunction{T}` (quadratic objectives)

Both minimization and maximization are supported.
