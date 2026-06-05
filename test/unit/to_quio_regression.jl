const RMOI = ToQUIO.MOI
const SAF64 = RMOI.ScalarAffineFunction{Float64}
const SQF64 = RMOI.ScalarQuadraticFunction{Float64}

struct HintedModel{T} <: RMOI.ModelLike
    inner::RMOI.Utilities.Model{T}
    hints::Dict{Any,T}
end

RMOI.get(model::HintedModel, attr::ToQUIO.ConstraintPenaltyHint, ci::RMOI.ConstraintIndex) =
    get(model.hints, ci, nothing)

RMOI.supports(
    ::HintedModel,
    ::ToQUIO.ConstraintPenaltyHint,
    ::Type{<:RMOI.ConstraintIndex},
) = true

RMOI.get(model::HintedModel, attr::RMOI.AbstractModelAttribute) =
    RMOI.get(model.inner, attr)
RMOI.get(model::HintedModel, attr::RMOI.AbstractVariableAttribute, vi::RMOI.VariableIndex) =
    RMOI.get(model.inner, attr, vi)
RMOI.get(model::HintedModel, attr::RMOI.AbstractConstraintAttribute, ci::RMOI.ConstraintIndex) =
    RMOI.get(model.inner, attr, ci)

function affine_term(coefficient, variable)
    return RMOI.ScalarAffineTerm(Float64(coefficient), variable)
end

function quadratic_term(coefficient, variable_1, variable_2)
    return RMOI.ScalarQuadraticTerm(Float64(coefficient), variable_1, variable_2)
end

function affine_function(terms...; constant = 0.0)
    return SAF64(collect(terms), Float64(constant))
end

function quadratic_function(quadratic_terms, affine_terms; constant = 0.0)
    return SQF64(quadratic_terms, affine_terms, Float64(constant))
end

function add_interval_integer_variable(model, lower, upper)
    variable = RMOI.add_variable(model)
    RMOI.add_constraint(model, variable, RMOI.Interval(Float64(lower), Float64(upper)))
    RMOI.add_constraint(model, variable, RMOI.Integer())
    return variable
end

function add_binary_variable(model)
    variable = RMOI.add_variable(model)
    RMOI.add_constraint(model, variable, RMOI.ZeroOne())
    return variable
end

function set_affine_objective!(model, sense, terms...; constant = 0.0)
    RMOI.set(model, RMOI.ObjectiveSense(), sense)
    RMOI.set(model, RMOI.ObjectiveFunction{SAF64}(), affine_function(terms...; constant))
    return model
end

function set_quadratic_objective!(model, sense, quadratic_terms, affine_terms; constant = 0.0)
    RMOI.set(model, RMOI.ObjectiveSense(), sense)
    RMOI.set(
        model,
        RMOI.ObjectiveFunction{SQF64}(),
        quadratic_function(quadratic_terms, affine_terms; constant),
    )
    return model
end

function reformulate(model)
    return ToQUIO.to_quio(Float64, variable -> variable.value, constraint -> constraint.value, model)
end

function penalized_value(data, z)
    Q = data[:Q]
    L = data[:L]
    quadratic = sum(z[i] * Q[i, j] * z[j] for i in eachindex(z), j in eachindex(z))
    linear = sum(L[i] * z[i] for i in eachindex(z))
    return quadratic + linear + data[:c]
end

function mock_backend_with_primal(primal)
    mock = RMOI.Utilities.MockOptimizer(RMOI.Utilities.Model{Float64}())
    RMOI.Utilities.set_mock_optimize!(
        mock,
        mock -> RMOI.Utilities.mock_optimize!(
            mock,
            RMOI.OPTIMAL,
            (RMOI.FEASIBLE_POINT, Float64[primal...]),
        ),
    )
    return mock
end

@testset "to_quio solver-independent regression tests" begin
    @testset "linear objective with equality expands penalty" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(2, x); constant = 1)
        ci = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.EqualTo(1.0))

        target, data = reformulate(source)

        @test RMOI.get(target, RMOI.ObjectiveSense()) == RMOI.MIN_SENSE
        @test data[:n] == 1
        # Δ = 6, ρ = 7; 2x + 1 + ρ(x - 1)^2 gives Q = 7, L = -12, c = 8.
        @test data[:Q] == reshape([7.0], 1, 1)
        @test data[:L] == [-12.0]
        @test data[:c] == 8.0
        @test data[:rho] == [7.0]
        @test data[:rho_auto] == [7.0]
        @test data[:penalty_hints] == [nothing]
        @test data[:penalty_constraints] == Any[ci]
        @test data[:l] == [0.0]
        @test data[:u] == [3.0]
    end

    @testset "penalty hints override automatic penalties and are recorded" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 2)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        ci = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.EqualTo(1.0))

        hinted = HintedModel(source, Dict{Any,Float64}(ci => 2.0))
        _, data = @test_logs (
            :warn,
            r"Constraint penalty hint is below the automatic sufficient penalty",
        ) reformulate(hinted)

        @test data[:rho_auto] == [3.0]
        @test data[:rho] == [2.0]
        @test data[:penalty_hints] == [2.0]
        @test data[:penalty_constraints] == Any[ci]
        @test data[:D] == reshape([2.0], 1, 1)
    end

    @testset "penalty metadata records source constraints in reformulation order" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        ci_lt = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.LessThan(2.0))
        ci_eq = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.EqualTo(1.0))
        ci_gt = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.GreaterThan(0.0))

        _, data = reformulate(source)

        @test data[:penalty_constraints] == Any[ci_eq, ci_lt, ci_gt]
        @test length(data[:rho]) == length(data[:penalty_constraints])
        @test length(data[:rho_auto]) == length(data[:penalty_constraints])
        @test length(data[:penalty_hints]) == length(data[:penalty_constraints])
    end

    @testset "less-than inequality expands slack penalty" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.LessThan(2.0))

        target, data = reformulate(source)

        @test RMOI.get(target, RMOI.ObjectiveSense()) == RMOI.MIN_SENSE
        @test data[:n] == 2
        # Δ = 3, ρ = 4; x + ρ(x + s - 2)^2 gives Q, L, and c below.
        @test data[:Q] == [4.0 4.0; 4.0 4.0]
        @test data[:L] == [-15.0, -16.0]
        @test data[:c] == 16.0
        @test data[:l] == [0.0, 0.0]
        @test data[:u] == [3.0, 2.0]
    end

    @testset "greater-than inequality is sign-canonicalized" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.GreaterThan(1.0))

        _, data = reformulate(source)

        @test data[:n] == 2
        # Δ = 3, ρ = 4; x + ρ(-x + s + 1)^2 gives the canonicalized >= form.
        @test data[:Q] == [4.0 -4.0; -4.0 4.0]
        @test data[:L] == [-7.0, 8.0]
        @test data[:c] == 4.0
        @test data[:l] == [0.0, 0.0]
        @test data[:u] == [3.0, 2.0]
    end

    @testset "maximization uses negative penalties and max sense" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 2)
        set_affine_objective!(source, RMOI.MAX_SENSE, affine_term(1, x))
        RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.EqualTo(1.0))

        target, data = reformulate(source)

        @test RMOI.get(target, RMOI.ObjectiveSense()) == RMOI.MAX_SENSE
        # Δ = 2, ρ = 3; maximization subtracts the penalty: x - ρ(x - 1)^2.
        @test data[:Q] == reshape([-3.0], 1, 1)
        @test data[:L] == [7.0]
        @test data[:c] == -3.0
    end

    @testset "quadratic objective follows MOI coefficient convention" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 2)
        y = add_interval_integer_variable(source, 0, 3)
        set_quadratic_objective!(
            source,
            RMOI.MIN_SENSE,
            [quadratic_term(6, x, x), quadratic_term(5, x, y)],
            [affine_term(2, x), affine_term(-1, y)];
            constant = 4,
        )

        _, data = reformulate(source)

        @test data[:n] == 2
        # No penalties; MOI diagonal quadratic terms are halved, off-diagonal terms are not.
        @test data[:Q] == [3.0 5.0; 0.0 0.0]
        @test data[:L] == [2.0, -1.0]
        @test data[:c] == 4.0
    end

    @testset "binary variables expose binary bounds and integer target variables" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_binary_variable(source)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))

        target, data = reformulate(source)

        @test data[:l] == [0.0]
        @test data[:u] == [1.0]
        @test RMOI.get(target, RMOI.NumberOfConstraints{RMOI.VariableIndex,RMOI.Integer}()) == 1
    end

    @testset "automatic penalties prefer feasible optima on small enumerations" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 2)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(-1, x))
        RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.LessThan(1.0))

        _, data = reformulate(source)

        best_value = Inf
        best_x = Int[]
        for x_value in Int(data[:l][1]):Int(data[:u][1])
            for slack_value in Int(data[:l][2]):Int(data[:u][2])
                z = Float64[x_value, slack_value]
                value = penalized_value(data, z)
                if value < best_value - 1e-8
                    best_value = value
                    empty!(best_x)
                    push!(best_x, x_value)
                elseif isapprox(value, best_value; atol = 1e-8)
                    push!(best_x, x_value)
                end
            end
        end

        @test best_x == [1]
        @test best_value == -1.0
    end

    @testset "backend results use original-model semantics" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.LessThan(2.0))

        optimizer = ToQUIO.Optimizer{Float64}(() -> mock_backend_with_primal([3, 0]))

        RMOI.optimize!(optimizer, source)

        @test RMOI.get(optimizer, RMOI.TerminationStatus()) == RMOI.OPTIMAL
        @test RMOI.is_set_by_optimize(ToQUIO.PenalizedObjectiveValue())
        @test optimizer.data[:source_to_target_variables][x] == RMOI.VariableIndex(1)
        @test optimizer.data[:target_variables] == [RMOI.VariableIndex(1)]
        @test optimizer.data[:slack_variables] == [RMOI.VariableIndex(2)]
        @test RMOI.get(optimizer, RMOI.VariablePrimal(), x) == 3.0
        @test_throws RMOI.InvalidIndex RMOI.get(
            optimizer,
            RMOI.VariablePrimal(),
            RMOI.VariableIndex(2),
        )
        @test RMOI.get(optimizer, RMOI.ObjectiveValue()) == 3.0
        @test RMOI.get(optimizer, ToQUIO.PenalizedObjectiveValue()) == 7.0
    end

    @testset "backend objective value evaluates quadratic source objective" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        y = add_interval_integer_variable(source, 0, 3)
        set_quadratic_objective!(
            source,
            RMOI.MIN_SENSE,
            [quadratic_term(6, x, x), quadratic_term(5, x, y)],
            [affine_term(2, x), affine_term(-1, y)];
            constant = 4,
        )

        optimizer = ToQUIO.Optimizer{Float64}(() -> mock_backend_with_primal([2, 3]))

        RMOI.optimize!(optimizer, source)

        @test RMOI.get(optimizer, RMOI.VariablePrimal(), x) == 2.0
        @test RMOI.get(optimizer, RMOI.VariablePrimal(), y) == 3.0
        @test RMOI.get(optimizer, RMOI.ObjectiveValue()) == 47.0
        @test RMOI.get(optimizer, ToQUIO.PenalizedObjectiveValue()) == 47.0
    end

    @testset "invalid source models fail before reformulation" begin
        unbounded = RMOI.Utilities.Model{Float64}()
        x = RMOI.add_variable(unbounded)
        RMOI.add_constraint(unbounded, x, RMOI.Integer())
        set_affine_objective!(unbounded, RMOI.MIN_SENSE, affine_term(1, x))
        @test_throws ErrorException reformulate(unbounded)

        continuous = RMOI.Utilities.Model{Float64}()
        x = RMOI.add_variable(continuous)
        RMOI.add_constraint(continuous, x, RMOI.Interval(0.0, 1.0))
        set_affine_objective!(continuous, RMOI.MIN_SENSE, affine_term(1, x))
        @test_throws ErrorException reformulate(continuous)

        noninteger_coefficients = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(noninteger_coefficients, 0, 2)
        set_affine_objective!(noninteger_coefficients, RMOI.MIN_SENSE, affine_term(1, x))
        RMOI.add_constraint(
            noninteger_coefficients,
            affine_function(affine_term(0.5, x)),
            RMOI.EqualTo(1.0),
        )
        @test_throws ErrorException reformulate(noninteger_coefficients)

        infeasible_equality = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(infeasible_equality, 0, 1)
        set_affine_objective!(infeasible_equality, RMOI.MIN_SENSE, affine_term(1, x))
        RMOI.add_constraint(infeasible_equality, affine_function(affine_term(1, x)), RMOI.EqualTo(2.0))
        @test_throws ErrorException reformulate(infeasible_equality)

        integer_infeasible_equality = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(integer_infeasible_equality, 0, 2)
        set_affine_objective!(integer_infeasible_equality, RMOI.MIN_SENSE, affine_term(1, x))
        RMOI.add_constraint(
            integer_infeasible_equality,
            affine_function(affine_term(2, x)),
            RMOI.EqualTo(1.0),
        )
        @test_throws ErrorException reformulate(integer_infeasible_equality)

        infeasible_inequality = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(infeasible_inequality, 0, 1)
        set_affine_objective!(infeasible_inequality, RMOI.MIN_SENSE, affine_term(1, x))
        RMOI.add_constraint(
            infeasible_inequality,
            affine_function(affine_term(1, x)),
            RMOI.LessThan(-1.0),
        )
        @test_throws ErrorException reformulate(infeasible_inequality)

        nonpositive_penalty = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(nonpositive_penalty, 0, 2)
        set_affine_objective!(nonpositive_penalty, RMOI.MIN_SENSE, affine_term(1, x))
        ci = RMOI.add_constraint(
            nonpositive_penalty,
            affine_function(affine_term(1, x)),
            RMOI.EqualTo(1.0),
        )
        for invalid_penalty in (0.0, -1.0, Inf, NaN)
            hinted = HintedModel(nonpositive_penalty, Dict{Any,Float64}(ci => invalid_penalty))
            @test_throws ErrorException reformulate(hinted)
        end
    end
end
