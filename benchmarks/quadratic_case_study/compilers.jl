module FreshCompilers
using ..FreshQuadraticModels, Random, LinearAlgebra, SHA, TOML, Pkg
import ToQUIO, ToQUBO
const F=FreshQuadraticModels
const M=F.M
struct VerificationError <: Exception
    message::String
end
Base.showerror(io::IO,e::VerificationError)=print(io,e.message)
include("../metropolis.jl") # Owned, frozen proposal kernel; no vendor modifications.
const ARMS=("native","radix4","bounded4-cap64","binary-radix2",
            "toqubo-controlled-binary","toqubo-default-binary")
struct Coordinate
    row::Int # 0 denotes an original variable, otherwise source slack owner.
    lower::Int
    upper::Int
    offset::Int
    positions::Vector{Int}
    weights::Vector{Int}
end
struct Cell
    polynomial::Polynomial
    maps::Vector{Coordinate}
    penalties::Vector{Dict{String,Any}}
    record::Dict{String,Any}
end
value(m::Coordinate,z)=m.offset+sum(w*z[p] for (p,w) in zip(m.positions,m.weights);init=0)
decode(c::Cell,z,n)=Int[value(m,z) for m in c.maps[1:n]]
maprecord(m)=Dict("row"=>m.row,"lower"=>m.lower,"upper"=>m.upper,"offset"=>m.offset,
    "positions"=>m.positions,"weights"=>m.weights)
function rowids(instance)
    counts=Dict("eq"=>0,"le"=>0);result=Dict{Any,Int}()
    for (i,r) in enumerate(instance.relations)
        counts[r]+=1;S=r=="eq" ? M.EqualTo{Float64} : M.LessThan{Float64}
        result[M.ConstraintIndex{M.ScalarAffineFunction{Float64},S}(counts[r])]=i
    end
    result
end
function strategy(arm)
    arm=="native" && return ToQUIO.NativeEncoding()
    arm=="radix4" && return ToQUIO.RadixEncoding(;levels=4,max_digits=25000)
    arm=="bounded4-cap64" && return ToQUIO.BoundedEncoding(;levels=4,max_weight=64,max_digits=25000)
    arm=="binary-radix2" && return ToQUIO.RadixEncoding(;levels=2,max_digits=25000)
    throw(ArgumentError("Unknown integer arm"))
end
function native_bounds(instance)
    l=copy(instance.lower);u=copy(instance.upper)
    for (row,r,b) in zip(instance.rows,instance.relations,instance.rhs)
        r=="eq" && continue
        minimum=sum(big(a)*(a>=0 ? instance.lower[i] : instance.upper[i]) for (i,a) in row;init=big(0))
        width=big(b)-minimum
        0<=width<=typemax(Int) || throw(ArgumentError("Invalid native slack interval"))
        push!(l,0);push!(u,Int(width))
    end
    l,u
end
function preflight(instance,arm;max_variables=25000,memory_bytes=12*2^30)
    F.validate_instance(instance);arm in ARMS || throw(ArgumentError("Unknown arm"))
    l,u=native_bounds(instance)
    count=arm=="native" ? length(l) : 0
    if arm!="native"
        # Pinned binary comparator uses at most ceil(log2(width+1)) digits.
        # Include unreduced native slacks: GCD/redundancy can only reduce this bound.
        for (lo,hi) in zip(l,u)
            if startswith(arm,"toqubo-")
                width=big(hi)-lo
                count+=iszero(width) ? 0 : ndigits(width;base=2)
            else
                layout=ToQUIO.variable_encoding(strategy(arm),lo,hi;context=nothing)
                count+=length(layout.weights)
            end
        end
    end
    count<=max_variables || throw(ArgumentError("Expanded target exceeds variable admission"))
    # Conservative simultaneous dense arrays, MOI term objects, BLAS/eigen work,
    # maps and compiler intermediates. Checked before invoking either compiler.
    factor=startswith(arm,"toqubo-") ? 40 : 16
    bytes=big(factor)*count^2+big(32)*length(l)^2+big(64)*count*length(l)+512*2^20
    bytes<=memory_bytes || throw(ArgumentError("Expanded target exceeds memory admission"))
    Dict("target_variable_upper_bound"=>count,"estimated_peak_bytes"=>Int(bytes),
         "memory_allowance_bytes"=>memory_bytes,
         "estimate_kind"=>"calibrated-conservative-admission-estimate-not-a-proven-heap-bound")
end
function extract(target)
    variables=M.get(target,M.ListOfVariableIndices());n=length(variables)
    n<=25000 || throw(ArgumentError("Target exceeds allocation admission"))
    positions=Dict(v=>i for (i,v) in enumerate(variables))
    G=zeros(n,n);g=zeros(n);l=zeros(Int,n);u=ones(Int,n)
    for (ft,st) in M.get(target,M.ListOfConstraintTypesPresent())
        ft==M.VariableIndex && (st<:M.Interval || st==M.Integer || st==M.ZeroOne) ||
            error("Target is not an unconstrained bounded integer quadratic model")
        if ft==M.VariableIndex && st<:M.Interval
            for ci in M.get(target,M.ListOfConstraintIndices{ft,st}())
                p=positions[M.get(target,M.ConstraintFunction(),ci)]
                set=M.get(target,M.ConstraintSet(),ci);l[p]=ceil(Int,set.lower);u[p]=floor(Int,set.upper)
            end
        end
    end
    ft=M.get(target,M.ObjectiveFunctionType());f=M.get(target,M.ObjectiveFunction{ft}())
    for t in f.affine_terms;g[positions[t.variable]]+=t.coefficient;end
    for t in f.quadratic_terms
        i,j=positions[t.variable_1],positions[t.variable_2]
        G[i,j]+=t.coefficient/(i==j ? 2 : 1)
    end
    p=Polynomial(G,g,f.constant,l,u,M.get(target,M.ObjectiveSense())==M.MIN_SENSE ? "min" : "max")
    validate_polynomial(p;max_variables=25000),positions
end
function native_maps(instance,metadata,p)
    native=get(metadata,"native_reformulation",metadata);n=length(instance.lower)
    rows=rowids(instance)
    slackrows=Dict(e["target_position"]=>rows[reference(e["source_constraint"])] for e in native["slack_variables"])
    maps=Coordinate[]
    for i in eachindex(native["target_variable_order"])
        l=Int(native["target_lower_bounds"][i]);u=Int(native["target_upper_bounds"][i])
        if metadata["schema_version"]==1
            push!(maps,Coordinate(get(slackrows,i,0),l,u,0,[i],[1]))
        else
            e=metadata["native_variables"][i]["expansion"]
            push!(maps,Coordinate(get(slackrows,i,0),l,u,Int(e["offset"]),
                Int[t["target_position"] for t in e["terms"]],Int[t["coefficient"] for t in e["terms"]]))
        end
    end
    maps
end
function reference(ref)
    st=ref["set_type"]
    S=occursin("EqualTo",st) ? M.EqualTo{Float64} :
      occursin("LessThan",st) ? M.LessThan{Float64} : error("Unsupported source row")
    M.ConstraintIndex{M.ScalarAffineFunction{Float64},S}(ref["id"])
end
function native_penalties(instance,metadata,maps)
    native=get(metadata,"native_reformulation",metadata);rows=rowids(instance)
    [Dict{String,Any}("row"=>rows[reference(e["source_constraint"])],"divisor"=>1,
        "form"=>"square","coefficient"=>(instance.sense=="min" ? 1 : -1)*e["applied_penalty"],
        "slack_map"=>something(findfirst(m->m.row==rows[reference(e["source_constraint"])],maps),0))
        for e in native["constraint_encodings"]]
end
function compile_integer(instance,arm)
    guard=preflight(instance,arm)
    built=@timed F.source_model(instance)
    o=ToQUIO.Optimizer(;encoding=strategy(arm),max_encoded_variables=25000)
    compiled=@timed M.optimize!(o,built.value)
    extracted=@timed begin
        d=o.data
        p=arm=="native" ? Polynomial(d[:Q],d[:L],d[:c],Int.(d[:l]),Int.(d[:u]),instance.sense) :
          Polynomial(d[:encoded_Q],d[:encoded_L],d[:encoded_c],Int.(d[:encoded_l]),Int.(d[:encoded_u]),instance.sense)
        metadata=ToQUIO.reformulation_metadata(o)
        p,metadata
    end
    p,metadata=extracted.value
    maps=native_maps(instance,metadata,p);penalties=native_penalties(instance,metadata,maps)
    record=Dict{String,Any}("arm"=>arm,"compiler"=>"ToQUIO","compiler_version"=>string(pkgversion(ToQUIO)),
        "construction_seconds"=>built.time,"compilation_seconds"=>compiled.time,
        "extraction_seconds"=>extracted.time,"full_conversion_seconds"=>compiled.time+extracted.time,
        "compilation_allocated_bytes"=>compiled.bytes,
        "metadata"=>metadata,"preflight"=>guard)
    cell=Cell(p,maps,penalties,record);validate_maps(cell);cell
end
function tqmap(entry,positions,row,l,u)
    offset=0;ps=Int[];ws=Int[]
    for t in entry["expansion_terms"]
        a=t["coefficient"];isinteger(a) || error("Noninteger binary map")
        vs=t["variables"];length(vs)<=1 || error("Nonaffine binary map")
        if isempty(vs);offset+=Int(a)
        else;push!(ps,positions[M.VariableIndex(only(vs))]);push!(ws,Int(a));end
    end
    sort(ps)==sort([positions[M.VariableIndex(v)] for v in entry["target_variables"]]) || error("Lost binary digit")
    Coordinate(row,l,u,offset,ps,ws)
end
function residual_domain(instance,row,maps)
    terms=instance.rows[row];b=instance.rhs[row]
    constant=sum(a*maps[i].offset for (i,a) in terms;init=0)-b
    divisor=big(abs(constant))
    for (i,a) in terms,w in maps[i].weights;divisor=gcd(divisor,big(a)*w);end
    divisor=iszero(divisor) ? 1 : Int(divisor)
    lo=sum(a*(a>=0 ? instance.lower[i] : instance.upper[i]) for (i,a) in terms;init=0)-b
    hi=sum(a*(a>=0 ? instance.upper[i] : instance.lower[i]) for (i,a) in terms;init=0)-b
    lo%divisor==hi%divisor==0 || error("Nonintegral residual endpoint")
    lo÷divisor,hi÷divisor,divisor
end
function compile_binary(instance,arm)
    guard=preflight(instance,arm);controlled=arm=="toqubo-controlled-binary"
    built=@timed F.source_model(instance)
    input=built.value;native=nothing
    prepared=@timed begin
        if controlled
            native=ToQUIO.Optimizer();M.optimize!(native,input);input=native.target_model
        end
    end
    o=ToQUBO.Optimizer{Float64}()
    M.set(o,ToQUBO.Attributes.DefaultVariableEncodingMethod(),ToQUBO.Encoding.Binary())
    M.set(o,ToQUBO.Attributes.Discretize(),!controlled)
    M.set(o,ToQUBO.Attributes.MaxPenaltyUpdates(),0)
    copied=@timed M.copy_to(o,input)
    compiled=@timed M.optimize!(o)
    extracted=@timed begin
        p,positions=extract(M.get(o,ToQUBO.Attributes.TargetModel()))
        metadata=ToQUBO.reformulation_metadata(o)
        p,positions,metadata
    end
    p,positions,metadata=extracted.value
    p.sense==instance.sense || error("Unexpected target sense")
    isempty(metadata["applied_penalties"]["variables"]) &&
        isempty(metadata["applied_penalties"]["slack_variables"]) || error("Unexpected digit enforcement")
    entries=sort(metadata["original_variables"];by=e->e["id"])
    inputvariables=M.get(input,M.ListOfVariableIndices())
    [e["id"] for e in entries]==[copied.value[v].value for v in inputvariables] || error("Copied map order differs")
    l,u=controlled ? (Int.(native.data[:l]),Int.(native.data[:u])) : (instance.lower,instance.upper)
    length(entries)==length(l) || error("Missing source map")
    owner=controlled ? native_maps(instance,ToQUIO.reformulation_metadata(native),nothing) : Coordinate[]
    maps=[tqmap(e,positions,controlled ? owner[i].row : 0,l[i],u[i])
        for (i,e) in enumerate(entries)]
    penalties=Dict{String,Any}[];rows=rowids(instance)
    if controlled
        isempty(metadata["constraint_encodings"]) && isempty(metadata["slack_variables"]) ||
            error("Controlled input acquired constraints")
        penalties=native_penalties(instance,ToQUIO.reformulation_metadata(native),maps)
    else
        for e in metadata["slack_variables"]
            row=rows[reference(e["constraint"])];lo,hi,d=residual_domain(instance,row,maps)
            push!(maps,tqmap(e,positions,row,0,abs(lo)))
        end
        encoded=Int[]
        for e in metadata["constraint_encodings"]
            row=rows[reference(e["constraint"])];push!(encoded,row)
            e["method"]["type"]=="QuadraticPenalty" || error("Unexpected penalty method")
            lo,hi,d=residual_domain(instance,row,maps);slack=something(findfirst(m->m.row==row,maps),0)
            push!(penalties,Dict("row"=>row,"divisor"=>d,"slack_map"=>slack,
                "form"=>(lo>=0 && slack==0 ? "linear" : "square"),"coefficient"=>e["penalty"]))
        end
        for row in setdiff(eachindex(instance.rows),encoded)
            lo,hi,d=residual_domain(instance,row,maps)
            (instance.relations[row]=="eq" ? lo==hi==0 : hi<=0) || error("Removed nonredundant row")
            push!(penalties,Dict("row"=>row,"divisor"=>d,"slack_map"=>0,"form"=>"removed","coefficient"=>0.0))
        end
    end
    record=Dict{String,Any}("arm"=>arm,"compiler"=>"ToQUBO","compiler_version"=>string(pkgversion(ToQUBO)),
        "compiler_revision"=>Pkg.dependencies()[Base.PkgId(ToQUBO).uuid].git_revision,
        "construction_seconds"=>built.time,"native_preparation_seconds"=>prepared.time,
        "source_copy_seconds"=>copied.time,
        "full_conversion_seconds"=>prepared.time+copied.time+compiled.time+extracted.time,
        "compilation_seconds"=>compiled.time,"extraction_seconds"=>extracted.time,
        "compilation_allocated_bytes"=>compiled.bytes,"metadata"=>metadata,"preflight"=>guard,
        "penalty_policy"=>(controlled ? "preserve-native" : "pinned-default-with-gcd"))
    c=Cell(p,maps,penalties,record);validate_maps(c);c
end
compile(instance,arm)=startswith(arm,"toqubo-") ? compile_binary(instance,arm) : compile_integer(instance,arm)
function validate_maps(c)
    p=validate_polynomial(c.polynomial;max_variables=25000);seen=Int[]
    for m in c.maps
        length(m.positions)==length(m.weights) || error("Malformed affine map")
        all(>(0),m.weights) || error("Nonpositive affine weight")
        all(1<=j<=length(p.g) for j in m.positions) || error("Invalid digit position")
        length(unique(m.positions))==length(m.positions) || error("Duplicate local digit")
        start=big(m.offset)+sum(big(w)*p.lower[j] for (j,w) in zip(m.positions,m.weights);init=big(0))
        covered=big(0)
        for k in sortperm(m.weights)
            j=m.positions[k];w=m.weights[k]
            w<=covered+1 || error("Affine coverage gap")
            covered+=big(w)*(p.upper[j]-p.lower[j])
        end
        start==m.lower && start+covered==m.upper || error("Affine image differs from native interval")
        append!(seen,m.positions)
    end
    sort(seen)==collect(eachindex(p.g)) || error("Target digit ownership is incomplete")
    true
end
function lift(c,native)
    length(native)==length(c.maps) || throw(DimensionMismatch())
    z=copy(c.polynomial.lower)
    for (m,x) in zip(c.maps,native)
        m.lower<=x<=m.upper || throw(ArgumentError("Native lift outside interval"))
        remaining=x-m.lower
        for k in sortperm(m.weights;rev=true)
            j=m.positions[k];amount=min(c.polynomial.upper[j]-c.polynomial.lower[j],remaining÷m.weights[k])
            z[j]+=amount;remaining-=amount*m.weights[k]
        end
        remaining==0 || error("No lift")
    end
    z
end
function independent_energy(instance,c,z;exact=false)
    native=[value(m,z) for m in c.maps];x=native[1:length(instance.lower)]
    convertvalue=exact ? x->Rational{BigInt}(x) : Float64
    e=exact ? F.exact_objective(instance,x) : F.objective(instance,x)
    for entry in c.penalties
        entry["form"]=="removed" && continue
        row=entry["row"];s=entry["slack_map"]
        residual=(sum(a*x[i] for (i,a) in instance.rows[row];init=0)-instance.rhs[row])//entry["divisor"]
        s>0 && (residual+=native[s])
        e+=convertvalue(entry["coefficient"])*(entry["form"]=="square" ? residual^2 : residual)
    end
    e
end
function exact_energy(p,z)
    e=Rational{BigInt}(p.constant)
    for i in eachindex(z)
        e+=Rational{BigInt}(p.g[i])*z[i]
        for j in eachindex(z);e+=Rational{BigInt}(p.G[i,j])*z[i]*z[j];end
    end
    e
end
include("metrics.jl")
include("sampling.jl")
end
