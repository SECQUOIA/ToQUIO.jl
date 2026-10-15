using Test
using ToQUIO

@testset "ToQUIO" begin
    include("unit/maintenance.jl")
    include("unit/to_quio_regression.jl")
    include("unit/reformulation_metadata.jl")
    include("unit/penalty_controls.jl")
    include("unit/feasibility.jl")
    include("unit/encoding_interface.jl")
    include("unit/radix_encoding.jl")
    include("unit/bounded_encoding.jl")
    include("unit/exact_ilp.jl")
    include("unit/penalty_documentation.jl")
    include("unit/study_protocol.jl")
    include("../benchmarks/test_core.jl")
    include("../benchmarks/test_analysis.jl")
    include("test_examples.jl")
end
