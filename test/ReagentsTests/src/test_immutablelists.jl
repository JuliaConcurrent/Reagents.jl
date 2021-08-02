module TestImmutableLists

using Reagents.Internal: combine, ilist, pushsortedby, has
using Test

function test_combine()
    @test collect(combine(ilist(1:3...), ilist(4:6...))) == 1:6
end

function test_pushsortedby()
    @test collect(pushsortedby(identity, ilist(1, 3, 4), 2)) == 1:4
end

function test_has()
    @test has(ilist(1:3...), 1)
    @test has(ilist(1:3...), 2)
    @test has(ilist(1:3...), 3)
    @test !has(ilist(1:3...), 4)
end

end  # module
