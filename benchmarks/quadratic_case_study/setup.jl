using Pkg
const HERE = @__DIR__
Pkg.activate(HERE)
# Hydrate the frozen git source without re-resolving the portable local package.
Pkg.instantiate(; allow_autoprecomp=false)
