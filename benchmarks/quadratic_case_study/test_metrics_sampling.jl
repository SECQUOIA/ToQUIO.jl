@testset "Canonical metrics and sample replay" begin
    p=C.Polynomial([1.0 2 0;4 0 0;0 0 7],[2.0,3,4],5.0,[1,0,2],[2,2,2],"min")
    cell=C.Cell(p,[C.Coordinate(0,1,2,0,[1],[1]),C.Coordinate(0,0,2,0,[2],[1]),
        C.Coordinate(0,2,2,0,[3],[1])],Dict{String,Any}[],Dict{String,Any}())
    canonical=C.canonicalize(p)
    for x in Iterators.product(1:2,0:2,2:2)
        z=collect(x)[canonical.active]-p.lower[canonical.active]
        @test C.energy(p,collect(x))≈C.dot(z,canonical.G*z)+C.dot(canonical.g,z)+canonical.constant
    end
    metrics=C.structural(cell)
    @test metrics["active_variables"]==2 && metrics["unique_couplers"]==1
    @test metrics["total_domain_width"]==3 && metrics["total_domain_levels"]==6
    @test metrics["nonbinary_square_terms"]==0
    @test length(metrics["eigenvalues"])==2
    # An alternative asymmetric storage of the SAME polynomial canonicalizes equally.
    alternative=C.Polynomial([1.0 6 0;0 0 0;0 0 7],copy(p.g),p.constant,p.lower,p.upper,p.sense)
    c2=C.Cell(alternative,cell.maps,cell.penalties,cell.record)
    @test C.structural(c2)["canonical_polynomial_sha256"]==metrics["canonical_polynomial_sha256"]
    z=C.Cell(C.Polynomial(zeros(1,1),[0.0],0.0,[0],[1],"min"),
        [C.Coordinate(0,0,1,0,[1],[1])],Dict{String,Any}[],Dict{String,Any}())
    @test C.structural(z)["density"]=="undefined"
    @test C.structural(z)["symmetric_2norm_condition_status"]=="numerically-singular"
    instance=Models.manufactured_fixtures()[4]
    initial_sources=Vector{Int}[]
    for arm in C.ARMS
        cell=C.compile(instance,arm)
        record=C.sampled_chain(instance,cell;batch=1,read=1,reserved_proposals=40,
            clock=()->UInt64(0),check_deltas=true)
        @test C.replay_chain(instance,cell,record)
        @test record["source_observations"]==41
        @test Models.feasible(instance,record["terminal_source"])==record["terminal_source_feasible"]
        push!(initial_sources,C.decode(cell,record["initial"],length(instance.lower)))
        corrupted=deepcopy(record);corrupted["final"]=copy(record["final"]);corrupted["final"][1]+=1
        @test_throws C.VerificationError C.replay_chain(instance,cell,corrupted)
    end
    @test all(==(first(initial_sources)),initial_sources)
    seeds=[C.chain_seed(Models.generate("knapsack",c.n,c.m,c.replicate),b,r)
        for c in Models.planned_sources() if c.family=="knapsack" for b in 1:3 for r in 1:10]
    @test length(unique(seeds))==1440
end

@testset "Empty active box and rejected constrained target" begin
    fixed=C.Cell(C.Polynomial(ones(1,1),[0.0],0.0,[2],[2],"min"),
        [C.Coordinate(0,2,2,0,[1],[1])],Dict{String,Any}[],Dict{String,Any}())
    metrics=C.structural(fixed)
    @test metrics["active_variables"]==0
    @test isempty(metrics["eigenvalues"])
    @test metrics["symmetric_2norm_condition_status"]=="undefined-empty"
    @test_throws ErrorException C.extract(Models.source_model(Models.manufactured_fixtures()[4]))
end
