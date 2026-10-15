# Included inside FreshCompilers; local software analogue, no provider calls.
function chain_seed(instance,batch,read)
    h=sha256("fresh-quadratic-case-study-v1-knapsack-chains|$(instance.id)|$batch|$read")
    x=zero(UInt64)
    for b in h[1:8];x=(x<<8)|UInt64(b);end
    Int(x%UInt64(typemax(Int)-1_000_000_000))
end
function objective_scale(instance)
    u=max.(abs.(instance.lower),abs.(instance.upper))
    max(1.0,2sum(abs(instance.quadratic[i,j])*u[i]*u[j] for j in eachindex(u),i in eachindex(u))+
        2sum(abs.(instance.linear).*u))
end
function sampled_chain(instance,c;batch,read,reserved_proposals=4000,max_seconds=2.0,
                       completed_limit=reserved_proposals,clock=time_ns,check_deltas=false)
    instance.family=="knapsack" || throw(ArgumentError("Only knapsack sampling is preregistered"))
    seed=chain_seed(instance,batch,read);n=length(instance.lower)
    function initialize(rng)
        native=[rand(rng,m.lower:m.upper) for m in c.maps]
        lift(c,native)
    end
    function observe(z)
        x=decode(c,z,n);valid=F.feasible(instance,x)
        (feasible=valid,objective=F.objective(instance,x),sense=instance.sense,source=x,target=false)
    end
    result=metropolis(c.polynomial,initialize,observe;seed,reserved_proposals,completed_limit,
        max_sweeps=reserved_proposals,max_seconds,temperature_start=2.0,temperature_end=0.01,
        energy_scale=objective_scale(instance),clock,check_deltas)
    terminal=observe(result["final"])
    merge!(result,Dict("instance_id"=>instance.id,"arm"=>c.record["arm"],"batch"=>batch,"read"=>read,
        "source_hash"=>F.instance_hash(instance),"polynomial_sha256"=>polynomial_hash(c.polynomial),
        "source_projection_sha256"=>mapping_hash(c),"terminal_source"=>terminal.source,
        "terminal_source_feasible"=>terminal.feasible,"terminal_source_objective"=>terminal.objective,
        "terminal_target_energy"=>energy(c.polynomial,result["final"]),
        "experiment_type"=>"local-software-analogue-not-hardware",
        "first_feasible_censored"=>result["first_feasible_proposal"]=="missing"))
    result
end
function replay_chain(instance,c,record)
    # Clock-independent replay fixes *actual* completed work, not the reserved cap.
    # It reproduces proposal decisions/observations; wall timestamps are not replayable.
    constant_clock=()->UInt64(0)
    replay=sampled_chain(instance,c;batch=record["batch"],read=record["read"],
        reserved_proposals=record["reserved_proposals"],completed_limit=record["completed_proposals"],
        max_seconds=record["max_seconds"],clock=constant_clock)
    fields=("seed","initial","final","samples","move_counts","completed_proposals",
        "source_observations","best_feasible_objective","best_feasible_source","any_feasible",
        "first_feasible_proposal","terminal_source","terminal_source_feasible",
        "terminal_source_objective","terminal_target_energy","polynomial_sha256","source_projection_sha256")
    for key in fields;replay[key]==record[key] || throw(VerificationError("Replay mismatch: $key"));end
    true
end
