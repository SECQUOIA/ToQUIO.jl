# Freeze concrete fresh inputs before campaign measurements. No optimization here.
include("models.jl")
using .FreshQuadraticModels, TOML, SHA
const F=FreshQuadraticModels
VERSION==v"1.10.11" || error("Input generator requires the frozen Julia version")
length(ARGS)==1 || error("Usage: prepare.jl OUTPUT_DIRECTORY")
root=abspath(only(ARGS));mkpath(root)
isempty(readdir(root)) || error("Refuse to overwrite existing concrete inputs")
ledger=Dict{String,Any}[]
for case in F.planned_sources()
    profiles=case.family=="route_allocation" ? ("rounded-fidelity","unrounded-quadratic") : ("rounded-fidelity",)
    for profile in profiles
        x=F.generate(case.family,case.n,case.m,case.replicate;profile)
        directory=joinpath(root,case.family);mkpath(directory)
        relative=joinpath(case.family,x.id*".toml");path=joinpath(root,relative)
        open(path,"w") do io;TOML.print(io,F.instance_record(x);sorted=true);end
        digest=bytes2hex(sha256(read(path)))
        digest==F.instance_hash(x) || error("Concrete source hash mismatch")
        push!(ledger,Dict("instance_id"=>x.id,"family"=>x.family,"profile"=>profile,
            "file"=>relative,"sha256"=>digest,"n"=>case.n,"m"=>case.m,
            "replicate"=>case.replicate,"direct"=>F.has_direct_baseline(case)))
    end
end
length(ledger)==456 && count(e->e["direct"],ledger)==396 || error("Incomplete input grid")
open(joinpath(root,"inventory.toml"),"w") do io
    TOML.print(io,Dict("schema_version"=>1,"generator_runtime"=>string(VERSION),"instances"=>ledger);sorted=true)
end
println("Prepared ",length(ledger)," concrete profiles; no measurements performed.")
