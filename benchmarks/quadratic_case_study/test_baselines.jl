using Test, .FreshDirectBaselines
@testset "Direct solver original-source audit" begin
    preferences=get(ENV,"TOQUIO_CHECK_GUROBI","false")=="true" ? (false,true) : (false,)
    for prefer in preferences
        factory=FreshDirectBaselines.select_factory(;prefer_gurobi=prefer)
        @test factory.backend==(prefer ? "Gurobi" : "SCIP")
        try
            for (instance,value) in zip(Models.manufactured_fixtures(),[6,-1.25,4,8,-263169])
                result=FreshDirectBaselines.solve(instance,factory;seconds=5.0)
                @test result["source_feasible"]
                @test result["termination"]=="OPTIMAL"
                @test result["source_objective"]≈value
                @test result["certification"]=="numerical-global-solver-status-not-exhaustive-proof"
            end
            k=Models.manufactured_fixtures()[4]
            infeasible=Models.Instance("fixture-infeasible",k.family,k.profile,k.seed,
                k.parameters,k.lower,k.upper,k.quadratic,k.linear,k.sense,k.rows,k.relations,[-1],nothing)
            result=FreshDirectBaselines.solve(infeasible,factory;seconds=5.0)
            @test !result["primal_available"]
            @test !haskey(result,"solver_objective") && !haskey(result,"source_objective")
            @test result["termination"]=="INFEASIBLE"
        finally
            isnothing(factory.environment) || finalize(factory.environment)
        end
    end
end
