baremodule Reagents

export ⨟, compose, opcompose

import Base

using CompositionsBase: ⨟, compose, opcompose

abstract type Reagent end

abstract type Ref{T} end

abstract type Failure end
struct Block <: Failure end
struct Retry <: Failure end

# The original implementation by Turon (2012) combines what is called `Reactor`
# and `Reagent` here simply as reagent.  This is structurally identical to how
# Transducers.jl splits transducers (`Reagent` here) and reducing functions
# (`Reactor` here). It makes implemneting the pairting combinator `&` (`Both`)
# easier (which is similar to `Transducers.TeeZip`).
struct Reactor{R<:Reagent,C}
    reagent::R
    continuation::C
end

# TODO: Is it better to provide factory functions like `updating(f, ref)`
# instead of exposing types (constructors) which is rather leaky?

struct Identity <: Reagent end

struct Update{F,R<:Ref} <: Reagent
    f::F
    ref::R
end

struct Read{R<:Ref} <: Reagent
    ref::R
end

struct CAS{T,R<:Ref{T}} <: Reagent
    ref::R
    old::T
    new::T
end

struct Return{T} <: Reagent
    value::T
end

struct Computed{F} <: Reagent
    f::F
end

struct Map{F} <: Reagent
    f::F
end

struct WithNack{F} <: Reagent
    f::F
end

struct Until{F,R<:Reagent} <: Reagent
    f::F
    reagent::R
end

struct PostCommit{F} <: Reagent
    f::F
end

function channel end
function dissolve end

function try! end
function trysync! end

module Internal

using Accessors: @set
using CompositionsBase: ⨟

using ..Reagents:
    Block,
    CAS,
    Computed,
    Failure,
    Identity,
    Map,
    PostCommit,
    Reactor,
    Read,
    Reagent,
    Reagents,
    Retry,
    Return,
    Until,
    Update,
    WithNack

include("utils.jl")
include("immutablelists.jl")
include("tracing.jl")
include("anchors.jl")
include("reactions.jl")
include("react.jl")
include("combinators.jl")
include("computational.jl")
include("refs.jl")
include("bags.jl")
include("channels.jl")
include("dissolve.jl")

end  # module Internal

# For defining the docstrings
const (|) = Internal.Base.:|
const (&) = Internal.Base.:&

module __Reagents_API__
using ..Reagents
export ⨟, compose, opcompose, Reagents

module DefaultNames end

for n in names(Reagents; all = true)
    try
        getfield(DefaultNames, n)
        continue
    catch
    end
    match(r"^[a-z]"i, string(n)) === nothing && continue
    x = try
        getfield(Reagents, n)
    catch
        continue
    end
    x isa Union{Type,Function} || continue
    @eval begin
        $n = $x
        export $n
    end
end

end  # module __Reagents_API__

"""
    Reagents.*

A module that re-exports a subset of Reagents public API at top-level.

Use `using Reagents.*` to import all public APIs. Do not use this inside a
package. The set of exported names is not the part of stable API. For example,
if a name collistion with `Base` or important packages are recognized, the
corresponding name may be removed in the next realease, without incrementing
the leading non-zero version number.
"""
const * = __Reagents_API__

Internal.define_docstrings()

end  # baremodule Reagents
