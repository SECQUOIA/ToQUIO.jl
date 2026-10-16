using Test, Random, .FreshCompilers
const C=FreshCompilers
@testset "Public compilation and independent target equations" begin
    for instance in Models.manufactured_fixtures(),arm in C.ARMS
        cell=C.compile(instance,arm);p=cell.polynomial
        @test C.validate_maps(cell)
        rng=MersenneTwister(91)
        for k in 1:4
            z=[rand(rng,l:u) for (l,u) in zip(p.lower,p.upper)]
            @test C.exact_energy(p,z)==C.independent_energy(instance,cell,z;exact=true)
            native=[C.value(m,z) for m in cell.maps]
            lifted=C.lift(cell,native)
            @test [C.value(m,lifted) for m in cell.maps]==native
        end
        ref=Models.exact_reference(instance)
        native=copy(ref.point)
        for m in cell.maps[(length(native)+1):end]
            entry=only(filter(e->e["row"]==m.row,cell.penalties))
            residual=sum(a*ref.point[i] for (i,a) in instance.rows[m.row];init=0)-instance.rhs[m.row]
            push!(native,-residual÷entry["divisor"])
        end
        lifted=C.lift(cell,native)
        @test C.exact_energy(p,lifted)==ref.objective
    end
    instance=Models.generate("facility",50,16,1)
    @test_throws ArgumentError C.preflight(instance,"binary-radix2";memory_bytes=1024)
    @test_throws ArgumentError C.preflight(instance,"bounded4-cap64";max_variables=1)
end
@testset "Exhaustive target global optima" begin
    # All four objective families, with hand-sized boxes. No solver/backend used.
    fixtures=Models.manufactured_fixtures()
    tiny=Models.Instance("tiny-inventory","inventory","manufactured",UInt64(0),Dict{String,Any}(),
        [0,0],[1,1],[0.25 0;0 0],[0.5,-1.0],"min",[[2=>1,1=>-1]],["le"],[0],[0,0])
    total_states=big(0)
    for instance in [fixtures[1],tiny,fixtures[3],fixtures[4]],arm in C.ARMS
        cell=C.compile(instance,arm);p=cell.polynomial;ref=Models.exact_reference(instance)
        states=prod(big(u)-l+1 for (l,u) in zip(p.lower,p.upper);init=big(1))
        0<states<=1_000_000 || error("Target oracle refused before iteration")
        states*max(1,big(length(p.g))^2)<=20_000_000 || error("Target oracle operation allowance exhausted")
        total_states+=states
        total_states<=4_000_000 || error("Shared target oracle allowance exhausted")
        @test states<=1_000_000
        best=nothing;invalid_best=false;optimal_count=0
        for state in Iterators.product((l:u for (l,u) in zip(p.lower,p.upper))...)
            e=C.exact_energy(p,state)
            x=C.decode(cell,state,length(instance.lower))
            valid=Models.feasible(instance,x) && Models.exact_objective(instance,x)==ref.objective
            if isnothing(best) || (instance.sense=="min" ? e<best : e>best)
                best=e;invalid_best=!valid;optimal_count=1
            elseif e==best
                invalid_best|=!valid;optimal_count+=1
            end
        end
        @test best==ref.objective
        @test !invalid_best
        @test optimal_count>0
    end
end

@testset "Default binary canonicalization branches" begin
    function fixture(id,l,u,rows,relations,rhs)
        n=length(l)
        Models.Instance(id,"validation","manufactured",UInt64(0),Dict{String,Any}(),l,u,
            zeros(n,n),ones(n),"min",rows,relations,rhs,nothing)
    end
    cases=[fixture("gcd-shift",[1,0],[3,2],[[1=>2,2=>4]],["le"],[6]),
        fixture("linear-residual",[0],[2],[[1=>2]],["eq"],[0]),
        fixture("redundant-row",[0],[2],[[1=>2]],["le"],[4]),
        fixture("fixed-source",[2,0],[2,2],[[1=>1,2=>1]],["le"],[3])]
    for instance in cases
        cell=C.compile(instance,"toqubo-default-binary");p=cell.polynomial
        @test C.validate_maps(cell)
        for z in Iterators.product((l:u for (l,u) in zip(p.lower,p.upper))...)
            @test C.exact_energy(p,z)==C.independent_energy(instance,cell,z;exact=true)
        end
        if instance.id=="gcd-shift";@test only(cell.penalties)["divisor"]==2;end
        if instance.id=="linear-residual";@test only(cell.penalties)["form"]=="linear";end
        if instance.id=="redundant-row";@test only(cell.penalties)["form"]=="removed";end
        if instance.id=="fixed-source";@test isempty(first(cell.maps).positions);end
    end
end
