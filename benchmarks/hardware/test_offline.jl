using Test
include("offline.jl")
const H = CQTOfflineHardware
const S = H.S
const M = H.M

@testset "Pinned real driver and coefficient convention" begin
    @test H.verify_driver()
    @test normpath(dirname(dirname(pathof(S.ToQUIO)))) == normpath(S.ROOT)
    # Independent hand equation, including unequal shifts and a fixed coordinate:
    # f(x)=7+3x1-x2+2x3+2x1^2+4x1*x2; x=(-3+y1,2+y2,5).
    for sense in ("min", "max")
        p = S.Polynomial([2.0 4.0 0.0; 0.0 0.0 0.0; 0.0 0.0 0.0],
            [3.0, -1.0, 2.0], 7.0, [-3, 2, 5], [-1, 5, 5], sense)
        exported = H.export_request(H.target_model(p))
        @test exported.request.num_levels == [3, 4, 1]
        for y1 in 0:2, y2 in 0:3
            y = [y1, y2, 0]
            x = [-3 + y1, 2 + y2, 5]
            f = 7 + 3x[1] - x[2] + 2x[3] + 2x[1]^2 + 4x[1]*x[2]
            sign = sense == "min" ? 1 : -1
            @test exported.request.poly(exported.vars => Float64.(y)) == sign*f
            # The file omits the shifted constant only; there is no hidden scaling.
            origin = exported.request.poly(exported.vars => zeros(3))
            @test H.payload_energy(exported.request.file, y) + origin == sign*f
        end
        response = H.QCIOpt.Solution{Float64,Float64}(
            [H.QCIOpt.Sample{Float64,Float64}([0.0, 0.0, 0.0], -999.0, 2)],
            Dict{String,Any}("status" => "COMPLETED"))
        H.QCIOpt.qci_store_results!(exported.solver, exported.device,
            exported.model, exported.vars, response)
        @test M.get(exported.solver, M.VariablePrimal(), M.VariableIndex(1)) == -3
        @test M.get(exported.solver, M.VariablePrimal(), M.VariableIndex(3)) == 5
        @test M.get(exported.solver, M.ObjectiveValue()) == 0
        @test M.get(exported.solver, H.QCIOpt.ResultMultiplicity()) == 2
        @test "singleton-provider-contract-unconfirmed" in H.readiness(exported.request)["reasons"]
    end
end

@testset "Composed source decoding and failure-preserving mock responses" begin
    instance = first(S.corpus(S.PROTOCOL))
    for arm in ("native", "radix", "bounded")
        cell = S.compile_quio(instance, arm, "controlled"; cap = 4)
        exported = H.export_request(H.target_model(cell.polynomial))
        x = instance.witness
        state = S.reference_lift(cell, x)
        shifted = state - cell.polynomial.lower
        response = Dict{String,Any}("status" => "COMPLETED",
            "results" => Dict("solutions" => [shifted], "energies" => [-123.0], "counts" => [3]),
            "job_info" => Dict("job_id" => "mock-job", "job_result" => Dict("device_usage_s" => 0.5)),
            "api_token" => "DO-NOT-PERSIST", "unknown_secret" => "DO-NOT-PERSIST")
        record = H.response_record(exported, response, cell)
        @test record["evidence_kind"] == "mock"
        @test only(record["samples"])["source_point"] == x
        @test only(record["samples"])["source_objective"] == S.source_value(instance, x)
        @test only(record["samples"])["source_feasible"]
        @test only(record["samples"])["multiplicity"] == 3
        @test record["timing"]["queue_time_sec"] == "unavailable"
        @test record["timing"]["device_usage_sec"] == 0.5
        @test !occursin("DO-NOT-PERSIST", H.JSON.json(record))
        @test record["reported_provider_energies"] == [-123.0]
        @test !record["optimality_certificate"]
        infeasible = deepcopy(response)
        infeasible["results"]["solutions"] = [cell.polynomial.upper - cell.polynomial.lower]
        audit = H.response_record(exported, infeasible, cell)
        @test !only(audit["samples"])["source_feasible"]
        @test only(audit["samples"])["source_objective"] != only(audit["samples"])["target_objective"]
        for status in ("CANCELLED", "QUEUED", "RUNNING", "SUBMITTED")
            failed = H.response_record(exported, Dict("status" => status), cell)
            @test isempty(failed["samples"])
            @test failed["provider_status"] == status
            @test failed["failure_class"] == "provider-not-completed"
        end
        error_response = Dict("status" => "ERRORED",
            "job_info" => Dict("job_result" => Dict("error" => "DO-NOT-PERSIST")))
        failed = @test_logs (:error, r"without a job-error message") H.response_record(exported, error_response, cell)
        @test failed["provider_status"] == "ERRORED"
        @test isempty(failed["samples"])
        @test !occursin("DO-NOT-PERSIST", H.JSON.json(failed))
        for (field, badvalue) in (("solutions", [Float64.(shifted) .+ 0.5]),
                                  ("solutions", [shifted .+ 1000]),
                                  ("solutions", [[0]]), ("counts", [0]),
                                  ("counts", [101]), ("energies", [NaN]))
            bad = deepcopy(response)
            bad["results"][field] = badvalue
            @test_throws ArgumentError H.response_record(exported, bad, cell)
        end
        bad = deepcopy(response)
        bad["results"]["counts"] = [1, 2]
        @test_throws ErrorException H.response_record(exported, bad, cell)
        @test_throws ArgumentError H.response_record(exported, response, cell; evidence_kind = "live")
    end
end

@testset "Explicit admission refusals" begin
    p = S.Polynomial(zeros(2, 2), [1.0, 1000.0], 2.0, [0, 0], [2, 3], "min")
    exported = H.export_request(H.target_model(p))
    @test "coefficient-dynamic-range" in H.readiness(exported.request)["reasons"]
    @test_throws ArgumentError H.require_conservative_payload(exported.request)
    @test "total-level-allocation-cap" in H.readiness(exported.request; total_level_cap = 6)["reasons"]
    @test "per-variable-conservative-level-cap" in H.readiness(exported.request; max_levels = 2)["reasons"]
    @test !H.readiness(exported.request; dynamic_range = 2000)["live_eligible"]
    p2 = S.Polynomial(zeros(2, 2), [1.0, 1.001], 0.0, [0, 0], [1, 1], "min")
    @test "coefficient-resolution" in H.readiness(H.export_request(H.target_model(p2)).request)["reasons"]
    model = H.target_model(p)
    vars = M.get(model, M.ListOfVariableIndices())
    f = M.ScalarAffineFunction([M.ScalarAffineTerm(1.0, vars[1])], 0.0)
    M.add_constraint(model, f, M.LessThan(1.0))
    @test_throws ArgumentError H.export_request(model)
    @test_throws ArgumentError H.safe_identifier("contains secret spaces")
    @test_throws ArgumentError H.timing_value(-1)
end
