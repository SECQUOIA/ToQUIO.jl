using Test
using Random
using JuMP
using ToQUIO

Random.seed!(0)

m = 3 # number of equalities
k = 2 # number of inequalities
n = 4 # number of variables

A = rand(-3:3, m, n)
b = rand(-3:3, m)

C = rand(-3:3, k, n)
d = rand(-3:3, k)

model = Model(() -> ToQUIO.Optimizer(Gurobi.Optimizer))

@variable(model, -5 <= x[1:n] <= 10, Int)

@objective(model, Min, sum(i * j * (-1)^(i + j) * x[i] * x[j] for i = 1:n for j = 1:n))

@constraint(model, A * x .== b)
@constraint(model, C * x .<= d)
