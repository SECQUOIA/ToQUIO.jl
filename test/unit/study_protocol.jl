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
                @test sum(weights .* digits; init = big(0)) - 2 == value - 2
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
    @testset "Nonsymmetric MOI matrix convention and overflow" begin
        G, g = [1 3; 0 2], [-2, 4]
        offset, expansion = [-2, 1], [1 1 0; 0 0 1]
        transformed = Base.invokelatest(substitute, G, g, 7, offset, expansion)
        for digits in Iterators.product(0:1, 0:1, 0:1)
            d = collect(digits)
            z = offset + expansion * d
            @test sum(d .* (transformed.G * d)) + sum(transformed.g .* d) + transformed.gamma ==
                  sum(z .* (G * z)) + sum(g .* z) + 7
        end
        @test_throws ArgumentError Base.invokelatest(substitute,
            reshape([floatmax(Float64)], 1, 1), [0.0], 0.0, [0.0], reshape([2.0], 1, 1))
    end
end
