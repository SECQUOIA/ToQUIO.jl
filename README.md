# ToQUIO.jl

[![License](https://img.shields.io/badge/License-MPL%202.0-blue.svg)](https://opensource.org/licenses/MPL-2.0)

**ToQUIO.jl** - Transform optimization problems **To** **Q**uadratic **U**nconstrained **I**nteger **O**ptimization

A Julia package that reformulates constrained integer optimization problems into Quadratic Unconstrained Integer Optimization (QUIO) format using penalty methods. ToQUIO integrates seamlessly with JuMP and MathOptInterface (MOI), enabling you to leverage QUIO-specialized solvers for problems originally formulated with constraints.

## Features

- **Automatic Reformulation**: Converts constrained integer programs to QUIO format
- **Penalty-Based Approach**: Uses quadratic penalty functions to handle constraints
- **JuMP Integration**: Works as a drop-in optimizer for JuMP models
- **Flexible Solver Backend**: Can use any MOI-compatible QUIO solver as backend
- **Type-Generic**: Supports arbitrary numeric types (Float64, BigFloat, etc.)

## Installation

ToQUIO.jl is a Julia package. To install it, open a Julia REPL and run:

```julia
using Pkg
Pkg.add(url="https://github.com/SECQUOIA/ToQUIO.jl")
```

Or from the Julia package manager (press `]`):

```julia
pkg> add https://github.com/SECQUOIA/ToQUIO.jl
```

## Quick Start

### Basic Example

```julia
using JuMP
using ToQUIO

# Create a JuMP model with ToQUIO as the optimizer
model = Model(() -> ToQUIO.Optimizer())

# Define integer variables with bounds
@variable(model, -3 <= x[1:3] <= 3, Int)

# Set a quadratic objective
@objective(model, Min, sum(i * j * (-1)^(i + j) * x[i] * x[j] for i = 1:3 for j = 1:3))

# Optimize the model
optimize!(model)

# Access results
println("Objective value: ", objective_value(model))
println("Solution: ", value.(x))
```

### Using with a QUIO Solver Backend

ToQUIO can reformulate your problem and pass it to a specialized QUIO solver:

```julia
using JuMP
using ToQUIO
# using YourQUIOSolver  # Replace with your preferred QUIO solver

# Define constraints
A = [0 2 4; 5 3 5]
b = [1, 5]

# Create model with ToQUIO wrapping a backend solver
model = Model(() -> ToQUIO.Optimizer(() -> YourQUIOSolver.Optimizer()))

@variable(model, -5 <= x[1:3] <= 10, Int)
@objective(model, Min, sum(x))

# Add equality and inequality constraints
@constraint(model, A * x .== b)

optimize!(model)
```

## How It Works

ToQUIO reformulates constrained integer optimization problems into the QUIO format:

**Original Problem:**
```
minimize   f(x)
subject to A_eq * x = b_eq    (equality constraints)
           A_le * x ≤ b_le    (inequality constraints)
           l ≤ x ≤ u          (variable bounds)
           x ∈ ℤⁿ             (integer variables)
```

**QUIO Reformulation:**
```
minimize   x' Q x + c' x + γ
subject to l ≤ x ≤ u
           x ∈ ℤⁿ
```

The reformulation uses quadratic penalty functions to incorporate constraints into the objective:
- Equality constraints: penalized as `ρ * (Ax - b)²`
- Inequality constraints: penalized using slack variables
- Penalty coefficients (ρ) are automatically computed or can be user-specified

## API Documentation

### Optimizer

```julia
ToQUIO.Optimizer{T}(backend_optimizer = nothing)
```

Creates a ToQUIO optimizer that reformulates problems into QUIO format.

**Parameters:**
- `T`: Numeric type for the optimization (default: `Float64`)
- `backend_optimizer`: Optional callable that returns a MOI-compatible optimizer for solving the reformulated QUIO problem

**Example:**
```julia
# Reformulation only (no solving)
optimizer = ToQUIO.Optimizer()

# With a backend solver
optimizer = ToQUIO.Optimizer(() -> SomeQUIOSolver.Optimizer())
```

### Reformulation Function

```julia
to_quio(T, varmap, conmap, source; ϵ = 1.0)
```

Core reformulation function that transforms a MOI model into QUIO format.

**Parameters:**
- `T`: Numeric type
- `varmap`: Variable index mapping function
- `conmap`: Constraint index mapping function
- `source`: Source MOI model
- `ϵ`: Penalty coefficient adjustment (default: 1.0)

**Returns:**
- `target`: QUIOModel containing the reformulated problem
- `data`: Dictionary with reformulation metadata (Q matrix, linear terms, etc.)

## Supported Problem Types

### Constraints
- ✅ Variable bounds (lower, upper, intervals)
- ✅ Equality constraints (`=`)
- ✅ Inequality constraints (`≤`, `≥`)
- ✅ Integer and binary variables

### Objectives
- ✅ Linear objectives
- ✅ Quadratic objectives
- ✅ Minimization and maximization

### Not Yet Supported
- ❌ Nonlinear constraints
- ❌ SOS constraints
- ❌ Indicator constraints

## Examples

### Integer Programming with Constraints

```julia
using JuMP, ToQUIO

model = Model(() -> ToQUIO.Optimizer())

@variable(model, 0 <= x <= 5, Int)
@variable(model, 0 <= y <= 5, Int)

@objective(model, Min, x^2 + y^2 - 2x - 4y)

@constraint(model, x + y >= 3)
@constraint(model, 2x + y <= 8)

optimize!(model)

println("x = ", value(x))
println("y = ", value(y))
```

### Examining the Reformulated Model

```julia
using JuMP, ToQUIO, MathOptInterface
const MOI = MathOptInterface

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

@variable(model, -2 <= x[1:2] <= 2, Int)
@objective(model, Min, x[1]^2 + x[2]^2)
@constraint(model, x[1] + x[2] == 1)

optimize!(model)

# Access reformulation data
backend = backend(model)
data = backend.optimizer.model.data

println("Q matrix: ", data[:Q])
println("Linear terms: ", data[:L])
println("Constant: ", data[:c])
```

## Development

### Setting Up the Development Environment

1. Clone the repository:
   ```bash
   git clone https://github.com/SECQUOIA/ToQUIO.jl.git
   cd ToQUIO.jl
   ```

2. Start Julia and activate the project:
   ```julia
   using Pkg
   Pkg.activate(".")
   Pkg.instantiate()
   ```

3. Run tests:
   ```julia
   Pkg.test()
   ```

### Project Structure

```
ToQUIO.jl/
├── src/
│   ├── ToQUIO.jl              # Main module
│   ├── to_quio.jl             # Core reformulation logic
│   └── MOI_wrapper/           # MathOptInterface integration
│       ├── MOI_wrapper.jl     # Optimizer implementation
│       ├── QUIO_model.jl      # QUIO model definition
│       └── attributes/        # MOI attributes
├── test/
│   └── runtests.jl            # Test suite
├── Project.toml               # Package metadata
└── README.md                  # This file
```

### Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### For AI/Copilot Development

When working with AI assistants or GitHub Copilot on this project:

1. **Understand the reformulation**: The core algorithm converts constraints into quadratic penalties
2. **Key files**: 
   - `src/to_quio.jl`: Contains the main reformulation logic
   - `src/MOI_wrapper/MOI_wrapper.jl`: MOI optimizer interface
3. **Type system**: The code is type-generic; maintain this property in changes
4. **Testing**: Always run tests after modifications
5. **MOI compliance**: Ensure changes maintain MathOptInterface compliance

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed development instructions.

## References

- [JuMP Documentation](https://jump.dev/JuMP.jl/stable/)
- [MathOptInterface Documentation](https://jump.dev/MathOptInterface.jl/stable/)
- Penalty Methods in Optimization Theory

## License

This project is licensed under the Mozilla Public License Version 2.0 - see the [LICENSE](LICENSE) file for details.

## Authors

- Pedro Maciel Xavier
- Albert Lee

## Citation

If you use ToQUIO.jl in your research, please cite:

```bibtex
@software{toquio_jl,
  title = {ToQUIO.jl: Quadratic Unconstrained Integer Optimization Reformulation},
  author = {Xavier, Pedro Maciel and Lee, Albert},
  year = {2024},
  url = {https://github.com/SECQUOIA/ToQUIO.jl}
}
```

