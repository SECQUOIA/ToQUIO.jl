using Test, .FreshQuadraticModels
const Models=FreshQuadraticModels
const MOI=Models.M

@testset "Fresh mathematical source models" begin
    cases=Models.planned_sources()
    @test length(cases)==360
    @test count(Models.has_direct_baseline,cases)==300
    @test [count(c->c.family==name,cases) for name in
        ("facility","inventory","route_allocation","knapsack")]==[72,144,96,48]
    @test length(unique(Models.stream_seed(c.family,c.n,c.m,c.replicate) for c in cases))==360
    for family in ("facility","inventory","route_allocation","knapsack")
        instance=Models.generate(family,2,2,1)
        @test Models.instance_hash(instance)==Models.instance_hash(Models.generate(family,2,2,1))
        @test instance.parameters["rng"]=="Julia-$VERSION-MersenneTwister"
        @test isnothing(instance.witness) || Models.feasible(instance,instance.witness)
        source=Models.source_model(instance)
        f=MOI.get(source,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
        point=collect(instance.upper)
        @test MOI.Utilities.eval_variables(v->point[v.value],f)≈Models.objective(instance,point)
    end
    rounded=Models.generate("route_allocation",3,4,2)
    unrounded=Models.generate("route_allocation",3,4,2;profile="unrounded-quadratic")
    @test rounded.seed==unrounded.seed
    @test rounded.lower==unrounded.lower && rounded.upper==unrounded.upper
    @test rounded.rows==unrounded.rows && rounded.rhs==unrounded.rhs
    @test all(iszero,rounded.quadratic)
    @test any(!iszero,unrounded.quadratic)
    @test rounded.quadratic==round.(unrounded.quadratic)
    @test rounded.linear==round.(unrounded.linear)
    @test Models.feasible(unrounded,unrounded.witness)
    @test Models.objective(unrounded,unrounded.witness)≈unrounded.parameters["analytic_optimum"]
    @test_throws ArgumentError Models.generate("facility",100000,100000,1)
    @test_throws ArgumentError Models.generate("inventory",2,4,1;profile="unrounded-quadratic")
end

@testset "Independent exact original-box oracles" begin
    # Values follow hand calculations, not the reformulation or a numerical solver.
    expected=[6//1,-5//4,4//1,8//1,-263169//1]
    for (instance,value) in zip(Models.manufactured_fixtures(),expected)
        reference=Models.exact_reference(instance)
        @test reference.status=="EXACT_OPTIMAL"
        @test reference.objective==value
        @test Models.feasible(instance,reference.point)
        @test Models.exact_objective(instance,reference.point)==value
    end
    wide=last(Models.manufactured_fixtures())
    @test_throws ArgumentError Models.exact_reference(wide;max_states=1024)
    knapsack=Models.manufactured_fixtures()[4]
    infeasible=Models.Instance("fixture-infeasible",knapsack.family,knapsack.profile,
        knapsack.seed,knapsack.parameters,knapsack.lower,knapsack.upper,knapsack.quadratic,
        knapsack.linear,knapsack.sense,knapsack.rows,knapsack.relations,[-1],nothing)
    reference=Models.exact_reference(infeasible)
    @test reference.status=="EXACT_INFEASIBLE"
    @test isnothing(reference.objective) && isempty(reference.point)
end
