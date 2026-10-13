using Test
using ToQUIO

@testset "ToQUIO" begin
    include("unit/maintenance.jl")
    include("unit/to_quio_regression.jl")
    include("unit/reformulation_metadata.jl")
    include("unit/penalty_controls.jl")
    include("unit/feasibility.jl")
    include("unit/encoding_interface.jl")
    include("unit/penalty_documentation.jl")
    include("unit/study_protocol.jl")
    include("test_examples.jl")
end
