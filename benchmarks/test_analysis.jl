module CQTStudyAnalysisTests
using Test
include("CQTBenchmarks.jl")
Base.include(CQTBenchmarks, joinpath(@__DIR__, "runner.jl"))
Base.include(CQTBenchmarks, joinpath(@__DIR__, "study_analysis.jl"))
const A = CQTBenchmarks

@testset "Frozen instance-level descriptive analysis" begin
    @test A.percentile([1.0, 2.0, 3.0], 0.5) == 2.0
    @test A.sign_flip_sensitivity(ones(8))["p"] == 2 / 256
    @test A.sign_flip_sensitivity(zeros(8))["p"] == 1
    @test A.sign_flip_sensitivity(["missing"])["p"] == "missing"
    @test_throws ErrorException A.sign_flip_sensitivity(ones(9))
    # Exact rational enumeration of this published contrast gives160/256.
    ties = [0.0, 0.0, 0.8, 0.4, -0.2, 0.0, 0.0, -0.2]
    for order in (1:8, 8:-1:1, [3, 4, 5, 8, 1, 2, 6, 7]), scale in (1.0, 1e-12, 1e12)
        @test A.sign_flip_sensitivity(ties[order] .* scale)["p"] == 160 / 256
        @test A.sign_flip_sensitivity([1.0, 2.0, zeros(6)...] .* scale)["p"] == 0.5
    end
    function record(feasible, time, gap)
        return Dict("trajectory" => Dict{String,Any}("any_feasible" => feasible,
            "target_time_score" => time, "target_work_score" => 10time, "signed_gap" => gap))
    end
    left = [record(true, 0.4, 0.2) for _ in 1:5]
    right = [record(true, 0.7, 0.5) for _ in 1:5]
    pairs = [(id = "i$i", family = "f$(ceil(Int, i / 2))", left = deepcopy(left), right = deepcopy(right))
             for i in 1:8]
    result = A.paired_contrast(pairs, "target_time_score")
    @test result["mean_difference"] ≈ -0.3
    @test all(v ≈ -0.3 for v in result["interval"])
    @test result["valid_bootstrap_replicates"] == 2000
    @test result == A.paired_contrast(pairs, "target_time_score")
    @test all(v["paired_restarts"] == 5 for v in result["instance_differences"])
    pairs[1].left[1]["trajectory"]["any_feasible"] = false
    pairs[1].left[1]["trajectory"]["signed_gap"] = "missing"
    @test A.pair_differences(pairs[1].left, pairs[1].right, "signed_gap").paired_restarts == 4
    @test A.pair_differences(pairs[1].left, pairs[1].right, "feasibility").difference == -0.2
    for r in pairs[2].left
        r["trajectory"]["any_feasible"] = false
        r["trajectory"]["signed_gap"] = "missing"
    end
    gap = A.paired_contrast(pairs, "signed_gap")
    @test gap["instance_differences"][2]["difference"] == "missing"
    @test gap["sign_flip"]["n"] == 7
    pairs[1].left[1]["trajectory"]["target_time_score"] = "missing"
    time = A.paired_contrast(pairs, "target_time_score")
    @test time["incomplete_time_comparison"]
    @test time["mean_difference"] == "missing"
    @test time["interval"] == ["missing", "missing"]
    @test_throws ErrorException A.paired_contrast(pairs[1:7], "feasibility")
end

@testset "Frozen reference and observed-score binding" begin
    instance = first(A.corpus(A.PROTOCOL))
    reference = A.exact_reference(instance)
    trajectory = Dict{String,Any}("any_feasible" => true, "best_feasible_source" => reference["point"],
        "best_feasible_objective" => reference["objective"], "signed_gap" => 0.0,
        "timely_target" => true, "first_target_seconds" => 0.2, "first_target_proposal" => 3,
        "completed_proposals" => 128, "target_time_score" => 0.2, "target_work_score" => 3)
    record = Dict("status" => "complete", "trajectory" => trajectory,
                  "reference_objective" => reference["objective"], "job" => Dict("reserved_proposals" => 128))
    @test A.validate_trajectory_scores(record, reference, instance)
    for (field, value) in (("signed_gap", 0.1), ("target_time_score", 1.0), ("target_work_score", 4),
                           ("timely_target", false))
        bad = deepcopy(record)
        bad["trajectory"][field] = value
        @test_throws ErrorException A.validate_trajectory_scores(bad, reference, instance)
    end
    bad_reference = deepcopy(reference)
    bad_reference["objective"] += 1
    @test_throws ErrorException A.validate_trajectory_scores(record, bad_reference, instance)
    nohit = deepcopy(record)
    nohit["trajectory"]["first_target_seconds"] = "missing"
    nohit["trajectory"]["first_target_proposal"] = "missing"
    nohit["trajectory"]["timely_target"] = false
    nohit["trajectory"]["target_time_score"] = 2.0
    nohit["trajectory"]["target_work_score"] = 128
    @test_throws ErrorException A.validate_trajectory_scores(nohit, reference, instance)
    nohit["trajectory"]["overshoot_target_proposal"] = 128
    @test A.validate_trajectory_scores(nohit, reference, instance)
    for (field, value) in (("best_feasible_objective", reference["objective"] + 1),
                           ("first_target_proposal", 129))
        bad = deepcopy(record)
        bad["trajectory"][field] = value
        @test_throws ErrorException A.validate_trajectory_scores(bad, reference, instance)
    end
    invalid = Dict("status" => "invalid", "job" => Dict("reserved_proposals" => 128),
        "trajectory" => A.invalid_trajectory(Dict("reserved_proposals" => 128), "fixture"))
    @test A.validate_trajectory_scores(invalid, reference, instance)
    invalid["trajectory"]["target_time_score"] = 0.0
    @test_throws ErrorException A.validate_trajectory_scores(invalid, reference, instance)
    falsehit = deepcopy(record)
    falsehit["trajectory"]["best_feasible_source"] = [0, 0]
    falsehit["trajectory"]["best_feasible_objective"] = 0
    falsehit["trajectory"]["signed_gap"] = 1.0
    @test_throws ErrorException A.validate_trajectory_scores(falsehit, reference, instance)
end

end
