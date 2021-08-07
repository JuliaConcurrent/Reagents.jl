module TestChannels

using Reagents
using Reagents.Internal: @trace
using Test
using ..Utils: concurrently

function test_simple_swap()
    @testset for spawn in [false, true]
        test_simple_swap(spawn)
    end
end

function test_simple_swap(spawn::Bool)
    c1, c2 = Reagents.channel(Int, Char)
    local y1, y2
    concurrently(function f1()
        y1 = c1(1)
    end, function f2()
        y2 = c2('2')
    end; spawn = spawn)
    @test (y1, y2) == ('2', 1)
end

function test_multi_swap()
    @testset for spawn in [false, true]
        test_multi_swap(spawn)
    end
end

function test_multi_swap(spawn::Bool, nrepeat = spawn ? 1000 : 1)
    c1, c2 = Reagents.channel(Int)
    c3, c4 = Reagents.channel(Int)
    local y1, y2, y3
    ok1 = ok2 = ok3 = true
    failed = Threads.Atomic{Bool}(false)
    concurrently(
        function f1()
            for i in 1:nrepeat
                failed[] && break
                @trace label = :f1 i taskid = objectid(current_task())
                y1 = (c1 ⨟ c3)(1 + 100i)
                ok1 &= y1 == 3 + 100i
                if !ok1
                    failed[] = true
                    error("f1 failed: got $(y1)")
                    break
                end
            end
        end,
        function f2()
            for i in 1:nrepeat
                failed[] && break
                @trace label = :f2 i taskid = objectid(current_task())
                y2 = c2(2 + 100i)
                ok2 &= y2 == 1 + 100i
                if !ok1
                    failed[] = true
                    error("f2 failed: got $(y2)")
                    break
                end
            end
        end,
        function f3()
            for i in 1:nrepeat
                failed[] && break
                @trace label = :f3 i taskid = objectid(current_task())
                y3 = c4(3 + 100i)
                ok3 &= y3 == 2 + 100i
                if !ok1
                    failed[] = true
                    error("f3 failed: got $(y3)")
                    break
                end
            end
        end;
        spawn = spawn,
    )
    @test ok1 == ok2 == ok3 == true
    @test (y1, y2, y3) == (3, 1, 2) .+ 100nrepeat
end

function test_simple_choice()
    @testset for spawn in [false, true]
        test_simple_choice(spawn)
    end
end

function test_simple_choice(spawn::Bool, nrepeat = spawn ? 1000 : 1)
    a2b, b2a = Reagents.channel(Int, Nothing)
    c2d, d2c = Reagents.channel(Int, Nothing)
    ok = true
    concurrently(
        function receiver()
            for i in 1:nrepeat
                y = (b2a | d2c)()
                ok &= y == i
                ok || error("receiver failed: got $y")
            end
        end,
        function sender()
            for i in 1:nrepeat
                if rand() > 0.5
                    a2b(i)
                else
                    c2d(i)
                end
            end
        end,
        spawn = spawn,
    )
    @test ok
end

end  # module
