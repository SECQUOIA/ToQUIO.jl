# One bounded process executes cells sequentially; supervisor independently watches
# phase deadlines. Existing attempt markers prohibit invisible repeats after crash.
include("models.jl")
include("baselines.jl")
include("compilers.jl")
using .FreshQuadraticModels,.FreshDirectBaselines,.FreshCompilers,TOML,SHA,Random,Dates,LinearAlgebra,Pkg
const F=FreshQuadraticModels;const B=FreshDirectBaselines;const C=FreshCompilers
VERSION==v"1.10.11" || error("Wrong Julia runtime")
length(ARGS)==3 || error("Usage: worker.jl INPUT_ROOT OUTPUT_ROOT SOURCE_SHA")
const INPUT=abspath(ARGS[1]);const OUTPUT=abspath(ARGS[2]);const SOURCE_SHA=ARGS[3]
const PROTOCOL=TOML.parsefile(joinpath(@__DIR__,"protocol.toml"))
const PROTOCOL_HASH=bytes2hex(sha256(Base.read(joinpath(@__DIR__,"protocol.toml"))))
const INVENTORY=TOML.parsefile(joinpath(INPUT,"inventory.toml"))["instances"]
const RUN=TOML.parsefile(joinpath(OUTPUT,"run.toml"))
PROTOCOL["status"]=="frozen" && RUN["source_commit"]==SOURCE_SHA || error("Unfrozen run")
function safe(x)
    x===nothing && return "null"
    x isa AbstractDict && return Dict(string(k)=>safe(v) for (k,v) in x)
    x isa AbstractVector && return [safe(v) for v in x]
    x isa Tuple && return [safe(v) for v in x]
    x isa Rational && return string(x)
    x isa UInt64 && return string(x;base=16,pad=16)
    x
end
function write_record(path,r;replace=true)
    !replace && isfile(path) && error("Refuse to overwrite retained record")
    mkpath(dirname(path));tmp=path*".tmp"
    open(tmp,"w") do io;TOML.print(io,safe(r);sorted=true);end
    mv(tmp,path;force=replace)
end
function phase(id,stage,seconds)
    write_record(joinpath(OUTPUT,"progress.toml"),Dict("cell_id"=>id,"stage"=>stage,
        "utc"=>string(now(UTC)),"watchdog_seconds"=>seconds))
end
function cell_start(id)
    path=joinpath(OUTPUT,"attempts",id*".toml")
    isfile(path) && error("Refuse a second attempt of $id")
    write_record(path,Dict("cell_id"=>id,"started_utc"=>string(now(UTC)),"attempt"=>1))
end
function finish(id,record)
    merge!(record,Dict("cell_id"=>id,"source_commit"=>SOURCE_SHA,"protocol_sha256"=>PROTOCOL_HASH,
        "finished_utc"=>string(now(UTC))))
    write_record(joinpath(OUTPUT,"cells",id*".toml"),record;replace=false)
    phase(id,"idle",180)
end
completed(id)=isfile(joinpath(OUTPUT,"cells",id*".toml"))
function diagnose(instance,cell)
    rng=MersenneTwister(391);p=cell.polynomial
    checks=Dict{String,Any}[]
    for z in (p.lower,p.upper,[rand(rng,l:u) for (l,u) in zip(p.lower,p.upper)])
        a=C.energy(p,z);b=C.independent_energy(instance,cell,z)
        magnitude=abs(p.constant)+sum(abs.(p.g).*abs.(z))+
            sum(abs(p.G[i,j])*abs(z[i])*abs(z[j]) for j in eachindex(z),i in eachindex(z))
        bound=64eps(Float64)*max(1,length(z)^2)*max(1.0,magnitude)
        abs(a-b)<=bound || error("Independent target-energy diagnostic failed")
        push!(checks,Dict("target_energy"=>a,"independent_equation_energy"=>b,
            "absolute_discrepancy"=>abs(a-b),"roundoff_screen"=>bound))
    end
    result=Dict{String,Any}("domain_coverage"=>"exact-integer-affine-interval-proof",
        "energy_checks"=>checks,"energy_scope"=>"three-Float64-diagnostics-not-exhaustive-proof")
    if !isnothing(instance.witness)
        native=copy(instance.witness)
        for m in cell.maps[(length(instance.lower)+1):end]
            e=only(filter(e->e["row"]==m.row,cell.penalties))
            residual=sum(a*instance.witness[i] for (i,a) in instance.rows[m.row];init=0)-instance.rhs[m.row]
            push!(native,-residual÷e["divisor"])
        end
        z=C.lift(cell,native);a=C.energy(p,z);b=F.objective(instance,instance.witness)
        result["feasible_witness_target_energy"]=a;result["feasible_witness_source_objective"]=b
        result["feasible_witness_absolute_error"]=abs(a-b)
    end
    result
end
Threads.nthreads()==BLAS.get_num_threads()==1 || error("Thread limits differ from protocol")
string(pkgversion(F.M))==PROTOCOL["moi_version"] || error("MOI version differs from protocol")
Pkg.dependencies()[Base.PkgId(C.ToQUBO).uuid].git_revision==PROTOCOL["toqubo_revision"] ||
    error("ToQUBO source differs from protocol")
environment=Dict("julia_version"=>string(VERSION),"moi_version"=>string(pkgversion(F.M)),
    "toquio_version"=>string(pkgversion(C.ToQUIO)),"toqubo_version"=>string(pkgversion(C.ToQUBO)),
    "cpu_name"=>Sys.CPU_NAME,"architecture"=>string(Sys.ARCH),"kernel"=>string(Sys.KERNEL),
    "blas"=>string(BLAS.get_config()),"julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads())
for name in ("memory.max","memory.swap.max","cpu.max")
    path=joinpath("/sys/fs/cgroup",name)
    isfile(path) && (environment[name]=strip(Base.read(path,String)))
end
envpath=joinpath(OUTPUT,"environment.toml")
if isfile(envpath)
    TOML.parsefile(envpath)==environment || error("Execution environment changed during resume")
else
    write_record(envpath,environment;replace=false)
end
phase("setup","symmetric-warmup",600)
for fixture in F.manufactured_fixtures()[1:4],arm in C.ARMS
    c=C.compile(fixture,arm)
    fixture.family=="knapsack" && C.sampled_chain(fixture,c;batch=1,read=1,reserved_proposals=10)
    C.structural(c;consume=true)
end
factory=B.select_factory(;prefer_gurobi=RUN["backend"]=="Gurobi")
factory.backend==RUN["backend"] || error("Frozen solver backend unavailable")
for fixture in F.manufactured_fixtures()[1:4]
    B.solve(fixture,factory;seconds=5.0)
end
try
    entries=sort(INVENTORY;by=e->bytes2hex(sha256("fresh-study-order|"*e["instance_id"])))
    for entry in entries
        phase(entry["instance_id"],"input-verification",180)
        sourcepath=joinpath(INPUT,entry["file"])
        bytes2hex(sha256(Base.read(sourcepath)))==entry["sha256"] || error("Concrete input digest mismatch")
        instance=F.from_record(TOML.parsefile(sourcepath))
        F.instance_hash(instance)==entry["sha256"] || error("Source schema digest mismatch")
        if entry["direct"]
            id=instance.id*"--direct"
            if !completed(id)
                cell_start(id);phase(id,"direct-solve",360)
                try
                    result=B.solve(instance,factory;seconds=PROTOCOL["baseline"]["time_limit_seconds"])
                    if instance.family=="route_allocation" && result["source_feasible"]
                        expected=F.objective(instance,instance.witness)
                        result["analytic_optimum"]=expected
                        result["analytic_objective_discrepancy"]=result["source_objective"]-expected
                    end
                    finish(id,Dict("status"=>"measured","kind"=>"direct","instance_id"=>instance.id,
                        "source_hash"=>entry["sha256"],"result"=>result))
                catch err
                    finish(id,Dict("status"=>"error","kind"=>"direct","instance_id"=>instance.id,
                        "source_hash"=>entry["sha256"],"error_type"=>string(nameof(typeof(err)))))
                end
            end
        end
        order=shuffle(MersenneTwister(instance.seed),collect(C.ARMS))
        for arm in order
            id=instance.id*"--"*arm;completed(id) && continue
            cell_start(id);phase(id,"compile-and-extract",PROTOCOL["resources"]["per_compilation_seconds"])
            try
                cell=C.compile(instance,arm)
                GC.gc() # Release compiler/MOI graphs before diagnostics.
                phase(id,"independent-parity",300)
                diagnosis=diagnose(instance,cell)
                if instance.family=="knapsack"
                    phase(id,"sampling",180)
                    write_record(joinpath(OUTPUT,"polynomials",id*".toml"),
                        Dict("polynomial"=>C.polynomial_record(cell.polynomial),"maps"=>C.maprecord.(cell.maps),
                            "penalties"=>cell.penalties,"arm"=>arm,"instance_id"=>instance.id))
                    for batch in 1:3,read in 1:10
                        path=joinpath(OUTPUT,"chains",id*"--b$batch-r$read.toml")
                        isfile(path) && error("Refuse repeated chain")
                        record=C.sampled_chain(instance,cell;batch,read)
                        C.replay_chain(instance,cell,record)
                        write_record(path,record;replace=false)
                        polynomialpath=joinpath(OUTPUT,"polynomials",id*".toml")
                        write_record(joinpath(OUTPUT,"replay-audits",basename(path)),Dict(
                            "chain_sha256"=>bytes2hex(sha256(Base.read(path))),
                            "polynomial_file_sha256"=>bytes2hex(sha256(Base.read(polynomialpath))),
                            "input_file_sha256"=>entry["sha256"],"source_commit"=>SOURCE_SHA,
                            "protocol_sha256"=>PROTOCOL_HASH,"julia_version"=>string(VERSION),
                            "replay_result"=>"pass",
                            "replay_scope"=>"actual-proposals-and-decision-observations-not-wall-times");
                            replace=false)
                    end
                end
                phase(id,"canonical-metrics-and-spectral",PROTOCOL["resources"]["per_spectral_seconds"])
                GC.gc()
                result=C.structural(cell;consume=true)
                finish(id,Dict("status"=>"measured","kind"=>"structural","instance_id"=>instance.id,
                    "arm"=>arm,"source_hash"=>entry["sha256"],"compiler"=>cell.record,
                    "penalties"=>cell.penalties,"maps"=>C.maprecord.(cell.maps),"verification"=>diagnosis,
                    "metrics"=>result))
            catch err
                finish(id,Dict("status"=>"error","kind"=>"structural","instance_id"=>instance.id,
                    "arm"=>arm,"source_hash"=>entry["sha256"],"error_type"=>string(nameof(typeof(err)))))
            end
            cell=nothing;result=nothing;diagnosis=nothing
            GC.gc()
        end
    end
finally
    isnothing(factory.environment) || finalize(factory.environment)
end
phase("complete","complete",1)
println("All planned cells reached terminal status.")
