# This file is included inside FreshQuadraticModels. Exact oracles evaluate the
# original equations, without constructing a penalized/encoded target.
function exact_objective(instance::Instance,x)
    value=zero(Rational{BigInt})
    for j in eachindex(x),i in eachindex(x)
        value+=Rational{BigInt}(instance.quadratic[i,j])*big(x[i])*big(x[j])
    end
    for i in eachindex(x)
        value+=Rational{BigInt}(instance.linear[i])*big(x[i])
    end
    return value
end

function exact_reference(instance::Instance;max_states=1_000_000)
    validate_instance(instance)
    max_states isa Integer && 0<=max_states<=1_000_000 ||
        throw(ArgumentError("Invalid exact-reference allowance"))
    states=prod(big(u)-l+1 for (l,u) in zip(instance.lower,instance.upper);init=big(1))
    0<states<=max_states || throw(ArgumentError("Source enumeration exceeds its allowance"))
    operations=states*(big(length(instance.lower))^2+sum(length,instance.rows;init=0))
    operations<=20_000_000 || throw(ArgumentError("Source oracle exceeds its operation allowance"))
    best=nothing;best_point=Int[];count_feasible=0;optimal_count=0
    for point in Iterators.product((l:u for (l,u) in zip(instance.lower,instance.upper))...)
        feasible(instance,point) || continue
        count_feasible+=1
        value=exact_objective(instance,point)
        if isnothing(best) || (instance.sense=="min" ? value<best : value>best)
            best=value;best_point=collect(point);optimal_count=0
        end
        value==best && (optimal_count+=1)
    end
    return (status=isnothing(best) ? "EXACT_INFEASIBLE" : "EXACT_OPTIMAL",
        objective=best,point=best_point,optimal_count=optimal_count,
        states=states,feasible_states=count_feasible)
end

function manufactured_fixtures()
    parameters=Dict{String,Any}("purpose"=>"independent-hand-computable-validation")
    make(id,family,l,u,Q,g,sense,rows,relations,rhs,witness)=Instance(
        id,family,"manufactured",zero(UInt64),copy(parameters),l,u,Float64.(Q),
        Float64.(g),sense,rows,relations,rhs,witness)
    facility=make("fixture-facility","facility",[0,0,0],[2,2,1],
        [1 1 0;1 0 0;0 0 0],[0,0,3],"min",
        [[1=>1],[2=>1],[1=>1,2=>1,3=>-2],[1=>1,3=>-1],[2=>1,3=>-1]],
        ["eq","eq","le","le","le"],[1,1,0,0,0],[1,1,1])
    inventory=make("fixture-inventory","inventory",[0,0,0,0],[4,4,2,2],
        [1/16 2/16 0 0;2/16 1/16 0 0;0 0 0 0;0 0 0 0],
        [1/2,1/4,-1,-1],"min",
        [[1=>1,2=>1],[3=>1,4=>1],[3=>1,1=>-1],[4=>1,2=>-1]],
        fill("le",4),[4,2,0,0],[0,0,0,0])
    route=make("fixture-route","route_allocation",[1,1,0,0],[2,2,2,2],
        [1/4 1/8 0 0;1/8 1/2 0 0;0 0 0 0;0 0 0 0],
        [1,2,0,0],"min",[[1=>-1,2=>-1,3=>1,4=>1]],["eq"],[0],[1,1,2,0])
    knapsack=make("fixture-knapsack","knapsack",[0,0],[2,2],
        [2 1;1 3],[0,0],"max",[[1=>1,2=>2]],["le"],[3],[0,0])
    wide=make("fixture-weight-cap64","wide",[0],[1024],
        reshape([1],1,1),[-1026],"min",Vector{Pair{Int,Int}}[],String[],Int[],[513])
    return [facility,inventory,route,knapsack,wide]
end
