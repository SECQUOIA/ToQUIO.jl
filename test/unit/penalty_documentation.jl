function penalty_documentation_example(name)
    page = read(joinpath(pkgdir(ToQUIO), "docs", "src", "penalties.md"), String)
    pattern = Regex("<!-- penalty-example:" * name * " -->\\s*```julia\\n(.*?)\\n```" *
                    "\\s*<!-- /penalty-example:" * name * " -->", "s")
    matched = match(pattern, page)
    isnothing(matched) && error("Missing executable penalty documentation example: $name")
    return matched.captures[1]
end

@testset "Executable penalty documentation" begin
    # The snippets import the root's existing MOI dependency. Keep the active
    # test environment first, and verify the already-loaded MOI identity.
    paths = copy(LOAD_PATH)
    try
        push!(LOAD_PATH, pkgdir(ToQUIO))
        inspection = Module(:PenaltyInspectionExample)
        include_string(inspection, penalty_documentation_example("inspection"))
        @test inspection.MOI === ToQUIO.MOI
        @test [entry["applied_penalty"] for entry in inspection.metadata["constraint_encodings"]] ==
              [10, 10, 10]
        @test [entry["source_relation"] for entry in inspection.metadata["constraint_encodings"]] ==
              ["=", "<=", ">="]
        sweep = Module(:PenaltySweepExample)
        @test_logs (:warn, r"Applied automatic penalty is below") include_string(
            sweep, penalty_documentation_example("sweep"))
        @test sweep.MOI === ToQUIO.MOI
        @test getproperty.(sweep.sweep, :penalty) ≈ [0.7, 7, 14]
        @test getproperty.(sweep.sweep, :x) == [0, 1, 1]
        @test getproperty.(sweep.sweep, :feasible) == [false, true, true]
    finally
        empty!(LOAD_PATH)
        append!(LOAD_PATH, paths)
    end
end
