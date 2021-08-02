module TestDualContainers

using Reagents.Internal: @trace
using Test
using ..Utils: run_concurrently

using ArgCheck: @check as @assert
include("../../../examples/dualcontainers.jl")

function test_fifo_data()
    @testset for f in [dual_queue, quack]
        test_fifo_data(f)
    end
end

function test_fifo_data(constructor)
    c = constructor(Int)
    put!(c, 1)
    put!(c, 2)
    put!(c, 3)
    @test [take!(c), take!(c), take!(c)] == [1, 2, 3]
end

function test_lifo_data()
    @testset for f in [dual_stack, steue]
        test_lifo_data(f)
    end
end

function test_lifo_data(constructor)
    c = constructor(Int)
    put!(c, 1)
    put!(c, 2)
    put!(c, 3)
    @test [take!(c), take!(c), take!(c)] == [3, 2, 1]
end

function put_take!(c, items)
    takeorder = Int[]
    tasks = map(1:3) do i
        t = @task begin
            y = take!(c)
            push!(takeorder, i)
            y
        end
        yield(t)
        t
    end
    for x in items
        put!(c, x)
    end
    taken = map(fetch, tasks)
    return (; taken, takeorder)
end

function test_fifo_reservation()
    @testset for f in [dual_queue, steue]
        test_fifo_reservation(f)
    end
end

function test_fifo_reservation(constructor)
    c = constructor(Int)
    (; taken, takeorder) = put_take!(c, [111, 222, 333])
    @test taken == [111, 222, 333]
    @test takeorder == [1, 2, 3]
end

function test_lifo_reservation()
    @testset for f in [dual_stack, quack]
        test_lifo_reservation(f)
    end
end

function test_lifo_reservation(constructor)
    c = constructor(Int)
    (; taken, takeorder) = put_take!(c, [111, 222, 333])
    @test taken == [333, 222, 111]
    @test takeorder == [3, 2, 1]
end

function test_many_items(; kwargs...)
    @testset for spawn in [false, true]
        test_many_items(spawn; kwargs...)
    end
end

function test_many_items(spawn::Bool; kwargs...)
    @testset for f in [dual_stack, dual_queue, quack, steue]
        test_many_items(f, spawn; kwargs...)
    end
end

function test_many_items(constructor, spawn::Bool, nrepeat = 1000)
    c = constructor(Int)

    sentinel = -1  # TODO: support `close` and get rid of this

    received = [Int[] for _ in 1:5]
    receivers = map(eachindex(received), received) do i, dest
        function receiver_task()
            while true
                y = take!(c)
                y == sentinel && break
                push!(dest, y)
            end
            @debug "`test_many_items`: Reciever $i done"
        end
    end

    nsenders = 5
    nfinished = Threads.Atomic{Int}(0)  # not using a task for this for `concurrently`
    senders = map(1:nsenders) do i
        function sender_task()
            for j in 1:nrepeat
                put!(c, nsenders * (j - 1) + i)
            end
            if Threads.atomic_add!(nfinished, 1) + 1 == nsenders
                sleep(0.2)  # TODO: don't do this; support `close`
                # `sleep` here is just a "hint" but it's still bad...
                for _ in receivers
                    put!(c, sentinel)
                end
                @debug "`test_many_items`: All sent"
            end
        end
    end
    allsent = 1:nsenders*nrepeat

    run_concurrently([senders; receivers]; spawn)
    @debug "`test_many_items`: All sendres and receivers done"

    allreceived = reduce(vcat, received)
    nleft = 0
    ncleaned = 0
    while true
        ref = trytaking(c.items)()
        ref === nothing && break  # empty
        ncleaned += 1
        y = something(ref)[]
        y === nothing && continue  # taken
        push!(allreceived, something(y))
        nleft += 1
    end
    @debug "`test_many_items`: $nleft items not recieved; $ncleaned refs cleaned"

    @test length(allreceived) == length(allsent)
    @test sort!(allreceived) == allsent
end

end  # module
