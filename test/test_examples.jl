# Test file that runs examples from documentation
# This ensures documentation examples stay up-to-date and working

using Test
using JuMP
using ToQUIO

@testset "Documentation Examples" begin
    
    @testset "Simple Integer Linear Program" begin
        # Example from docs/examples.md - Basic Usage
        model = Model(() -> ToQUIO.Optimizer())
        
        @variable(model, 0 <= x <= 10, Int)
        @variable(model, 0 <= y <= 10, Int)
        
        @objective(model, Min, x + 2y)
        @constraint(model, x + y >= 5)
        
        optimize!(model)
        
        # Test that model was set up correctly
        @test num_variables(model) == 2
        @test num_constraints(model; count_variable_in_set_constraints = false) == 1
    end
    
    @testset "Binary Variables" begin
        # Example from docs/examples.md - Basic Usage
        model = Model(() -> ToQUIO.Optimizer())
        
        @variable(model, x[1:5], Bin)
        @objective(model, Max, sum(x))
        @constraint(model, sum(x) <= 3)
        
        optimize!(model)
        
        @test num_variables(model) == 5
        @test num_constraints(model; count_variable_in_set_constraints = false) == 1
    end
    
    @testset "Knapsack Problem" begin
        # Example from docs/examples.md - Linear Programming
        values = [10, 13, 18, 31, 7, 15]
        weights = [11, 15, 20, 35, 10, 33]
        capacity = 47
        
        model = Model(() -> ToQUIO.Optimizer())
        
        n = length(values)
        @variable(model, x[1:n], Bin)
        
        @objective(model, Max, sum(values[i] * x[i] for i in 1:n))
        @constraint(model, sum(weights[i] * x[i] for i in 1:n) <= capacity)
        
        optimize!(model)
        
        @test num_variables(model) == n
        @test num_constraints(model; count_variable_in_set_constraints = false) == 1
    end
    
    @testset "Quadratic Objective" begin
        # Example from docs/examples.md - Quadratic Programming
        model = Model(() -> ToQUIO.Optimizer())
        
        @variable(model, 0 <= x <= 5, Int)
        @variable(model, 0 <= y <= 5, Int)
        
        @objective(model, Min, x^2 + y^2 - 2x - 4y)
        @constraint(model, x + y >= 3)
        @constraint(model, 2x + y <= 8)
        
        optimize!(model)
        
        @test num_variables(model) == 2
        @test num_constraints(model; count_variable_in_set_constraints = false) == 2
    end
    
    @testset "Production Planning" begin
        # Example from docs/examples.md - Constrained Problems
        costs = [10, 12, 15]
        profits = [25, 30, 35]
        
        A = [2 3 4;
             1 2 3]
        b = [100, 80]
        
        model = Model(() -> ToQUIO.Optimizer())
        
        @variable(model, 0 <= x[1:3] <= 50, Int)
        @objective(model, Max, sum((profits[i] - costs[i]) * x[i] for i in 1:3))
        
        for r in 1:2
            @constraint(model, sum(A[r,p] * x[p] for p in 1:3) <= b[r])
        end
        
        optimize!(model)
        
        @test num_variables(model) == 3
        @test num_constraints(model; count_variable_in_set_constraints = false) == 2
    end
    
    @testset "Set Cover Problem" begin
        # Example from docs/examples.md - Constrained Problems
        elements = 1:10
        
        sets = [
            [1, 2, 3, 4],
            [3, 4, 5, 6],
            [5, 6, 7, 8],
            [7, 8, 9, 10],
            [1, 5, 9],
            [2, 6, 10]
        ]
        
        costs = [4, 3, 3, 4, 2, 3]
        
        model = Model(() -> ToQUIO.Optimizer())
        
        n_sets = length(sets)
        @variable(model, x[1:n_sets], Bin)
        
        @objective(model, Min, sum(costs[i] * x[i] for i in 1:n_sets))
        
        for e in elements
            containing_sets = [i for i in 1:n_sets if e in sets[i]]
            @constraint(model, sum(x[i] for i in containing_sets) >= 1)
        end
        
        optimize!(model)
        
        @test num_variables(model) == n_sets
        @test num_constraints(model; count_variable_in_set_constraints = false) == length(elements)
    end
    
end
