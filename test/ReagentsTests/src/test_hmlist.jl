module TestHMList

using Reagents
using Test
using ..Utils: concurrently, random_sleep

include("../../../examples/hmlist.jl")

function test_12()
    list = HMList{Int}()
    @test !(1 in list)
    push!(list, 1)
    @test 1 in list
    @test !(2 in list)
    push!(list, 2)
    @test 1 in list
    @test 2 in list
    delete!(list, 2)
    @test 1 in list
    @test !(2 in list)
    delete!(list, 1)
    @test !(1 in list)
    @test !(2 in list)
end

function test_1_to_9()
    list = HMList{Int}()
    for i in 1:9
        push!(list, i)
    end
    for i in 1:9
        @test i in list
    end
    for i in 1:9
        push!(list, i)
    end
    for i in 1:9
        @test i in list
    end
    for i in 1:9
        delete!(list, i)
    end
    for i in 1:9
        @test !(i in list)
    end
end

function test_spawn()
    list = HMList{Int}()
    iterated = Threads.Atomic{Int}(0)
    maxiter = 100_000

    function notdone()
        n = Threads.atomic_add!(iterated, 1)
        if mod(n, 1000) == 0
            random_sleep(false)
            # @show 11 in list
            # mod(n, 10000) == 0 && @show n
        end
        return n < maxiter
    end

    persistent = 10:10:90
    pushdelete = persistent .+ 1

    for i in persistent
        push!(list, i)
    end

    function pusher()
        while notdone()
            for i in pushdelete
                push!(list, i)
            end
        end
    end
    function deleter()
        while notdone()
            for i in pushdelete
                delete!(list, i)
            end
        end
    end
    function always_contains!(ref, xs)
        function repeat_always_contains!()
            while notdone()
                for i in xs
                    ref[] &= i in list
                    if !ref[]
                        iterated[] = maxiter
                        break
                    end
                end
            end
        end
    end
    function never_contains!(ref, xs)
        function repeat_never_contains!()
            while notdone()
                for i in xs
                    ref[] &= !(i in list)
                    if !ref[]
                        iterated[] = maxiter
                        break
                    end
                end
            end
        end
    end

    a1 = Ref(true)
    a2 = Ref(true)
    n1 = Ref(true)
    n2 = Ref(true)

    concurrently(
        pusher,
        pusher,
        deleter,
        deleter,
        always_contains!(a1, persistent),
        always_contains!(a2, persistent),
        never_contains!(n1, pushdelete .+ 1),
        never_contains!(n2, pushdelete .+ 1),
        spawn = true,
    )
    @test a1[] === a2[] === n1[] === n2[] === true
end

end  # module
