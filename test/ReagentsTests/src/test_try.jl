module TestTry

using ArgCheck: @check
using Reagents
using Reagents: CAS, Computed, Map, Return, WithNack
using Reagents.Internal: ReturnIfBlocked, maysync
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

function test_trysync_nack()
    send_nack, receive_nack = Reagents.channel(Int, Nothing)
    never, _ = Reagents.channel(Nothing)
    reagent = WithNack() do nack
        Reagents.dissolve(Return(111) ⨟ send_nack ⨟ nack)
        @test Reagents.trysync!(receive_nack) === nothing  # not yet NACK'ed
        return never
    end
    @test Reagents.trysync!(receive_nack) === nothing  # not yet NACK'ed
    @test Reagents.trysync!(reagent) === nothing
    @test Reagents.trysync!(receive_nack) == Some(111)  # now NACK'ed
end

# Not used anywhere, but this is the behavior implemented:
function test_rib_pre_cas()
    never, _ = Reagents.channel(Nothing)
    ref = Reagents.Ref(111)
    @test (CAS(ref, 111, 222) ⨟ ReturnIfBlocked(:yes) ⨟ never)() == :yes
    @test ref[] == 222
end

end  # module
