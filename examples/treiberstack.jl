# # [Example: Treiber stack](@id ex-treiberstack)

using Reagents

# [Treiber stack](https://en.wikipedia.org/wiki/Treiber_stack) is a simple
# concurrent data structure where an immutable list holds the data items

struct TSNode{T}
    head::T
    tail::Union{TSNode{T},Nothing}
end

const TSList{T} = Union{TSNode{T},Nothing}

# ... which is referenced through an atomically updatable memory location (here,
# a [`Reagents.Ref`](@ref)):

struct TreiberStack{T,Ref<:Reagents.Ref{TSList{T}}}
    head::Ref
end

Base.eltype(::Type{<:TreiberStack{T}}) where {T} = T

# An empty stack can be constructed as a reference to the empty list; i.e.,
# `nothing`:

TreiberStack{T}() where {T} = TreiberStack(Reagents.Ref{TSList{T}}(nothing))

# To push an element to the stack, we can use [`Reagents.Update`](@ref)

pushing(stack::TreiberStack) =
    Reagents.Update((xs, x) -> (TSNode(x, xs), nothing), stack.head)

# Let's see how it works.

using Test

function test_pushing()
    #=
    When a stack is created, its head points to `nothing`:
    =#
    stack = TreiberStack{Int}()
    @test stack.head[] === nothing  # empty

    #=
    We can create a reagent for pushing a value to the stack:
    =#
    reagent = pushing(stack)

    #=
    However, note that reagent does nothing when it's created.
    =#
    @test stack.head[] === nothing  # empty

    #=
    The reagent must be executed ("react") to invoke its side-effect:
    =#
    reagent(111)
    @test stack.head[] === TSNode(111, nothing)
end

# Similarly, we can pop off an element from the stack, again by
# [`Reagents.Update`](@ref). To support empty stack, we return `nothing` when
# it's empty and return `Some(value)` when we find a `value`:

trypopping(stack::TreiberStack) =
    Reagents.Update(stack.head) do xs, _ignored
        if xs === nothing
            return (nothing, nothing)
        else
            return (xs.tail, Some(xs.head))
        end
    end

# Here's how it works.

function test_trypopping()
    #=
    Let's push 111 and then 222 using the `pushing` reagent:
    =#
    stack = TreiberStack{Int}()
    pushing(stack)(111)
    pushing(stack)(222)

    #=
    We can invoke the reagent `trypopping(stack)` by calling it. Since
    `trypopping` ignores the input (see the argument `_ignored` in `trypopping`
    definition above), we can pass an arbitrary value to the reagent, e.g.,
    `nothing`.
    =#
    @test trypopping(stack)(nothing) === Some(222)
    #=
    For convinience, `nothing` is the default argument when the reagent is
    called without an argument:
    =#
    @test trypopping(stack)() === Some(111)
    #=
    Now that all values are popped, invoking `trypopping` returns `nothing`:
    =#
    @test trypopping(stack)() === nothing
end

# It is simple to wrap these reagents into the `Base` API:

Base.push!(stack::TreiberStack, value) = pushing(stack)(convert(eltype(stack), value))
Base.pop!(stack::TreiberStack) = something(trypopping(stack)())

# Note that this version of `pop!(stack::TreiberStack)` throws when the `stack`
# is empty.  See [Blocking containers](@ref ex-blockingcontainers) for a
# *generic* derivation of a blocking version of `pop!` that waits for the value
# to be `push!`ed.
#
# For more usage examples, see
# [`/test/ReagentsTests/src/test_treiberstack.jl`](https://github.com/tkf/Reagents.jl/blob/master/test/ReagentsTests/src/test_treiberstack.jl).
