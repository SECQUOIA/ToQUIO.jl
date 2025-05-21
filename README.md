# ToQUIO.jl

JuMP To Quadratic Unconstrained Integer Optimization

## Example

```julia
using JuMP
using ToQUIO

A = [0, 2, 4; 5, 3, 5]
b = [1, 5]

model = Model(() -> ToQUIO.Optimizer())

@variable(model, -3 <= x[1:3] <= 3, Int)
@objective(model, Min, sum(i * j * (-1)^(i + j) * x[i] * x[j] for i = 1:3 for j = 1:3))

optimize!(model)

