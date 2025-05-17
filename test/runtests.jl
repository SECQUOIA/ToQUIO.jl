using Test
using Revise
using Random
using JuMP
using ToQUIO

using AmplNLWriter
using Bonmin_jll
const Bonmin_Optimizer = () -> AmplNLWriter.Optimizer(Bonmin_jll.amplexe)

Random.seed!(0)

m = 1 # number of equalities
k = 2 # number of inequalities
n = 4 # number of variables

A = rand(-3:3, m, n)
b = rand(-3:3, m)

C = rand(-3:3, k, n)
d = rand(0:3, k)

model = Model()

@variable(model, -5 <= x[1:n] <= 10, Int)

# @objective(model, Min, sum(i * j * (-1)^(i + j) * x[i] * x[j] for i = 1:n for j = 1:n))
@objective(model, Min, sum(x))

@constraint(model, A * x .== b)
@constraint(model, C * x .<= d)

set_optimizer(model, () -> ToQUIO.Optimizer(Bonmin_Optimizer))

optimize!(model)

print(model)

@show termination_status(model)

if result_count(model) > 0
    @show objective_value(model)
    @show value.(x)
end

set_optimizer(model, Bonmin_Optimizer)

optimize!(model)

@show termination_status(model)

if result_count(model) > 0
    @show objective_value(model)
    @show value.(x)
end