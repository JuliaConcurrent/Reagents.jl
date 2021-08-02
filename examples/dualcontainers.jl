# Generic dual container inspired by Izraelevitz & Scott (2017) "Generality and
# Speed in Nonblocking Dual Containers."

# TODO: The following construction is suggesting that it may be possible to
# further decompose the components in Reagents into the part concerining kCAS
# and the part concerning synchronization ("offer").

using Reagents: Block, CAS, Computed, Reagents, Return, maysucceed

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

# TODO: Expose put! and take! on DualContainer as reagent

function Base.put!(dual::DualContainer{T}, x) where {T}
    x = convert(T, x)
    s = Some{T}(x)
    ref = Reagents.Ref{Union{Nothing,Some{T}}}(s)
    putting(dual.items)(ref)
    task = take_and_cancel!(dual.reservations, CAS(ref, s, nothing))
    if task === nothing
        # Successfully "logically" stored the element in the item container.
        # That is to say, no waiter `task` was observed.
    else
        schedule(task::Task, x)
        @assert ref[] === nothing
        # A waiter `task` is found and the item is removed from the item
        # container.
    end
    return dual
end

function Base.take!(dual::DualContainer{T}) where {T}
    task = current_task()
    ref = Reagents.Ref{Union{Nothing,Task}}(task)
    putting(dual.reservations)(ref)
    x = take_and_cancel!(dual.items, CAS(ref, task, nothing))
    if x === nothing
        return wait()::T
        # The CAS failure is always `Retry`. So, `nothing` here means that
        # `taking(dual.item)` failed with `Block`.
    else
        @assert ref[] === nothing
        return something(x)::T
        # An item is found and the reservation is removed from the reservation
        # container.
    end
end

function take_and_cancel!(dual, canceller)
    takeblocking! =
        trytaking(dual) ⨟ Computed() do found
            found === nothing && return Return(nothing)
            dualref = something(found)
            x = dualref[]
            if x === nothing
                return Return(missing)  # remove `dualref` from `dual`
            elseif !maysucceed(canceller)
                # self (`canceller.ref`) already consumed (not possible to
                # cancel) so, `dualref` should not be consumed.
                return Block()
            else
                return CAS(dualref, x, nothing) ⨟ canceller ⨟ Return(x)
            end
        end
    trytake! = takeblocking! | Return(nothing)
    while true
        x = trytake!()
        if x === missing
            continue
        else
            return x
        end
    end
end

include("treiberstack.jl")
include("msqueue.jl")

putting(c::TreiberStack) = pushing(c)
trytaking(c::TreiberStack) = trypopping(c)

putting(c::MSQueue) = pushing(c)
trytaking(c::MSQueue) = trypoppingfirst(c)

# Any concurrent data structures that define `putting` and `trytaking` reagents
# can be used for the data and reservation (dual) containers. For example, we
# get the following four combinations of blocking data structure.

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

# See ../test/ReagentsTests/src/test_dualcontainers.jl for more usage
