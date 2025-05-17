#                           get set supports
# [x] SolverName	        Yes	No	No
function MOI.get(solver::Optimizer{T}, attr::MOI.SolverName) where {T}
    if isnothing(solver.inner)
        return "ToQUIO Optimizer (reformulation mode)"
    else
        return "ToQUIO Optimizer ($(MOI.get(solver.inner, attr)))"
    end
end

# [x] SolverVersion	        Yes	No	No
function MOI.get(::Optimizer{T}, ::MOI.SolverVersion) where {T}
    return v"0.1.0" # Package Version
end 

# [x] RawSolver	            Yes	No	No
function MOI.get(solver::Optimizer{T}, ::MOI.RawSolver) where {T}
    return solver.inner
end

# [x] Silent	            Yes	Yes	Yes     - check on QCI on how to suppress output, return that it's not supported if not; 
# TODO: use redirect_stdout to suppress output? 
function MOI.get(solver::Optimizer{T}, attr::MOI.Silent) where {T}
    return MOI.get(solver.inner, attr)
end

function MOI.set(solver::Optimizer{T}, attr::MOI.Silent, silent::Bool) where {T}
    MOI.set(solver.inner, attr, silent)

    return nothing
end

MOI.supports(solver::Optimizer{T}, attr::MOI.Silent) where {T} = MOI.supports(solver.inner, attr)

# [x] TimeLimitSec	        Yes	Yes	Yes     - check on QCI on how long you allow the solver to run, if not, no support also; might be device dependent; may need to differentiate among the solvers- if tricky do last. 
function MOI.get(solver::Optimizer{T}, attr::MOI.TimeLimitSec) where {T}
    return MOI.get(solver.inner, attr)
end

function MOI.set(solver::Optimizer{T}, attr::MOI.TimeLimitSec, time_limit_sec::Real) where {T}
    MOI.set(solver.inner, attr, time_limit_sec)

    return nothing
end

MOI.supports(solver::Optimizer{T}, attr::MOI.TimeLimitSec) where {T} = MOI.supports(solver.inner, attr)

# [x] RawOptimizerAttribute	Yes	Yes	Yes
function MOI.get(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute) where {T}
    return MOI.get(solver.inner, attr)
end

function MOI.set(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute, value) where {T}
    MOI.set(solver.inner, attr, value)
    
    return nothing
end

function MOI.supports(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute) where {T}
    return MOI.supports(solver.inner, attr)
end

# [x] NumberOfThreads	    Yes	Yes	Yes
function MOI.get(solver::Optimizer{T}, attr::MOI.NumberOfThreads) where {T}
    return MOI.get(solver.inner, attr)
end

function MOI.set(solver::Optimizer{T}, attr::MOI.NumberOfThreads, num_threads::Integer) where {T}
    MOI.set(solver.inner, attr, num_threads)
    
    return nothing
end

MOI.supports(solver::Optimizer{T}, attr::MOI.NumberOfThreads) where {T} = MOI.supports(solver.inner, attr)
