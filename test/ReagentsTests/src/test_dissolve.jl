module TestDissolve

using Reagents
using Test

include("../../../examples/catalysts.jl")

function zip_channels(inputs, output)
    Reagents.dissolve((&)(inputs...) ⨟ output)
end

function test_zip3()
    s1, r1 = Reagents.channel(Int, Nothing)
    s2, r2 = Reagents.channel(Int, Nothing)
    s3, r3 = Reagents.channel(Int, Nothing)
    sa, ra = Reagents.channel(Tuple{Tuple{Int,Int},Int}, Nothing)
    zip_channels((r1, r2, r3), sa)
    function check(i)
        @sync begin
            @async s1(1 + i)
            @async s2(2 + i)
            @async s3(3 + i)
            @test ra() == ((1 + i, 2 + i), 3 + i)
        end
    end
    @testset for i in 1:10
        check(i)
    end
end

function test_pre_block()
    ref = Reagents.Ref{Int}(0)
    send, receive = Reagents.channel(Int, Nothing)
    Reagents.dissolve(Reagents.Update((x, _) -> (x + 1, x), ref) ⨟ send)
    @test receive() == 0
    @test receive() == 1
    @test receive() == 2
    ref[] = 10  # invalidate the CAS
    @test receive() == 10
    @test receive() == 11
end

end  # module
