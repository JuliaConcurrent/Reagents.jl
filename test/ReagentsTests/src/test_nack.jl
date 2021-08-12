module TestNack

using Reagents
using Test
using ..Utils: @spawn_named

include("../../../examples/nack.jl")

function test_trivial_withnack_fired()
    send, receive = Reagents.channel()
    local nack
    reagent = Reagents.WithNack() do x
        nack = x
        return Reagents.Return(Reagents.Block())
    end | receive
    t = @task reagent()
    yield(t)
    send(222)
    @test fetch(t) == 222
    nack()
    @test true
end

function test_trivial_withnack_not_fired()
    s1, r1 = Reagents.channel()
    local nack
    reagent = Reagents.WithNack() do x
        nack = x
        return r1
    end | Reagents.Return(Reagents.Block())
    t1 = @task reagent()
    yield(t1)
    s1(111)
    @test fetch(t1) == 111

    s2, r2 = Reagents.channel()
    t2 = @task (nack | r2)()
    yield(t2)
    @test !istaskdone(t2)
    s2(333)
    @test fetch(t2) == 333
end

function with_simple_withnack_test_setup(f)
    s0, r0 = Reagents.channel()
    s1, r1 = Reagents.channel()
    s2, r2 = Reagents.channel()
    s3, r3 = Reagents.channel()
    Base.Experimental.@sync begin
        reagent = Reagents.WithNack() do nack
            local t1 = @spawn_named :t1 (nack | r3)()
            s0(t1)
            return r1
        end | r2

        t2 = @spawn_named :t2 reagent()
        t1 = r0()::Task

        for _ in 1:10
            sleep(0.01)
            if istaskdone(t1)
                wait(t1)
                break
            end
            if istaskdone(t2)
                wait(t2)
                break
            end
        end
        @test !istaskdone(t1)
        @test !istaskdone(t2)

        f((; t1, t2, s1, s2, s3))
    end
end

function test_withnack_nack_first()
    with_simple_withnack_test_setup() do (; t1, t2, s2)
        s2(111)
        @test fetch(t2) == 111
        @test fetch(t1) === nothing
    end
end

function test_withnack_no_nack()
    with_simple_withnack_test_setup() do (; t1, t2, s1, s3)
        s1(111)
        @test fetch(t2) == 111
        Reagents.try(s3, 222)
        @test fetch(t1) == 222
    end
end

function test_withnack_nack_lost()
    with_simple_withnack_test_setup() do (; t1, t2, s1, s3)
        Reagents.try(s3, 222)
        @test fetch(t1) == 222
        s1(111)
        @test fetch(t2) == 111
    end
end

end  # module
