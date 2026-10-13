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
  - `:D`: Diagonal penalty matrix used in the target objective, including the
    objective-sense sign
  - `:rho`: Selected positive penalty coefficients before applying the
    objective-sense sign
  - `:rho_auto`: Automatic sufficient positive penalty coefficients
  - `:penalty_hints`: User-provided penalty hints, or `nothing` for automatic
    penalties
  - `:penalty_constraints`: Source constraint indices corresponding to
    `:rho`, `:rho_auto`, and `:penalty_hints`, ordered as equalities,
    less-than inequalities, then greater-than inequalities
  - `:l`: Lower bounds vector
  - `:u`: Upper bounds vector

MathOptInterface 1.11 or later is required for source distance evaluation.

**Input validation:**
- Direct source models must implement `MOI.ListOfConstraintTypesPresent`.
  Unsupported types, including scalar affine functions in `MOI.Interval`, are
  rejected with `ArgumentError` rather than silently omitted.
- Every source variable must have finite lower and upper bounds and be marked
  `MOI.Integer` or `MOI.ZeroOne`.
- Affine constraint coefficients and right-hand sides must be integer-valued.
- Equality and inequality rows must be feasible within the variable bounds.
- Equality rows must also pass the integer divisibility check for integer
  assignments.
- Custom `ConstraintPenaltyHint` values must be finite and positive.

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
MOI.add_constraint(model, x, MOI.Integer())
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

Returns the original source-model objective evaluated at the mapped source
variable primal values returned by the inner solver.

#### `PenalizedObjectiveValue`

```julia
MOI.get(optimizer::Optimizer, ToQUIO.PenalizedObjectiveValue())
```

Returns the objective value reported by the inner solver for the reformulated
QUIO target model. This includes penalty and slack-variable terms.

#### `MOI.VariablePrimal`

```julia
MOI.get(optimizer::Optimizer, ::MOI.VariablePrimal, vi::VariableIndex)
```

Returns the primal value for an original source-model variable by mapping it to
the corresponding target-model variable before querying the inner solver. Slack
variables introduced by reformulation are not exposed as source variables.

### Custom Attributes

#### `ConstraintPenaltyHint`

```julia
struct ConstraintPenaltyHint <: MOI.AbstractConstraintAttribute end
```

Allows users to specify custom penalty coefficients for constraints. Hints must
be finite and positive. They override the automatic sufficient coefficient, so
small hints are treated as heuristic values and may not preserve equivalence to
the constrained source problem. ToQUIO emits a warning when a hint is below the
automatic sufficient coefficient.

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

### Automatic Penalty Controls

See [Penalty tuning](penalties.md) for executable inspection/sweep examples,
hint precedence and warning semantics.

```@docs
ToQUIO.PenaltyOffset
ToQUIO.PenaltyScale
ToQUIO.AppliedPenalty
```

For an unhinted constraint, ToQUIO applies
`scale * (Δ_bound / ε^2 + offset)`. Defaults are `offset = 1` and `scale = 1`,
reproducing the existing objective exactly. A `ConstraintPenaltyHint` remains an
exact per-constraint magnitude and bypasses both controls. ToQUIO uses the same
control names as ToQUBO but keeps its own squared-residual penalty formula.

```julia
optimizer = ToQUIO.Optimizer(; penalty_offset = 1.0, penalty_scale = 1.0)
MOI.set(optimizer, ToQUIO.PenaltyScale(), 2.0)
MOI.optimize!(optimizer, source)
MOI.get(optimizer, ToQUIO.AppliedPenalty(), constraint_index)
```

`source` and `constraint_index` refer to the supported MOI source model and an
affine constraint index. Setting a control changes the **next** reformulation;
applied-penalty queries and snapshots retain the values from the last one.
For a JuMP model without a backend solver, query the compiled value through
`MOI.get(backend(model), ToQUIO.AppliedPenalty(), index(con))` after `optimize!`.
JuMP's high-level `get_attribute(con, ...)` result path requires a solver status
other than `OPTIMIZE_NOT_CALLED`, which reformulation-only mode does not provide.
A failed new reformulation invalidates the current applied-penalty query.
Use `nothing` with either control attribute to reset its default. Global controls
persist across `MOI.empty!`; computed penalties do not. Offset and scale must be
finite positive real values representable in the optimizer's numeric type.
Invalid controls and overflowing target coefficients are rejected.

Direct calls keep the existing additive `ϵ` keyword and add `penalty_scale`:

```julia
target, data = ToQUIO.to_quio(
    Float64, varmap, conmap, source; ϵ = 1.0, penalty_scale = 2.0,
)
```

`:rho_auto` records the **unscaled** automatic value with the chosen offset;
`:rho` records the actual scaled or hinted magnitude. Maximization subtracts
the applied magnitude in the objective, while `AppliedPenalty()` returns its
positive value. Scales below 1 can weaken feasibility protection and warn when
the applied value falls below the unscaled sufficient coefficient. Existing
low-hint warnings retain their meaning; a hint is compared to that unscaled
reference even when a global scale is set.
Global-scale warnings are aggregated once per equality/inequality kind with the
affected row count, while warnings for individual low hints remain per constraint.

## Reformulation Metadata and Projection

These helpers accept the dictionary returned by `to_quio` or an `Optimizer`
after reformulation. Variable-list helpers return copies. The metadata snapshot
can also be saved with a JSON serializer and used for projection without keeping
the MOI model alive.

```@docs
ToQUIO.reformulation_metadata
ToQUIO.original_variables
ToQUIO.auxiliary_variables
ToQUIO.project_original_state
```

For example, this reformulation introduces one integer slack for `x <= 2`:

```julia
using ToQUIO
import MathOptInterface as MOI

source = MOI.Utilities.Model{Float64}()
x = MOI.add_variable(source)
MOI.add_constraint(source, x, MOI.Interval(0.0, 3.0))
MOI.add_constraint(source, x, MOI.Integer())
f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0)
MOI.set(source, MOI.ObjectiveSense(), MOI.MIN_SENSE)
MOI.set(source, MOI.ObjectiveFunction{typeof(f)}(), f)
MOI.add_constraint(source, f, MOI.LessThan(2.0))

optimizer = ToQUIO.Optimizer()
MOI.optimize!(optimizer, source) # Reformulation only; no backend is required.
metadata = reformulation_metadata(optimizer)
original_variables(optimizer)  # MOI.VariableIndex[MOI.VariableIndex(1)]
auxiliary_variables(metadata)  # [2]
project_original_state(optimizer, [1, 1]) # Dict(x => 1)
project_original_state(metadata, [1, 1])  # Dict(1 => 1), using source IDs
```

Native schema version 1 is a string-keyed dictionary with the following fields:

| Field | Meaning |
|:--|:--|
| `schema_version`, `package` | Schema version and producing package name/version |
| `source_variable_order` | Original source IDs in source-model order |
| `target_variable_order` | Full target IDs in state-vector order, including slacks |
| `target_lower_bounds`, `target_upper_bounds` | Bounds aligned with the full target order |
| `original_variables` | Source IDs and affine projection expansions |
| `auxiliary_variables`, `slack_variables` | Slack IDs, target positions and typed source-constraint identities |
| `constraint_encodings` | Penalized affine constraints in equality, `<=`, then `>=` order, with source/canonical relations, row multipliers, slack positions and automatic/applied/hinted penalties |
| `penalty_controls` | Offset and scale used at compilation; optional in older v1 snapshots |
| `guarantees` | Explicit projection, feasibility-check and repair boundaries |

Constraint identities use fully qualified, context-independent function and set
type strings (for example `MathOptInterface.LessThan{Core.Float64}`): a numeric MOI
constraint ID alone is not unique across constraint types. A `>=` row is negated
to `<=` before introducing its slack; metadata records its row multiplier `-1`.
Bounds and integer-domain constraints are represented by target bounds and the
native QUIO domain, rather than included in the penalized-constraint list.

Each source expansion has `kind = "affine"`, an `offset`, and `terms` containing
a `target_position` and `coefficient`. Positions are **one-based state-vector
positions**, independent of MOI variable IDs. Native reformulation uses one term
with coefficient 1 and offset 0; the format permits later multi-digit affine
projections without changing the legacy one-to-one raw mapping. Optional integer
encodings use schema version2 with composed source maps, encoded target order and
a nested complete native snapshot; see [Integer Encoding](encoding.md).

Metadata contains finite integer or floating-point numbers, strings, booleans,
`nothing`, vectors and string-keyed dictionaries. Numeric precision is retained;
the chosen JSON serializer/reader must support the number type when using
arbitrary precision. Matrices `Q`, `L`, `D` and `c` stay in the internal data
dictionary and are excluded from the stable snapshot.

Projection accepts a full target vector, including all slacks, and rejects a
wrong length or nonfinite/non-real values. It preserves fractional samples and
does not certify source feasibility, check target-domain/slack consistency, or
repair auxiliaries. For example, projecting `[1.5, -10]` yields `x = 1.5` even
though that sample violates the target's integer and slack domains. Unknown
schema versions and malformed document fields are rejected with `ArgumentError`.
IDs, positions and numeric expansion fields reject booleans. A failed new
reformulation invalidates the optimizer's current metadata; a previously retained
raw dictionary or metadata snapshot remains usable across that failed call.
`MOI.empty!(optimizer)` clears the live raw dictionary and models; save a returned
metadata snapshot when a record must survive this reset. Existing raw keys such as `:target_variables`
(original-variable targets only), `:rho` and `:Q` keep their previous meaning;
`:quio_variables` adds the full target order and `:slack_constraints` adds ownership.
`:source_constraints` stores copied `(index, func, set)` named tuples for source
feasibility evaluation. These MOI functions/sets stay in raw data and are not
part of the portable projection snapshot. With optional encoding, those raw keys
continue to describe native coordinates; `:encoded_variables` and
`:encoded_Q, :encoded_L, :encoded_c` describe the actual backend target.
`auxiliary_variables` returns actual slack-owned target digits, while
`project_native_state` restores the native coordinates.

## Original Source Feasibility

Aggregate optimizer reports retain every result record, with `result_index`,
`primal_status` and `evaluated`. Only feasible, nearly feasible, and infeasible
primal points are evaluated; absent solutions, certificates and unknown statuses
are skipped. `feasible_fraction` divides by `primal_point_count`, not
`result_count`, and is `nothing` if there are no points. Requesting a nonpoint
result explicitly raises `ArgumentError`. Direct state calls have no backend
status and evaluate the supplied values.

```@docs
ToQUIO.ConstraintViolation
ToQUIO.violations
ToQUIO.is_feasible
ToQUIO.feasibility_report
```

For the reformulation-only example above, the full target order is `[x, slack]`:

```julia
is_feasible(optimizer, [1, 1])     # true: x <= 2, and x is integer/in bounds
violations(optimizer, [3, 0])      # source LessThan violation of magnitude 1
report = feasibility_report(optimizer, [1, 9])
report["feasible"]                # true for the source point x = 1
report["constraints"]             # target residual exposes inconsistent slack
```

For a solver-backed optimizer, `violations(optimizer; result=2)` reads that
result's complete target state through the recorded backend index map. The
default `feasibility_report(optimizer)` summarizes all result records; these
counts do not include sampler read multiplicities. A report with no results has
`feasible_fraction = nothing`. A requested missing result raises
`MOI.ResultIndexBoundsError`.

The analysis evaluates a captured copy of the source constraints from the most
recent successful reformulation. It supports source scalar affine `=`, `<=`,
`>=`, and variable bounds, intervals, integrality and binary domains. Later edits
to the caller's model do not change that snapshot; reformulate to analyze them.
Direct `to_quio` dictionaries contain the same snapshot. Older dictionaries and
serialized projection metadata without source functions cannot perform this check.

`atol` is a finite nonnegative absolute tolerance in each constraint's native
units. Violation magnitudes and signed residuals remain unmodified in the report,
including small residuals accepted by the tolerance. Max/sum diagnostics do not
normalize different constraint units. Integrality checks use the actual sample
values without rounding. The source-feasibility verdict is independent of target
slack consistency and penalized objective energy; neither feasible samples nor a
target-optimal status certify optimality for the source problem.

## Internal Functions

These functions are used internally and are not part of the public API, but may be useful for understanding or extending the package.

### Penalty Computation

```julia
get_objective_delta(varmap::Function, f, l::AbstractVector{T}, u::AbstractVector{T}) where {T}
```

Computes the objective value range based on variable bounds. This is exact for
affine objectives. For quadratic objectives, it is a conservative termwise
interval bound and may overestimate the exact range.

**Returns:**
- `Δ = δ_max - δ_min`: Objective range or range bound

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
- Currently requires integer-valued constraint coefficients and right-hand
  sides, which makes `ε = 1`

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
