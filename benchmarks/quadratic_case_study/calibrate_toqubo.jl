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
for j in 1:m;add([[pos(i,j)=>1 for i in 1:n];[d+j=>-200]],"le",0);end
for i in 1:n,j in 1:m;add([pos(i,j)=>1,d+j=>-200],"le",0);end
x=F.Instance("resource-calibration","facility","manufactured",UInt64(0),Dict{String,Any}(),
    zeros(Int,N),[fill(1000,d);fill(5,m)],Q,[zeros(d);ones(m)],"min",rows,rel,rhs,nothing)

for arm in ("toqubo-controlled-binary","toqubo-default-binary")
    c=C.compile(F.manufactured_fixtures()[4],arm);c=nothing;GC.gc()
    c=C.compile(x,arm)
    println("CALIBRATION_COMPILED arm=",arm," dimension=",length(c.polynomial.g),
        " peak_bytes=",read("/sys/fs/cgroup/memory.peak",String))
    c=nothing;GC.gc()
end
