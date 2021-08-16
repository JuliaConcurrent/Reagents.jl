module TestTry

using ArgCheck: @check
using Reagents
using Reagents: CAS, Computed, Map
using Reagents.Internal: maysync
using Test
using ..Utils: @test_error, ⊏

function test_try_cas()
    ref = Reagents.Ref(0)
    @test Reagents.try!(CAS(ref, 1, 2)) === nothing
    @test ref[] == 0
    @test Reagents.try!(CAS(ref, 0, 2)) !== nothing
    @test ref[] == 2
end

function test_try_2cas()
    ref1 = Reagents.Ref(0)
    ref2 = Reagents.Ref(0)
    @test Reagents.try!(CAS(ref1, 1, 2) ⨟ CAS(ref2, 0, 3)) === nothing
    @test ref1[] == ref2[] == 0
    @test Reagents.try!(CAS(ref1, 0, 2) ⨟ CAS(ref2, 0, 3)) !== nothing
    @test ref1[] == 2
    @test ref2[] == 3
end

function test_trysync_requires_blocking_reagent()
    ref = Reagents.Ref(0)
    cas = CAS(ref, 1, 2)
    @check !maysync(cas)
    @check !maysync(cas | Map(Some))  # used in `trysync!`
    err = @test_error Reagents.trysync!(cas)
    @test "synchronizing continuation is required" ⊏ sprint(showerror, err)
end

function test_trysync_retries()
    state = Ref(0)
    ref = Reagents.Ref(10)
    reagent = Computed() do _
        old = state[] += 1  # eventually correct
        CAS(ref, old, 111)
    end
    Reagents.trysync!(reagent)
    @test ref[] == 111
end

end  # module
