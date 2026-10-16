include("models.jl");include("compilers.jl")
using .FreshQuadraticModels,.FreshCompilers,TOML,SHA
const F=FreshQuadraticModels;const C=FreshCompilers
function main()
    VERSION==v"1.10.11" || error("Replay requires the frozen Julia runtime")
    length(ARGS) in (1,2) || error("Usage: replay.jl CAMPAIGN [MAX_CHAINS]")
    root=abspath(ARGS[1]);limit=length(ARGS)==2 ? parse(Int,ARGS[2]) : 8640
    0<limit<=8640 || error("Invalid replay allowance")
    entries=TOML.parsefile(joinpath(root,"inputs","inventory.toml"))["instances"]
    lookup=Dict(e["instance_id"]=>e for e in entries)
    seen=0;lastbase="";instance=nothing;cell=nothing
    # Round-robin arms first, so a bounded CI audit covers every compiler policy.
    paths=sort(readdir(joinpath(root,"chains");join=true);by=p->begin
        r=TOML.parsefile(p);(r["batch"],r["read"],r["instance_id"],r["arm"])
    end)
    for path in paths
        seen>=limit && break
        r=TOML.parsefile(path);base=r["instance_id"]*"--"*r["arm"]
        if base!=lastbase
            entry=lookup[r["instance_id"]];sourcepath=joinpath(root,"inputs",entry["file"])
            bytes2hex(sha256(read(sourcepath)))==entry["sha256"] || error("Replay input digest mismatch")
            instance=F.from_record(TOML.parsefile(sourcepath))
            archived=TOML.parsefile(joinpath(root,"polynomials",base*".toml"))
            p=C.polynomial_from_record(archived["polynomial"])
            maps=[C.Coordinate(m["row"],m["lower"],m["upper"],m["offset"],
                Int.(m["positions"]),Int.(m["weights"])) for m in archived["maps"]]
            cell=C.Cell(p,maps,Dict{String,Any}[Dict(e) for e in archived["penalties"]],
                Dict{String,Any}("arm"=>r["arm"]))
            C.validate_maps(cell);lastbase=base
        end
        C.replay_chain(instance,cell,r);seen+=1
    end
    seen==min(limit,length(paths)) && seen>0 || error("Empty/incomplete replay")
    println("Replayed ",seen," retained chains with actual completed proposal counts.")

end
main()
