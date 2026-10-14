using Test
include("CQTBenchmarks.jl")
const CQT = CQTBenchmarks

@testset "CQT frozen corpus and bounded kernel" begin
    instances = CQT.corpus(CQT.PROTOCOL)
    @test length(instances) == 16
    @test [i.ordinal for i in instances] == collect(1:16)
    @test all(CQT.source_feasible(i, i.witness) for i in instances)
    @test all(CQT.instance_hash(i) == CQT.instance_hash(j)
              for (i, j) in zip(instances, CQT.corpus(CQT.PROTOCOL)))
    pilots = filter(i -> i.stage == "pilot", instances)
    references = CQT.exact_reference.(pilots)
    @test [r["enumerated_states"] for r in references] == [6, 64, 324, 256]
    @test [r["objective"] for r in references] == [5, 6, 5, 4]
    @test all(r["status"] == "EXACT_OPTIMAL" for r in references)
    for instance in instances
        restored = CQT.instance_from_record(CQT.TOML.parse(String(CQT.toml_bytes(CQT.instance_record(instance)))))
        @test CQT.instance_hash(restored) == CQT.instance_hash(instance)
        @test CQT.source_feasible(restored, restored.witness)
        @test CQT.M.get(CQT.source_model(instance), CQT.M.NumberOfVariables()) == length(instance.lower)
    end
    for i in pilots
        # An independent contradictory row makes every family infeasible without
        # changing its normal fixture or generator. No solver status is inferred.
        n = length(i.lower)
        bad = CQT.Instance(i.id * "-infeasible", i.family, i.ordinal, i.stage, i.seed,
            i.parameters, i.lower, i.upper, i.costs, i.sense,
            [i.rows; [ones(Int, n)]], [i.relations; "ge"], [i.rhs; sum(i.upper) + 1], i.witness)
        @test !CQT.source_feasible(bad, bad.witness)
        @test CQT.exact_reference(bad)["status"] == "EXACT_INFEASIBLE"
        @test_throws ArgumentError CQT.exact_reference(i; max_states = 1)
    end

    # Nonsymmetric G, negative offset, a fixed coordinate, and both senses.
    G, g = [2.0 3.0 1.0; -1.0 -2.0 0.0; 0.0 2.0 4.0], [1.0, -3.0, 2.0]
    for sense in ("min", "max")
        p = CQT.Polynomial(G, g, 7.0, [-2, 0, 3], [2, 1, 3], sense)
        for state in Iterators.product(-2:2, 0:1, 3:3), site in 1:3, step in (-1, 1)
            proposed = collect(state)
            proposed[site] += step
            independent(x) = 2x[1]^2 + 2x[1]*x[2] + x[1]*x[3] - 2x[2]^2 +
                             2x[2]*x[3] + 4x[3]^2 + x[1] - 3x[2] + 2x[3] + 7
            @test CQT.energy(p, collect(state)) == independent(state)
            @test CQT.delta_energy(p, collect(state), site, step) == independent(proposed) - independent(state)
        end
        initialize(rng) = [rand(rng, -2:2), rand(rng, 0:1), 3]
        observe(x) = (source = copy(x), feasible = x[1] >= 0,
                      objective = Float64(x[1] + x[2]), sense = "min", target = x[1] == 0)
        first_run = CQT.metropolis(p, initialize, observe; seed = 117, reserved_proposals = 500,
            max_seconds = 60.0, check_deltas = true)
        second_run = CQT.metropolis(p, initialize, observe; seed = 117, reserved_proposals = 500,
            max_seconds = 60.0, check_deltas = true)
        for key in ("initial", "final", "samples", "move_counts", "best_feasible_objective",
                    "best_feasible_source", "first_target_proposal", "first_feasible_proposal")
            @test first_run[key] == second_run[key]
        end
        partial = CQT.metropolis(p, initialize, observe; seed = 117, reserved_proposals = 500,
            completed_limit = 127, max_seconds = 60.0)
        replay = CQT.metropolis(p, initialize, observe; seed = partial["seed"],
            reserved_proposals = partial["reserved_proposals"], completed_limit = partial["completed_proposals"],
            max_seconds = 60.0)
        @test replay["final"] == partial["final"]
        @test replay["samples"] == partial["samples"]
        @test partial["completed_proposals"] == 127
        @test partial["move_counts"]["boundary"] > 0
        @test all(sample["state"][3] == 3 for sample in partial["samples"])
        @test first_run["source_observations"] == 501
        metrics = CQT.structural_metrics(p)
        @test metrics["unique_couplers"] == 1
        @test metrics["density_denominator"] == 1
        @test metrics["physical_resources"] == "not-measured"
    end
    @test CQT.temperature(1, 100, 2.0, 0.01) == 2.0
    @test CQT.temperature(100, 100, 2.0, 0.01) == 0.01
    @test CQT.temperature(1, 1, 2.0, 0.01) == 2.0
    fixed = CQT.Polynomial(zeros(1, 1), [0.0], 0.0, [2], [2], "min")
    observe_fixed(x) = (source = copy(x), feasible = true, objective = 0.0, sense = "min", target = true)
    r = CQT.metropolis(fixed, rng -> [2], observe_fixed; seed = 1, reserved_proposals = 100)
    @test r["completed_proposals"] == 0
    @test r["first_target_proposal"] == 0
    @test r["samples"][1]["multiplicity"] == 1
    @test_throws ArgumentError CQT.validate_polynomial(fixed; max_variables = 0)
    @test_throws ArgumentError CQT.metropolis(fixed, rng -> [3], observe_fixed; seed = 1,
                                            reserved_proposals = 1)

    @testset "clock overshoot and allocation refusals" begin
        p = CQT.Polynomial(zeros(1, 1), [0.0], 0.0, [0], [1], "min")
        ticks, visits = Ref(UInt64(0)), Ref(0)
        clock() = (ticks[] += UInt64(500_000_000))
        function observe_late(x)
            visits[] += 1
            return (source = copy(x), feasible = true, objective = 0.0, sense = "min", target = visits[] > 1)
        end
        late = CQT.metropolis(p, rng -> [0], observe_late; seed = 1, reserved_proposals = 100,
                              max_seconds = 1.25, clock)
        @test late["completed_proposals"] == 1
        @test late["clock_censored"]
        @test !late["timely_target"]
        @test late["overshoot_target_proposal"] == 1
        @test late["first_target_seconds"] == "missing"
        @test late["target_time_score"] == 1.25
        @test_throws ArgumentError CQT.metropolis(p, rng -> error("initializer must not run"), observe_late;
            seed = 1, reserved_proposals = 10_001)
        @test_throws ArgumentError CQT.polynomial_from_record(Dict("g" => zeros(257)))
        budget = CQT.EnumerationBudget(100, 120, 0)
        @test CQT.reserve_enumeration!(budget, 80) == 80
        @test_throws ArgumentError CQT.reserve_enumeration!(budget, 41)
        @test budget.reserved == 80
    end

    @testset "portable archive and corruption gates" begin
        mktempdir() do root
            payload = Dict("wide" => big(2)^216, "none" => nothing, "text" => SubString("hello", 1, 3))
            hash = CQT.write_archive(root, "record.toml", payload)
            @test CQT.read_archive(root, "record.toml"; expected_hash = hash) == payload
            @test CQT.write_archive(root, "record.toml", payload) == hash
            @test_throws ErrorException CQT.write_archive(root, "record.toml", Dict("different" => true))
            @test_throws ErrorException CQT.read_archive(root, "record.toml"; expected_hash = repeat("0", 64))
            @test_throws ArgumentError CQT.safe_artifact_path(root, "../escape.toml")
            @test_throws ArgumentError CQT.safe_artifact_path(root, "/tmp/escape.toml")
            symlink("record.toml", joinpath(root, "link.toml"))
            @test_throws ArgumentError CQT.read_archive(root, "link.toml")
        end
        instance = first(instances)
        cell = CQT.compile_quio(instance, "native", "controlled")
        original = first(cell.maps)
        wrong = CQT.CoordinateMap(original.kind, original.row, original.lower, original.upper,
            original.offset, original.positions, [2], original.digit_lower, original.digit_upper)
        @test_throws ErrorException CQT.validate_map(cell, wrong)
        public = CQT.ToQUIO.Optimizer()
        CQT.M.optimize!(public, CQT.source_model(instance))
        actual, _ = CQT.polynomial_from_moi(public.target_model)
        @test CQT.compare_polynomials(actual, cell.polynomial)
    end
end
