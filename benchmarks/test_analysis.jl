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

end
