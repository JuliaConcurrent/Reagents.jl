module TestBlocking

using ..TestCancellableContainers: Blocking, TreiberStack, taking
using Test

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
