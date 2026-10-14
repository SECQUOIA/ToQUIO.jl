module CQTBenchmarks
using ToQUIO, Random, SHA, TOML, LinearAlgebra, Pkg
const M = ToQUIO.MOI
const ROOT = dirname(@__DIR__)
const PROTOCOL = TOML.parsefile(joinpath(@__DIR__, "protocol_v1.toml"))
# These literal implementation limits belong to protocol v1. Any protocol edit
# must update the implementation deliberately, rather than archiving unused knobs.
let resources = PROTOCOL["resources"], sampler = PROTOCOL["metropolis"], reference = PROTOCOL["reference"]
    for (key, expected) in (("max_target_variables", 256), ("max_native_width", 64),
                           ("max_states_per_enumeration", 1_000_000),
                           ("max_total_enumerated_states", 4_000_000))
        resources[key] == expected || error("Unsupported protocol-v1 implementation limit: $key.")
    end
    sampler["proposal_seed_offset"] == 1_000_000_000 && PROTOCOL["pilot_bounded_weight"] == 2 ||
        error("Unsupported protocol-v1 seed offset/pilot cap.")
    reference["threads"] == 1 && reference["random_seed"] == 777 &&
        reference["mip_relative_gap"] == reference["mip_absolute_gap"] == 0.0 ||
        error("Unsupported protocol-v1 reference settings.")
    first(PROTOCOL["families"])["capacity_fraction"] == 0.45 ||
        error("Unsupported protocol-v1 knapsack capacity fraction.")
end
struct VerificationError <: Exception
    message::String
end
Base.showerror(io::IO, e::VerificationError) = print(io, e.message)
include("protocol_helpers.jl")
include("corpus.jl")
include("metropolis.jl")
include("compilers.jl")
include("preflight.jl")
include("artifacts.jl")
end
