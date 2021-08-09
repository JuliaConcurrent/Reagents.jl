# # [How to create a cancellable blocking API](@id ex-cancellablecontainers)

using Reagents: Block, CAS, Computed, Map, Read, Reagents, Return

# As demonstrated in the examples [Treiber stack](@ref ex-treiberstack) and
# [Michael and Scott queue](@ref ex-msqueue), reagents can be used for defining
# nonblocking data structures. However, reagents can also be used for
# constructing complex synchronization APIs.

# ## [Blocking containers](@id ex-blockingcontainers)
#
# When a value is not available in a nonblocking container, it is very useful to
# wait (*block*) until the value is available (as in
# [`Base.Channel`](https://docs.julialang.org/en/v1/base/parallel/#Base.Channel)).
# Using [`Reagents.channel`](@ref) (which is like unbuffered `Base.Channel`), we
# can *mechanically* transform a nonblocking data container to a waitable data
# structure.
#
# To this end, let us define a simple wrapper type that wraps underlying
# nonblocking data collection (`.data`) and the channel (`.send` and
# `.receive`):

struct Blocking{T,Data,Send,Receive}
    eltype::Val{T}
    data::Data          # holds value of type T
    send::Send          # swaps value::T -> nothing
    receive::Receive    # swaps nothing -> value::T
end

function Blocking(data)
    send, receive = Reagents.channel(eltype(data), Nothing)
    return Blocking(Val(eltype(data)), data, send, receive)
end

Base.eltype(::Type{<:Blocking{T}}) where {T} = T

# The idea is to try sending or receiving the item via the channel and *"then"*
# try to manipulate the data collection. We can do this *atomically* by using
# the choice reagent [`|`](@ref Reagents.:|).

putting(b::Blocking) = b.send | putting(b.data)
taking(b::Blocking) = b.receive | taking(b.data)

Base.put!(b::Blocking, x) = putting(b)(convert(eltype(b), x))
Base.take!(b::Blocking) = taking(b)()

# This `Blocking` wrapper can be used to extend existing nonblocking data
# structures such as [Treiber stack](@ref ex-treiberstack) and [Michael and
# Scott queue](@ref ex-msqueue) that we have already defined.

include("treiberstack.jl")
include("msqueue.jl")

# To this end, we need to transform `trypopping` and `trypoppingfirst` to a
# reagent that blocks when the item is not ready.  It can be done by this simple
# helper reagent that blocks when the input is `nothing`:

blocknothing() = Map(x -> x === nothing ? Block() : something(x))

# Then, it is straightforward to define the API required for the `Blocking`
# wrapper:

putting(c::TreiberStack) = pushing(c)
taking(c::TreiberStack) = trypopping(c) ⨟ blocknothing()

putting(c::MSQueue) = pushing(c)
taking(c::MSQueue) = trypoppingfirst(c) ⨟ blocknothing()

# ### Test blocking containers

using Test

function test_put_take_queue()
    #=
    When there are enough items in the data container,
    `Blocking(MSQueue{Int}())` behaves like `MSQueue{Int}()`:
    =#
    items = Blocking(MSQueue{Int}())
    put!(items, 111)
    put!(items, 222)
    @test take!(items) == 111
    @test take!(items) == 222

    #=
    However, when `take!` is invoked on an empty collection (which is enforced
    by the "unfair scheduling" `yield(::Task)`), it blocks until the
    corresponding `put!` is invoked:
    =#
    t = @task take!(items)
    yield(t)
    put!(items, 333)
    @test fetch(t) === 333
end

# It works with `TreiberStack`, too:

function test_put_take_stack()
    items = Blocking(TreiberStack{Int}())
    put!(items, 111)
    put!(items, 222)
    @test take!(items) == 222
    @test take!(items) == 111

    t = @task take!(items)
    yield(t)
    put!(items, 333)
    @test fetch(t) === 333
end

# ## Generic cancellable operations
#
# It is often useful to cancel blocking operation safely. It can be expressed by
# reagents quite naturally.
#
# First, let us define a singleton sentinel value for indicating a given
# reaction is cancelled:

struct Cancelled end

# To illustrate the idea, let us again use a `Blocking(MSQueue{Int}())`:

function test_cancellation_idea()
    items = Blocking(MSQueue{Int}())

    #=
    We use additonal channel for sending cancellation signal:
    =#
    send, receive = Reagents.channel(Cancelled, Nothing)

    #=
    The idea is to "listen to" the cancellation signal and then try to invoke a
    blocking reaction. If there is no cancellation signal, it behaves like the
    reagent without the cancellation:
    =#
    t = @task (receive | taking(items))()
    yield(t)
    put!(items, 111)
    @test fetch(t) == 111

    #=
    If the cancellation signal is fired before the corresponding `put!`, the
    result of the reaction is the sentinel `Cancelled()`.
    =#
    t = @task (receive | taking(items))()
    yield(t)
    send(Cancelled())
    @test fetch(t) isa Cancelled
end

# Note that the above idea is still hard to use directly, since
# `send(Cancelled())` only triggers the reactions that are happening
# simultaneously. We can introduce a `Reagents.Ref{Bool}` to make the
# cancellation permanent.
#
# Let us wrap this idea in a single object:

struct CancellationToken
    iscancelled::typeof(Reagents.Ref{Bool}())
    send::typeof(Reagents.channel(Cancelled, Nothing)[1])
    receive::typeof(Reagents.channel(Cancelled, Nothing)[2])
end

function CancellationToken()
    iscancelled = Reagents.Ref{Bool}(false)
    send, receive = Reagents.channel(Cancelled, Nothing)
    return CancellationToken(iscancelled, send, receive)
end

# We can then transform an arbitrary reagent to a reagent that can be cancelled
# via a "signal" through `CancellationToken` (defined in `cancel!` below). The
# resulting reagent is the compostion of three components: `listener`,
# `checker`, and the original `reagent`:

function cancellable(reagent::Reagents.Reagent, token::CancellationToken)
    listener = Return(nothing) ⨟ token.receive
    checker = Read(token.iscancelled) ⨟ Map(x -> x ? Cancelled() : Block())
    return listener | checker | reagent
end

# The `listener` reagent is essentially equivalent to the idea demonstrated
# above.  It is prefixed with the `Return(nothing)` reagent to make sure we
# always invoke the `token.receive` swap point with the valid input `nothing`.
#
# The `checker` reagent checks `token.iscancelled`; if it is already `true`, it
# ends the reaction with the value `Cancelled()`.  Otherwise, it indicates that
# the next reagent should be tried by returning the `Block` failure value.
#
# Finally, if both `listener` and `checker` are blocked, the original `reagent`
# is invoked. When this `reagent` is blocked, the first reagent between
# `listener` and `reagent` that is awaken determines the result value of this
# reaction.
#
# We can then use `cancellable` combinator to define a `cancellable_take!`
# function:

cancellable_take!(b::Blocking, token::CancellationToken) = cancellable(taking(b), token)()

# To fire the cancellation signal, we first set `iscancelled[]`. This way, all
# future `cancellable_take!` returns `Cancelled` due to the `checker` reagent
# defined above. We then clear out any existing peers listening to the
# `toeken.receive` swap endpoint.

function cancel!(token::CancellationToken)
    token.iscancelled[] = true
    while Reagents.try(token.send, Cancelled()) !== nothing
    end
end

# ### Test generic cancellable operations

function test_cancellation_token()
    items = Blocking(MSQueue{Int}())
    token = CancellationToken()

    #=
    Before cancellation, `cancellable_take!` works like normal `take!`:
    =#

    t = @task cancellable_take!(items, token)
    yield(t)
    put!(items, 111)
    @test fetch(t) == 111

    #=
    Calling `cancel!(token)` cancells all `cancellable_take!(items, token)`
    calls that are already happening (waiting for an item) and also the calls
    happening after the cancellation.
    =#

    t = @task cancellable_take!(items, token)
    yield(t)
    cancel!(token)
    @test fetch(t) isa Cancelled
    @test cancellable_take!(items, token) isa Cancelled

    #=
    Note that the cancellation mechanism is introduced *outside* the
    `Blocking` container.  It is different from, e.g., cancelling
    `put!(::Base.Channel)` via closing the `Base.Channel`. Thus, the container
    itself still works:
    =#
    put!(items, 222)
    @test take!(items) == 222
end
