function metadata_is_json_value(value)
    if value isa AbstractDict
        return all(k isa String && metadata_is_json_value(v) for (k, v) in value)
    elseif value isa AbstractVector
        return all(metadata_is_json_value, value)
    end
    return value isa Union{Nothing,String,Bool} ||
        (value isa Union{Integer,AbstractFloat} && isfinite(value))
end

function parsed_metadata_shape(value)
    if value isa AbstractDict
        return Dict{String,Any}(key => parsed_metadata_shape(v) for (key, v) in value)
    elseif value isa AbstractVector
        return Any[parsed_metadata_shape(v) for v in value]
    elseif value isa AbstractFloat
        return Float64(value)
    end
    return value
end

@testset "Reformulation metadata and source projection" begin
    @testset "unconstrained native model and copies" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, -3, 2)
        y = add_interval_integer_variable(source, 1, 4)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(2, x), affine_term(1, y))
        _, data = reformulate(source)
        metadata = ToQUIO.reformulation_metadata(data)
        @test metadata["schema_version"] == 1
        declared_version = TOML.parsefile(joinpath(@__DIR__, "..", "..", "Project.toml"))["version"]
        @test metadata["package"] == Dict("name" => "ToQUIO", "version" => declared_version)
        @test metadata_is_json_value(metadata)
        @test metadata["source_variable_order"] == [x.value, y.value]
        @test metadata["target_variable_order"] == [1, 2]
        @test isempty(metadata["slack_variables"])
        @test isempty(metadata["constraint_encodings"])
        @test !haskey(metadata, "Q")
        @test ToQUIO.project_original_state(data, [-2, 3]) == Dict(x => -2, y => 3)
        @test ToQUIO.project_original_state(metadata, [-2, 3]) == Dict(x.value => -2, y.value => 3)
        @test ToQUIO.original_variables(data) == [x, y]
        @test ToQUIO.original_variables(metadata) == [x.value, y.value]
        @test isempty(ToQUIO.auxiliary_variables(data))
        empty!(ToQUIO.original_variables(data))
        metadata["target_lower_bounds"][1] = -100
        @test data[:source_variables] == [x, y]
        @test data[:l] == [-3.0, 1.0]
        @test ToQUIO.reformulation_metadata(data)["target_lower_bounds"] == [-3.0, 1.0]
    end

    @testset "source ordering differs from target ordering" begin
        source = RMOI.Utilities.Model{Float64}()
        removed = add_interval_integer_variable(source, 0, 1)
        x = add_interval_integer_variable(source, 0, 4)
        y = add_interval_integer_variable(source, -2, 2)
        RMOI.delete(source, removed)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x), affine_term(3, y))
        _, data = ToQUIO.to_quio(Float64, vi -> vi == x ? 2 : 1, ci -> ci.value, source)
        metadata = ToQUIO.reformulation_metadata(data)
        @test metadata["source_variable_order"] == [x.value, y.value]
        @test [e["expansion"]["terms"][1]["target_position"]
               for e in metadata["original_variables"]] == [2, 1]
        @test ToQUIO.project_original_state(data, [-1, 4]) == Dict(x => 4, y => -1)
        @test ToQUIO.project_original_state(metadata, [-1, 4]) == Dict(x.value => 4, y.value => -1)
    end

    @testset "equality and both inequality slack owners" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        y = add_interval_integer_variable(source, 0, 4)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(2, x), affine_term(1, y))
        eq = RMOI.add_constraint(source, affine_function(affine_term(1, x), affine_term(1, y)), RMOI.EqualTo(4.0))
        lt = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.LessThan(2.0))
        gt = RMOI.add_constraint(source, affine_function(affine_term(1, y)), RMOI.GreaterThan(1.0))
        _, data = reformulate(source)
        metadata = ToQUIO.reformulation_metadata(data)
        @test data[:target_variables] == [RMOI.VariableIndex(1), RMOI.VariableIndex(2)]
        @test data[:quio_variables] == RMOI.VariableIndex.(1:4)
        @test data[:slack_constraints] == [lt, gt]
        @test ToQUIO.auxiliary_variables(data) == RMOI.VariableIndex.(3:4)
        @test ToQUIO.auxiliary_variables(metadata) == [3, 4]
        @test [s["source_constraint"]["set_type"]
               for s in metadata["slack_variables"]] == [
            "MathOptInterface.LessThan{Core.Float64}",
            "MathOptInterface.GreaterThan{Core.Float64}",
        ]
        @test metadata["slack_variables"][1]["source_constraint"]["function_type"] ==
            "MathOptInterface.ScalarAffineFunction{Core.Float64}"
        entries = metadata["constraint_encodings"]
        @test [e["source_relation"] for e in entries] == ["=", "<=", ">="]
        @test [e["canonical_relation"] for e in entries] == ["=", "<=", "<="]
        @test [e["row_multiplier"] for e in entries] == [1, 1, -1]
        @test [e["slack_target_position"] for e in entries] == [nothing, 3, 4]
        @test [e["applied_penalty"] for e in entries] == data[:rho]
        @test [e["automatic_penalty"] for e in entries] == data[:rho_auto]
        @test [e["penalty_hint"] for e in entries] == data[:penalty_hints]
        @test metadata_is_json_value(metadata)
        @test ToQUIO.project_original_state(data, [1, 3, 1, 2]) == Dict(x => 1, y => 3)
        @test ToQUIO.project_original_state(metadata, [1, 3, 1, 2]) == Dict(x.value => 1, y.value => 3)
        parsed = parsed_metadata_shape(metadata)
        @test parsed["original_variables"] isa Vector{Any}
        @test ToQUIO.original_variables(parsed) == [x.value, y.value]
        @test ToQUIO.auxiliary_variables(parsed) == [3, 4]
        @test ToQUIO.project_original_state(parsed, [1, 3, 1, 2]) == Dict(x.value => 1, y.value => 3)
        duplicate = deepcopy(parsed)
        duplicate["original_variables"][2]["id"] = x.value
        @test_throws ArgumentError ToQUIO.project_original_state(duplicate, [1, 3, 1, 2])
        # Projection deliberately does not repair or reject an inconsistent slack.
        @test ToQUIO.project_original_state(data, [1.5, 3, -10, 99])[x] == 1.5
        @test_throws DimensionMismatch ToQUIO.project_original_state(data, [1, 3])
        @test_throws DimensionMismatch ToQUIO.project_original_state(metadata, [1, 3, 1, 2, 0])
        @test_throws ArgumentError ToQUIO.project_original_state(data, [NaN, 3, 1, 2])
        @test_throws ArgumentError ToQUIO.project_original_state(metadata, [1, 3, Inf, 2])
    end

    @testset "hinted penalties" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(2, x))
        ci = RMOI.add_constraint(source, affine_function(affine_term(1, x)), RMOI.EqualTo(1.0))
        hinted = HintedModel(source, Dict{Any,Float64}(ci => 100.0))
        _, data = reformulate(hinted)
        metadata = ToQUIO.reformulation_metadata(data)
        @test only(metadata["constraint_encodings"])["applied_penalty"] == 100.0
        @test only(metadata["constraint_encodings"])["automatic_penalty"] == 7.0
        @test only(metadata["constraint_encodings"])["penalty_hint"] == 100.0
    end

    @testset "failed reformulation invalidates current metadata" begin
        source = RMOI.Utilities.Model{Float64}()
        x = add_interval_integer_variable(source, 0, 3)
        set_affine_objective!(source, RMOI.MIN_SENSE, affine_term(1, x))
        optimizer = ToQUIO.Optimizer()
        RMOI.optimize!(optimizer, source)
        previous_data = optimizer.data
        invalid = RMOI.Utilities.Model{Float64}()
        unbounded = RMOI.add_variable(invalid)
        RMOI.add_constraint(invalid, unbounded, RMOI.Integer())
        set_affine_objective!(invalid, RMOI.MIN_SENSE, affine_term(1, unbounded))
        @test_throws ErrorException RMOI.optimize!(optimizer, invalid)
        @test isnothing(optimizer.target_model)
        @test_throws ArgumentError ToQUIO.reformulation_metadata(optimizer)
        @test_throws ArgumentError ToQUIO.project_original_state(optimizer, [2])
        @test ToQUIO.project_original_state(previous_data, [2]) == Dict(x => 2)
        recovered = RMOI.Utilities.Model{Float64}()
        y = add_interval_integer_variable(recovered, -1, 2)
        set_affine_objective!(recovered, RMOI.MIN_SENSE, affine_term(1, y))
        RMOI.optimize!(optimizer, recovered)
        @test ToQUIO.reformulation_metadata(optimizer)["target_lower_bounds"] == [-1.0]
        @test previous_data[:l] == [0.0]
    end

    @testset "optimizer lifecycle and numeric precision" begin
        optimizer = ToQUIO.Optimizer()
        @test_throws ArgumentError ToQUIO.reformulation_metadata(optimizer)
        @test_throws ArgumentError ToQUIO.original_variables(optimizer)
        source = RMOI.Utilities.Model{BigFloat}()
        x = RMOI.add_variable(source)
        RMOI.add_constraint(source, x, RMOI.Interval(big"-2.0", big"3.0"))
        RMOI.add_constraint(source, x, RMOI.Integer())
        RMOI.set(source, RMOI.ObjectiveSense(), RMOI.MIN_SENSE)
        RMOI.set(source, RMOI.ObjectiveFunction{RMOI.ScalarAffineFunction{BigFloat}}(),
                 RMOI.ScalarAffineFunction([RMOI.ScalarAffineTerm(big"1.25", x)], big"0.0"))
        typed = ToQUIO.Optimizer{BigFloat}()
        RMOI.optimize!(typed, source)
        metadata = ToQUIO.reformulation_metadata(typed)
        @test metadata_is_json_value(metadata)
        value = big"1.2345678901234567890123456789"
        @test ToQUIO.project_original_state(typed, [value])[x] === value
        @test ToQUIO.project_original_state(metadata, [value])[x.value] == value
        @test ToQUIO.original_variables(typed) == [x]
        copied = ToQUIO.reformulation_metadata(metadata)
        empty!(copied["source_variable_order"])
        @test metadata["source_variable_order"] == [x.value]
        invalid = deepcopy(metadata)
        invalid["schema_version"] = 2
        @test_throws ArgumentError ToQUIO.project_original_state(invalid, [value])
        invalid = deepcopy(metadata)
        invalid["package"]["name"] = "AnotherCompiler"
        @test_throws ArgumentError ToQUIO.reformulation_metadata(invalid)
        invalid = deepcopy(metadata)
        invalid["target_lower_bounds"][1] = NaN
        @test_throws ArgumentError ToQUIO.reformulation_metadata(invalid)
        invalid = deepcopy(metadata)
        invalid["original_variables"][1]["expansion"]["terms"][1]["target_position"] = 2
        @test_throws ArgumentError ToQUIO.project_original_state(invalid, [value])
        invalid = deepcopy(metadata)
        invalid["original_variables"][1]["expansion"]["kind"] = "nonlinear"
        @test_throws ArgumentError ToQUIO.project_original_state(invalid, [value])
        invalid = deepcopy(metadata)
        invalid["schema_version"] = true
        @test_throws ArgumentError ToQUIO.reformulation_metadata(invalid)
        invalid = deepcopy(metadata)
        invalid["original_variables"][1]["expansion"]["terms"][1]["target_position"] = true
        @test_throws ArgumentError ToQUIO.project_original_state(invalid, [value])
        invalid = deepcopy(metadata)
        invalid["original_variables"][1]["expansion"]["offset"] = true
        @test_throws ArgumentError ToQUIO.project_original_state(invalid, [value])
        invalid = deepcopy(metadata)
        invalid["original_variables"][1]["expansion"]["terms"][1]["coefficient"] = false
        @test_throws ArgumentError ToQUIO.project_original_state(invalid, [value])
        invalid = deepcopy(metadata)
        delete!(invalid, "original_variables")
        @test_throws ArgumentError ToQUIO.project_original_state(invalid, [value])
        invalid = deepcopy(metadata)
        invalid["original_variables"][1]["expansion"]["terms"] = 5
        @test_throws ArgumentError ToQUIO.project_original_state(invalid, [value])
        invalid = deepcopy(metadata)
        invalid["source_variable_order"] = Any["a"]
        @test_throws ArgumentError ToQUIO.original_variables(invalid)
        typed.data[:l][1] = BigFloat(-Inf)
        @test_throws ArgumentError ToQUIO.reformulation_metadata(typed)
        RMOI.empty!(typed)
        @test_throws ArgumentError ToQUIO.reformulation_metadata(typed)
    end
end
