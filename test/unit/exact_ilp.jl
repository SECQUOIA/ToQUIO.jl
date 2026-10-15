module ExactILPRegression
using Test, ToQUIO, LinearAlgebra
const M = ToQUIO.MOI

function model(strategy)
    optimizer = ToQUIO.Optimizer(; encoding=strategy)
    source = M.Utilities.Model{Float64}()
    x,y = M.add_variables(source,2)
    for v in (x,y)
        M.add_constraint(source,v,M.Interval(0.0,10.0))
        M.add_constraint(source,v,M.Integer())
    end
    f = M.ScalarAffineFunction([M.ScalarAffineTerm(1.0,x),M.ScalarAffineTerm(2.0,y)],0.0)
    M.set(source,M.ObjectiveSense(),M.MIN_SENSE)
    M.set(source,M.ObjectiveFunction{typeof(f)}(),f)
    row = M.ScalarAffineFunction([M.ScalarAffineTerm(1.0,x),M.ScalarAffineTerm(1.0,y)],0.0)
    M.add_constraint(source,row,M.GreaterThan(5.0))
    M.optimize!(optimizer,source)
    return optimizer
end

function check(name, strategy)
    opt = model(strategy)
    vars = M.get(opt.target_model,M.ListOfVariableIndices())
    pos = Dict(v=>i for (i,v) in enumerate(vars))
    F = M.get(opt.target_model,M.ObjectiveFunctionType())
    f = M.get(opt.target_model,M.ObjectiveFunction{F}())
    n = length(vars)
    G = zeros(Int,n,n); g = zeros(Int,n)
    exactint(v) = (isinteger(v) && BigInt(v)==Int(v) ? Int(v) : error("Noninteger coefficient"))
    for term in f.quadratic_terms
        i,j = pos[term.variable_1],pos[term.variable_2]
        G[i,j] += exactint(term.coefficient/(i==j ? 2 : 1))
    end
    for term in f.affine_terms
        g[pos[term.variable]] += exactint(term.coefficient)
    end
    c = exactint(f.constant)
    metadata = reformulation_metadata(opt)
    lower = Int.(metadata["target_lower_bounds"])
    upper = Int.(metadata["target_upper_bounds"])
    widths = upper-lower.+1
    states = prod(big.(widths))
    states <= 1_000_000 || error("Enumeration exceeds cap")
    mag = max.(abs.(lower),abs.(upper))
    bound = sum(abs(big(G[i,j]))*mag[i]*mag[j] for i in 1:n,j in 1:n) +
        sum(abs(big(g[i]))*mag[i] for i in 1:n) + abs(big(c))
    bound <= typemax(Int) || error("Exact machine integer evaluation could overflow")
    rho = exactint(only(opt.data[:rho]))
    # Independent source proof: x+2y=(x+y)+y>=5; (x,y)=(5,0) attains5.
    best = typemax(Int); minimizers = 0; visited = 0
    min_infeasible = typemax(Int)
    points = Set{Tuple{Int,Int}}()
    for ztuple in Iterators.product((l:u for (l,u) in zip(lower,upper))...)
        z = collect(ztuple)
        energy = dot(z,G*z)+dot(g,z)+c
        native = exactint.(project_native_state(opt,z))
        x,y,slack = native
        @test 0<=x<=10 && 0<=y<=10 && 0<=slack<=15
        @test energy == x+2y+rho*(x+y-slack-5)^2
        feasible = x+y>=5
        if !feasible
            min_infeasible = min(min_infeasible,energy)
        end
        if energy < best
            best = energy; minimizers=0; empty!(points)
        end
        if energy == best
            minimizers += 1
            push!(points,(x,y))
            # Public original-variable projection independently agrees on minimizers.
            original = project_original_state(opt,z)
            @test [original[v] for v in opt.data[:source_variables]] == [x,y]
        end
        visited += 1
    end
    @test visited == states
    @test best == 5
    @test points == Set([(5,0)])
    @test min_infeasible > best
    row = Dict("encoding"=>name,"target_variables"=>n,"enumerated_states"=>visited,
        "minimum_target_energy"=>best,"target_minimizer_count"=>minimizers,
        "decoded_global_minimizers"=>[[x,y] for (x,y) in points],
        "minimum_source_infeasible_energy"=>min_infeasible,
        "penalty"=>rho,"integer_energy_absolute_bound"=>Int(bound),
        "every_target_matches_independent_penalty_equation"=>true)
    return row
end

@testset "Global-optimum preservation differs from heuristic success" begin
    arms=(("native",NativeEncoding()),("radix4",RadixEncoding(;levels=4)),
        ("bounded4-cap2",BoundedEncoding(;levels=4,max_weight=2)),
        ("binary-radix2",RadixEncoding(;levels=2)))
    rows=[check(name,strategy) for (name,strategy) in arms]
    @test [r["enumerated_states"] for r in rows] == [1936,4096,65536,4096]
    @test [r["target_minimizer_count"] for r in rows] == [1,2,4,2]
    @test all(r->r["minimum_target_energy"]==5,rows)
end
end # module ExactILPRegression
