function feasibility_fixture()
    source = RMOI.Utilities.Model{Float64}()
    x = add_interval_integer_variable(source, 0, 3)
    y = add_interval_integer_variable(source, 0, 3)
    set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x), affine_term(1, y))
    eq = RMOI.add_constraint(source,
        affine_function(affine_term(1, x), affine_term(1, y)), RMOI.EqualTo(3.0))
    lt = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.LessThan(2.0))
    gt = RMOI.add_constraint(source, affine_function(affine_term(1, y)), RMOI.GreaterThan(1.0))
    return source, x, y, eq, lt, gt
end

function multi_result_backend(states)
    mock = RMOI.Utilities.MockOptimizer(RMOI.Utilities.Model{Float64}())
    RMOI.Utilities.set_mock_optimize!(mock, backend -> begin
        RMOI.set(backend, RMOI.TerminationStatus(), RMOI.OPTIMAL)
        RMOI.set(backend, RMOI.ResultCount(), length(states))
        variables = RMOI.get(backend, RMOI.ListOfVariableIndices())
        for (i, state) in enumerate(states)
            RMOI.set(backend, RMOI.PrimalStatus(i), RMOI.FEASIBLE_POINT)
            RMOI.set(backend, RMOI.VariablePrimal(i), variables, Float64[state...])
        end
    end)
    return mock
end

@testset "Original source feasibility" begin
    @testset "all affine relations and independent target residuals" begin
        source, x, y, eq, lt, gt = feasibility_fixture()
        _, data = reformulate(source)
        good = [1, 2, 1, 1]
        @test ToQUIO.is_feasible(data, good)
        @test isempty(ToQUIO.violations(data, good))
        report = ToQUIO.feasibility_report(data, good)
        @test report["feasible"]
        @test report["violation_count"] == 0
        @test report["projected_source_values"] == Dict("1" => 1, "2" => 2)
        @test report["max_violation"] == 0
        for ci in (eq, lt, gt)
            row = only(filter(r -> r["constraint"] == ToQUIO._constraint_identity(ci), report["constraints"]))
            @test row["target_residual"] == 0
        end
        bad = ToQUIO.violations(data, [3, 0, 0, 0])
        @test Set(v.constraint for v in bad) == Set([lt, gt])
        @test all(v.violation == 1 for v in bad)
        @test only(filter(v -> v.constraint == lt, bad)).source_values == Dict(x => 3)
        @test only(filter(v -> v.constraint == gt, bad)).source_values == Dict(y => 0)
        eq_bad = ToQUIO.violations(data, [1, 1, 1, 0])
        @test only(eq_bad).constraint == eq
        @test only(eq_bad).raw_residual == -1
        @test only(eq_bad).function_type == SAF64
        @test only(eq_bad).set_type == RMOI.EqualTo{Float64}

        inconsistent = ToQUIO.feasibility_report(data, [1, 2, 9, -9])
        @test inconsistent["feasible"]
        lt_row = only(filter(r -> r["constraint"] == ToQUIO._constraint_identity(lt), inconsistent["constraints"]))
        gt_row = only(filter(r -> r["constraint"] == ToQUIO._constraint_identity(gt), inconsistent["constraints"]))
        @test lt_row["target_residual"] == 8
        @test gt_row["target_residual"] == -10
        @test !ToQUIO.is_feasible(data, [1.25, 1.75, 0, 0]; atol = 0.2)
        @test ToQUIO.is_feasible(data, [1.25, 1.75, 0, 0]; atol = 0.3)
        fractional = ToQUIO.feasibility_report(data, [1.25, 1.75, 0, 0]; atol = 0.3)
        @test fractional["max_violation"] == 0.25
        @test fractional["projected_source_values"]["1"] == 1.25

        # The analysis uses the model at compile time, not later caller edits.
        RMOI.set(source, RMOI.ConstraintSet(), lt, RMOI.LessThan(0.0))
        RMOI.set(source, RMOI.ConstraintFunction(), eq,
                 affine_function(affine_term(2, x), affine_term(1, y)))
        @test ToQUIO.is_feasible(data, good)
    end

    @testset "bounds, integer and binary domains" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        _, data = reformulate(source)
        @test ToQUIO.is_feasible(data, [2])
        @test only(ToQUIO.violations(data, [4])).set_type == RMOI.Interval{Float64}
        @test only(ToQUIO.violations(data, [1.5])).set_type == RMOI.Integer
        @test only(ToQUIO.violations(data, [1.5])).violation == 0.5
        binary = RMOI.Utilities.Model{Float64}()
        z = add_binary_variable(binary)
        set_affine_objective!(binary, RMOI.MIN_SENSE, affine_term(1, z))
        _, binary_data = reformulate(binary)
        @test ToQUIO.is_feasible(binary_data, [true])
        @test only(ToQUIO.violations(binary_data, [0.5])).set_type == RMOI.ZeroOne
        @test only(ToQUIO.violations(binary_data, [2])).violation == 1
    end

    @testset "weak-penalty target optimum is source-infeasible" begin
        source, x, ci = penalty_fixture()
        hinted = HintedModel(source, Dict{Any,Float64}(ci => 0.5))
        _, data = @test_logs (:warn, r"Constraint penalty hint") reformulate(hinted)
        energies = [penalized_value(data, [i]) for i in 0:3]
        best = argmin(energies) - 1
        @test best == 0
        @test energies[1] < energies[2]
        @test !ToQUIO.is_feasible(data, [best])
        @test only(ToQUIO.violations(data, [best])).constraint == ci
    end

    @testset "optimizer results and noncontiguous source indices" begin
        source, x, y, _, _, _ = feasibility_fixture()
        optimizer = ToQUIO.Optimizer(() -> multi_result_backend([[1, 2, 1, 1], [3, 0, 0, 0]]))
        RMOI.optimize!(optimizer, source)
        @test ToQUIO.is_feasible(optimizer; result = 1)
        @test !ToQUIO.is_feasible(optimizer; result = 2)
        @test length(ToQUIO.violations(optimizer; result = 2)) == 2
        report = ToQUIO.feasibility_report(optimizer)
        @test report["result_count"] == 2
        @test report["feasible_count"] == 1
        @test report["feasible_fraction"] == 0.5
        @test report["max_violation"] == 1
        @test report["total_violation"] == 2
        @test ToQUIO.feasibility_report(optimizer; result = 2)["violation_count"] == 2
        @test_throws RMOI.ResultIndexBoundsError ToQUIO.violations(optimizer; result = 0)
        @test_throws RMOI.ResultIndexBoundsError ToQUIO.violations(optimizer; result = 3)
        @test_throws ArgumentError ToQUIO.violations(optimizer; result = true)

        reordered = RMOI.Utilities.Model{Float64}()
        removed = add_interval_integer_variable(reordered, 0, 1)
        a = add_interval_integer_variable(reordered, 0, 3)
        b = add_interval_integer_variable(reordered, 0, 3)
        RMOI.delete(reordered, removed)
        set_affine_objective!(reordered, RMOI.MIN_SENSE, affine_term(1, a), affine_term(2, b))
        ci = RMOI.add_constraint(reordered,
            affine_function(affine_term(1, a), affine_term(-1, b)), RMOI.EqualTo(1.0))
        _, reversed_data = ToQUIO.to_quio(Float64, vi -> vi == a ? 2 : 1, ci -> 1, reordered)
        @test ToQUIO.is_feasible(reversed_data, [1, 2])
        @test only(ToQUIO.violations(reversed_data, [2, 1])).source_values == Dict(a => 1, b => 2)
        @test only(ToQUIO.violations(reversed_data, [2, 1])).constraint == ci
    end

    @testset "numeric precision, no results and invalid calls" begin
        source = RMOI.Utilities.Model{BigFloat}()
        x = RMOI.add_variable(source)
        RMOI.add_constraint(source, x, RMOI.Interval(big"0.0", big"2.0"))
        RMOI.add_constraint(source, x, RMOI.Integer())
        f = RMOI.ScalarAffineFunction([RMOI.ScalarAffineTerm(big"1.0", x)], big"0.0")
        RMOI.set(source, RMOI.ObjectiveFunction{typeof(f)}(), f)
        optimizer = ToQUIO.Optimizer{BigFloat}()
        RMOI.optimize!(optimizer, source)
        value = big"1.0" + big"2.0"^(-180)
        @test !ToQUIO.is_feasible(optimizer, [value]; atol = big"1e-100")
        @test only(ToQUIO.violations(optimizer, [value]; atol = big"1e-100")).violation isa BigFloat
        empty_report = ToQUIO.feasibility_report(optimizer)
        @test empty_report["result_count"] == 0
        @test empty_report["feasible_fraction"] === nothing
        @test_throws RMOI.ResultIndexBoundsError ToQUIO.violations(optimizer)
        @test_throws ArgumentError ToQUIO.feasibility_report(ToQUIO.Optimizer())
        @test_throws DimensionMismatch ToQUIO.violations(optimizer, [0, 1])
        @test_throws ArgumentError ToQUIO.violations(optimizer, [NaN])
        for tolerance in (-1.0, Inf, NaN, true)
            @test_throws ArgumentError ToQUIO.violations(optimizer, [1]; atol = tolerance)
        end
        legacy = copy(optimizer.data)
        delete!(legacy, :source_constraints)
        @test_throws ArgumentError ToQUIO.violations(legacy, [1])
    end
end
