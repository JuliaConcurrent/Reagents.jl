module TestTreiberStack

using Reagents
using Test

include("../../../examples/treiberstack.jl")

function test_1()
    stack = TreiberStack{Int}()
    push!(stack, 1)
    @test pop!(stack) == 1
end

function test_123()
    stack = TreiberStack{Int}()
    push!(stack, 1)
    push!(stack, 2)
    push!(stack, 3)
    @test pop!(stack) == 3
    @test pop!(stack) == 2
    @test pop!(stack) == 1
end

function test_spawn_pops()
    ns = [Threads.nthreads()]
    if Threads.nthreads() > 1
        push!(ns, Threads.nthreads() - 1)
    end
    @testset for nconsumers in ns
        test_spawn_pops(nconsumers)
    end
end

function test_spawn_pops(nconsumers)
    stack = TreiberStack{Int}()
    for _ in 1:nconsumers
        push!(stack, 0)
    end
    m = 100 * nconsumers
    for i in 1:m
        push!(stack, i)
    end

    vectors = [Int[] for _ in 1:nconsumers]
    Base.Experimental.@sync begin
        for xs in vectors
            Threads.@spawn begin
                while true
                    x = pop!(stack)
                    if x == 0
                        break
                    else
                        push!(xs, x)
                    end
                end
            end
        end
        for i in m+1:2m
            push!(stack, i)
        end
    end
    @debug "" map(length, vectors)
    popped = sort!(reduce(vcat, vectors))
    @test length(popped) >= m
    @test popped == 1:length(popped)
end

function test_paired_pop_pop()
    s1 = TreiberStack{Int}()
    s2 = TreiberStack{Int}()
    push!(s1, 1)
    push!(s2, 2)
    @test (trypopping(s1) & trypopping(s2))() == (Some(1), Some(2))
end

function test_paired_pop_push()
    s1 = TreiberStack{Int}()
    s2 = TreiberStack{Int}()
    push!(s1, 1)
    (trypopping(s1) ⨟  Reagents.Map(something) ⨟ pushing(s2))()
    @test pop!(s2) == 1
end

end  # module
