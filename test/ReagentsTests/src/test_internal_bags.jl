module TestInternalBags

using ArgCheck: @check
using ProgressLogging: Progress
using Reagents.Internal: Internal, Bag
using Test
using UUIDs: uuid4
using ..Utils: random_sleep, run_concurrently

struct Positive{T}
    value::T
end

Internal.isdeleted(p::Positive) = p.value <= 0

function test_concurrent_push_iterate(; nrepeat = 10, kwargs...)
    id = uuid4()
    try
        for i in 1:nrepeat
            @debug Progress(
                id,
                (i - 1) / nrepeat;
                name = "`test_concurrent_push_iterate`: trial $i",
            )
            check_concurrent_push_iterate(; kwargs...)
        end
    finally
        @debug Progress(id; done = true)
    end
    @test true
end

function check_concurrent_push_iterate(; randomize = true, nitems = 100)
    items = Bag{Positive{Int}}()
    sentinel = typemax(Int)

    receivers = map(1:5) do i
        function receiver_task()
            while true
                for p in items
                    if p.value == sentinel
                        @debug "`check_concurrent_push_iterate`: Iterator $i done"
                        return
                    end
                    randomize && random_sleep()
                end
                yield()
            end
        end
    end

    nsenders = 5
    nfinished = Threads.Atomic{Int}(0)
    senders = map(1:nsenders) do i
        function sender_task()
            for j in 1:nitems
                push!(items, Positive(nsenders * (j - 1) + i))
                push!(items, Positive(-1))
                randomize && random_sleep()
            end
            if Threads.atomic_add!(nfinished, 1) + 1 == nsenders
                # Note: using `nfinished` instead of using a task that waits for
                # all senders, so that we can use a single `run_concurrently`
                # call (to make debugging easier).

                push!(items, Positive(sentinel))
                @debug "`check_concurrent_push_iterate`: All sent"
            end
            @debug "`check_concurrent_push_iterate`: Sender $i done"
        end
    end
    allsent = 1:nsenders*nitems

    run_concurrently([senders; receivers]; spawn = true)
    @debug "`check_concurrent_push_iterate`: All sendres and receivers done"

    allreceived = sort!(Int[p.value for p in items])
    if allreceived[end] == sentinel
        pop!(allreceived)
    end
    @check length(allreceived) == length(allsent)
    @check sort!(allreceived) == allsent
end

end  # module
