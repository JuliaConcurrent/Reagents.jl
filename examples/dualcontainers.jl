# # Dual data structures
#
# Generic dual container inspired by Izraelevitz & Scott (2017) "Generality and
# Speed in Nonblocking Dual Containers."

# TODO: maybe it's better to generalize `Reagents.channel` over the underlying
# bag?

using Reagents: Block, CAS, Computed, Map, Reagents, Return, Until

struct DualContainer{T,Items,Reservations}
    eltype::Val{T}
    items::Items
    reservations::Reservations
end

function dualcontainer(::Type{T}, Items, Reservations = Items) where {T}
    return DualContainer(
        Val{T}(),
        Items{typeof(Reagents.Ref{Union{Nothing,Some{T}}}())}(),
        Reservations{typeof(Reagents.Ref{Union{Nothing,Task}}())}(),
    )
end

# APIs required for the containres:
function putting end
function taking end

# To separate the reaction and synchronization, let us abstract out the
# synchronizations as a "promise" that must be consumed once and exactly once.

abstract type LinearPromise{T} end

struct Fulfilled{T} <: LinearPromise{T}
    value::T
end

struct NeedWait{T} <: LinearPromise{T} end

struct NeedSend{V} <: LinearPromise{Nothing}
    task::Task
    value::V
end

Base.fetch(p::Fulfilled) = p.value
Base.fetch(::NeedWait{T}) where {T} = wait()::T
function Base.fetch(p::NeedSend)
    schedule(p.task, p.value)
    return nothing
end

# (Note: For simplicity, there's no error check for the violation of the
# "exactly once" condition ("linearity"). Furthermore, these promises must be
# fetched right after the reaction manually.)

Base.put!(dual::DualContainer, x) = fetch(promise_putting(dual, x)())
Base.take!(dual::DualContainer) = fetch(promise_taking(dual)())

function promise_putting(dual::DualContainer{T}, x) where {T}
    x = convert(T, x)
    return annihilating(dual.reservations, dual.items, Some{T}(x)) ⨟ Map() do task
        if task === nothing
            # Successfully "logically" stored the element in the item container.
            # That is to say, no waiter `task` was observed.
            Fulfilled(nothing)
        else
            # A waiter `task` is found and the item is removed from the item
            # container.
            NeedSend{T}(task, x)
        end
    end
end

promise_taking(dual::DualContainer{T}) where {T} =
    annihilating(dual.items, dual.reservations, current_task()) ⨟ Map() do x
        if x === nothing
            # The CAS failure is always `Retry`. So, `nothing` here means that
            # `taking(dual.item)` failed with `Block`.
            NeedWait{T}()
        else
            # An item is found and the reservation is removed from the
            # reservation container.
            Fulfilled{T}(something(x))
        end
    end

# TODO: Izraelevitz & Scott (2017) has the property that the at most one of the
# subcontainers is nonempty. Does the algorithm below has something similar?

function annihilating(opposite, self, selfvalue)
    # First advertise that we have a value:
    SelfRefType = eltype(self)::Type{<:Reagents.Ref}
    selfref = SelfRefType(selfvalue)
    putting(self)(selfref)

    return (
        Until(trytaking(opposite)) do found
            found === nothing && return missing
            oppsref = something(found)
            oppsvalue = oppsref[]
            if oppsvalue === nothing
                return nothing
                # Cleaning up a stale ref in the opposite container; i.e., this
                # `oppref` will be removed by committing `trytaking(opposite)`.
            else
                return (oppsref, oppsvalue)
            end
        end ⨟
        Computed() do found
            found === missing && return Return(nothing)
            oppsref, oppsvalue = found
            if selfref[] !== selfvalue
                # `selfref` already consumed (not possible to cancel) so,
                # `oppref` should not be consumed.
                return Block()
            else
                return CAS(oppsref, oppsvalue, nothing) ⨟ # Delete the opposite entry
                       CAS(selfref, selfvalue, nothing) ⨟ # ...and the self entry atomically
                       Return(oppsvalue)
            end
        end | # if blocked (i.e., `selfref[] !== selfvalue`), then:
        Return(nothing)
    )
end

include("treiberstack.jl")
include("msqueue.jl")

putting(c::TreiberStack) = pushing(c)
trytaking(c::TreiberStack) = trypopping(c)

putting(c::MSQueue) = pushing(c)
trytaking(c::MSQueue) = trypoppingfirst(c)

# Any concurrent data structures that define `putting` and `trytaking` reagents
# can be used for the data and reservation containers. For example, we get the
# following four combinations of synchronizable data structure.

dual_queue(T) = dualcontainer(T, MSQueue)
dual_stack(T) = dualcontainer(T, TreiberStack)
quack(T) = dualcontainer(T, MSQueue, TreiberStack)
steue(T) = dualcontainer(T, TreiberStack, MSQueue)

# Note: The name and idea of "quack" and "steue" are due to Izraelevitz & Scott
# (2017).

using Test

# Since `quack` uses a queue for data items, `put!` is FIFO:

function test_quack_data_is_fifo()
    c = quack(Int)
    put!(c, 111)
    put!(c, 222)
    put!(c, 333)
    @test [take!(c), take!(c), take!(c)] == [111, 222, 333]
end

# Since `quack` uses a stack for the waiters (reservations) list, `take!` is
# LIFO:

function test_quack_waiter_is_lifo()
    c = quack(Int)

    t1 = @task take!(c)
    yield(t1)
    t2 = @task take!(c)
    yield(t2)
    t3 = @task take!(c)
    yield(t3)

    put!(c, 111)
    @test fetch(t3) == 111
    put!(c, 222)
    @test fetch(t2) == 222
    put!(c, 333)
    @test fetch(t1) == 333
end

# See `../test/ReagentsTests/src/test_dualcontainers.jl` for more usage
