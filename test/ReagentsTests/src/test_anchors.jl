module TestAnchors

using Reagents
using Reagents.Internal: withanchor, nextanchor!, finish!, Offer, Reaction
using Test
using ..TestCancellableContainers: blocking_treiberstack

function module_context(f)
    Reagents.Internal.use_anchors() && return f()
    Reagents.Internal.enable_anchors()
    try
        Base.invokelatest(f)
    finally
        Reagents.Internal.disable_anchors()
    end
end

function can_test()
    if Reagents.Internal.use_anchors()
        return true
    else
        @test_skip nothing
        return false
    end
end

function test_simple_commit()
    can_test() || return
    ref1 = Reagents.Ref{Int}(0)
    ref2 = Reagents.Ref{Int}(0)
    # Using two CASes to avoid the single-CAS optimization:
    reagent = Reagents.CAS(ref1, 0, 111) ⨟ Reagents.CAS(ref2, 0, 222)
    anc = withanchor() do
        reagent()
    end
    k, v = nextanchor!(anc)
    @test k === :commit
    @test v.offer === nothing
    @test v.rx isa Reaction
    @test ref1[] == ref2[] == 0
    finish!(anc)
    @test ref1[] == 111
    @test ref2[] == 222
end

function test_simple_race()
    can_test() || return
    ref1 = Reagents.Ref{Int}(0)
    ref2 = Reagents.Ref{Int}(0)
    # Using two CASes to avoid the single-CAS optimization:
    r1 = Reagents.CAS(ref1, 0, 111) ⨟ Reagents.CAS(ref2, 0, 222)
    r2 = Reagents.CAS(ref1, 0, 333) ⨟ Reagents.CAS(ref2, 0, 444)
    a1 = withanchor() do
        Reagents.try(r1)
    end
    a2 = withanchor() do
        Reagents.try(r2)
    end
    k1, _ = nextanchor!(a1)
    k2, _ = nextanchor!(a2)
    @test k1 == k2 === :commit
    @test ref1[] == ref2[] == 0
    @test finish!(a2) !== nothing
    @test ref1[] == 333
    @test ref2[] == 444
    @test finish!(a1) === nothing
end

function test_blocking_treiberstack_late_take_win()
    can_test() || return
    b = blocking_treiberstack(Int)
    a1 = withanchor(==(:commit)) do
        put!(b, 111)
    end
    a2 = withanchor(==(:commit)) do
        take!(b)
    end
    nextanchor!(a1)
    nextanchor!(a2)
    @test b.data.head[] === nothing
    @test finish!(a2) == 111
    @test b.data.head[] === nothing
    @test finish!(a1) === nothing
    @test b.data.head[] === nothing
end

end  # module
