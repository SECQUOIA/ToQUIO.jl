# Deterministic allocation admission only: no compilation, solve, or sampling.
include("models.jl");include("compilers.jl")
using .FreshQuadraticModels,.FreshCompilers,TOML,SHA
const F=FreshQuadraticModels;const C=FreshCompilers
function main()
    length(ARGS)==2 || error("Usage: admission.jl INPUT_ROOT OUTPUT_FILE")
    root=abspath(ARGS[1]);output=abspath(ARGS[2]);isfile(output) && error("Refuse existing admission record")
    inventory=TOML.parsefile(joinpath(root,"inventory.toml"))["instances"]
    length(inventory)==456 || error("Incomplete concrete input grid")
    records=Dict{String,Any}[]
    for e in inventory
        path=joinpath(root,e["file"])
        bytes2hex(sha256(read(path)))==e["sha256"] || error("Changed concrete input")
        instance=F.from_record(TOML.parsefile(path))
        F.instance_hash(instance)==e["sha256"] || error("Source record roundtrip changed its identity")
        isnothing(instance.witness) || F.feasible(instance,instance.witness) || error("Invalid retained witness")
        for arm in C.ARMS
            guard=C.preflight(instance,arm)
            push!(records,merge(guard,Dict("instance_id"=>instance.id,"arm"=>arm,"source_hash"=>e["sha256"])))
        end
    end
    result=Dict("schema_version"=>1,"cells"=>records,"admitted_cells"=>length(records),
        "compilers_source_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__,"compilers.jl")))),
        "input_inventory_sha256"=>bytes2hex(sha256(read(joinpath(root,"inventory.toml")))),
        "scope"=>"allocation-estimate-before-compiler-dispatch-no-measurements")
    open(output,"w") do io;TOML.print(io,result;sorted=true);end
    println("All ",length(records)," planned structural cells pass allocation admission.")
end
main()
