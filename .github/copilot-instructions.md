# ToQUIO.jl - Copilot Instructions

## Project Overview

ToQUIO.jl is a Julia package that provides a JuMP interface to Quadratic Unconstrained Integer Optimization (QUIO). The package reformulates constrained integer optimization problems into quadratic unconstrained integer optimization problems using penalty methods.

## Architecture

### Core Components

1. **MOI Wrapper** (`src/MOI_wrapper/`):
   - `Optimizer{T,O}`: Main optimizer struct that wraps an inner optimizer
   - `QUIOModel`: Model definition using MOI utilities
   - Custom attributes for reformulation control and penalty hints

2. **Reformulation Logic** (`src/to_quio.jl`):
   - `to_quio()`: Main function that transforms constrained problems to QUIO
   - Variable bounds handling
   - Constraint matrix construction (equality, less-than, greater-than)
   - Penalty calculation and slack variable introduction
   - Quadratic objective construction with penalty terms

3. **Attributes** (`src/MOI_wrapper/attributes/`):
   - `model.jl`: Optimizer model attributes (SolverName, SolverVersion, etc.)
   - `reformulation.jl`: Custom attributes for reformulation control
   - `results.jl`: Result attributes (TerminationStatus, ObjectiveValue, etc.)

## Key Dependencies

- **MathOptInterface (MOI)**: Mathematical optimization interface
- **JuMP**: High-level modeling language for optimization
- **LinearAlgebra**: Matrix operations for reformulation

## Mathematical Reformulation

The package transforms problems from:
```
minimize f(x)
subject to:
  A_eq * x = b_eq
  A_lt * x ≤ b_lt
  A_gt * x ≥ b_gt
  l ≤ x ≤ u
  x integer
```

To quadratic unconstrained form using penalty methods and slack variables.

## Code Conventions

### Julia Style

- Use explicit type parameters where needed (e.g., `{T}`, `{F,S}`)
- Follow Julia naming conventions: `snake_case` for functions, `PascalCase` for types
- Use type aliases for clarity (e.g., `const VI = MOI.VariableIndex`)
- Document public functions with docstrings using `@doc raw"""..."""`

### MOI Integration

- Implement required MOI methods: `get`, `set`, `supports`, `optimize!`, `is_empty`, `empty!`
- Support scalar affine and quadratic functions: `SAF{T}`, `SQF{T}`
- Support constraint sets: `EqualTo`, `LessThan`, `GreaterThan`, `Interval`
- Support integer variables: `MOI.Integer`

### Type Handling

- Generic programming with type parameter `T` (typically `Float64`)
- Use `Maybe{T} = Union{T,Nothing}` for optional values
- Matrix types use `AbstractVector` and `AbstractMatrix` for flexibility

## Testing

- Test infrastructure in `test/runtests.jl`
- Uses JuMP for modeling and Bonmin as a reference solver
- Tests verify reformulation correctness by comparing results
- Random test case generation with seed control

## Common Patterns

### Variable Mapping
```julia
varmap = vi -> vi.value  # VI to Int
conmap = ci -> ci.value  # CI{F,S} to Int
```

### MOI Utilities
```julia
const MOIU = MOI.Utilities
const VI = MOI.VariableIndex
const CI{F,S} = MOI.ConstraintIndex{F,S}
```

### Penalty Calculation
```julia
# Priority: user-defined > auto-calculated
ρ = something.(θ, (Δ ./ ε) .+ ϵ)
```

## Development Guidelines

1. **Minimal Changes**: Prefer targeted fixes over broad refactoring
2. **Type Safety**: Maintain type stability for performance
3. **MOI Compliance**: Follow MOI interface specifications
4. **Documentation**: Update docstrings for API changes
5. **Testing**: Verify reformulation preserves optimization semantics

## File Organization

```
src/
├── ToQUIO.jl              # Main module file
├── to_quio.jl             # Core reformulation logic
└── MOI_wrapper/
    ├── QUIO_model.jl      # Model definition
    ├── MOI_wrapper.jl     # Optimizer implementation
    └── attributes/
        ├── model.jl       # Model attributes
        ├── reformulation.jl  # Custom reformulation attributes
        └── results.jl     # Result attributes
```

## Important Notes

- All variables must have finite bounds for reformulation
- Penalty values must be large enough to enforce constraints
- Slack variables are introduced for inequality constraints
- The reformulated objective includes penalty terms for constraint violations
