# # Promises and Futures
#
# [Blocking containers](@ref ex-blockingcontainers) tutorial demonstrated how to
# wait on the arrival (`put!`) of a new element.  However, `put!` is not the
# only interesting event on a concurrent data structure.  By defining `Promise`
# and `Future`, the following code demonstrates a strategy for signaling and
# responding to additional events such as a call to `close`. 

using Reagents
using Reagents: Block, CAS, Computed, Map, PostCommit, Read, Return

# ## Promise
#
# Let us implement
# [*Promise*](https://en.wikipedia.org/wiki/Futures_and_promises) with
# the following API:

function test_promise_fetches()
    #=
    We can create a promise, possibly with a specific element type:
    =#
    p = Promise{Int}()

    #=
    Calling `fetch(p::Promise)` will wait for `p` to be fullfiled:
    =#
    task = @task fetch(p)
    yield(task)
    @test !istaskdone(task)  # the task is suspended

    #=
    We can set the value of the promise with the `Ref`-like interface:
    =#
    p[] = 111

    #=
    Once the value is set, all the calls to `fetch` are unblocked:
    =#
    @test fetch(task) == 111  # Note: `task` is calling `fetch(p)`

    #=
    `fetch(p::Promise)` can be called multiple times and it does not block after
    the value is set:
    =#
    @test fetch(p) == 111
end

# We also implement `close(::Promise)`, which unblock `fetch` but with
# exception.

function test_promise_close_before_fetches()
    #=
    Suppose we created a promise and there is a task waiting for it:
    =#
    p = Promise{Int}()
    t = @task fetch(p)
    yield(t)

    #=
    ... but the promise is closed before setting the value
    =#
    close(p)

    #=
    Then, previously blocked `fetch(::Promise)` rasies an exception:
    =#
    err = try
        wait(t)
        nothing
    catch err
        err
    end
    @test err isa TaskFailedException
    @test occursin("promise is closed", sprint(showerror, err))

    #=
    Subsequent call to `fetch(::Promise)` also throws an exception:
    =#
    @test_throws ErrorException("promise is closed") fetch(p)
end

# ### Implementing `Promise`
#
# We store the state of `Promise` in a single `Ref` by using the `Union` type.

struct Closed end

const PromiseRef{T} = Reagents.Ref{Union{
    Nothing,  # indicates the value is not set and the promise is not closed
    Some{T},  # indicates that the value of type `T` is set
    Closed,   # indicates that the promise is closed
}}

# The `Promise` type also contains a channel for sending and receiving signals
# on the state change:

struct Promise{T,Ref<:PromiseRef{T}}
    value::Ref
    send::typeof(Reagents.channel(Nothing)[1])
    receive::typeof(Reagents.channel(Nothing)[2])
end

Promise() = Promise{Any}()
function Promise{T}() where {T}
    send, receive = Reagents.channel(Nothing)
    return Promise(PromiseRef{T}(nothing), send, receive)
end

# Since setting value and closing the channel are similar, we define an internal
# function that tries to set `p.value::Reagents.Ref` if it's not already set and
# then, upon success, notify all the waiters:

tryputting_internal(p::Promise) =
    Computed() do x
        CAS(p.value, nothing, x)
    end ⨟ PostCommit() do _
        while Reagents.try(p.send) !== nothing
        end
    end

# Then, we can define a reagent for setting a value and a reagent for closing
# the promise as simple wrappers:

tryputting(p::Promise{T}) where {T} = Map(Some{T}) ⨟ tryputting_internal(p)
closing(p::Promise) = Return(Closed()) ⨟ tryputting_internal(p)

# The reagent for fetching the promise needs to first listen to the putting and
# closing events (to avoid missing the notification) and *then* check if the
# value is set:

fetching(p::Promise{T}) where {T} =
    (p.receive ⨟ Read(p.value) ⨟ Map(something)) |
    (Read(p.value) ⨟ Map(x -> x === nothing ? Block() : something(x)))

# We check the returned value of `fetching` outside reagent. If it is the
# `Closed` sentinel value, the exception is thrown:

function check_promise_closed(@nospecialize(value))
    if value isa Closed
        error("promise is closed")
    end
    return value
end

# It is now straightforward to define the API mentioned above:

Base.fetch(p::Promise) = check_promise_closed(fetching(p)())

Base.close(p::Promise) = closing(p)()
Base.isopen(p::Promise) = !(p.value[] isa Closed)

function Base.setindex!(p::Promise{T}, x) where {T}
    x = convert(T, x)
    if Reagents.try(tryputting(p), x) === nothing
        check_promise_closed(p.value[])
        error("promise already has a value")
    end
end

# Since we defined underlying synchronization mechanisms as reagents, we can
# compose them. For example, to wait for two promises to be ready, we can use
# the combinator `&`:

function test_promise_fetch_all()
    p1 = Promise{Int}()
    p2 = Promise{Int}()
    t = @task (fetching(p1) & fetching(p2))()
    yield(t)
    p1[] = 222
    @test !istaskdone(t)
    p2[] = 333
    @test fetch(t) == (222, 333)
end

# Or to wait for the first available promise, use `|`

function test_promise_fetch_any()
    p1 = Promise{Int}()
    p2 = Promise{Int}()
    t = @task (fetching(p1) | fetching(p2))()
    yield(t)
    p1[] = 444
    @test fetch(t) == 444
end

# ## Future
#
# Let us define a `Future` as a `Promise` and a thunk that generates the value
# to be stored in the `Promise`. That is to say, we'd like to have the following
# API:

function test_future_fetch_calls_thunk()
    thunk() = 111 + 222
    f = Future{Int}(thunk)
    @test fetch(f) == 333
end

# Importantly, `Future(thunk)` calls `thunk` at most once.

function test_future_thunk_is_called_once()
    #=
    To define this behavior, consider that we have a `thunk` that has a
    side-effect (which is not an intended use-case but useful for describing the
    behavior):
    =#
    ncalled = Ref(0)
    function thunk()
        ncalled[] += 1
        return 111 + 222
    end
    f = Future{Int}(thunk)

    #=
    The first `fetch` will call the `thunk`:
    =#
    ncalled[] = 0
    @test fetch(f) == 333
    @test ncalled[] == 1

    #=
    The Subsequent call to `fetch` does not call the `thunk` and uses the value
    internally stored:
    =#
    ncalled[] = 0
    @test fetch(f) == 333
    @test ncalled[] == 0
end

# Like `Promise`, `fetch`ing `close`d `Future` throws an exception:

function test_future_close()
    ncalled = Ref(0)
    function thunk()
        ncalled[] += 1
        return 111 + 222
    end
    f = Future{Int}(thunk)
    close(f)
    @test_throws ErrorException("promise is closed") fetch(f)
    @test_throws ErrorException("promise is closed") fetch(f)
    #=
    Furthermore, the thunk is not called when the future is `close`d before the
    first `fetch` call:
    =#
    @test ncalled[] == 0
end

# ### Implementing `Future`
#
# A `Future{T}` wraps a `Promise{T}` and a thunk that produces a value of type
# `T`. We also have an auxiliary state `started` tracking if the call to thunk
# is already started or not.

struct Future{T,F,Value<:Promise{T}}
    thunk::F
    value::Value
    started::Threads.Atomic{Bool}
end

Future(f) = Future{Any}(f)
Future{T}(f) where {T} = Future(f, Promise{T}(), Threads.Atomic{Bool}(false))

# We also use this example to demonstrate that not all states have to be
# expressed through Reagents.jl API.  Here, we use a simple
# `Threads.Atomic{Bool}` flag for the `started` state.
#
# The core functionality of `Future` is the ability to run the `thunk` (at most)
# once. Let us define an internal function that assures this invariance. The
# following function `tryrun!(f::Future)` returns `nothing` when the thunk is
# already called. Otherwise, it calls the thunk and then set its value. However,
# if there is a call to `close` before this function returns (i.e., setting the
# value to the promise failed), it also returns `nothing`. If it successfully
# sets the `value` to the promise, it returns `Some(nothing)`.

function tryrun!(f::Future{T}) where {T}
    if Threads.atomic_cas!(f.started, false, true) === false
        y = f.thunk()
        y = convert(T, y)
        # Set the value, if it hasn't been set:
        if Reagents.try(tryputting(f.value), y) === nothing
            return nothing  # already closed
        end
        # Successfully stored the value:
        return Some(y)
    else
        # Lost the race:
        return nothing
    end
end

# We can then wrap this in a reagent. If the call to thunk is successfully, the
# computed value is returned as-is (`Return(something(y))`).  Otherwise,

fetching(f::Future) =
    Computed() do _
        # Optimization: if already closed, not need to call the thunk:
        isopen(f.value) || return fetching(f.value)
        # If still open, try to compute the value:
        y = tryrun!(f)
        if y === nothing
            fetching(f.value)
        else
            Return(something(y))
        end
    end

# The future can be closed by simply closing the underlying promise:

closing(f::Future) = closing(f.value)

# Finally, we can wrap these reagents into the blocking API mentioned above:

Base.fetch(f::Future) = check_promise_closed(fetching(f)())
Base.close(f::Future) = closing(f)()
