@doc raw"""
    AbstractEncodingMethod{T}
"""
abstract type AbstractEncodingMethod{T} end

@doc raw"""
    encode(var::Function, vi::VI, ::E) where {T,E<:AbstractEncodingMethod{T}}

where

var : Int -> Vector{VI}
var : Nothing -> VI

"""
function encode end

@doc raw"""
    DigitalEncoding{T,N}
"""
struct DigitalEncoding{T,N} <: AbstractEncodingMethod{T}
    lower::T
    upper::T

    function DigitalEncoding{T,N}(lower::Real, upper::Real) where {T,N}
        @assert N isa Integer && N >= 1

        return new{T,N}(
            convert(T, lower),
            convert(T, upper),
        )
    end
end

DigitalEncoding{T}(lower, upper; base::Integer) where {T} = DigitalEncoding{T, base}(lower, upper)
DigitalEncoding(lower, upper; base::Integer)              = DigitalEncoding{Float64}(lower, upper; base)

const UnaryEncoding{T}   = DigitalEncoding{T,1}
const BinaryEncoding{T}  = DigitalEncoding{T,2}
const DecimalEncoding{T} = DigitalEncoding{T,10}

function nvars(enc::DigitalEncoding{T,N}) where {T,N}
    a = ceil(T, enc.lower)
    b = floor(T, enc.upper)

    @assert a < b

    ℓ = b - a

    return ceil(Int, log(N, ℓ) + 1)
end

function encode(enc::DigitalEncoding{T,N}) where {T,N}
    a = ceil(T, enc.lower)
    b = floor(T, enc.upper)

    @assert a < b

    ℓ = b - a
    n = nvars(enc)

    l = zeros(T, n)                           # lower
    u = [fill(N, n - 1); ℓ - N ^ (n - 1) + 1] # upper
    e = [[N ^ (j - 1) for j = 1:(n - 1)]; 1]  # coeffs

    return (l, u, e)
end