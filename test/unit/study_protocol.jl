using TOML

@testset "Frozen CQT study protocol" begin
    specification = TOML.parsefile(joinpath(pkgdir(ToQUIO), "benchmarks", "protocol_v1.toml"))
    families, arms, regimes = specification["families"], specification["arms"], specification["regimes"]
    pilot, tuning, evaluation = specification["pilot"], specification["tuning"], specification["evaluation"]
    warmup, resources = specification["warmup"], specification["resources"]
    @test specification["schema_version"] == 1
    @test length(families) == pilot["instance_count"] == tuning["instance_count"] == 4
    @test sum(length(f["evaluation_seeds"]) for f in families) == evaluation["instance_count"] == 8
    @test length(unique(vcat([f["tuning_seed"] for f in families],
                            [f["evaluation_seeds"] for f in families]...))) == 12
    @test pilot["starts"] == length(families) * length(arms) * length(regimes) * length(pilot["replicate_seeds"])
    @test tuning["starts"] == length(families) * length(tuning["arms"]) *
          length(specification["bounded_weight_candidates"]) * length(tuning["replicate_seeds"])
    @test evaluation["starts"] == evaluation["instance_count"] * length(arms) *
          length(regimes) * length(evaluation["replicate_seeds"])
    @test warmup["starts"] == length(families) * length(arms) * length(regimes)
    @test length(warmup["replicate_seeds"]) == 1
    @test vcat([f["instance_ordinals"] for f in families]...) == collect(1:16)
    stages = (warmup, pilot, tuning, evaluation)
    @test sum(stage["starts"] for stage in stages) == resources["max_sampler_starts"]
    @test sum(stage["starts"] * stage["max_proposals"] for stage in stages) ==
          resources["max_reserved_proposals"]
    @test all(stage["max_sweeps"] >= stage["max_proposals"] for stage in stages)

    # Execute the exact worked example used by the manual, returning its result
    # rather than accessing fresh module globals from an older world.
    proof = Module(:StudyProtocolProof)
    result = Base.include(proof, joinpath(pkgdir(ToQUIO), "benchmarks", "protocol_example.jl"))
    @test result.source_optimum == result.native_optimum == result.binary_optimum == 5
    @test result.automatic_penalty == 9
    @test (result.native_states, result.binary_states, result.decoded_states) == (24, 32, 24)
    @test result.weak_optimum == 7
    @test !result.weak_source_feasible
    layout = Base.invokelatest(getproperty, proof, :protocol_layout)
    lift = Base.invokelatest(getproperty, proof, :protocol_canonical_lift)
    state_count = Base.invokelatest(getproperty, proof, :protocol_state_count)
    substitute = Base.invokelatest(getproperty, proof, :protocol_affine_substitution)
    # Independent DP checks an emitted layout, rather than trusting its formula.
    function reachable_sums(weights, uppers; offset = 0)
        image = Set([big(offset)])
        for (weight, upper) in zip(weights, uppers)
            image = Set(value + weight * digit for value in image for digit in 0:upper)
        end
        return image
    end
    @testset "Exact boxes, offsets, multiplicity and canonical lift" begin
        for width in 0:12, levels in 2:4, cap in (nothing, 1, 2, 4)
            weights, uppers = Base.invokelatest(layout, width; levels, max_weight = cap)
            @test sum(weights .* uppers; init = big(0)) == width
            @test all(upper -> upper + 1 <= levels, uppers)
            @test isnothing(cap) || all(weight -> weight <= cap, weights)
            Base.invokelatest(state_count, uppers; limit = resources["max_states_per_enumeration"])
            image = Set(sum(weights .* collect(d); init = big(0))
                        for d in Iterators.product((big(0):upper for upper in uppers)...))
            @test image == Set(0:width)
            for value in 0:width
                digits = Base.invokelatest(lift, value, weights, uppers)
                @test all(0 .<= digits .<= uppers)
                @test sum(weights .* digits; init = big(0)) == value
            end
        end
        weights, uppers = Base.invokelatest(layout, 2; levels = 2)
        @test weights == [1, 1] && uppers == [1, 1]
        @test_throws ArgumentError Base.invokelatest(layout, -1; levels = 4)
        @test_throws ArgumentError Base.invokelatest(layout, 1; levels = 1)
        @test_throws ArgumentError Base.invokelatest(layout, 1; levels = 4, max_weight = 0)
        @test_throws ArgumentError Base.invokelatest(layout, big(10)^100; levels = 2, max_weight = 1)
        @test_throws ArgumentError Base.invokelatest(state_count, [big(10)^100]; limit = 1_000_000)
        @test_throws ArgumentError Base.invokelatest(state_count, Int[]; limit = 0)
    end
    @testset "Independent coverage and negative-offset decoding through campaign widths" begin
        @test reachable_sums([2], [1]) != Set(0:2) # A deliberately gapped map fails.
        for width in 0:resources["max_native_width"], levels in 2:4, cap in (nothing, 1, 2, 4)
            weights, uppers = Base.invokelatest(layout, width; levels, max_weight = cap)
            offset = -7
            @test reachable_sums(weights, uppers; offset) == Set(offset:(offset + width))
            # Compose negative offsets into the same affine decoder as parity.
            expansion = reshape(weights, 1, :)
            for value in offset:(offset + width)
                digits = Base.invokelatest(lift, value - offset, weights, uppers)
                @test only([offset] + expansion * digits) == value
                @test all(0 .<= digits .<= uppers)
            end
        end
    end
    @testset "Worst-case dimensions for every frozen family, arm, cap and regime" begin
        dimensions = Dict{String,Int}()
        for family in families
            name, size = family["name"], family["campaign_size"]
            widths = if name == "knapsack"
                n = only(size)
                upper = family["quantity_upper"]
                capacity = floor(Int, family["capacity_fraction"] * n * family["weight_max"] * upper)
                [fill(upper, n); capacity]
            elseif name == "facility"
                facilities, clients = size
                # Worst witness load per facility plus margin; assignment<=open
                # rows contribute width1, capacity rows contribute capacity_j.
                capacity = cld(clients, facilities) * family["demand_max"] + family["capacity_witness_margin"]
                [ones(Int, facilities + facilities * clients);
                 ones(Int, facilities * clients); fill(capacity, facilities)]
            elseif name == "inventory"
                periods = only(size)
                upper = family["quantity_upper"]
                [fill(upper, periods); fill(family["stock_upper"], periods);
                 ones(Int, periods); fill(upper, periods)]
            else
                customers, _, capacity = size
                minimum_demand = family["demand_min"]
                [ones(Int, customers * (customers + 1));
                 fill(capacity - minimum_demand, customers);
                 fill(2capacity - 2minimum_demand, customers * (customers - 1))]
            end
            @test maximum(widths) <= resources["max_native_width"]
            worst = 0
            for regime in regimes, arm in arms, cap in specification["bounded_weight_candidates"]
                # Default ToQUBO integer residual GCD scaling/removal can only
                # reduce these affine slack widths; real-ATol maps are refused.
                count = if arm == "native"
                    length(widths)
                else
                    levels = startswith(arm, "toqubo") ? 2 : specification["levels"]
                    max_weight = arm in tuning["arms"] ? cap : nothing
                    sum(length(first(Base.invokelatest(layout, width; levels, max_weight,
                               max_digits = resources["max_target_variables"]))) for width in widths)
                end
                @test count <= resources["max_target_variables"]
                worst = max(worst, count)
            end
            dimensions[name] = worst
        end
        @test dimensions == Dict("knapsack" => 58, "facility" => 48, "inventory" => 52, "cvrp" => 216)
        @test 8resources["max_target_variables"]^2 <= 524288
    end
    @testset "Pinned upstream bounded formula failures and exact shim" begin
        # Arithmetic transcription of pinned Bounded{Binary}: residual d+r,
        # followed by r-1 weight-mu digits. It is not compiler execution.
        function upstream_formula(width, cap)
            r, d = divrem(width, cap)
            residual = d + r
            n = ndigits(residual; base = 2)
            weights = residual == 0 ? Int[] : [2 .^ (0:(n - 2)); residual - 2^(n - 1) + 1]
            append!(weights, fill(cap, max(0, r - 1)))
            return weights, r - 1
        end
        for (width, expected_image, expected_shim) in
            ((3, 0:2, [1, 2]), (6, 0:7, [1, 2, 2, 1]))
            upstream, request = upstream_formula(width, 2)
            @test request >= 0
            @test reachable_sums(upstream, ones(Int, length(upstream))) == Set(expected_image)
            weights, uppers = Base.invokelatest(layout, width; levels = 2, max_weight = 2)
            @test weights == expected_shim
            @test reachable_sums(weights, uppers) == Set(0:width)
        end
        weights, _ = upstream_formula(20, 2)
        @test maximum(weights) == 4 > 2
        @test reachable_sums(weights, ones(Int, length(weights))) == Set(0:28)
        _, negative_request = upstream_formula(1, 2)
        @test negative_request == -1
    end
    @testset "Nonsymmetric MOI matrix convention and overflow" begin
        G, g = [1 3; 0 2], [-2, 4]
        offset, expansion = [-2, 1], [1 1 0; 0 0 1]
        transformed = Base.invokelatest(substitute, G, g, 7, offset, expansion)
        function moi_polynomial(G, g, constant)
            n = length(g)
            quadratic = [RMOI.ScalarQuadraticTerm(2.0 * G[i, i], RMOI.VariableIndex(i), RMOI.VariableIndex(i)) for i in 1:n]
            append!(quadratic, [RMOI.ScalarQuadraticTerm(Float64(G[i, j] + G[j, i]), RMOI.VariableIndex(i), RMOI.VariableIndex(j))
                               for i in 1:n for j in (i + 1):n])
            affine = [RMOI.ScalarAffineTerm(Float64(g[i]), RMOI.VariableIndex(i)) for i in 1:n]
            return RMOI.ScalarQuadraticFunction(quadratic, affine, Float64(constant))
        end
        native_function = moi_polynomial(G, g, 7)
        digit_function = moi_polynomial(transformed.G, transformed.g, transformed.gamma)
        for digits in Iterators.product(0:1, 0:1, 0:1)
            d = collect(digits)
            z = offset + expansion * d
            @test sum(d .* (transformed.G * d)) + sum(transformed.g .* d) + transformed.gamma ==
                  sum(z .* (G * z)) + sum(g .* z) + 7
            @test RMOI.Utilities.eval_variables(vi -> z[vi.value], native_function) ==
                  RMOI.Utilities.eval_variables(vi -> d[vi.value], digit_function) ==
                  sum(z .* (G * z)) + sum(g .* z) + 7
        end
        @test_throws ArgumentError Base.invokelatest(substitute,
            reshape([floatmax(Float64)], 1, 1), [0.0], 0.0, [0.0], reshape([2.0], 1, 1))
    end
end
