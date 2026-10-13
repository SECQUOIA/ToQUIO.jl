function penalty_documentation_example(name)
    page = read(joinpath(pkgdir(ToQUIO), "docs", "src", "penalties.md"), String)
    pattern = Regex("<!-- penalty-example:" * name * " -->\\s*```julia\\n(.*?)\\n```" *
                    "\\s*<!-- /penalty-example:" * name * " -->", "s")
    matched = match(pattern, page)
    isnothing(matched) && error("Missing executable penalty documentation example: $name")
    return matched.captures[1]
end

# Access fresh include_string module bindings in the latest world.
penalty_example_binding(example, name) = Base.invokelatest(getproperty, example, name)

@testset "Executable penalty documentation" begin
    # The snippets import the root's existing MOI dependency. Keep the active
    # test environment first, and verify the already-loaded MOI identity.
    paths = copy(LOAD_PATH)
    try
        push!(LOAD_PATH, pkgdir(ToQUIO))
        inspection = Module(:PenaltyInspectionExample)
        include_string(inspection, penalty_documentation_example("inspection"))
        @test penalty_example_binding(inspection, :MOI) === ToQUIO.MOI
        metadata = penalty_example_binding(inspection, :metadata)
        optimizer = penalty_example_binding(inspection, :optimizer)
        constraints = [penalty_example_binding(inspection, name) for name in (:eq, :lt, :gt)]
        @test [RMOI.get(optimizer, ToQUIO.AppliedPenalty(), ci) for ci in constraints] == [10, 10, 10]
        identities = [entry["source_constraint"] for entry in metadata["constraint_encodings"]]
        @test getindex.(identities, "id") == [1, 1, 1]
        @test length(unique(getindex.(identities, "set_type"))) == 3
        @test [entry["applied_penalty"] for entry in metadata["constraint_encodings"]] ==
              [10, 10, 10]
        @test [entry["source_relation"] for entry in metadata["constraint_encodings"]] ==
              ["=", "<=", ">="]
        sweep = Module(:PenaltySweepExample)
        @test_logs (:warn, r"Applied automatic penalty is below") include_string(
            sweep, penalty_documentation_example("sweep"))
        @test penalty_example_binding(sweep, :MOI) === ToQUIO.MOI
        records = penalty_example_binding(sweep, :sweep)
        @test getproperty.(records, :offset) == [1, 1, 1, 3]
        @test getproperty.(records, :penalty) ≈ [0.7, 7, 14, 9]
        @test getproperty.(records, :x) == [0, 1, 1, 1]
        @test getproperty.(records, :feasible) == [false, true, true, true]
    finally
        empty!(LOAD_PATH)
        append!(LOAD_PATH, paths)
    end
end
