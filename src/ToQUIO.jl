module ToQUIO

import MathOptInterface as MOI

const MOIU   = MOI.Utilities
const VI     = MOI.VariableIndex
const EQ{T}  = MOI.EqualTo{T}
const LT{T}  = MOI.LessThan{T}
const GT{T}  = MOI.GreaterThan{T}
const SAF{T} = MOI.ScalarAffineFunction{T}
const SQF{T} = MOI.ScalarQuadraticFunction{T}

const Maybe{T} = Union{T,Nothing}

@doc raw"""
    to_quio(model::MOI.ModelLike)
"""
function to_quio end

include("MOI_wrapper/QUIO_model.jl")
include("MOI_wrapper/MOI_wrapper.jl")

include("to_quio.jl")

end # module ToQUIO
