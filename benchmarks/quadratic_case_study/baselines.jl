module FreshDirectBaselines
using ..FreshQuadraticModels
import SCIP
# Precompilation can initialize a licensed backend before Env is called below.
# Keep that native output local and disposable too.
mktemp() do path,io
    Base.Libc.flush_cstdio()
    redirect_stdio(;stdout=io,stderr=io) do
        try
            @eval import Gurobi
        finally
            Base.Libc.flush_cstdio()
        end
    end
end
const F=FreshQuadraticModels
const M=F.M

struct Factory
    backend::String
    environment::Any
    availability::Dict{String,Any}
end

function select_factory(;prefer_gurobi=true)
    environment=nothing
    diagnostic=Dict{String,Any}("gurobi_requested"=>prefer_gurobi)
    if prefer_gurobi
        # GRBemptyenv can print account details before OutputFlag takes effect.
        # Capture native file descriptors as well as Julia streams; never archive
        # license text or include it in structured diagnostic messages.
        mktemp() do path,io
            Base.Libc.flush_cstdio()
            redirect_stdio(;stdout=io,stderr=io) do
                try
                    environment=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
                    diagnostic["gurobi_available"]=true
                catch err
                    diagnostic["gurobi_available"]=false
                    diagnostic["error_type"]=string(nameof(typeof(err)))
                    hasproperty(err,:code) && (diagnostic["error_code"]=getproperty(err,:code))
                finally
                    Base.Libc.flush_cstdio()
                end
            end
        end
    end
    return Factory(isnothing(environment) ? "SCIP" : "Gurobi",environment,diagnostic)
end

function optimizer(factory::Factory;seconds=300.0)
    0<seconds<=300 || throw(ArgumentError("Invalid direct-solver time cap"))
    if factory.backend=="Gurobi"
        raw=Gurobi.Optimizer(factory.environment)
        M.set(raw,M.Silent(),true)
        for (name,value) in (("Threads",1),("Seed",777),("NonConvex",2),
                             ("MIPGap",0.0),("MIPGapAbs",0.0),
                             ("IntFeasTol",1e-9),("FeasibilityTol",1e-9))
            M.set(raw,M.RawOptimizerAttribute(name),value)
        end
        model=raw
    else
        raw=SCIP.Optimizer()
        M.set(raw,M.Silent(),true)
        for (name,value) in (("parallel/maxnthreads",1),
                             ("randomization/randomseedshift",777),
                             ("limits/gap",0.0),("limits/absgap",0.0))
            M.set(raw,M.RawOptimizerAttribute(name),value)
        end
        model=M.Bridges.full_bridge_optimizer(raw,Float64)
    end
    M.set(model,M.TimeLimitSec(),seconds)
    return model,raw
end

finite_record(value)=isfinite(value) ? value :
    value>0 ? "+infinity" : value<0 ? "-infinity" : "NaN"

function solve(instance,factory::Factory;seconds=300.0)
    constructed=@timed F.source_model(instance)
    source=constructed.value
    variables=M.get(source,M.ListOfVariableIndices())
    model,raw=optimizer(factory;seconds)
    try
        copied=@timed M.copy_to(model,source)
        solved=@timed M.optimize!(model)
        result=Dict{String,Any}("instance_id"=>instance.id,"source_hash"=>F.instance_hash(instance),
            "backend"=>factory.backend,"solver_version"=>M.get(model,M.SolverVersion()),
            "threads"=>1,"seed"=>777,"time_limit_seconds"=>seconds,
            "relative_gap_limit"=>0.0,"absolute_gap_limit"=>0.0,
            "construction_seconds"=>constructed.time,"source_copy_seconds"=>copied.time,
            "optimize_wall_seconds"=>solved.time,
            "termination"=>string(M.get(model,M.TerminationStatus())),
            "result_count"=>M.get(model,M.ResultCount()),
            "objective_bound"=>finite_record(M.get(model,M.ObjectiveBound())),
            "primal_available"=>false,"source_feasible"=>false,
            "certification"=>"numerical-global-solver-status-not-exhaustive-proof")
        if result["result_count"]>0
            status=M.get(model,M.PrimalStatus())
            result["primal_status"]=string(status)
            if status in (M.FEASIBLE_POINT,M.NEARLY_FEASIBLE_POINT)
                point=[M.get(model,M.VariablePrimal(),copied.value[v]) for v in variables]
                result["primal_available"]=true
                result["raw_point"]=point
                result["solver_objective"]=finite_record(M.get(model,M.ObjectiveValue()))
                integer=all(isfinite,point) && all(abs(x-round(x))<=1e-6 for x in point) &&
                    all(instance.lower.-1e-6 .<= point .<= instance.upper.+1e-6)
                if integer
                    rounded=round.(Int,point)
                    result["rounded_point"]=rounded
                    result["source_feasible"]=F.feasible(instance,rounded)
                    result["source_objective"]=F.objective(instance,rounded)
                    result["exact_dyadic_source_objective"]=string(F.exact_objective(instance,rounded))
                end
            end
        end
        return result
    finally
        finalize(raw)
    end
end
end
