module TestBlocking

using ..TestCancellableContainers: Blocking, TreiberStack, taking
using Reagents
using Test

function test_unblock()
    s1 = Blocking(TreiberStack{Int}())
    a2b, b2a = Reagents.channel(Int, Int)
    t = @task (taking(s1) ⨟ a2b)()
    yield(t)
    put!(s1, 111)
    istaskdone(t) && wait(t)
    @test b2a(222) == 111
    @test fetch(t) == 222
end

function test_both()
    s1 = Blocking(TreiberStack{Int}())
    s2 = Blocking(TreiberStack{Int}())
    t = @task (taking(s1) & taking(s2))()
    yield(t)
    put!(s1, 111)
    put!(s2, 222)
    @test fetch(t) == (111, 222)
end

end  # module
