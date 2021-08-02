module TestMSQueue

using Reagents
using Test

include("../../../examples/msqueue.jl")

function test_1()
    q = MSQueue{Int}()
    push!(q, 1)
    @test popfirst!(q) == 1
end

function test_123()
    q = MSQueue{Int}()
    push!(q, 1)
    push!(q, 2)
    push!(q, 3)
    @test popfirst!(q) == 1
    @test popfirst!(q) == 2
    @test popfirst!(q) == 3
end

end  # module
