# Quick Start Guide for Developers

This guide provides a quick overview for developers who want to work with ToQUIO.jl.

## What is ToQUIO.jl?

ToQUIO.jl reformulates **constrained integer optimization problems** into **Quadratic Unconstrained Integer Optimization (QUIO)** format using penalty methods.

## 5-Minute Setup

```bash
# Clone the repository
git clone https://github.com/SECQUOIA/ToQUIO.jl.git
cd ToQUIO.jl

# Start Julia and set up
julia
```

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
Pkg.test()  # Run tests
```

## Core Concepts in 3 Points

1. **Input**: Constrained integer program (equality/inequality constraints)
2. **Process**: Converts constraints to quadratic penalties in the objective
3. **Output**: Unconstrained problem with only bounds (QUIO format)

## Key Files

- `src/to_quio.jl` - Core reformulation logic (400+ lines)
- `src/MOI_wrapper/MOI_wrapper.jl` - Optimizer interface (~60 lines)
- `src/MOI_wrapper/QUIO_model.jl` - QUIO model definition (~10 lines)
- `src/ToQUIO.jl` - Main module (~30 lines)

## Quick Example

```julia
using JuMP, ToQUIO

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)
@variable(model, 0 <= x <= 10, Int)
@variable(model, 0 <= y <= 10, Int)
@objective(model, Min, x^2 + y^2)
@constraint(model, x + y == 5)  # This becomes a penalty term

optimize!(model)

data = optimizer.data
println("Reformulated variables: ", data[:n])
```

## Development Patterns

### Code Patterns to Follow

1. **Always use type parameters**: `{T}` instead of hard-coded `Float64`
2. **Follow existing function signatures**: Look at similar functions
3. **Use type aliases**: `SAF{T}` not `MOI.ScalarAffineFunction{T}`
4. **Add docstrings**: Use `@doc raw"""..."""` format

### Common Tasks

#### Adding a new constraint type

1. Add support in `MOI_wrapper.jl` via `MOI.supports_constraint`
2. Implement extraction in `to_quio.jl` (e.g., `get_new_constraint_type_matrices`)
3. Integrate into the reformulation in `to_quio()`
4. Add tests

#### Modifying penalty computation

See `to_quio.jl`:
- `get_objective_delta()`: Computes objective range
- `get_sensibility()`: Constraint violation granularity  
- Lines ~210-214: Actual penalty computation `ρ = Δ/ε + ϵ`

#### Debugging reformulation

```julia
# Access reformulation data after optimize!(model)
data = optimizer.data
Q = data[:Q]  # Quadratic matrix
L = data[:L]  # Linear terms
c = data[:c]  # Constant
```

## Documentation Structure

```
ToQUIO.jl/
├── README.md              ← Start here: Overview, installation, basic usage
├── CONTRIBUTING.md        ← Development guide
└── docs/
    ├── README.md          ← Documentation index
    ├── api.md             ← Complete API reference
    ├── algorithm.md       ← Mathematical details
    └── examples.md        ← Extensive examples
```

## Testing Strategy

Tests are in `test/runtests.jl`. Currently uses Bonmin as a backend solver to verify reformulation correctness.

```julia
# Run tests
Pkg.test()

# Or manually
include("test/runtests.jl")
test_example()  # Basic test function
```

## Common Gotchas

1. **All variables must be bounded**: ToQUIO requires `l ≤ x ≤ u` for all variables
2. **Integer coefficients required**: Current implementation requires integer constraint coefficients for penalty computation
3. **Type consistency**: Maintain type parameter `T` throughout the codebase
4. **MOI conventions**: Follow MathOptInterface naming (e.g., `get` not `retrieve`)

## Key Algorithms

### Reformulation Formula

Original problem:
```
min  f(x)
s.t. Ax = b    (equality)
     Cx ≤ d    (inequality)
     l ≤ x ≤ u
     x ∈ ℤⁿ
```

Becomes:
```
min  z'Qz + g'z + γ
s.t. l̃ ≤ z ≤ ũ
     z ∈ ℤᵐ
```

Where `z = [x; s]` includes slack variables for inequalities.

### Penalty Coefficients

```julia
ρ = Δ/ε + ϵ
```

- `Δ`: Objective function range over feasible region
- `ε`: Minimum constraint violation (sensibility)
- `ϵ`: User adjustment (default: 1.0)

## Type System

```julia
# Key type parameters
T                           # Numeric type (Float64, BigFloat, etc.)
O<:Maybe{MOI.AbstractOptimizer}  # Optional inner optimizer

# Main types
Optimizer{T,O}              # Main optimizer wrapper
QUIOModel{T}                # QUIO model type

# Type aliases (see docs/api.md for full list)
SAF{T}  # ScalarAffineFunction
SQF{T}  # ScalarQuadraticFunction
VI      # VariableIndex
```

## Contributing Workflow

1. Fork and clone
2. Create feature branch: `git checkout -b feature/your-feature`
3. Make changes with tests
4. Run tests: `Pkg.test()`
5. Commit and push
6. Create pull request

## Getting Help

- **Issues**: Report bugs or request features
- **Documentation**: Check README.md and docs/
- **Code**: Read inline comments and docstrings
- **Examples**: See docs/examples.md for ~15 different use cases

## Quick Reference Card

| Task | Command/Location |
|------|------------------|
| Install | `Pkg.add(url="https://github.com/SECQUOIA/ToQUIO.jl")` |
| Activate dev env | `Pkg.activate(".")` |
| Run tests | `Pkg.test()` |
| Core logic | `src/to_quio.jl` |
| Optimizer | `src/MOI_wrapper/MOI_wrapper.jl` |
| Examples | `docs/examples.md` |
| API docs | `docs/api.md` |
| Math details | `docs/algorithm.md` |

## License

Mozilla Public License 2.0 - See LICENSE file

---

**Last Updated**: 2024-12-04  
**Version**: 0.1.0
