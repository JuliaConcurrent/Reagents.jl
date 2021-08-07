module TestCancellableContainers

using ArgCheck: @check
using ProgressLogging: Progress
using Reagents.Internal: Waiting, @trace, offerid
using UUIDs: uuid4
using ..Utils: random_sleep, run_concurrently

include("../../../examples/cancellablecontainers.jl")

blocking_treiberstack(T) = Blocking(TreiberStack{T}())
blocking_msqueue(T) = Blocking(MSQueue{T}())

function test_cancellation_token_internal()
    items = blocking_msqueue(Int)
    token = CancellationToken()

    t = @task cancellable_take!(items, token)
    yield(t)

    # At this point, the `offer` of `cancellable_take!` is registered into the
    # channels for the item taker *and* the cancellation listener:
    @test items.send.dual.next.value.offer === token.receive.msgs.next.value.offer
    # And it is waiting:
    @test items.send.dual.next.value.offer.state[] isa Waiting
end

function test_repeat_cancellation(; parentid = uuid4(), kwargs...)
    id = uuid4()
    i = 0
    try
        @testset for spawn in [false, true]
            @debug Progress(
                id,
                i / 2;
                name = "`test_repeat_cancellation`: spawn=$spawn",
                parentid,
            )
            i += 1

            test_repeat_cancellation(spawn; parentid = id, kwargs...)
        end
    finally
        @debug Progress(id; done = true)
    end
end

function test_repeat_cancellation(spawn::Bool; parentid = uuid4(), kwargs...)
    id = uuid4()
    i = 0
    try
        @testset for f in [blocking_msqueue, blocking_treiberstack]
            @debug Progress(id, i / 2; name = "`test_repeat_cancellation`: $f", parentid)
            i += 1

            test_repeat_cancellation(f, spawn; parentid = id, kwargs...)
        end
    finally
        @debug Progress(id; done = true)
    end
end

function test_repeat_cancellation(
    constructor,
    spawn::Bool;
    parentid = uuid4(),
    nrepeat = 10,
    kwargs...,
)
    id = uuid4()
    try
        for i in 1:nrepeat
            @debug Progress(
                id,
                (i - 1) / nrepeat;
                name = "`test_repeat_cancellation`: trial $i",
                parentid,
            )
            check_repeat_cancellation(constructor, spawn; kwargs...)
        end
    finally
        @debug Progress(id; done = true)
    end
    @test true
end

function check_repeat_cancellation(constructor, spawn::Bool; nitems = 100, randomize = true)
    items = constructor(Int)
    token = CancellationToken()
    global ITEMS = items
    global TOKEN = token

    received = [Int[] for _ in 1:5]
    receivers = map(eachindex(received), received) do i, dest
        function receiver_task()
            @trace(label = :start_receiver, i, taskid = objectid(current_task()))
            while true
                @trace(label = :taking, i, taskid = objectid(current_task()))
                y = cancellable_take!(items, token)
                if y isa Cancelled
                    @trace(label = :received_cancelled, i, taskid = objectid(current_task()))
                    break
                end
                @trace(label = :took, i, value = y, taskid = objectid(current_task()))
                push!(dest, y)
                randomize && random_sleep()
            end
            @debug "`check_repeat_cancellation`: Reciever $i done"
        end
    end

    nsenders = 5
    nfinished = Threads.Atomic{Int}(0)
    senders = map(1:nsenders) do i
        function sender_task()
            @trace(label = :start_sender, i, taskid = objectid(current_task()))
            for j in 1:nitems
                put!(items, nsenders * (j - 1) + i)
                randomize && random_sleep()
            end
            if Threads.atomic_add!(nfinished, 1) + 1 == nsenders
                # Note: using `nfinished` instead of using a task that waits for
                # all senders, so that we can use a single `run_concurrently`
                # call (to make debugging easier).

                sleep(0.2)  # TODO: don't do this; support `close`
                # `sleep` here is just a "hint" but it's still bad...

                @debug "`check_repeat_cancellation`: All sent"
                for msg in token.receive.msgs
                    @trace(
                        label = :check_token,
                        i,
                        taskid = objectid(current_task()),
                        offerid = offerid(msg.offer)
                    )
                end
                @trace(label = :sending_cancelled, i, taskid = objectid(current_task()))
                cancel!(token)
                @trace(label = :sent_cancelled, i, taskid = objectid(current_task()))
            end
            @debug "`check_repeat_cancellation`: Sender $i done"
        end
    end
    allsent = 1:nsenders*nitems

    run_concurrently([senders; receivers]; spawn)
    @debug "`check_repeat_cancellation`: All sendres and receivers done"
    @check token.iscancelled[]

    allreceived = reduce(vcat, received)
    nleft = 0
    ncleaned = 0
    while true
        ref = Reagents.try(taking(items))
        ref === nothing && break  # empty
        ncleaned += 1
        y = something(ref)[]
        y === nothing && continue  # taken
        push!(allreceived, something(y))
        nleft += 1
    end
    @debug "`check_repeat_cancellation`: $nleft items not recieved; $ncleaned refs cleaned"

    # Not using `@test` to avoid overhead in while "fuzzing"
    @check length(allreceived) == length(allsent)
    @check sort!(allreceived) == allsent
end

end  # module
