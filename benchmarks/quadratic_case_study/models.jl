# Independent implementation from mathematical requirements. No reference-study
# implementation or instance file is an input to this module.
module FreshQuadraticModels
using Random, SHA, TOML, LinearAlgebra
import MathOptInterface as M

const STREAM_NAMESPACE = "toquio-fresh-quadratic-20261015-v1"
const GRIDS = (
    ("facility", [5,10,20,25,30,50], [4,8,10,16]),
    ("inventory", [10,20,40,50,70,100,150,200], [4,64,128,200,512,1024]),
    ("route_allocation", [10,20,40,50,70,100,150,200], [4,64,128,200]),
    ("knapsack", [5,10,15,20], [5,10,15,20]),
)

struct Instance
    id::String
    family::String
    profile::String
    seed::UInt64
    parameters::Dict{String,Any}
    lower::Vector{Int}
    upper::Vector{Int}
    quadratic::Matrix{Float64} # x'Qx; symmetric, both off-diagonal entries count.
    linear::Vector{Float64}
    sense::String
    rows::Vector{Vector{Pair{Int,Int}}}
    relations::Vector{String}
    rhs::Vector{Int}
    witness::Union{Nothing,Vector{Int}}
end

function stream_seed(family, n, m, replicate)
    digest = sha256("$STREAM_NAMESPACE|$family|$n|$m|$replicate")
    value = zero(UInt64)
    for byte in digest[1:8]
        value = (value << 8) | UInt64(byte)
    end
    return value
end

function planned_sources()
    return [(family=family,n=n,m=m,replicate=r)
        for (family,ns,ms) in GRIDS for n in ns for m in ms for r in 1:3]
end

function has_direct_baseline(case)
    return case.family != "facility" || (case.n in (5,10) && case.m in (4,8))
end

function generate(family::String, n::Int, m::Int, replicate::Int;
                  profile="rounded-fidelity")
    n > 0 && m > 1 && replicate > 0 || throw(ArgumentError("Invalid instance dimensions"))
    dimension = family == "facility" ? big(n)*m+m :
        family == "inventory" ? 2big(n) :
        family == "route_allocation" ? big(n)+m : big(n)
    n <= 200 && m <= 1024 && dimension <= 1024 ||
        throw(ArgumentError("Source generation exceeds the admitted storage bound"))
    profile in ("rounded-fidelity", "unrounded-quadratic") ||
        throw(ArgumentError("Unknown coefficient profile"))
    profile == "rounded-fidelity" || family == "route_allocation" ||
        throw(ArgumentError("The additional profile belongs to route allocation"))
    seed=stream_seed(family,n,m,replicate)
    rng=MersenneTwister(seed)
    parameters=Dict{String,Any}("n"=>n,"m"=>m,"replicate"=>replicate,
        "units"=>"integer-quantity-and-stated-objective-cost",
        "rng"=>"Julia-$VERSION-MersenneTwister","seed_namespace"=>STREAM_NAMESPACE)
    rows=Vector{Pair{Int,Int}}[];relations=String[];rhs=Int[]
    addrow(terms,relation,bound)=(push!(rows,Pair{Int,Int}[terms...]);
        push!(relations,relation);push!(rhs,bound);nothing)
    if family == "facility"
        h=rand(rng,1:5)
        demand=rand(rng,1:200,n)
        unscaled=rand(rng,500:1000,m)
        capacity=round.(Int,unscaled./h)
        fixed=rand(rng,500:1000,m)
        quantities=n*m;dimension=quantities+m
        draw=rand(rng,quantities,quantities)
        interaction=round.((draw+draw')/2)
        Q=zeros(dimension,dimension);Q[1:quantities,1:quantities]=interaction
        linear=[zeros(quantities);Float64.(fixed)]
        lower=zeros(Int,dimension);upper=[fill(h*maximum(capacity),quantities);fill(h,m)]
        position(i,j)=(i-1)*m+j
        for i in 1:n
            addrow([position(i,j)=>1 for j in 1:m],"eq",demand[i])
        end
        for j in 1:m
            addrow([[position(i,j)=>1 for i in 1:n];[quantities+j=>-capacity[j]]],"le",0)
        end
        for i in 1:n,j in 1:m
            addrow([position(i,j)=>1,quantities+j=>-demand[i]],"le",0)
        end
        available=h.*capacity
        witness=zeros(Int,dimension);witness[(quantities+1):end].=h
        if sum(available)<sum(demand)
            witness=nothing
        else
            for i in 1:n
                remaining=demand[i]
                for j in 1:m
                    amount=min(remaining,available[j])
                    witness[position(i,j)]=amount
                    remaining-=amount;available[j]-=amount
                end
                iszero(remaining) || error("Transportation witness construction failed")
            end
        end
        merge!(parameters,Dict("facility_units_upper"=>h,"demand"=>demand,
            "capacity_per_unit"=>capacity,"fixed_cost"=>fixed,
            "assignment_order"=>"client-major-then-facility",
            "rounding"=>"nearest-ties-to-even-capacity-and-interactions",
            "capacity_screen"=>sum(demand)<=h*sum(capacity)))
        sense="min"
    elseif family == "inventory"
        supply=m;demand=rand(rng,1:(supply-1))
        cost=rand(rng,n);revenue=round.(1.1.*cost)
        draw=rand(rng,n,n);factor=0.01*rand(rng)/supply^2
        holding=factor.*((draw+draw')/2)
        Q=zeros(2n,2n);Q[1:n,1:n]=holding
        lower=zeros(Int,2n);upper=[fill(supply,n);fill(min(demand,supply),n)]
        linear=[cost;-revenue];sense="min";witness=zeros(Int,2n)
        addrow([i=>1 for i in 1:n],"le",supply)
        addrow([n+i=>1 for i in 1:n],"le",demand)
        for i in 1:n
            addrow([n+i=>1,i=>-1],"le",0)
        end
        merge!(parameters,Dict("supply"=>supply,"aggregate_demand"=>demand,
            "purchase_cost"=>cost,"rounded_revenue"=>revenue,
            "holding_scale"=>factor,"rounding"=>"revenue-only",
            "variable_order"=>"production-then-sales"))
    elseif family == "route_allocation"
        transport=rand(rng,n);draw=rand(rng,n,n);factor=rand(rng)/m^2
        interaction=factor.*((draw+draw')/2)
        Q=zeros(n+m,n+m)
        Q[1:n,1:n]=profile=="rounded-fidelity" ? round.(interaction) : interaction
        linear=[profile=="rounded-fidelity" ? round.(transport) : transport;zeros(m)]
        lower=[ones(Int,n);zeros(Int,m)];upper=[fill(m,n);fill(n,m)]
        addrow([[i=>-1 for i in 1:n];[n+j=>1 for j in 1:m]],"eq",0)
        witness=[ones(Int,n);n;zeros(Int,m-1)];sense="min"
        merge!(parameters,Dict("interaction_scale"=>factor,
            "variable_order"=>"route-category-counts-then-vehicle-counts",
            "rounding"=>(profile=="rounded-fidelity" ? "transport-and-interactions" : "none"),
            "analytic_optimum"=>sum(Q)+sum(linear)))
    elseif family == "knapsack"
        draw=rand(rng,1:9,n,n);gram=draw*draw'
        # floor(sqrt(a/n)) == isqrt(fld(a,n)); avoid floating square-root drift.
        Q=Float64.(isqrt.(fld.(gram,n)))
        weights=rand(rng,1:10,n);capacity=fld(m*sum(weights),2)
        lower=zeros(Int,n);upper=fill(m,n);linear=zeros(n);sense="max"
        addrow([i=>weights[i] for i in 1:n],"le",capacity)
        witness=zeros(Int,n)
        merge!(parameters,Dict("weights"=>weights,"capacity"=>capacity,
            "quantity_upper"=>m,"capacity_fraction"=>"1/2"))
    else
        throw(ArgumentError("Unknown family $family"))
    end
    id="$family-n$n-m$m-r$replicate-$profile"
    instance=Instance(id,family,profile,seed,parameters,lower,upper,Q,linear,sense,
        rows,relations,rhs,witness)
    isnothing(witness) || feasible(instance,witness) || error("Invalid source witness")
    return instance
end

function feasible(instance::Instance,x;atol=0.0)
    length(x)==length(instance.lower) || return false
    all(isfinite,x) && all(abs(v-round(v))<=atol for v in x) || return false
    all(instance.lower.-atol .<= x .<= instance.upper.+atol) || return false
    for (row,relation,bound) in zip(instance.rows,instance.relations,instance.rhs)
        value=sum(a*x[i] for (i,a) in row;init=0)
        (relation=="eq" ? abs(value-bound)<=atol :
         relation=="le" ? value<=bound+atol : error("Unknown relation")) || return false
    end
    return true
end

objective(instance::Instance,x)=dot(x,instance.quadratic*x)+dot(instance.linear,x)

function validate_instance(instance::Instance)
    n=length(instance.lower)
    0<n<=1024 && length(instance.upper)==length(instance.linear)==n &&
        size(instance.quadratic)==(n,n) || throw(ArgumentError("Invalid source dimensions"))
    all(instance.lower .<= instance.upper) || throw(ArgumentError("Empty source interval"))
    all(isfinite,instance.quadratic) && all(isfinite,instance.linear) ||
        throw(ArgumentError("Nonfinite objective"))
    instance.quadratic==instance.quadratic' || throw(ArgumentError("Asymmetric source objective"))
    length(instance.rows)==length(instance.relations)==length(instance.rhs) ||
        throw(ArgumentError("Invalid source constraints"))
    all(r in ("eq","le") for r in instance.relations) || throw(ArgumentError("Unknown relation"))
    all(1<=i<=n for row in instance.rows for (i,a) in row) ||
        throw(ArgumentError("Source constraint index out of bounds"))
    integers=Iterators.flatten((instance.lower,instance.upper,instance.rhs,
        (a for row in instance.rows for (i,a) in row)))
    for value in integers
        converted=Float64(value)
        isfinite(converted) && BigInt(converted)==big(value) ||
            throw(ArgumentError("Integer input is not exactly representable"))
    end
    magnitudes=[max(abs(big(l)),abs(big(u))) for (l,u) in zip(instance.lower,instance.upper)]
    for row in instance.rows
        sum(abs(big(a))*magnitudes[i] for (i,a) in row;init=big(0))<=big(2)^53 ||
            throw(ArgumentError("Integer row evaluation exceeds exact machine arithmetic"))
    end
    instance.sense in ("min","max") || throw(ArgumentError("Unknown objective sense"))
    return instance
end

function source_model(instance::Instance)
    validate_instance(instance)
    source=M.Utilities.Model{Float64}()
    variables=M.add_variables(source,length(instance.lower))
    for (v,l,u) in zip(variables,instance.lower,instance.upper)
        M.add_constraint(source,v,M.Interval(Float64(l),Float64(u)))
        M.add_constraint(source,v,M.Integer())
    end
    Q=instance.quadratic
    Q==Q' || error("Asymmetric source coefficient matrix")
    terms=M.ScalarQuadraticTerm{Float64}[]
    for j in axes(Q,2),i in 1:j
        iszero(Q[i,j]) || push!(terms,M.ScalarQuadraticTerm(2Q[i,j],variables[i],variables[j]))
    end
    linear=[M.ScalarAffineTerm(a,v) for (a,v) in zip(instance.linear,variables) if !iszero(a)]
    f=M.ScalarQuadraticFunction(terms,linear,0.0)
    M.set(source,M.ObjectiveFunction{typeof(f)}(),f)
    M.set(source,M.ObjectiveSense(),instance.sense=="min" ? M.MIN_SENSE : M.MAX_SENSE)
    for (row,relation,rhs) in zip(instance.rows,instance.relations,instance.rhs)
        f=M.ScalarAffineFunction([M.ScalarAffineTerm(Float64(a),variables[i]) for (i,a) in row],0.0)
        set=relation=="eq" ? M.EqualTo(Float64(rhs)) : M.LessThan(Float64(rhs))
        M.add_constraint(source,f,set)
    end
    return source
end

function instance_record(instance::Instance)
    return Dict{String,Any}("id"=>instance.id,"family"=>instance.family,
        "profile"=>instance.profile,"seed_hex"=>string(instance.seed;base=16,pad=16),
        "license"=>"MPL-2.0","provenance"=>"independent-fresh-quadratic-study-v1",
        "parameters"=>instance.parameters,"lower"=>instance.lower,"upper"=>instance.upper,
        "quadratic_rows"=>[collect(row) for row in eachrow(instance.quadratic)],
        "linear"=>instance.linear,"sense"=>instance.sense,
        "rows"=>[[[i,a] for (i,a) in row] for row in instance.rows],
        "relations"=>instance.relations,"rhs"=>instance.rhs,
        "witness_status"=>(isnothing(instance.witness) ? "capacity-infeasible" : "source-feasible"),
        "witness"=>something(instance.witness,Int[]))
end

function instance_hash(instance::Instance)
    io=IOBuffer();TOML.print(io,instance_record(instance);sorted=true)
    return bytes2hex(sha256(take!(io)))
end
include("oracles.jl")
include("load_instance.jl")
end
