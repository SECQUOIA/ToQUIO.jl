# ToQUIO.jl Documentation

Welcome to the ToQUIO.jl documentation! This directory contains detailed documentation for developers and users.

## Documentation Index

### For Users
- **[Main README](../README.md)** - Start here for overview, installation, and basic usage
- **[Examples](examples.md)** - 15+ detailed examples covering various problem types
- **[API Reference](api.md)** - Complete API documentation for all public functions

### For Developers
- **[QUICKSTART](QUICKSTART.md)** - ⭐ Quick reference for developers (5-minute setup)
- **[Contributing Guide](../CONTRIBUTING.md)** - Development setup, code style, PR process
- **[Algorithm Details](algorithm.md)** - Mathematical formulation and derivation

## Quick Navigation

### New to ToQUIO.jl?
1. Read [README](../README.md) for project overview
2. Try the [Quick Start example](../README.md#quick-start)
3. Explore [Examples](examples.md) for your use case

### Want to Contribute?
1. Read [QUICKSTART](QUICKSTART.md) for fast setup
2. Follow [CONTRIBUTING](../CONTRIBUTING.md) guidelines

### Need API Details?
1. Check [API Reference](api.md) for function signatures
2. See [Algorithm](algorithm.md) for mathematical background
3. Look at [Examples](examples.md) for usage patterns

## Overview

ToQUIO.jl transforms constrained integer optimization problems into Quadratic Unconstrained Integer Optimization (QUIO) format. The reformulation uses quadratic penalty functions to handle constraints, making the problems suitable for QUIO-specialized solvers.

### Core Concepts

1. **Penalty Methods**: Constraints are incorporated into the objective using quadratic penalties
2. **Slack Variables**: Inequality constraints use slack variables to avoid infeasibility
3. **Automatic Penalty Computation**: Penalty coefficients are computed based on problem structure
4. **MOI Integration**: Seamless integration with Julia's optimization ecosystem

## Documentation Files

| File | Description | Audience |
|------|-------------|----------|
| [README.md](README.md) | Documentation index (this file) | All |
| [QUICKSTART.md](QUICKSTART.md) | Quick developer reference | Developers |
| [api.md](api.md) | Complete API reference | Developers |
| [algorithm.md](algorithm.md) | Mathematical details | Researchers |
| [examples.md](examples.md) | Usage examples | Users |

## External Links

- [GitHub Repository](https://github.com/SECQUOIA/ToQUIO.jl)
- [JuMP Documentation](https://jump.dev/JuMP.jl/stable/)
- [MathOptInterface Documentation](https://jump.dev/MathOptInterface.jl/stable/)

## Getting Help

- **Issues**: Report bugs or request features on [GitHub Issues](https://github.com/SECQUOIA/ToQUIO.jl/issues)
- **Documentation**: Search this documentation
- **Examples**: Check [examples.md](examples.md) for similar use cases

## License

ToQUIO.jl is licensed under the Mozilla Public License Version 2.0. See the [LICENSE](../LICENSE) file for details.
