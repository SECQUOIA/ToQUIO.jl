# GitHub Copilot Development Guide for ToQUIO.jl

This guide is specifically designed for developers using GitHub Copilot or other AI coding assistants to contribute to ToQUIO.jl.

## Understanding ToQUIO.jl for AI Assistants

### What This Package Does

ToQUIO.jl performs a mathematical transformation:
- **Input**: Integer optimization problem with constraints (equalities, inequalities)
- **Transformation**: Penalty method that adds constraint violations as quadratic terms to the objective
- **Output**: Quadratic Unconstrained Integer Optimization (QUIO) problem

### Why It Exists

QUIO problems can be solved by specialized hardware (quantum annealers) and algorithms. This package makes arbitrary constrained problems compatible with these solvers.

## Copilot Prompting Best Practices

### Context to Provide

When asking Copilot for help, always include:

```
Context: ToQUIO.jl - Julia package for QUIO reformulation using penalty methods
MOI Version: 1.x (MathOptInterface)
Type System: Parametric with type parameter T (usually Float64)
Key Constraint: Maintain type-generic code throughout
```

### Example Prompts

**Good Prompt:**
```
# Add support for Interval constraints in ToQUIO reformulation
# Input: VariableIndex-in-Interval{T} constraints from MOI model
# Output: Extract lower and upper bounds for variable bounds vector
# Follow pattern from get_variable_bounds() function
# Maintain type parameter T
```

**Poor Prompt:**
```
# Add interval constraint support
```

## Code Patterns Reference

### 1. Type-Generic Functions

Always maintain the type parameter `T`:

```julia
# ✅ GOOD - Type-generic
function my_function(source::MOI.ModelLike, ::Type{T}) where {T}
    result = zeros(T, n)
    # ...
    return result
end

# ❌ BAD - Hard-coded type
function my_function(source::MOI.ModelLike)
    result = zeros(Float64, n)
    # ...
    return result
end
```

### 2. MOI Function Patterns

Follow MathOptInterface conventions:

```julia
# ✅ GOOD - MOI convention
function MOI.get(optimizer::Optimizer{T}, attr::MOI.SolverName) where {T}
    return "ToQUIO Optimizer"
end

# ❌ BAD - Non-standard naming
function get_solver_name(optimizer::Optimizer{T}) where {T}
    return "ToQUIO Optimizer"
end
```

### 3. Matrix Extraction Pattern

When extracting constraints, follow this pattern:

```julia
function get_constraint_type_matrices(::Type{T}, varmap::Function, conmap::Function, source) where {T}
    F = SAF{T}  # Function type
    S = SomeSet{T}  # Set type
    
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
        
        b[i] = # extract from set s
    end
    
    return (A, b)
end
```

### 4. Documentation Pattern

Use this format for all public functions:

```julia
@doc raw"""
    function_name(arg1::Type1, arg2::Type2) -> ReturnType

Brief one-line description.

Longer description explaining what the function does, how it works,
and any important details.

# Arguments
- `arg1::Type1`: Description of first argument
- `arg2::Type2`: Description of second argument

# Returns
- `ReturnType`: Description of what is returned

# Examples
```julia
result = function_name(value1, value2)
```

# Notes
- Any important implementation details
- Edge cases to be aware of
"""
function function_name(arg1::Type1, arg2::Type2) where {T}
    # Implementation
end
```

## Common Copilot Tasks

### Task 1: Add a New Constraint Type

**Prompt Template:**
```
Add support for [ConstraintType] constraints in ToQUIO.jl reformulation.
Current supported types: EqualTo, LessThan, GreaterThan
Pattern to follow: get_eq_matrices(), get_lt_matrices() in to_quio.jl
Maintain type parameter T
Create function get_[constrainttype]_matrices(::Type{T}, varmap, conmap, source)
```

**Steps:**
1. Add `MOI.supports_constraint` declaration in `MOI_wrapper.jl`
2. Create extraction function `get_*_matrices` in `to_quio.jl`
3. Integrate into main `to_quio()` function
4. Add tests in `test/runtests.jl`

### Task 2: Modify Penalty Computation

**Prompt Template:**
```
Modify penalty coefficient computation in to_quio() function.
Current formula: ρ = Δ/ε + ϵ
Located around line 210-214 in to_quio.jl
New formula: [describe new formula]
Maintain type T, ensure ρ remains positive
```

**Key Lines:**
```julia
# Current penalty computation (line ~212-214)
ρ_eq = something.(θ_eq, (Δ ./ ε_eq) .+ ϵ)
ρ_ie = something.(θ_ie, (Δ ./ ε_ie) .+ ϵ)
ρ    = T[ρ_eq; ρ_ie]
```

### Task 3: Add Custom MOI Attribute

**Prompt Template:**
```
Add new MOI attribute for ToQUIO optimizer.
Type: [AbstractOptimizerAttribute | AbstractModelAttribute | AbstractConstraintAttribute]
Name: [AttributeName]
Purpose: [description]
Follow pattern in src/MOI_wrapper/attributes/reformulation.jl
```

**Pattern:**
```julia
@doc raw"""
    AttributeName <: MOI.AbstractOptimizerAttribute

Description of what this attribute represents.
"""
struct AttributeName <: MOI.AbstractOptimizerAttribute end

MOI.supports(solver::Optimizer{T}, ::AttributeName) where {T} = true

function MOI.get(solver::Optimizer{T}, ::AttributeName) where {T}
    # Implementation
end

function MOI.set(solver::Optimizer{T}, ::AttributeName, value) where {T}
    # Implementation
end
```

## Testing with Copilot

### Test Template

Use this template when asking Copilot to generate tests:

```julia
@testset "Feature Description" begin
    model = Model(() -> ToQUIO.Optimizer())
    
    # Setup variables
    @variable(model, l <= x <= u, Int)
    
    # Setup objective
    @objective(model, Min, ...)
    
    # Setup constraints
    @constraint(model, ...)
    
    # Optimize
    optimize!(model)
    
    # Assertions
    @test termination_status(model) == MOI.OPTIMAL
    @test isapprox(value(x), expected_value, atol=1e-6)
    @test # other assertions
end
```

### Test Coverage Checklist

When adding new features, ensure tests cover:
- ✅ Basic functionality
- ✅ Edge cases (empty constraints, zero coefficients)
- ✅ Different numeric types (Float64, BigFloat if applicable)
- ✅ Error conditions (unbounded variables, invalid inputs)
- ✅ Integration with existing features

## Debugging with Copilot

### Inspecting Reformulation

**Prompt:**
```
Add debug output to inspect ToQUIO reformulation.
Show: Q matrix, linear terms, bounds, penalty coefficients
Access via optimizer.data dictionary
Format output nicely for console
```

**Code:**
```julia
backend_opt = backend(model).optimizer.model
data = backend_opt.data

println("=== Reformulation Debug Info ===")
println("Dimension: ", data[:n])
println("\nQ matrix (quadratic terms):")
display(data[:Q])
println("\nLinear terms:")
display(data[:L])
println("\nConstant: ", data[:c])
println("\nPenalty matrix:")
display(data[:D])
```

### Common Issues and Copilot Queries

**Issue: Type instability**
```
Copilot: Review function [name] for type stability.
Check that all intermediate values maintain type parameter T.
Suggest @code_warntype annotations.
```

**Issue: MOI constraint not supported**
```
Copilot: Why does ToQUIO not support [ConstraintType]?
Check MOI.supports_constraint implementations.
Suggest how to add support.
```

**Issue: Incorrect reformulation**
```
Copilot: Verify penalty computation in to_quio().
Check that constraint matrices A, b are correctly extracted.
Verify slack variable bounds calculation.
Compare with mathematical derivation in docs/algorithm.md.
```

## Copilot Code Review Checklist

When reviewing Copilot-generated code:

- [ ] Type parameter `T` used consistently
- [ ] No hard-coded `Float64` or other types
- [ ] Follows MOI naming conventions (`get`, `set`, `supports`)
- [ ] Has docstring with `@doc raw"""..."""`
- [ ] Includes usage example in docstring
- [ ] Has corresponding tests
- [ ] No breaking changes to existing API
- [ ] Matches code style (4 spaces, line length < 120)

## Advanced Copilot Techniques

### Multi-Step Refactoring

Break complex tasks into steps:

```
Step 1: Extract constraint handling into separate function
Step 2: Generalize to handle multiple constraint types
Step 3: Optimize performance (reduce allocations)
Step 4: Add comprehensive tests
```

### Code Generation from Math

When implementing mathematical formulas:

```
Implement the following mathematical transformation:
Input: f(x) = x'Qx + ℓ'x + β, constraints Ax = b
Output: F(z) = z'Gz + g'z + γ where G = [Q + A'DA, A'D; DA, D]
Use sparse matrices for efficiency
Maintain type parameter T
Refer to docs/algorithm.md for derivation
```

### Performance Optimization

```
Optimize [function_name] for performance:
- Reduce allocations (use in-place operations)
- Use @inbounds where safe
- Consider @simd for loops
- Profile with @time or BenchmarkTools
- Maintain type stability
```

## Resources for Copilot Context

When working on ToQUIO.jl, provide these resources to Copilot:

1. **MOI Documentation**: https://jump.dev/MathOptInterface.jl/stable/
2. **Julia Style Guide**: https://docs.julialang.org/en/v1/manual/style-guide/
3. **Penalty Methods**: Standard optimization textbook reference
4. **Project-Specific**: 
   - `docs/algorithm.md` for mathematical details
   - `docs/api.md` for function signatures
   - `src/to_quio.jl` for reformulation implementation

## Final Tips

1. **Start Small**: Test Copilot suggestions on small, isolated functions first
2. **Verify Mathematics**: Double-check any mathematical transformations
3. **Run Tests Frequently**: `Pkg.test()` after each change
4. **Use Type Assertions**: Add `@assert` to catch type issues early
5. **Read Existing Code**: Understand patterns before generating new code
6. **Iterate**: Copilot suggestions improve with context; iterate on prompts

## Getting Help

If Copilot generates incorrect code:
1. Provide more context about ToQUIO's design patterns
2. Reference specific existing functions as examples
3. Include type signatures explicitly
4. Ask for step-by-step implementation rather than full solution

Remember: Copilot is a tool to accelerate development, but understanding the underlying mathematics and architecture is essential for maintaining code quality in ToQUIO.jl.
