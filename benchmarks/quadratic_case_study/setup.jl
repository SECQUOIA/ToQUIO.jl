using Pkg
const HERE = @__DIR__
const ROOT = normpath(joinpath(HERE,"..",".."))
Pkg.activate(HERE)
Pkg.develop(PackageSpec(path=ROOT))
Pkg.add(PackageSpec(url="https://github.com/JuliaQUBO/ToQUBO.jl",
    rev="69ac52592f4c47ed2168bf480c9947d1fcbbfc2c"))
Pkg.instantiate()
