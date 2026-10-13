function penalty_fixture(; sense = RMOI.MIN_SENSE)
    source = RMOI.Utilities.Model{Float64}()
    x = add_interval_integer_variable(source, 0, 3)
    set_affine_objective!(source, sense, affine_term(2, x); constant = 1)
    eq = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.EqualTo(1.0))
    return source, x, eq
end

@testset "Penalty controls and applied queries" begin
    @testset "defaults and offset/scale composition" begin
        source, x, ci = penalty_fixture()
        _, defaults = reformulate(source)
        optimizer = ToQUIO.Optimizer()
        @test RMOI.supports(optimizer, ToQUIO.PenaltyScale())
        @test RMOI.supports(optimizer, ToQUIO.PenaltyOffset())
        @test RMOI.get(optimizer, ToQUIO.PenaltyScale()) == 1.0
        @test RMOI.get(optimizer, ToQUIO.PenaltyOffset()) == 1.0
        @test_throws RMOI.GetAttributeNotAllowed RMOI.get(optimizer, ToQUIO.AppliedPenalty(), ci)
        RMOI.optimize!(optimizer, source)
        @test RMOI.is_set_by_optimize(ToQUIO.AppliedPenalty())
        @test RMOI.get(optimizer, ToQUIO.AppliedPenalty(), ci) == 7.0
        @test defaults[:Q] == reshape([7.0], 1, 1)
        @test defaults[:L] == [-12.0]
        @test defaults[:c] == 8.0
        @test optimizer.data[:Q] == defaults[:Q]
        @test optimizer.data[:L] == defaults[:L]
        @test optimizer.data[:c] == defaults[:c]

        RMOI.set(optimizer, ToQUIO.PenaltyOffset(), 2)
        RMOI.set(optimizer, ToQUIO.PenaltyScale(), 2)
        @test RMOI.get(optimizer, ToQUIO.AppliedPenalty(), ci) == 7.0 # Previous compile.
        RMOI.optimize!(optimizer, source)
        @test optimizer.data[:rho_auto] == [8.0]
        @test RMOI.get(optimizer, ToQUIO.AppliedPenalty(), ci) == 16.0
        @test optimizer.data[:Q] == reshape([16.0], 1, 1)
        @test optimizer.data[:L] == [-30.0]
        @test optimizer.data[:c] == 17.0
        metadata = ToQUIO.reformulation_metadata(optimizer)
        @test metadata["penalty_controls"] == Dict("offset" => 2.0, "scale" => 2.0)
        @test only(metadata["constraint_encodings"])["automatic_penalty"] == 8.0
        @test only(metadata["constraint_encodings"])["applied_penalty"] == 16.0
        @test ToQUIO.reformulation_metadata(parsed_metadata_shape(metadata)) == metadata
        invalid = deepcopy(metadata)
        invalid["penalty_controls"]["scale"] = false
        @test_throws ArgumentError ToQUIO.reformulation_metadata(invalid)

        RMOI.set(optimizer, ToQUIO.PenaltyScale(), nothing)
        RMOI.set(optimizer, ToQUIO.PenaltyOffset(), nothing)
        RMOI.optimize!(optimizer, source)
        @test optimizer.data[:Q] == defaults[:Q]
        @test optimizer.data[:L] == defaults[:L]
        @test optimizer.data[:c] == defaults[:c]
        bad_ci = RMOI.ConstraintIndex{SAF64,RMOI.EqualTo{Float64}}(99)
        @test_throws RMOI.InvalidIndex RMOI.get(optimizer, ToQUIO.AppliedPenalty(), bad_ci)
        bound_ci = RMOI.ConstraintIndex{RMOI.VariableIndex,RMOI.Interval{Float64}}(x.value)
        @test !RMOI.supports(optimizer, ToQUIO.AppliedPenalty(), typeof(bound_ci))
        @test_throws RMOI.GetAttributeNotAllowed RMOI.get(optimizer, ToQUIO.AppliedPenalty(), bound_ci)
    end

    @testset "matched sweep and exact hints" begin
        source, _, ci = penalty_fixture()
        optimizer = ToQUIO.Optimizer()
        for scale in (0.5, 1.0, 2.0)
            RMOI.set(optimizer, ToQUIO.PenaltyScale(), scale)
            if scale < 1
                @test_logs (:warn, r"Applied automatic penalty is below") RMOI.optimize!(optimizer, source)
            else
                @test_logs RMOI.optimize!(optimizer, source)
            end
            @test optimizer.data[:rho_auto] == [7.0]
            @test RMOI.get(optimizer, ToQUIO.AppliedPenalty(), ci) == 7.0 * scale
            @test penalized_value(optimizer.data, [2]) == 5 + 7 * scale
        end
        hinted = HintedModel(source, Dict{Any,Float64}(ci => 100.0))
        configured = ToQUIO.Optimizer(; penalty_offset = 2, penalty_scale = 2)
        RMOI.optimize!(configured, hinted)
        @test RMOI.get(configured, ToQUIO.AppliedPenalty(), ci) == 100.0
        @test configured.data[:rho_auto] == [8.0]
        @test configured.data[:penalty_hints] == [100.0]
        _, direct = ToQUIO.to_quio(Float64, vi -> vi.value, ci -> ci.value, source;
                                  ϵ = 2.0, penalty_scale = 2.0)
        @test direct[:rho] == [16.0]
        @test direct[:rho_auto] == [8.0]
        RMOI.set(configured, ToQUIO.PenaltyScale(), 0.5)
        @test_logs RMOI.optimize!(configured, hinted) # No automatic penalty was scaled.
        @test RMOI.get(configured, ToQUIO.AppliedPenalty(), ci) == 100.0
    end

    @testset "global warning count is independent of row count" begin
        source, x, _ = penalty_fixture()
        RMOI.add_constraint(source, affine_function(affine_term(-1, x)), RMOI.EqualTo(-1.0))
        RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.LessThan(2.0))
        RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.GreaterThan(1.0))
        optimizer = ToQUIO.Optimizer(; penalty_scale = 0.5)
        @test_logs (
            :warn, r"Applied automatic penalty is below",
        ) (
            :warn, r"Applied automatic penalty is below",
        ) RMOI.optimize!(optimizer, source)
        @test optimizer.data[:rho] == fill(3.5, 4)
    end

    @testset "both inequality signs and maximization" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MAX_SENSE, affine_term(2, x); constant = 1)
        lt = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.LessThan(2.0))
        gt = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.GreaterThan(1.0))
        optimizer = ToQUIO.Optimizer(; penalty_offset = 2, penalty_scale = 2)
        RMOI.optimize!(optimizer, source)
        @test RMOI.get(optimizer, ToQUIO.AppliedPenalty(), lt) == 16.0
        @test RMOI.get(optimizer, ToQUIO.AppliedPenalty(), gt) == 16.0
        @test RMOI.get(optimizer.target_model, RMOI.ObjectiveSense()) == RMOI.MAX_SENSE
        for value in 0:3, slack_lt in 0:2, slack_gt in 0:2
            expected = 2value + 1 - 16(value + slack_lt - 2)^2 - 16(-value + slack_gt + 1)^2
            @test penalized_value(optimizer.data, [value, slack_lt, slack_gt]) == expected
        end
    end

    @testset "caching optimizer interface and persistent settings" begin
        cache = RMOI.Utilities.CachingOptimizer(
            RMOI.Utilities.UniversalFallback(RMOI.Utilities.Model{Float64}()),
            ToQUIO.Optimizer(),
        )
        x = add_interval_integer_variable(cache, 0, 3)
        set_affine_objective!(cache, RMOI.MIN_SENSE, affine_term(2, x))
        ci = RMOI.add_constraint(cache, affine_function(affine_term(1, x)), RMOI.EqualTo(1.0))
        RMOI.set(cache, ToQUIO.PenaltyScale(), 2.0)
        RMOI.optimize!(cache)
        @test RMOI.get(cache, ToQUIO.AppliedPenalty(), ci) == 14.0
        @test RMOI.get(cache, ToQUIO.PenaltyScale()) == 2.0
        optimizer = ToQUIO.Optimizer(; penalty_offset = 3, penalty_scale = 2)
        RMOI.empty!(optimizer)
        @test RMOI.get(optimizer, ToQUIO.PenaltyOffset()) == 3.0
        @test RMOI.get(optimizer, ToQUIO.PenaltyScale()) == 2.0
        legacy = ToQUIO.Optimizer{Float64,Nothing}(nothing, nothing, nothing, Dict{Symbol,Any}())
        @test RMOI.get(legacy, ToQUIO.PenaltyScale()) == 1.0
    end

    @testset "invalid controls and overflow" begin
        source, _, _ = penalty_fixture()
        optimizer = ToQUIO.Optimizer()
        for value in (0.0, -1.0, Inf, NaN, true, "2")
            @test_throws ArgumentError RMOI.set(optimizer, ToQUIO.PenaltyScale(), value)
            @test_throws ArgumentError RMOI.set(optimizer, ToQUIO.PenaltyOffset(), value)
            @test_throws ArgumentError ToQUIO.Optimizer(; penalty_scale = value)
            @test_throws ArgumentError ToQUIO.Optimizer(; penalty_offset = value)
            called = Ref(false)
            factory = () -> begin
                called[] = true
                return mock_backend_with_primal([0])
            end
            @test_throws ArgumentError ToQUIO.Optimizer(factory; penalty_scale = value)
            @test !called[]
            @test_throws ArgumentError ToQUIO.Optimizer(factory; penalty_offset = value)
            @test !called[]
            @test_throws ArgumentError ToQUIO.to_quio(
                Float64, vi -> vi.value, ci -> ci.value, source; ϵ = value,
            )
        end
        @test RMOI.get(optimizer, ToQUIO.PenaltyScale()) == 1.0
        @test RMOI.get(optimizer, ToQUIO.PenaltyOffset()) == 1.0
        @test_throws ArgumentError ToQUIO.to_quio(
            Float64, vi -> vi.value, ci -> ci.value, source; penalty_scale = 1e308,
        )
        @test_throws ArgumentError ToQUIO.to_quio(
            Float64, vi -> vi.value, ci -> ci.value, source; ϵ = 1e308,
        )
        typed = ToQUIO.Optimizer{BigFloat}(; penalty_scale = big"2.0", penalty_offset = big"1.5")
        @test RMOI.get(typed, ToQUIO.PenaltyScale()) == big"2.0"
        @test RMOI.get(typed, ToQUIO.PenaltyScale()) isa BigFloat
        @test RMOI.get(typed, ToQUIO.PenaltyOffset()) == big"1.5"
        big_source = RMOI.Utilities.Model{BigFloat}()
        x = RMOI.add_variable(big_source)
        RMOI.add_constraint(big_source, x, RMOI.Interval(big"0.0", big"3.0"))
        RMOI.add_constraint(big_source, x, RMOI.Integer())
        f = RMOI.ScalarAffineFunction([RMOI.ScalarAffineTerm(big"2.0", x)], big"1.0")
        RMOI.set(big_source, RMOI.ObjectiveSense(), RMOI.MIN_SENSE)
        RMOI.set(big_source, RMOI.ObjectiveFunction{typeof(f)}(), f)
        ci = RMOI.add_constraint(big_source,
            RMOI.ScalarAffineFunction([RMOI.ScalarAffineTerm(big"1.0", x)], big"0.0"),
            RMOI.EqualTo(big"1.0"))
        RMOI.optimize!(typed, big_source)
        @test RMOI.get(typed, ToQUIO.AppliedPenalty(), ci) == big"15.0"
        @test typed.data[:rho_auto] == [big"7.5"]
    end
end
