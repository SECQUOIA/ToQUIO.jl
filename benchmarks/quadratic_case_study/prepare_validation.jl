# New manufactured fixtures only. This does not generate campaign-grid instances.
include("models.jl")
using .FreshQuadraticModels,TOML,SHA
const F=FreshQuadraticModels
root=abspath(only(ARGS));mkpath(root);isempty(readdir(root)) || error("Refuse existing validation inputs")
entries=Dict{String,Any}[]
for instance in F.manufactured_fixtures()[1:4]
    file=instance.id*".toml"
    open(joinpath(root,file),"w") do io;TOML.print(io,F.instance_record(instance);sorted=true);end
    push!(entries,Dict("instance_id"=>instance.id,"file"=>file,"sha256"=>F.instance_hash(instance),
        "family"=>instance.family,"profile"=>instance.profile,"n"=>2,"m"=>2,"replicate"=>1,"direct"=>true))
end
open(joinpath(root,"inventory.toml"),"w") do io;TOML.print(io,Dict("instances"=>entries);sorted=true);end
println("Prepared four manufactured validation fixtures; no campaign-grid instances.")
