using Test
using ToQUIO

@testset "ToQUIO" begin
    include("unit/maintenance.jl")
    include("test_examples.jl")
end
