# Resource calibration only, excluded from campaign outcomes/timing comparisons.
# A manufactured maximal-layout model, with deterministic all-one interactions,
# does not consume any fresh campaign instance or inspect optimization outcomes.
include("models.jl");include("compilers.jl")
using .FreshQuadraticModels,.FreshCompilers, LinearAlgebra
const F=FreshQuadraticModels;const C=FreshCompilers;const M=F.M
n,m=50,16;d=n*m;N=d+m
Q=zeros(N,N);Q[1:d,1:d].=1
rows=Vector{Pair{Int,Int}}[];rel=String[];rhs=Int[]
add(row,r,b)=(push!(rows,row);push!(rel,r);push!(rhs,b))
pos(i,j)=(i-1)*m+j
for i in 1:n;add([pos(i,j)=>1 for j in 1:m],"eq",200);end
for j in 1:m;add([[pos(i,j)=>1 for i in 1:n];[d+j=>-1000]],"le",0);end
for i in 1:n,j in 1:m;add([pos(i,j)=>1,d+j=>-200],"le",0);end
x=F.Instance("resource-calibration","facility","manufactured",UInt64(0),Dict{String,Any}(),
    zeros(Int,N),[fill(5000,d);fill(5,m)],Q,[zeros(d);ones(m)],"min",rows,rel,rhs,nothing)
# Symmetric warmup uses a manufactured tiny box; calibration is not a result arm.
c=C.compile(F.manufactured_fixtures()[4],"binary-radix2");c=nothing;GC.gc()
source=F.source_model(x)
o=C.ToQUIO.Optimizer(;encoding=C.strategy("binary-radix2"),max_encoded_variables=25000)
C.M.optimize!(o,source)
println("CALIBRATION_COMPILED dimension=",length(o.data[:encoded_L]))
# Retain only the encoded polynomial, then release the optimizer/MOI term graph.
d=o.data;p=C.Polynomial(d[:encoded_Q],d[:encoded_L],d[:encoded_c],Int.(d[:encoded_l]),Int.(d[:encoded_u]),"min")
o=nothing;d=nothing;source=nothing;GC.gc()
canonical=C.canonicalize(p;consume=true);p=nothing;GC.gc()
eigvals!(Symmetric(canonical.G))
println("CALIBRATION_SPECTRAL_COMPLETE peak_bytes=",read("/sys/fs/cgroup/memory.peak",String))
