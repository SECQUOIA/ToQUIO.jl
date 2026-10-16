# Included within FreshCompilers. Matrix diagnostics describe this representation.
function arrayhash(values)
    a=values isa Array{Float64} ? values : Array{Float64}(values)
    bytes2hex(sha256(reinterpret(UInt8,vec(a))))
end
function polynomial_hash(p)
    io=IOBuffer();print(io,arrayhash(p.G),'|',arrayhash(p.g),'|',repr(p.constant),'|',p.sense,'|')
    TOML.print(io,Dict("lower"=>p.lower,"upper"=>p.upper);sorted=true)
    bytes2hex(sha256(take!(io)))
end
function mapping_hash(c)
    io=IOBuffer();TOML.print(io,Dict("maps"=>maprecord.(c.maps));sorted=true)
    bytes2hex(sha256(take!(io)))
end
function canonicalize(p;consume=false)
    active=findall(p.lower.<p.upper);offset=Float64.(p.lower)
    g=(p.g+p.G*offset+p.G'*offset)[active]
    constant=energy(p,offset)
    G=consume && length(active)==length(p.g) ? p.G : p.G[active,active]
    widths=(p.upper-p.lower)[active]
    for j in eachindex(widths),i in 1:j
        if i!=j
            a=(G[i,j]+G[j,i])/2;G[i,j]=a;G[j,i]=a
        elseif widths[i]==1
            g[i]+=G[i,i];G[i,i]=0.0
        end
    end
    (G=G,g=g,constant=constant,widths=widths,active=active)
end
function structural(c;consume=false,spectral=true)
    p=c.polynomial
    rawhash=polynomial_hash(p);projectionhash=mapping_hash(c)
    canonical=canonicalize(p;consume);G=canonical.G;g=canonical.g;n=length(g)
    squares=0;linear=0;couplers=0;lo=Inf;hi=0.0
    for a in g
        if !iszero(a);linear+=1;lo=min(lo,abs(a));hi=max(hi,abs(a));end
    end
    for j in 1:n,i in 1:j
        a=(i==j ? G[i,i] : 2G[i,j])
        if !iszero(a)
            i==j ? (squares+=1) : (couplers+=1)
            lo=min(lo,abs(a));hi=max(hi,abs(a))
        end
    end
    io=IOBuffer();print(io,arrayhash(G),'|',arrayhash(g),'|',repr(canonical.constant),'|',p.sense,'|')
    TOML.print(io,Dict("widths"=>canonical.widths);sorted=true)
    canonicalhash=bytes2hex(sha256(take!(io)))
    widths=p.upper-p.lower
    result=Dict{String,Any}("logical_variables"=>length(p.g),"active_variables"=>n,
        "source_coordinates_including_slacks"=>length(c.maps),
        "total_domain_width"=>sum(widths),"total_domain_levels"=>sum(widths.+1),
        "max_domain_levels"=>maximum(widths.+1;init=0),
        "binary_variables"=>count(==(1),widths),"fixed_variables"=>count(iszero,widths),
        "nonbinary_variables"=>count(>(1),widths),"nonbinary_square_terms"=>squares,
        "linear_terms"=>linear,"unique_couplers"=>couplers,
        "density_denominator"=>n*(n-1)÷2,
        "density_status"=>(n<2 ? "undefined-fewer-than-two-active-variables" : "defined"),
        "density"=>(n<2 ? "undefined" : couplers/(n*(n-1)÷2)),
        "linear_density"=>(n==0 ? "undefined" : linear/n),
        "square_density"=>(n==0 ? "undefined" : squares/n),
        "coefficient_min_nonzero"=>(isfinite(lo) ? lo : "undefined"),
        "coefficient_max"=>hi,"coefficient_ratio"=>(hi==0 ? "undefined" : hi/lo),
        "raw_polynomial_sha256"=>rawhash,"canonical_polynomial_sha256"=>canonicalhash,
        "source_projection_sha256"=>projectionhash,
        "hash_array_format"=>"Float64-column-major-$(ENDIAN_BOM==0x04030201 ? "little" : "big")-endian",
        "spectral_convention"=>"canonical-symmetric-energy-matrix-after-binary-square-folding",
        "spectral_interpretation"=>"coefficient-matrix-not-discrete-optimization-or-quantum-gap")
    if spectral
        measured=@timed (n==0 ? Float64[] : eigvals!(Symmetric(G)))
        eigen=measured.value
        result["spectral_seconds"]=measured.time
        result["eigenvalues"]=eigen
        result["minimum_eigenvalue_spacing"]=n<2 ? "undefined" : minimum(diff(eigen))
        a=abs.(eigen);amax=maximum(a;init=0.0);amin=minimum(a;init=Inf)
        threshold=eps(Float64)*max(1,n)*amax
        result["spectral_zero_threshold"]=threshold
        result["symmetric_2norm_condition_status"]=n==0 ? "undefined-empty" :
            amin<=threshold ? "numerically-singular" : "finite"
        result["symmetric_2norm_condition"]=n==0 ? "undefined" : amin<=threshold ? "+infinity" : amax/amin
    else
        result["spectral_status"]="not-requested"
    end
    result
end
