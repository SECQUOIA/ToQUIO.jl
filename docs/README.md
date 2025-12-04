# ToQUIO.jl Documentation

Welcome to the ToQUIO.jl documentation! This directory contains detailed documentation for developers and users.

## Contents

- [API Reference](api.md) - Complete API documentation
- [Examples](examples.md) - Detailed usage examples
- [Algorithm](algorithm.md) - Mathematical details of the reformulation
- [Development Guide](../CONTRIBUTING.md) - Contributing guidelines

## Quick Links

- [Main README](../README.md)
- [Project Repository](https://github.com/SECQUOIA/ToQUIO.jl)

## Overview

ToQUIO.jl transforms constrained integer optimization problems into Quadratic Unconstrained Integer Optimization (QUIO) format. The reformulation uses quadratic penalty functions to handle constraints, making the problems suitable for QUIO-specialized solvers.

### Core Concepts

1. **Penalty Methods**: Constraints are incorporated into the objective using quadratic penalties
2. **Slack Variables**: Inequality constraints use slack variables to avoid infeasibility
3. **Automatic Penalty Computation**: Penalty coefficients are computed based on problem structure
4. **MOI Integration**: Seamless integration with Julia's optimization ecosystem

### Getting Started

If you're new to ToQUIO.jl, start with:
1. The [main README](../README.md) for installation and quick start
2. [Examples](examples.md) for common use cases
3. [API Reference](api.md) for detailed function documentation

### For Developers

If you're contributing to ToQUIO.jl:
1. Read the [CONTRIBUTING guide](../CONTRIBUTING.md)
2. Understand the [Algorithm](algorithm.md)
3. Review the [API Reference](api.md) for implementation details
