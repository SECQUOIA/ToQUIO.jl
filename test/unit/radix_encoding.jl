@testset "Exact bounded-tail radix encoding" begin
    @testset "parameters, allocation guards and wide integer construction" begin
        for cap in (false, 0, 1, -2, 2.5, Inf, NaN)
            @test_throws ArgumentError ToQUIO.RadixEncoding(; levels = cap)
        end
        for limit in (false, 0, -1, 1.5, big(typemax(Int)) + 1)
            @test_throws ArgumentError ToQUIO.RadixEncoding(; max_digits = limit)
        end
        strategy = ToQUIO.RadixEncoding()
        @test strategy.levels == 4 && strategy.max_digits == 256
        @test ToQUIO.encoding_descriptor(strategy) == Dict(
            "name" => "radix", "construction" => "exact-bounded-tail-v1",
            "levels" => 4, "max_digits" => 256)
        @test_throws ArgumentError ToQUIO.variable_encoding(strategy, 3, 2; context = nothing)
        @test_throws ArgumentError ToQUIO.variable_encoding(strategy, false, 2; context = nothing)
        @test_throws ArgumentError ToQUIO.variable_encoding(
            ToQUIO.RadixEncoding(; levels = 2, max_digits = 3), 0, 2^20; context = nothing)
        wide = ToQUIO.variable_encoding(strategy, -(big(2)^90), 0; context = nothing)
        @test wide.offset == -(big(2)^90)
        @test sum(big.(wide.weights) .* wide.upper_bounds) == big(2)^90
        @test all(wide.upper_bounds .< 4)
        for (width, weights, uppers) in ((0, Int[], Int[]), (2, [1], [2]),
                                       (4, [1, 1], [3, 1]), (7, [1, 4], [3, 1]),
                                       (14, [1, 4, 3], [3, 2, 1]))
            layout = ToQUIO.variable_encoding(strategy, -3, -3 + width; context = nothing)
            @test layout.weights == weights && layout.upper_bounds == uppers
        end
        binary = ToQUIO.variable_encoding(ToQUIO.RadixEncoding(; levels = 2), 0, 6; context = nothing)
        @test binary.weights == [1, 2, 3] && binary.upper_bounds == [1, 1, 1]
    end

    @testset "exhaustive tiny images and canonical lifts" begin
        for lower in (-7, 0, 5), width in 0:32, levels in 2:6
            strategy = ToQUIO.RadixEncoding(; levels)
            layout = ToQUIO.variable_encoding(strategy, lower, lower + width; context = nothing)
            @test layout.offset == lower
            @test all(1 .<= layout.upper_bounds .< levels)
            @test sum(big.(layout.weights) .* layout.upper_bounds; init = big(0)) == width
            # Reserve the complete product before enumeration; no state-space materialization.
            assignments = prod(big(m) + 1 for m in layout.upper_bounds; init = big(1))
            assignments <= 10_000 || throw(ArgumentError("Radix test enumeration exceeds its budget."))
            @test assignments <= 10_000
            images = Set{BigInt}()
            for digits in Iterators.product((0:m for m in layout.upper_bounds)...)
                value = big(lower) + sum(big(w) * d for (w, d) in zip(layout.weights, digits); init = big(0))
                @test lower <= value <= lower + width
                push!(images, value)
                @test ToQUIO._decode_layout(layout, collect(digits)) == value
            end
            @test images == Set(big(lower):big(lower + width))
            for value in lower:(lower + width)
                digits = ToQUIO._canonical_digits(layout, value)
                @test all(0 .<= digits .<= layout.upper_bounds)
                @test lower + sum(big(w) * d for (w, d) in zip(layout.weights, digits); init = big(0)) == value
            end
        end
    end

    @testset "compiled parity and every global optimum under sufficient source penalties" begin
        for sense in (RMOI.MIN_SENSE, RMOI.MAX_SENSE), levels in 2:5
            source, x, y, fixed, _, _ = encoding_fixture(sense)
            ci = RMOI.ConstraintIndex{RMOI.VariableIndex,RMOI.Interval{Float64}}(x.value)
            RMOI.set(source, RMOI.ConstraintSet(), ci, RMOI.Interval(-3.0, 4.0))
            optimizer = ToQUIO.Optimizer(; encoding = ToQUIO.RadixEncoding(; levels))
            RMOI.optimize!(optimizer, source)
            data = optimizer.data
            @test data[:rho] == data[:rho_auto]
            metadata = ToQUIO.reformulation_metadata(optimizer)
            @test metadata["encoding"]["strategy"]["levels"] == levels
            @test [e["role"] for e in metadata["native_variables"]] ==
                  ["original", "original", "original", "slack", "slack"]
            @test all(data[:encoded_u] .< levels)
            @test isempty(data[:encoding_digit_positions][3])
            native_lower, native_upper = [-3, 0, 2, 0, 0], [4, 1, 2, 4, 5]
            @test data[:l] == native_lower && data[:u] == native_upper
            count = prod(BigInt(u) + 1 for u in data[:encoded_u]; init = big(1))
            count <= 10_000 || throw(ArgumentError("Radix test enumeration exceeds its budget."))
            @test count <= 10_000
            original(xv, yv) = 2xv^2 + 3xv*yv + yv^2 + 10xv - 4yv + 7
            feasible_objectives = [original(xv, yv) for xv in -3:4 for yv in 0:1
                                   if xv <= yv && xv + yv >= 0]
            source_best = sense == RMOI.MIN_SENSE ? minimum(feasible_objectives) : maximum(feasible_objectives)
            best = sense == RMOI.MIN_SENSE ? Inf : -Inf
            best_points = Vector{Int}[]
            images = Set{Tuple}()
            sign = sense == RMOI.MIN_SENSE ? 1 : -1
            for digits in Iterators.product((0:Int(u) for u in data[:encoded_u])...)
                d = collect(digits)
                # Evaluate the declared affine layouts directly, independently of result helpers.
                z = [Int(layout.offset + sum(big(w) * d[p] for (w, p) in zip(layout.weights, positions);
                                            init = big(0)))
                     for (layout, positions) in zip(data[:encoding_layouts], data[:encoding_digit_positions])]
                push!(images, Tuple(z))
                @test ToQUIO.project_native_state(optimizer, d) == z
                @test ToQUIO.project_original_state(metadata, d) == Dict(x.value => z[1], y.value => z[2],
                                                                       fixed.value => 2)
                expected = original(z[1], z[2]) + sign * (
                    data[:rho][1] * (z[1] - z[2] + z[4])^2 +
                    data[:rho][2] * (-z[1] - z[2] + z[5])^2)
                energy = encoded_value(optimizer.target_model, data, d)
                @test energy == expected
                better = sense == RMOI.MIN_SENSE ? energy < best : energy > best
                if better
                    best = energy
                    empty!(best_points)
                end
                energy == best && push!(best_points, z)
            end
            @test images == Set(Tuple(z) for z in Iterators.product(
                (l:u for (l, u) in zip(native_lower, native_upper))...))
            @test best == source_best
            @test !isempty(best_points)
            @test all(z[1] <= z[2] && z[1] + z[2] >= 0 && original(z[1], z[2]) == source_best
                      for z in best_points)
            for state in Iterators.product((l:u for (l, u) in zip(native_lower, native_upper))...)
                z = collect(state)
                @test ToQUIO.project_native_state(optimizer, ToQUIO.lift_native_state(metadata, z)) == z
            end
        end
    end

    @testset "invalid source domains and arithmetic never reach the backend" begin
        for (lower, upper, integer, expected_error) in (
            (0.2, 0.8, true, ArgumentError), (-Inf, 2, true, ArgumentError),
            (0, Inf, true, ArgumentError), (0, NaN, true, ArgumentError),
            (0, 2, false, ErrorException),
        )
            source = RMOI.Utilities.Model{Float64}()
            x = RMOI.add_variable(source)
            RMOI.add_constraint(source, x, RMOI.Interval(Float64(lower), Float64(upper)))
            integer && RMOI.add_constraint(source, x, RMOI.Integer())
            set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
            called = Ref(false)
            backend = multi_result_backend([zeros(1)])
            RMOI.Utilities.set_mock_optimize!(backend, _ -> (called[] = true))
            optimizer = ToQUIO.Optimizer(() -> backend; encoding = ToQUIO.RadixEncoding())
            failure = try
                RMOI.optimize!(optimizer, source)
                nothing
            catch caught
                caught
            end
            @test failure isa expected_error
            if !isfinite(lower) || !isfinite(upper)
                @test failure isa ArgumentError &&
                      failure.msg == "Integer encoding requires finite native variable bounds."
            end
            @test !called[] && isempty(optimizer.data) && isnothing(optimizer.target_model)
        end
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 2.0^56)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        # A single digit bound 2^56-1 cannot be exactly represented in Float64.
        strategy = ToQUIO.RadixEncoding(; levels = big(2)^56)
        @test_throws ArgumentError RMOI.optimize!(ToQUIO.Optimizer(; encoding = strategy), source)
        @test_throws ArgumentError RMOI.optimize!(ToQUIO.Optimizer(;
            encoding = ToQUIO.RadixEncoding(; levels = 2), max_encoded_variables = 2), source)
    end

    @testset "documented JuMP example structure without optional dependencies" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, -2, 5)
        y = add_binary_variable(source)
        fixed = RMOI.add_variable(source)
        RMOI.add_constraint(source, fixed, RMOI.EqualTo(2.0))
        RMOI.add_constraint(source, fixed, RMOI.Integer())
        RMOI.add_constraint(source, affine_function(affine_term(1, x), affine_term(1, y)),
                            RMOI.LessThan(3.0))
        set_affine_objective!(source, RMOI.MAX_SENSE,
                             affine_term(3, x), affine_term(2, y), affine_term(1, fixed))
        baseline = nothing
        strategies = (ToQUIO.NativeEncoding(), ToQUIO.RadixEncoding(; levels = 4),
                      ToQUIO.RadixEncoding(; levels = 2))
        for (encoding, count, levels) in zip(strategies, [4, 5, 7], [8, 4, 2])
            optimizer = ToQUIO.Optimizer(; encoding)
            RMOI.optimize!(optimizer, source)
            saved = ToQUIO.reformulation_metadata(optimizer)
            @test RMOI.get(optimizer.target_model, RMOI.NumberOfVariables()) == count
            @test maximum(saved["target_upper_bounds"] .- saved["target_lower_bounds"] .+ 1) == levels
            isnothing(baseline) && (baseline = copy(optimizer.data[:rho]))
            @test optimizer.data[:rho] == baseline
            digits = ToQUIO.lift_native_state(optimizer, [1, 1, 2, 1])
            @test ToQUIO.project_native_state(optimizer, digits) == [1, 1, 2, 1]
            @test encoded_value(optimizer.target_model, optimizer.data, digits) == 3*1 + 2*1 + 2 == 7
            @test ToQUIO.is_feasible(optimizer, digits)
        end
    end
end
