# Deliberately test-only: the production radix/bounded strategies are later issues.
struct TestDigits <: ToQUIO.AbstractIntegerEncoding end
function ToQUIO.variable_encoding(::TestDigits, lower, upper; context)
    width = Int(upper - lower)
    return ToQUIO.IntegerVariableEncoding(lower, ones(Int, width), ones(Int, width))
end
ToQUIO.encoding_descriptor(::TestDigits) = Dict{String,Any}("name" => "test-digits", "weight" => 1)

struct TranslatedIdentity <: ToQUIO.AbstractIntegerEncoding end
ToQUIO.variable_encoding(::TranslatedIdentity, lower, upper; context) =
    ToQUIO.variable_encoding(ToQUIO.NativeEncoding(), lower, upper; context)

struct TestWeightedDigits <: ToQUIO.AbstractIntegerEncoding end
function ToQUIO.variable_encoding(::TestWeightedDigits, lower, upper; context)
    width = upper - lower
    width == 4 && return ToQUIO.IntegerVariableEncoding(lower, [2, 1], [1, 2])
    width == 3 && return ToQUIO.IntegerVariableEncoding(lower, [2, 1], [1, 1])
    return ToQUIO.variable_encoding(ToQUIO.NativeEncoding(), lower, upper; context)
end

struct WrongInterval <: ToQUIO.AbstractIntegerEncoding end
ToQUIO.variable_encoding(::WrongInterval, lower, upper; context) =
    ToQUIO.IntegerVariableEncoding(lower + 1, [1], [1])

struct BadDescriptor <: ToQUIO.AbstractIntegerEncoding end
ToQUIO.variable_encoding(::BadDescriptor, lower, upper; context) =
    ToQUIO.variable_encoding(ToQUIO.NativeEncoding(), lower, upper; context)
ToQUIO.encoding_descriptor(::BadDescriptor) = Dict("bad" => Inf)

struct CountedHints <: RMOI.ModelLike
    inner::HintedModel{Float64}
    calls::Base.RefValue{Int}
end
RMOI.get(m::CountedHints, a::RMOI.AbstractModelAttribute) = RMOI.get(m.inner, a)
RMOI.get(m::CountedHints, a::RMOI.AbstractVariableAttribute, v::RMOI.VariableIndex) = RMOI.get(m.inner, a, v)
RMOI.get(m::CountedHints, a::RMOI.AbstractConstraintAttribute, c::RMOI.ConstraintIndex) =
    RMOI.get(m.inner, a, c)
function RMOI.get(m::CountedHints, a::ToQUIO.ConstraintPenaltyHint, c::RMOI.ConstraintIndex)
    m.calls[] += 1
    return RMOI.get(m.inner, a, c)
end
RMOI.supports(m::CountedHints, a::ToQUIO.ConstraintPenaltyHint, c::Type{<:RMOI.ConstraintIndex}) =
    RMOI.supports(m.inner, a, c)

function encoding_fixture(sense)
    source = RMOI.Utilities.Model{Float64}()
    removed = add_interval_integer_variable(source, 0, 1)
    x = add_interval_integer_variable(source, -1, 1)
    y = add_binary_variable(source)
    fixed = add_interval_integer_variable(source, 2, 2)
    RMOI.delete(source, removed)
    set_quadratic_objective!(source, sense,
        [quadratic_term(4, x, x), quadratic_term(3, x, y),
         quadratic_term(2, y, y), quadratic_term(5, fixed, x)],
        [affine_term(-4, y)]; constant = 7)
    lt = RMOI.add_constraint(source,
        affine_function(affine_term(1, x), affine_term(-1, y)), RMOI.LessThan(0.0))
    gt = RMOI.add_constraint(source,
        affine_function(affine_term(1, x), affine_term(1, y)), RMOI.GreaterThan(0.0))
    return source, x, y, fixed, lt, gt
end

function encoded_value(target, data, digits)
    variables = RMOI.get(target, RMOI.ListOfVariableIndices())
    positions = Dict(vi => i for (i, vi) in enumerate(variables))
    F = RMOI.get(target, RMOI.ObjectiveFunctionType())
    f = RMOI.get(target, RMOI.ObjectiveFunction{F}())
    return RMOI.Utilities.eval_variables(vi -> digits[positions[vi]], f)
end

@testset "Exact encoding interface and composed decoding" begin
    @testset "default path and validation before backend construction" begin
        source, _, _, _, _, _ = encoding_fixture(RMOI.MIN_SENSE)
        native = ToQUIO.Optimizer()
        explicit = ToQUIO.Optimizer(; encoding = ToQUIO.NativeEncoding(), max_encoded_variables = 1)
        RMOI.optimize!(native, source)
        RMOI.optimize!(explicit, source)
        @test ToQUIO.reformulation_metadata(native) == ToQUIO.reformulation_metadata(explicit)
        @test !haskey(explicit.data, :encoded_variables)
        @test RMOI.get(native, ToQUIO.EncodingStrategy()) isa ToQUIO.NativeEncoding
        @test RMOI.supports(native, ToQUIO.EncodingStrategy())
        @test RMOI.supports(native, ToQUIO.MaxEncodedVariables())
        for parameters in ((; encoding = 1), (; max_encoded_variables = false),
                           (; max_encoded_variables = 0), (; max_encoded_variables = 1.0))
            constructed = Ref(false)
            @test_throws ArgumentError ToQUIO.Optimizer(() -> (constructed[] = true); parameters...)
            @test !constructed[]
        end
        for args in ((0, [2], [1]), (0, [0], [1]), (0, [1], [0]),
                     (0.0, [1], [1]), (false, [1], [1]))
            @test_throws ArgumentError ToQUIO.IntegerVariableEncoding(args...)
        end
        @test_throws DimensionMismatch ToQUIO.IntegerVariableEncoding(0, [1], Int[])
        map = ToQUIO.IntegerVariableEncoding(-2, [2, 1], [1, 1])
        @test ToQUIO._canonical_digits(map, 0) == [1, 0]
        @test ToQUIO._decode_layout(map, [1, 0]) == 0
        @test ToQUIO._decode_layout(
            ToQUIO.IntegerVariableEncoding(typemax(Int), [1], [1]), [1]) == big(typemax(Int)) + 1
    end

    @testset "all-state independent objective parity and exact image" begin
        for sense in (RMOI.MIN_SENSE, RMOI.MAX_SENSE)
            source, x, y, fixed, lt, gt = encoding_fixture(sense)
            varmap = vi -> vi == x ? 2 : vi == y ? 1 : 3
            conmap = ci -> 1
            native, baseline = ToQUIO.to_quio(Float64, varmap, conmap, source)
            target, data = ToQUIO.to_quio(Float64, varmap, conmap, source; encoding = TestDigits())
            @test baseline[:Q] != baseline[:Q]'
            for key in (:n, :Q, :L, :c, :D, :rho, :rho_auto, :penalty_hints,
                        :l, :u, :source_to_target_variables, :quio_variables)
                @test data[key] == baseline[key]
            end
            @test RMOI.get(target, RMOI.ObjectiveSense()) == sense
            @test data[:encoded_n] == 7
            @test ToQUIO.original_variables(data) == [x, y, fixed]
            @test data[:source_to_target_variables][x] isa RMOI.VariableIndex
            metadata = ToQUIO.reformulation_metadata(data)
            @test metadata["schema_version"] == 2
            @test metadata["native_reformulation"] == ToQUIO.reformulation_metadata(baseline)
            @test metadata_is_json_value(metadata)
            @test ToQUIO.auxiliary_variables(data) == data[:encoded_variables][4:7]
            @test metadata["auxiliary_variables"] == [4, 5, 6, 7]
            @test metadata["native_variables"][4]["source_constraint"] == ToQUIO._constraint_identity(lt)
            @test metadata["native_variables"][5]["source_constraint"] == ToQUIO._constraint_identity(gt)
            parsed = parsed_metadata_shape(metadata)
            images = Set{Tuple}()
            sigma = sense == RMOI.MIN_SENSE ? 1 : -1
            for state in Iterators.product(ntuple(_ -> 0:1, 7)...)
                digits = collect(state)
                z = ToQUIO.project_native_state(data, digits)
                push!(images, Tuple(z))
                values = ToQUIO.project_original_state(data, digits)
                @test values == Dict(x => z[2], y => z[1], fixed => 2)
                # Independent source expression plus both canonical residuals;
                # this detects offset, cross-term, constant and max-sign losses.
                xv, yv = values[x], values[y]
                original = 2xv^2 + 3xv*yv + yv^2 + 10xv - 4yv + 7
                expected = original + sigma * (
                    data[:rho][1] * (xv - yv + z[4])^2 +
                    data[:rho][2] * (-xv - yv + z[5])^2)
                @test encoded_value(target, data, digits) == expected
                @test penalized_value(baseline, z) == expected
                @test ToQUIO.project_native_state(parsed, digits) == z
                @test ToQUIO.project_original_state(parsed, digits) == Dict(v.value => p for (v, p) in values)
                @test ToQUIO.is_feasible(data, digits) == (xv <= yv && xv + yv >= 0)
                lifted = ToQUIO.lift_native_state(data, z)
                @test ToQUIO.project_native_state(data, lifted) == z
            end
            @test images == Set(Tuple(z) for z in Iterators.product(0:1, -1:1, 2:2, 0:2, 0:2))
            @test_throws ArgumentError ToQUIO.is_feasible(parsed, zeros(7))
            @test_throws DimensionMismatch ToQUIO.project_original_state(data, zeros(5))
            @test_throws ArgumentError ToQUIO.project_native_state(data, fill(NaN, 7))
            @test_throws ArgumentError ToQUIO.lift_native_state(data, [0, 0.5, 2, 0, 0])
        end
    end

    @testset "penalty hints read once and preserved verbatim" begin
        source, _, _, _, lt, gt = encoding_fixture(RMOI.MIN_SENSE)
        counted = CountedHints(HintedModel(source, Dict{Any,Float64}(lt => 100.0, gt => 200.0)), Ref(0))
        optimizer = ToQUIO.Optimizer(; encoding = TestDigits(), penalty_offset = 3, penalty_scale = 0.1)
        RMOI.optimize!(optimizer, counted)
        @test counted.calls[] == 2
        @test optimizer.data[:rho] == [100.0, 200.0]
        @test RMOI.get(optimizer, ToQUIO.AppliedPenalty(), lt) == 100
        @test RMOI.get(optimizer, ToQUIO.AppliedPenalty(), gt) == 200
        @test ToQUIO.reformulation_metadata(optimizer)["native_reformulation"]["penalty_controls"] ==
              Dict("offset" => 3.0, "scale" => 0.1)
    end

    @testset "compiled nonunit weights, nonbinary bounds and independent decoding" begin
        for sense in (RMOI.MIN_SENSE, RMOI.MAX_SENSE)
            source, x, y, fixed, _, _ = encoding_fixture(sense)
            bounds = RMOI.ConstraintIndex{RMOI.VariableIndex,RMOI.Interval{Float64}}(x.value)
            RMOI.set(source, RMOI.ConstraintSet(), bounds, RMOI.Interval(-2.0, 2.0))
            varmap = vi -> vi == x ? 2 : vi == y ? 1 : 3
            target, data = ToQUIO.to_quio(Float64, varmap, _ -> 1, source;
                                        encoding = TestWeightedDigits())
            expected_uppers = [1, 1, 2, 1, 1, 1, 1]
            @test data[:encoded_u] == expected_uppers
            for (vi, upper) in zip(data[:encoded_variables], expected_uppers)
                ci = RMOI.ConstraintIndex{RMOI.VariableIndex,RMOI.Interval{Float64}}(vi.value)
                @test RMOI.get(target, RMOI.ConstraintSet(), ci) == RMOI.Interval(0.0, Float64(upper))
            end
            metadata = ToQUIO.reformulation_metadata(data)
            images = Set{Tuple}()
            sign = sense == RMOI.MIN_SENSE ? 1 : -1
            for state in Iterators.product((0:u for u in expected_uppers)...)
                d = collect(state)
                # Hand-written coordinate map, independent of all compiler/decode helpers.
                z = [d[1], -2 + 2d[2] + d[3], 2, 2d[4] + d[5], 2d[6] + d[7]]
                push!(images, Tuple(z))
                @test ToQUIO.project_native_state(data, d) == z
                @test ToQUIO.project_native_state(metadata, d) == z
                @test ToQUIO.project_original_state(data, d) == Dict(x => z[2], y => z[1], fixed => 2)
                xv, yv = z[2], z[1]
                expected = 2xv^2 + 3xv*yv + yv^2 + 10xv - 4yv + 7 + sign * (
                    data[:rho][1] * (xv - yv + z[4])^2 +
                    data[:rho][2] * (-xv - yv + z[5])^2)
                @test encoded_value(target, data, d) == expected
                @test ToQUIO.is_feasible(data, d) == (xv <= yv && xv + yv >= 0)
            end
            @test images == Set(Tuple(z) for z in Iterators.product(0:1, -2:2, 2:2, 0:3, 0:3))
            shifted = ToQUIO.Optimizer(; encoding = TranslatedIdentity())
            RMOI.optimize!(shifted, source)
            @test shifted.data[:encoded_u] == [4, 1, 3, 3]
            for d in Iterators.product(0:4, 0:1, 0:3, 0:3)
                state = collect(d)
                z = [-2 + d[1], d[2], 2, d[3], d[4]]
                @test ToQUIO.project_native_state(shifted, state) == z
                @test encoded_value(shifted.target_model, shifted.data, state) == penalized_value(shifted.data, z)
            end
        end
    end

    @testset "backend remapping, results and source versus target objective" begin
        source, x, y, fixed, _, _ = encoding_fixture(RMOI.MIN_SENSE)
        compiled = ToQUIO.Optimizer(; encoding = TestDigits())
        RMOI.optimize!(compiled, source)
        states = [ToQUIO.lift_native_state(compiled, z) for z in ([0, 1, 2, 1, 1], [1, 0, 2, 0, 0])]
        optimizer = ToQUIO.Optimizer(() -> multi_result_backend(states); encoding = TestDigits())
        RMOI.optimize!(optimizer, source)
        @test all(v != backend for (v, backend) in optimizer.data[:target_to_backend_variables])
        @test [RMOI.get(optimizer, RMOI.VariablePrimal(1), v) for v in (x, y, fixed)] == [0, 1, 2]
        @test all(RMOI.get(optimizer, RMOI.VariablePrimal(1), v) isa Float64 for v in (x, y, fixed))
        @test [RMOI.get(optimizer, RMOI.VariablePrimal(2), v) for v in (x, y, fixed)] == [1, 0, 2]
        @test RMOI.get(optimizer, RMOI.ObjectiveValue(1)) == 4
        @test RMOI.get(optimizer, RMOI.ObjectiveValue(2)) == 19
        @test RMOI.get(optimizer, ToQUIO.PenalizedObjectiveValue(2)) ==
              encoded_value(optimizer.target_model, optimizer.data, states[2])
        @test RMOI.get(optimizer, ToQUIO.PenalizedObjectiveValue(2)) != 19
        @test ToQUIO.feasibility_report(optimizer)["feasible_fraction"] == 0.5
        @test_throws RMOI.ResultIndexBoundsError RMOI.get(optimizer, RMOI.VariablePrimal(3), fixed)
        @test_throws RMOI.InvalidIndex RMOI.get(optimizer, RMOI.VariablePrimal(), RMOI.VariableIndex(999))
        previous = optimizer.data
        RMOI.set(optimizer, ToQUIO.EncodingStrategy(), ToQUIO.NativeEncoding())
        RMOI.Utilities.set_mock_optimize!(optimizer.inner, backend ->
            RMOI.Utilities.mock_optimize!(backend, RMOI.OPTIMAL,
                (RMOI.FEASIBLE_POINT, [0.0, 1.0, 2.0, 1.0, 1.0])))
        RMOI.optimize!(optimizer, source)
        @test !haskey(optimizer.data, :encoded_variables)
        @test RMOI.get(optimizer, RMOI.VariablePrimal(), x) == 0
        @test ToQUIO.project_original_state(previous, states[1])[x] == 0
    end

    @testset "weak penalty remains source infeasible after encoding" begin
        source, x, ci = penalty_fixture()
        hinted = HintedModel(source, Dict{Any,Float64}(ci => 0.5))
        compiled = ToQUIO.Optimizer(; encoding = TestDigits())
        @test_logs (:warn, r"Constraint penalty hint") RMOI.optimize!(compiled, hinted)
        states = [collect(s) for s in Iterators.product(0:1, 0:1, 0:1)]
        energies = [encoded_value(compiled.target_model, compiled.data, s) for s in states]
        best = states[argmin(energies)]
        @test ToQUIO.project_original_state(compiled, best)[x] == 0
        @test !ToQUIO.is_feasible(compiled, best)
        optimizer = ToQUIO.Optimizer(() -> multi_result_backend([best]); encoding = TestDigits())
        @test_logs (:warn, r"Constraint penalty hint") RMOI.optimize!(optimizer, hinted)
        @test RMOI.get(optimizer, RMOI.ObjectiveValue()) == 1
        @test RMOI.get(optimizer, ToQUIO.PenalizedObjectiveValue()) == 1.5
        @test !ToQUIO.is_feasible(optimizer)
    end

    @testset "all-fixed model, lifecycle and failure invalidation" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 2, 2)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(3, x); constant = 1)
        optimizer = ToQUIO.Optimizer(() -> multi_result_backend([Int[]]); encoding = TestDigits())
        RMOI.optimize!(optimizer, source)
        @test optimizer.data[:encoded_n] == 0
        @test RMOI.get(optimizer, RMOI.VariablePrimal(), x) == 2
        @test RMOI.get(optimizer, RMOI.VariablePrimal(), x) isa Float64
        @test RMOI.get(optimizer, RMOI.ObjectiveValue()) == 7
        @test RMOI.get(optimizer, ToQUIO.PenalizedObjectiveValue()) == 7
        @test ToQUIO.is_feasible(optimizer)
        @test ToQUIO.lift_native_state(optimizer, [2]) == Int[]
        @test_throws RMOI.ResultIndexBoundsError RMOI.get(optimizer, RMOI.VariablePrimal(0), x)
        RMOI.set(optimizer, ToQUIO.EncodingStrategy(), WrongInterval())
        @test_throws ArgumentError RMOI.optimize!(optimizer, source)
        @test isempty(optimizer.data) && isnothing(optimizer.target_model)
        RMOI.set(optimizer, ToQUIO.EncodingStrategy(), TestDigits())
        RMOI.optimize!(optimizer, source)
        RMOI.empty!(optimizer)
        @test RMOI.get(optimizer, ToQUIO.EncodingStrategy()) isa TestDigits
        @test_throws ArgumentError ToQUIO.project_original_state(optimizer, Int[])
        RMOI.set(optimizer, ToQUIO.EncodingStrategy(), nothing)
        RMOI.set(optimizer, ToQUIO.MaxEncodedVariables(), nothing)
        @test RMOI.get(optimizer, ToQUIO.EncodingStrategy()) isa ToQUIO.NativeEncoding
        @test RMOI.get(optimizer, ToQUIO.MaxEncodedVariables()) == 256
    end

    @testset "malformed snapshots and allocation guard" begin
        source, _, _, _, _, _ = encoding_fixture(RMOI.MIN_SENSE)
        optimizer = ToQUIO.Optimizer(; encoding = TestDigits())
        RMOI.optimize!(optimizer, source)
        metadata = parsed_metadata_shape(ToQUIO.reformulation_metadata(optimizer))
        mutations = [
            m -> (m["native_variables"][1]["expansion"]["offset"] += 1),
            m -> (m["native_variables"][1]["role"] = "slack"),
            m -> (m["native_variables"][4]["source_constraint"]["id"] = 999),
            m -> (m["native_variables"][1]["expansion"]["terms"][1]["coefficient"] = 0),
            m -> (m["native_variables"][1]["expansion"]["terms"][1]["target_position"] = 0),
            m -> (m["target_upper_bounds"][1] = false),
            m -> (m["original_variables"][1]["expansion"]["offset"] += 1),
            m -> (m["auxiliary_variables"] = Any[]),
            m -> (m["encoding"]["penalty_policy"] = "recompute"),
            m -> (m["native_reformulation"]["schema_version"] = 2),
        ]
        for mutate! in mutations
            invalid = deepcopy(metadata)
            mutate!(invalid)
            @test_throws ArgumentError ToQUIO.reformulation_metadata(invalid)
        end
        @test_throws ArgumentError RMOI.optimize!(ToQUIO.Optimizer(; encoding = TestDigits(),
                                                                 max_encoded_variables = 2), source)
        @test_throws ArgumentError RMOI.optimize!(ToQUIO.Optimizer(; encoding = BadDescriptor()), source)
        @test_throws ArgumentError ToQUIO._exact_encoding_number(Float64, big(2)^54 - 1)
    end

    @testset "wide numeric projection, nonfinite samples and overflow rejection" begin
        source = RMOI.Utilities.Model{BigFloat}()
        x = RMOI.add_variable(source)
        RMOI.add_constraint(source, x, RMOI.Interval(big"-2.0", big"1.0"))
        RMOI.add_constraint(source, x, RMOI.Integer())
        f = RMOI.ScalarAffineFunction([RMOI.ScalarAffineTerm(big"1.25", x)], big"0.0")
        RMOI.set(source, RMOI.ObjectiveFunction{typeof(f)}(), f)
        optimizer = ToQUIO.Optimizer{BigFloat}(; encoding = TestDigits())
        RMOI.optimize!(optimizer, source)
        digit = big"0.5" + big"2.0"^(-180)
        state = [digit, big"0.0", big"0.0"]
        decoded = ToQUIO.project_original_state(optimizer, state)[x]
        @test decoded isa BigFloat && decoded == -2 + digit
        @test ToQUIO.project_original_state(ToQUIO.reformulation_metadata(optimizer), state)[x.value] == decoded
        @test_throws ArgumentError ToQUIO.project_original_state(optimizer, [Inf, 0, 0])

        wide = RMOI.Utilities.Model{Float64}()
        v = add_interval_integer_variable(wide, 2.0^64, 2.0^64 + 8192)
        set_affine_objective!(wide, RMOI.MIN_SENSE, affine_term(1, v))
        wide_backend = ToQUIO.Optimizer(() -> multi_result_backend([[1.0]]);
                                       encoding = TranslatedIdentity())
        RMOI.optimize!(wide_backend, wide)
        @test wide_backend.data[:encoding_layouts][1].offset isa BigInt
        @test RMOI.get(wide_backend, RMOI.VariablePrimal(), v) isa BigFloat
        @test RMOI.get(wide_backend, RMOI.VariablePrimal(), v) == big(2)^64 + 1
        @test ToQUIO.project_original_state(wide_backend, [1.0])[v] == big(2)^64 + 1

        small, _, _, _, _, _ = encoding_fixture(RMOI.MIN_SENSE)
        malformed = ToQUIO.Optimizer(() -> multi_result_backend([fill(NaN, 7)]); encoding = TestDigits())
        RMOI.optimize!(malformed, small)
        source_variable = first(ToQUIO.original_variables(malformed))
        @test_throws ArgumentError RMOI.get(malformed, RMOI.VariablePrimal(), source_variable)
        @test_throws ArgumentError ToQUIO.feasibility_report(malformed)

        overflow = RMOI.Utilities.Model{Float64}()
        v = add_interval_integer_variable(overflow, 4, 5)
        set_quadratic_objective!(overflow, RMOI.MIN_SENSE,
            [quadratic_term(floatmax(Float64) / 2, v, v)], RMOI.ScalarAffineTerm{Float64}[])
        called = Ref(false)
        backend = multi_result_backend([zeros(1)])
        RMOI.Utilities.set_mock_optimize!(backend, _ -> (called[] = true))
        guarded = ToQUIO.Optimizer(() -> backend; encoding = TranslatedIdentity())
        @test_throws ArgumentError RMOI.optimize!(guarded, overflow)
        @test !called[] && isempty(guarded.data) && isnothing(guarded.target_model)
    end
end
