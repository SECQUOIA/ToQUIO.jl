using Test
include("CQTExperiment.jl")
Base.include(CQTBenchmarks, joinpath(@__DIR__, "runner.jl"))
const B = CQTBenchmarks

@testset "CQT optional compiler/reference integrations" begin
    @test B.verify_dependency_pins()
    generated = first(filter(i -> i.stage == "tuning", B.corpus(B.PROTOCOL)))
    reference = B.highs_reference(generated)
    @test reference["source_feasible"]
    @test B.source_feasible(generated, reference["point"]; atol = 0)
    @test reference["point"] == round.(Int, reference["raw_point"])
    @test reference["objective"] == B.source_value(generated, reference["point"])
    @test reference["time_limit_seconds"] == 10.0
    instances = B.corpus(B.PROTOCOL)
    for instance in filter(i -> i.stage == "pilot", instances)
        oracle = B.native_optimizer(instance)
        before = copy(oracle.data[:Q])
        reference = B.exact_reference(instance)
        for (arm, strategy) in (("native", B.ToQUIO.NativeEncoding()),
                               ("radix", B.ToQUIO.RadixEncoding()),
                               ("bounded", B.ToQUIO.BoundedEncoding()))
            staged = B.compile_quio(instance, arm, "controlled"; oracle)
            public = B.ToQUIO.Optimizer(; encoding = strategy)
            B.M.optimize!(public, B.source_model(instance))
            actual, _ = B.polynomial_from_moi(public.target_model)
            @test actual.G == staged.polynomial.G
            @test actual.g == staged.polynomial.g
            @test actual.constant == staged.polynomial.constant
            @test actual.lower == staged.polynomial.lower
            @test actual.upper == staged.polynomial.upper
            @test oracle.data[:Q] == before
            @test B.layout_identity(staged) == B.layout_identity(B.compile_quio(instance, "native", "controlled";
                                                                              oracle))
        end
        for arm in ("toqubo_binary", "toqubo_bounded_shim"), regime in B.PROTOCOL["regimes"]
            cell = B.compile_toqubo(instance, arm, regime; oracle)
            @test B.compare_polynomials(cell.polynomial, B.reconstructed_polynomial(cell))
            @test B.cell_observer(cell, reference["objective"])(B.reference_lift(cell, reference["point"])).feasible
            @test isempty(cell.record["upstream_metadata"]["applied_penalties"]["variables"])
        end
    end
    @test_throws ArgumentError B.ToQUBO.Encoding.encode(n -> B.M.VariableIndex.(1:n),
        B.ExactBoundedShim(2, 256), (0.0, 2.0); tol = 0.01)
    @test_throws ArgumentError B.ToQUBO.Encoding.encode(n -> error("allocator must not run"),
        B.ExactBoundedShim(2, 256), (0.0, 65.0))
    @test [length(B.stage_jobs(instances, stage, Dict("bounded" => 1, "toqubo_bounded_shim" => 2)))
        for stage in ("warmup", "pilot", "tuning", "evaluation")] == [40, 120, 120, 400]
    plans = vcat([B.stage_jobs(instances, stage, Dict("bounded" => 1, "toqubo_bounded_shim" => 2))
        for stage in ("warmup", "pilot", "tuning", "evaluation")]...)
    @test sum(j["reserved_proposals"] for j in plans) == 5_325_120
    @test length(unique(j["key"] for j in plans)) == 680
    @test all(j["effective_seed"] == j["replicate_seed"] + 10_000j["ordinal"] for j in plans)

    # Selector evidence uses all twenty planned tuning runs per cap, including
    # invalid failures. It is independent of the sampler's measured output.
    mktempdir() do root
        ledger = Dict{String,Any}("jobs" => Dict{String,Any}[])
        for job in B.stage_jobs(instances, "tuning", Dict{String,Int}())
            cap = job["cap"]
            trajectory = Dict("timely_target" => cap != 1, "target_time_score" => cap == 1 ? 2.0 : 0.5)
            file = "jobs/" * job["key"] * ".toml"
            hash = B.write_archive(root, file, Dict("trajectory" => trajectory))
            push!(ledger["jobs"], Dict("key" => job["key"], "file" => file,
                                      "hash" => hash, "status" => cap == 1 ? "invalid" : "complete"))
        end
        selection = B.select_caps(root, ledger, instances)
        @test selection["selected"] == Dict("bounded" => 2, "toqubo_bounded_shim" => 2)
        @test all(r["planned_runs"] == 20 for r in selection["scores"])
        @test_throws ArgumentError B.select_caps(root, Dict("jobs" => ledger["jobs"][2:end]), instances)
    end

    @testset "correctness failures stop rather than score performance" begin
        pilot = first(instances)
        job = first(B.stage_jobs(instances, "warmup", Dict{String,Int}()))
        cell = B.compile_quio(pilot, "native", "controlled")
        cell.polynomial.upper[1] = cell.polynomial.lower[1] - 1
        mktempdir() do root
            ledger = Dict{String,Any}("jobs" => Dict{String,Any}[],
                "started_monotonic_ns" => Int(time_ns()), "sampler_starts_reserved" => 0,
                "proposals_reserved" => 0, "invocations" => [Dict("peak_rss_bytes" => 0)],
                "cells" => [Dict("key" => job["cell_key"])])
            @test_throws ArgumentError B.execute_job!(root, ledger, job,
                Dict(job["cell_key"] => cell), Dict(pilot.id => Dict("objective" => 5)))
            @test haskey(ledger, "correctness_failure")
            @test ledger["jobs"][1]["status"] == "reserved"
            @test !isdir(joinpath(root, "jobs"))
        end
    end
    @testset "failed and interrupted preflight cannot retry" begin
        pilot = first(instances)
        key = B.cell_key(pilot, "native", "controlled", 0)
        for status in ("reserved", "failed")
            ledger = Dict{String,Any}("cells" => [Dict("key" => key, "status" => status)])
            mktempdir() do root
                @test_throws ErrorException B.prepare_cells!(root, ledger, [pilot], Dict(), "smoke")
                @test length(ledger["cells"]) == 1
            end
        end
    end
    @testset "interrupted and corrupted jobs are retained without dispatch" begin
        job = first(B.stage_jobs(instances, "warmup", Dict{String,Int}()))
        mktempdir() do root
            entry = Dict{String,Any}("key" => job["key"], "status" => "reserved")
            ledger = Dict{String,Any}("jobs" => [entry], "started_monotonic_ns" => Int(time_ns()),
                "sampler_starts_reserved" => 1, "proposals_reserved" => 128,
                "invocations" => [Dict("peak_rss_bytes" => 0)])
            result = B.execute_job!(root, ledger, job, Dict(), Dict())
            @test result["status"] == "invalid"
            @test !result["trajectory"]["any_feasible"]
            @test result["trajectory"]["target_time_score"] == 2.0
            @test result["trajectory"]["target_work_score"] == 128
            @test ledger["sampler_starts_reserved"] == 1
            @test ledger["proposals_reserved"] == 128
            @test B.execute_job!(root, ledger, job, Dict(), Dict()) == result
        end
        mktempdir() do root
            file = "jobs/" * job["key"] * ".toml"
            hash = B.write_archive(root, file, Dict("status" => "complete"))
            open(joinpath(root, file), "w") do io
                write(io, "corrupted")
            end
            entry = Dict{String,Any}("key" => job["key"], "status" => "complete", "file" => file, "hash" => hash)
            ledger = Dict{String,Any}("jobs" => [entry], "started_monotonic_ns" => Int(time_ns()),
                "sampler_starts_reserved" => 1, "proposals_reserved" => 128,
                "invocations" => [Dict("peak_rss_bytes" => 0)])
            result = B.execute_job!(root, ledger, job, Dict(), Dict())
            @test result["status"] == "invalid"
            @test result["retained_prior_hash"] == hash
            @test read(joinpath(root, file), String) == "corrupted"
            @test ledger["sampler_starts_reserved"] == 1
        end
    end
end
