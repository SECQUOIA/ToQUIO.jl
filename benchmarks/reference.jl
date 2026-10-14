using HiGHS

function highs_reference(instance::Instance; max_seconds = PROTOCOL["reference"]["max_seconds_per_instance"])
    source_guard(instance)
    0 < max_seconds <= 10 || throw(ArgumentError("Reference solve exceeds frozen time allowance."))
    version = Pkg.dependencies()[Base.PkgId(HiGHS).uuid].version
    version == v"1.26.0" || error("HiGHS.jl differs from the frozen reference pin.")
    solver = HiGHS.Optimizer()
    M.set(solver, M.Silent(), true)
    M.set(solver, M.TimeLimitSec(), Float64(max_seconds))
    for (name, value) in (("threads", 1), ("random_seed", 777), ("mip_rel_gap", 0.0), ("mip_abs_gap", 0.0))
        M.set(solver, M.RawOptimizerAttribute(name), value)
    end
    built = @timed source_model(instance)
    copied = @timed M.copy_to(solver, built.value)
    solved = @timed M.optimize!(solver)
    termination = M.get(solver, M.TerminationStatus())
    primal = M.get(solver, M.PrimalStatus())
    point, raw_point = Int[], Float64[]
    objective, bound, valid = "missing", "missing", false
    if M.get(solver, M.ResultCount()) > 0 && primal in (M.FEASIBLE_POINT, M.NEARLY_FEASIBLE_POINT)
        raw_point = [M.get(solver, M.VariablePrimal(), copied.value[v]) for
                 v in M.get(built.value, M.ListOfVariableIndices())]
        oracle = native_optimizer(instance)
        valid = ToQUIO.is_feasible(oracle, native_source_point(oracle, raw_point);
                                   atol = PROTOCOL["source_feasibility_atol"])
        valid == source_feasible(instance, raw_point; atol = PROTOCOL["source_feasibility_atol"]) ||
            error("Reference feasibility API disagreement.")
        if valid
            point = integral_reference_point(instance, raw_point)
            objective = Float64(source_value(instance, point))
        end
    end
    bound = M.get(solver, M.ObjectiveBound())
    return Dict{String,Any}("status" => string(termination), "primal_status" => string(primal),
        "point" => point, "raw_point" => raw_point, "objective" => objective, "objective_bound" => bound,
        "source_feasible" => valid, "source_hash" => instance_hash(instance),
        "source_sense" => instance.sense, "solver" => "HiGHS", "solver_jl_version" => string(version),
        "solver_library_version" => M.get(solver, M.SolverVersion()),
        "threads" => 1, "seed" => 777, "time_limit_seconds" => max_seconds,
        "mip_relative_gap" => 0.0, "mip_absolute_gap" => 0.0,
        "construction_seconds" => built.time, "backend_copy_seconds" => copied.time,
        "optimization_wall_seconds" => solved.time, "solver_seconds" => M.get(solver, M.SolveTimeSec()),
        "certificate" => termination == M.OPTIMAL ? "numerical-MIP-with-solver-tolerances" : "bounded-incumbent",
        "target_label" => "frozen-best-known-feasible-incumbent-never-exact-arithmetic-proof")
end
