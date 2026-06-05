# Examples

Detailed examples demonstrating various use cases of ToQUIO.jl.

Unless a backend solver is explicitly shown, these examples use reformulation-only
mode. In this mode, `optimize!` builds `optimizer.target_model` and
`optimizer.data`; it does not produce primal values or objective values.

## Table of Contents

- [Basic Usage](#basic-usage)
- [Linear Programming](#linear-programming)
- [Quadratic Programming](#quadratic-programming)
- [Constrained Problems](#constrained-problems)
- [Custom Penalties](#custom-penalties)
- [Working with Different Solvers](#working-with-different-solvers)
- [Inspecting Reformulation](#inspecting-reformulation)

## Basic Usage

### Simple Integer Linear Program

```julia
using JuMP
using ToQUIO

# Create a model
optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

# Add variables
@variable(model, 0 <= x <= 10, Int)
@variable(model, 0 <= y <= 10, Int)

# Set objective
@objective(model, Min, x + 2y)

# Add constraints
@constraint(model, x + y >= 5)

# Reformulate
optimize!(model)

# Inspect the reformulated QUIO model
println("Reformulated variables: ", optimizer.data[:n])
println("Quadratic matrix size: ", size(optimizer.data[:Q]))
```

### Binary Variables

```julia
using JuMP, ToQUIO

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

# Binary variables (0 or 1)
@variable(model, x[1:5], Bin)

# Objective: maximize sum
@objective(model, Max, sum(x))

# Constraint: can select at most 3
@constraint(model, sum(x) <= 3)

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Variable upper bounds: ", optimizer.data[:u])
```

## Linear Programming

### Knapsack Problem

```julia
using JuMP, ToQUIO

# Item values and weights
values = [10, 13, 18, 31, 7, 15]
weights = [11, 15, 20, 35, 10, 33]
capacity = 47

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

n = length(values)
@variable(model, x[1:n], Bin)

# Maximize value
@objective(model, Max, sum(values[i] * x[i] for i in 1:n))

# Weight capacity constraint
@constraint(model, sum(weights[i] * x[i] for i in 1:n) <= capacity)

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Quadratic matrix size: ", size(optimizer.data[:Q]))
```

### Multi-dimensional Knapsack

```julia
using JuMP, ToQUIO

# Multiple resource constraints
values = [100, 150, 200, 120]
weights = [
    [10, 8, 12, 15],   # Weight constraint 1
    [5, 12, 8, 10],    # Weight constraint 2
    [8, 9, 11, 7]      # Weight constraint 3
]
capacities = [50, 40, 45]

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

n = length(values)
@variable(model, x[1:n], Bin)

@objective(model, Max, sum(values[i] * x[i] for i in 1:n))

# Multiple constraints
for (w, c) in zip(weights, capacities)
    @constraint(model, sum(w[i] * x[i] for i in 1:n) <= c)
end

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Quadratic matrix size: ", size(optimizer.data[:Q]))
```

## Quadratic Programming

### Portfolio Optimization (Simple)

```julia
using JuMP, ToQUIO

# Expected returns
μ = [0.1, 0.15, 0.12, 0.08]

# Risk (variance-covariance matrix)
Σ = [0.04 0.01 0.02 0.00;
     0.01 0.06 0.01 0.01;
     0.02 0.01 0.05 0.00;
     0.00 0.01 0.00 0.03]

# Risk aversion parameter
λ = 2.0

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

# Investment amounts (integer multiples of a base unit)
@variable(model, 0 <= w[1:4] <= 10, Int)

# Objective: maximize return - risk penalty
@objective(model, Max, 
    sum(μ[i] * w[i] for i in 1:4) - 
    λ * sum(w[i] * Σ[i,j] * w[j] for i in 1:4 for j in 1:4))

# Budget constraint (invest exactly 10 units)
@constraint(model, sum(w) == 10)

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Linear vector length: ", length(optimizer.data[:L]))
```

### Quadratic Assignment

```julia
using JuMP, ToQUIO

# Distance matrix between locations
D = [0 1 2 3;
     1 0 1 2;
     2 1 0 1;
     3 2 1 0]

# Flow matrix between facilities
F = [0 5 2 1;
     5 0 3 2;
     2 3 0 4;
     1 2 4 0]

n = 4
optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

# x[i,j] = 1 if facility i is at location j
@variable(model, x[1:n, 1:n], Bin)

# Minimize total flow × distance
@objective(model, Min,
    sum(F[i,k] * D[j,l] * x[i,j] * x[k,l] 
        for i in 1:n for j in 1:n for k in 1:n for l in 1:n))

# Each facility at exactly one location
for i in 1:n
    @constraint(model, sum(x[i,j] for j in 1:n) == 1)
end

# Each location has exactly one facility
for j in 1:n
    @constraint(model, sum(x[i,j] for i in 1:n) == 1)
end

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Number of bounds: ", length(optimizer.data[:l]))
```

## Constrained Problems

### Production Planning

```julia
using JuMP, ToQUIO

# Production costs and profits
costs = [10, 12, 15]
profits = [25, 30, 35]

# Resource requirements (3 products × 2 resources)
A = [2 3 4;
     1 2 3]

# Resource availability
b = [100, 80]

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

# Production quantities
@variable(model, 0 <= x[1:3] <= 50, Int)

# Maximize profit
@objective(model, Max, sum((profits[i] - costs[i]) * x[i] for i in 1:3))

# Resource constraints
for r in 1:2
    @constraint(model, sum(A[r,p] * x[p] for p in 1:3) <= b[r])
end

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Quadratic matrix size: ", size(optimizer.data[:Q]))
```

### Set Cover Problem

```julia
using JuMP, ToQUIO

# Elements to cover
elements = 1:10

# Sets available (each set covers certain elements)
sets = [
    [1, 2, 3, 4],
    [3, 4, 5, 6],
    [5, 6, 7, 8],
    [7, 8, 9, 10],
    [1, 5, 9],
    [2, 6, 10]
]

# Costs of sets
costs = [4, 3, 3, 4, 2, 3]

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

n_sets = length(sets)
@variable(model, x[1:n_sets], Bin)

# Minimize total cost
@objective(model, Min, sum(costs[i] * x[i] for i in 1:n_sets))

# Cover each element
for e in elements
    # Find which sets contain element e
    containing_sets = [i for i in 1:n_sets if e in sets[i]]
    @constraint(model, sum(x[i] for i in containing_sets) >= 1)
end

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Number of penalties: ", size(optimizer.data[:D], 1))
```

## Custom Penalties

### Specifying Penalty Coefficients

```julia
using JuMP, ToQUIO
using MathOptInterface
const MOI = MathOptInterface

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

@variable(model, 0 <= x <= 10, Int)
@variable(model, 0 <= y <= 10, Int)

@objective(model, Min, x + y)

# Add constraints with custom penalties
@constraint(model, c1, x + y >= 5)
@constraint(model, c2, x - y == 0)

# Set finite, positive custom penalties.
# These override automatic sufficient penalties and can be heuristic.
MOI.set(backend(model), ToQUIO.ConstraintPenaltyHint(), index(c2), 1000.0)
MOI.set(backend(model), ToQUIO.ConstraintPenaltyHint(), index(c1), 10.0)

optimize!(model)

println("Penalty matrix:")
display(optimizer.data[:D])
println("Selected penalties: ", optimizer.data[:rho])
println("Automatic penalties: ", optimizer.data[:rho_auto])
println("User hints: ", optimizer.data[:penalty_hints])
```

## Working with Different Solvers

### Reformulation Only (No Solving)

```julia
using JuMP, ToQUIO

# Create optimizer without backend solver
optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

@variable(model, 0 <= x[1:3] <= 5, Int)
@objective(model, Min, sum(x[i]^2 for i in 1:3))
@constraint(model, sum(x) == 6)

# This will reformulate but not solve
optimize!(model)

println("Reformulated model available")
println("Number of variables: ", optimizer.data[:n])
```

### With a Backend Solver

```julia
using JuMP, ToQUIO
# using SomeQUIOSolver  # Your QUIO solver

# Wrap the QUIO solver
model = Model(() -> ToQUIO.Optimizer(() -> SomeQUIOSolver.Optimizer()))

@variable(model, 0 <= x[1:5] <= 10, Int)
@objective(model, Min, sum((x[i] - 3)^2 for i in 1:5))
@constraint(model, sum(x) >= 15)

optimize!(model)

# Results come from the backend solver
println("Status: ", termination_status(model))
println("Solution: ", value.(x))
```

## Inspecting Reformulation

### Examining QUIO Matrices

```julia
using JuMP, ToQUIO

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

@variable(model, -2 <= x[1:2] <= 2, Int)
@objective(model, Min, x[1]^2 + x[2]^2 + x[1] + x[2])
@constraint(model, eq, x[1] + x[2] == 1)
@constraint(model, ineq, x[1] - x[2] <= 2)

optimize!(model)

# Access reformulation data
data = optimizer.data

println("=== Reformulation Data ===")
println("Dimension: ", data[:n])
println("\nQuadratic matrix Q:")
display(data[:Q])
println("\nLinear vector L:")
display(data[:L])
println("\nConstant: ", data[:c])
println("\nLower bounds: ", data[:l])
println("\nUpper bounds: ", data[:u])
```

### Analyzing Penalty Coefficients

```julia
using JuMP, ToQUIO

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

@variable(model, 0 <= x <= 10, Int)
@variable(model, 0 <= y <= 10, Int)

@objective(model, Min, x + 2y)

@constraint(model, c1, x + y == 8)
@constraint(model, c2, 2x + 3y <= 25)

optimize!(model)

# The penalty matrix D contains the penalty coefficients
D = optimizer.data[:D]

println("Penalty diagonal matrix:")
display(D)
```

### Verification

```julia
using JuMP, ToQUIO

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

@variable(model, 0 <= x <= 5, Int)
@variable(model, 0 <= y <= 5, Int)

@objective(model, Min, x^2 + y^2)
@constraint(model, x + y == 4)

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Quadratic matrix size: ", size(optimizer.data[:Q]))
```

## Advanced Examples

### Max-Cut Problem

```julia
using JuMP, ToQUIO

# Graph adjacency matrix (weights)
W = [0 1 1 0;
     1 0 1 1;
     1 1 0 1;
     0 1 1 0]

n = size(W, 1)
optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

# x[i] = 0 or 1 indicates which partition node i is in
@variable(model, x[1:n], Bin)

# Maximize cut: sum of weights crossing partitions
@objective(model, Max,
    sum(W[i,j] * (x[i] * (1-x[j]) + (1-x[i]) * x[j])
        for i in 1:n for j in i+1:n))

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Quadratic matrix size: ", size(optimizer.data[:Q]))
```

### Facility Location

```julia
using JuMP, ToQUIO

# Customer demands
demand = [10, 15, 20, 12]

# Fixed costs to open facilities
fixed_cost = [100, 120, 110]

# Transportation costs (customers × facilities)
transport_cost = [
    5 8 6;
    6 4 7;
    8 5 3;
    7 6 5
]

n_customers = length(demand)
n_facilities = length(fixed_cost)

optimizer = ToQUIO.Optimizer()
model = Model(() -> optimizer)

# y[j] = 1 if facility j is opened
@variable(model, y[1:n_facilities], Bin)

# x[i,j] = 1 if customer i is served by facility j
@variable(model, x[1:n_customers, 1:n_facilities], Bin)

# Minimize total cost
@objective(model, Min,
    sum(fixed_cost[j] * y[j] for j in 1:n_facilities) +
    sum(demand[i] * transport_cost[i,j] * x[i,j] 
        for i in 1:n_customers for j in 1:n_facilities))

# Each customer served by exactly one facility
for i in 1:n_customers
    @constraint(model, sum(x[i,j] for j in 1:n_facilities) == 1)
end

# Can only serve from open facilities
for i in 1:n_customers, j in 1:n_facilities
    @constraint(model, x[i,j] <= y[j])
end

optimize!(model)

println("Reformulated variables: ", optimizer.data[:n])
println("Number of penalties: ", size(optimizer.data[:D], 1))
```
