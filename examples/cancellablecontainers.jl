using Reagents: Block, CAS, Computed, Map, Read, Reagents, Return

struct Blocking{T,Data,Send,Receive}
    eltype::Val{T}
    data::Data
    send::Send
    receive::Receive
end

function Blocking(data)
    send, receive = Reagents.channel(eltype(data), Nothing)
    return Blocking(Val(eltype(data)), data, send, receive)
end

putting(b::Blocking) = b.send | putting(b.data)
taking(b::Blocking) = b.receive | taking(b.data)

Base.eltype(::Type{<:Blocking{T}}) where {T} = T
Base.put!(b::Blocking, x) = putting(b)(convert(eltype(b), x))
Base.take!(b::Blocking) = taking(b)()

include("treiberstack.jl")
include("msqueue.jl")

blocknothing() = Map(x -> x === nothing ? Block() : something(x))

putting(c::TreiberStack) = pushing(c)
taking(c::TreiberStack) = trypopping(c) ⨟ blocknothing()

putting(c::MSQueue) = pushing(c)
taking(c::MSQueue) = trypoppingfirst(c) ⨟ blocknothing()

using Test

function test_put_take_queue()
    items = Blocking(MSQueue{Int}())
    put!(items, 111)
    put!(items, 222)
    @test take!(items) == 111
    @test take!(items) == 222

    t = @task take!(items)
    yield(t)
    put!(items, 333)
    @test fetch(t) === 333
end

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


struct Cancelled end

function test_cancellation_idea()
    items = Blocking(MSQueue{Int}())

    send, receive = Reagents.channel(Cancelled, Nothing)

    t = @task (receive | taking(items))()
    yield(t)
    put!(items, 111)
    @test fetch(t) == 111

    t = @task (receive | taking(items))()
    yield(t)
    send(Cancelled())
    @test fetch(t) isa Cancelled
end

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

function cancellable(reagent::Reagents.Reagent, token::CancellationToken)
    listener = Map(_ -> nothing) ⨟ token.receive
    checker = Read(token.iscancelled) ⨟ Map(x -> x ? Cancelled() : Block())
    return listener | checker | reagent
end

cancellable_take!(b::Blocking, token::CancellationToken) = cancellable(taking(b), token)()

function cancel!(token::CancellationToken)
    token.iscancelled[] = true
    while Reagents.try(token.send, Cancelled()) !== nothing
    end
end

function test_cancellation_token()
    items = Blocking(MSQueue{Int}())
    token = CancellationToken()

    # Before cancellation, `cancellable_take!` works like normal `take!`:

    t = @task cancellable_take!(items, token)
    yield(t)
    put!(items, 111)
    @test fetch(t) == 111

    # Calling `cancel!(token)` cancells all `cancellable_take!(items, token)`
    # calls that are already happening (waiting for an item) and also the calls
    # happening after the cancellation.

    t = @task cancellable_take!(items, token)
    yield(t)
    cancel!(token)
    @test fetch(t) isa Cancelled
    @test cancellable_take!(items, token) isa Cancelled

    # Note that the cancellation mechanism is introduced *outside* the
    # `Blocking` container.  It is different from, e.g., cancelling
    # `put!(::Base.Channel)` via closing the `Base.Channel`. Thus, the container
    # itself still works:
    put!(items, 222)
    @test take!(items) == 222
end
