# Contributing to ToQUIO.jl

Thank you for your interest in contributing to ToQUIO.jl! This document provides guidelines and instructions for contributors, including those using AI assistants like GitHub Copilot.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Code Style](#code-style)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [AI-Assisted Development](#ai-assisted-development)
- [Architecture Overview](#architecture-overview)

## Getting Started

### Prerequisites

- Julia 1.11 or higher
- Git
- A GitHub account

### First Time Setup

1. **Fork the repository** on GitHub

2. **Clone your fork**:
   ```bash
   git clone https://github.com/YOUR-USERNAME/ToQUIO.jl.git
   cd ToQUIO.jl
   ```

3. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/SECQUOIA/ToQUIO.jl.git
   ```

4. **Set up the Julia environment**:
   ```julia
   using Pkg
   Pkg.activate(".")
   Pkg.instantiate()
   ```

## Development Setup

### Activating the Development Environment

Always activate the project environment before working:

```julia
using Pkg
Pkg.activate(".")
```

### Running Tests

Run the full test suite:

```julia
Pkg.test()
```

Or from the command line:

```bash
julia --project=. test/runtests.jl
```

### Interactive Development

For interactive development and testing:

```julia
using Pkg
Pkg.activate(".")

using ToQUIO
using JuMP

# Your development code here
```

## Code Style

### Julia Style Guidelines

We follow the [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/) with these specifics:

1. **Indentation**: Use 4 spaces (not tabs)

2. **Line length**: Prefer lines under 92 characters, hard limit at 120

3. **Naming conventions**:
   - Types: `UpperCamelCase`
   - Functions: `lowercase_with_underscores` or `lowercamelcase`
   - Constants: `UPPER_CASE_WITH_UNDERSCORES`
   - Type parameters: Single uppercase letters (`T`, `S`, `F`)

4. **Comments**: Use `#` for single-line comments, document functions with docstrings

### Type Annotations

Maintain type-generic code where possible:

```julia
# Good: Type-generic
function my_function(x::AbstractVector{T}) where {T}
    # ...
end

# Avoid: Hard-coded types unless necessary
function my_function(x::Vector{Float64})
    # ...
end
```

### Documentation

Document all public functions using Julia's docstring format:

```julia
@doc raw"""
    function_name(arg1::Type1, arg2::Type2) -> ReturnType

Brief description of what the function does.

# Arguments
- `arg1::Type1`: Description of first argument
- `arg2::Type2`: Description of second argument

# Returns
- `ReturnType`: Description of return value

# Examples
```julia
result = function_name(value1, value2)
```
"""
function function_name(arg1::Type1, arg2::Type2)
    # Implementation
end
```

## Testing

### Test Organization

Tests are located in `test/runtests.jl`. When adding new features:

1. Add corresponding tests
2. Test both successful cases and error conditions
3. Test with different numeric types (Float64, BigFloat, etc.)

### Example Test

```julia
@testset "New Feature" begin
    model = Model(() -> ToQUIO.Optimizer())
    @variable(model, x)
    # ... test setup ...
    
    optimize!(model)
    
    @test termination_status(model) == MOI.OPTIMAL
    @test isapprox(value(x), expected_value, atol=1e-6)
end
```

### Coverage

Aim for high test coverage, especially for:
- Core reformulation logic
- Edge cases (empty models, unbounded variables, etc.)
- Error handling

## Pull Request Process

### Before Submitting

1. **Update from upstream**:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run tests**: Ensure all tests pass

3. **Update documentation**: Update README.md or add docstrings as needed

4. **Commit messages**: Use clear, descriptive commit messages
   ```
   Add feature X to support Y
   
   - Implement core logic in to_quio.jl
   - Add tests for edge cases
   - Update documentation
   ```

### Submitting the PR

1. Push to your fork:
   ```bash
   git push origin your-branch-name
   ```

2. Create a pull request on GitHub

3. Fill out the PR template with:
   - Description of changes
   - Motivation for the changes
   - Any breaking changes
   - Testing performed

### Review Process

- Maintainers will review your PR
- Address any feedback or requested changes
- Once approved, your PR will be merged

## AI-Assisted Development

### Using GitHub Copilot or Other AI Assistants

ToQUIO.jl is designed to be AI-friendly. When using AI assistants:

#### Understanding the Codebase

1. **Core reformulation** (`src/to_quio.jl`):
   - Converts constrained problems to QUIO format
   - Key function: `to_quio(T, varmap, conmap, source; ϵ)`
   - Uses penalty methods for constraint handling

2. **MOI Wrapper** (`src/MOI_wrapper/`):
   - `MOI_wrapper.jl`: Main optimizer interface
   - `QUIO_model.jl`: Model type definition using MOI utilities
   - `attributes/`: MOI attribute implementations

3. **Type System**:
   - Heavy use of parametric types (`{T}` everywhere)
   - Type aliases for clarity (e.g., `SAF{T}`, `VI`)
   - Generic programming patterns

#### Best Practices for AI Development

1. **Preserve type genericity**: Don't hard-code `Float64` unless necessary

2. **Follow existing patterns**: Look at similar functions for style guidance

3. **Test incrementally**: Create small tests as you develop

4. **Use type assertions wisely**: The codebase uses `@assert` for internal checks

5. **Understand MOI**: Familiarity with MathOptInterface is crucial

#### AI Prompt Templates

When asking AI for help, provide context:

```
I'm working on ToQUIO.jl, a Julia package that reformulates constrained 
integer programs into QUIO format using penalty methods. It integrates 
with MathOptInterface (MOI).

Current task: [describe your task]

Relevant code: [paste relevant code]

Requirements:
- Maintain type-generic code (use {T} parameters)
- Follow existing function patterns
- Add appropriate docstrings
- Include tests
```

#### Common Pitfalls to Avoid

1. **Breaking type genericity**: Avoid assuming `Float64`
2. **Ignoring MOI conventions**: Follow MOI naming and patterns
3. **Incomplete error handling**: Add checks for invalid inputs
4. **Missing documentation**: Always add docstrings to public functions
5. **Untested code**: Add tests for new functionality

## Architecture Overview

### Key Components

```
┌─────────────────┐
│   JuMP Model    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ ToQUIO.Optimizer│  (MOI_wrapper.jl)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   to_quio()     │  (to_quio.jl)
│  Reformulation  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  QUIOModel      │  (QUIO_model.jl)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Backend Solver  │  (Optional)
└─────────────────┘
```

### Reformulation Process

1. **Extract problem data**: Read objective, constraints, bounds from source model
2. **Compute penalties**: Calculate penalty coefficients for constraints
3. **Build QUIO matrices**: Construct Q matrix, linear terms
4. **Add slack variables**: For inequality constraints
5. **Create target model**: Build QUIOModel with reformulated problem

### Key Data Structures

- `Optimizer{T,O}`: Main optimizer wrapper
  - `inner::O`: Optional backend solver
  - `source_model`: Original problem
  - `target_model`: Reformulated QUIO problem
  - `data::Dict`: Reformulation metadata

- `QUIOModel`: MOI model supporting QUIO format
  - Only bounds and integer constraints
  - Quadratic objective function

## Development Workflow

### Feature Development

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Implement your feature with tests

3. Run tests frequently:
   ```julia
   using Pkg
   Pkg.test()
   ```

4. Commit with clear messages

5. Push and create a PR

### Bug Fixes

1. Create a branch:
   ```bash
   git checkout -b fix/bug-description
   ```

2. Add a test that reproduces the bug

3. Fix the bug

4. Verify the test passes

5. Submit a PR

## Getting Help

- **Issues**: Open an issue on GitHub for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Documentation**: Check the README and inline code documentation

## License

By contributing to ToQUIO.jl, you agree that your contributions will be licensed under the Mozilla Public License Version 2.0.

## Acknowledgments

Thank you for contributing to ToQUIO.jl!
