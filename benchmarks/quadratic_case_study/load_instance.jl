# Included within FreshQuadraticModels.
function from_record(r)
    n=length(r["lower"]);n<=1024 || throw(ArgumentError("Archived source exceeds allocation bound"))
    length(r["quadratic_rows"])==n && all(length(row)==n for row in r["quadratic_rows"]) ||
        error("Invalid source matrix")
    Q=zeros(n,n)
    for i in 1:n;Q[i,:]=r["quadratic_rows"][i];end
    instance=Instance(r["id"],r["family"],r["profile"],parse(UInt64,r["seed_hex"];base=16),
        Dict{String,Any}(r["parameters"]),Int.(r["lower"]),Int.(r["upper"]),Q,Float64.(r["linear"]),
        r["sense"],[[Int(t[1])=>Int(t[2]) for t in row] for row in r["rows"]],String.(r["relations"]),
        Int.(r["rhs"]),r["witness_status"]=="source-feasible" ? Int.(r["witness"]) : nothing)
    validate_instance(instance)
end
