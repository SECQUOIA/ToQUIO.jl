module ToQUIO

import MathOptInterface as MOI

using LinearAlgebra

const MOIU    = MOI.Utilities
const VI      = MOI.VariableIndex
const CI{F,S} = MOI.ConstraintIndex{F,S}
const EQ{T}   = MOI.EqualTo{T}
const LT{T}   = MOI.LessThan{T}
const GT{T}   = MOI.GreaterThan{T}
const SAF{T}  = MOI.ScalarAffineFunction{T}
const SQF{T}  = MOI.ScalarQuadraticFunction{T}

const Maybe{T} = Union{T,Nothing}

@doc raw"""
    to_quio(model::MOI.ModelLike)
"""
function to_quio end

include("MOI_wrapper/QUIO_model.jl")
include("encoding.jl")
include("radix_encoding.jl")
include("bounded_encoding.jl")
include("MOI_wrapper/MOI_wrapper.jl")

include("to_quio.jl")
include("reformulation.jl")
include("encoding_metadata.jl")
include("feasibility.jl")

export reformulation_metadata, original_variables, auxiliary_variables, project_original_state
export ConstraintViolation, violations, is_feasible, feasibility_report
export AbstractIntegerEncoding, NativeEncoding, IntegerVariableEncoding
export variable_encoding, encoding_descriptor, EncodingStrategy, MaxEncodedVariables
export project_native_state, lift_native_state
export RadixEncoding
export BoundedEncoding

end # module ToQUIO
