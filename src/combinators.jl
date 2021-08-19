struct Sequence{Outer<:Reagent,Inner<:Reagent} <: Reagent
    outer::Outer
    inner::Inner
end

hascas(r::Sequence) = hascas(r.outer) || hascas(r.inner)
maysync(r::Sequence) = maysync(r.outer) || maysync(r.inner)

then(r::Sequence, actr::Reactable) = then(r.outer, then(r.inner, actr))
then(r::Reagent, actr::Reactable) = Reactor(r, actr)
then(::Identity, actr::Reactable) = actr

Reagents.Reagent(::Commit) = Identity()
Reagents.Reagent(actr::Reactor) = actr.reagent ⨟ Reagent(actr.continuation)

hascas(::Identity) = false

struct Choice{R1<:Reagent,R2<:Reagent} <: Reagent
    r1::R1
    r2::R2
end

hascas(r::Choice) = hascas(r.r1) || hascas(r.r2)
maysync(r::Choice) = maysync(r.r1) || maysync(r.r2)

_maysync(r::Reagent) = maysync(then(r, Commit()))
_hascas(r::Reagent) = hascas(then(r, Commit()))

function tryreact!(actr::Reactor{<:Choice}, a, rx::Reaction, offer::Union{Offer,Nothing})
    (; r1, r2) = actr.reagent
    rx = @set rx.restart_on_failure = true
    ans1 = tryreact!(then(r1, actr.continuation), a, rx, offer)
    @trace(
        label = :tried_choice1,
        offerid = offerid(offer),
        taskid = objectid(current_task()),
        ans = ans1,
        a,
        rx,
        offer,
        maysync_r1 = _maysync(r1),
        hascas_r2 = _hascas(r2),
    )
    ans1 isa Failure || return ans1
    if offer === nothing
        if _maysync(r1) && _hascas(r2)
            if ans1 isa NeedNack
                runpostcommithooks(ans1, nothing)
            end
            # If the first branch may synchronize, and the second branch has a
            # CAS, we need to simultaneously rescind the offer *and* commit the
            # CASes.
            @trace(
                label = :block_choice,
                offerid = offerid(offer),
                taskid = objectid(current_task()),
                ans = ans1,
                a,
                rx,
                offer,
            )
            return Block()
        end
    end
    ans2 = tryreact!(then(r2, actr.continuation), a, rx, offer)
    @trace(
        label = :tried_choice2,
        offerid = offerid(offer),
        taskid = objectid(current_task()),
        ans = ans2,
        a,
        rx,
        offer,
    )
    if ans1 isa NeedNack
        if ans2 isa NeedNack
            return NeedNack(combine(ans1.postcommithooks, ans2.postcommithooks))
        elseif ans2 isa Block
            return ans1
        else
            runpostcommithooks(ans1, nothing)
            return ans2
        end
    elseif ans1 isa Retry && ans2 isa Failure
        if ans2 isa NeedNack
            runpostcommithooks(ans2, nothing)
        end
        return Retry()
    else
        return ans2
    end
end

struct ZipSource{R<:Reagent} <: Reagent
    reagent::R
end

hascas(r::ZipSource) = hascas(r.reagent)
maysync(r::ZipSource) = maysync(r.reagent)


function tryreact!(actr::Reactor{<:ZipSource}, a, rx::Reaction, offer::Union{Offer,Nothing})
    (; reagent) = actr.reagent
    return tryreact!(then(reagent ⨟ Map(b -> (a, b)), actr.continuation), a, rx, offer)
end

struct Both{R1<:Reagent,R2<:Reagent} <: Reagent
    r1::R1
    r2::R2
end

hascas(r::Both) = hascas(r.r1) || hascas(r.r2)

struct Branch{Label,T}
    value::T
    label::Val{Label}
end

Branch{Label}(value) where {Label} = Branch(value, Val(Label))

function then(r::Both, actr::Reactable)
    (; r1, r2) = r
    function continuation(br)
        x, y = br.value
        if br isa Branch{1}
            return Return(x) ⨟ r2 ⨟ Map(z -> (y, z))
        else
            br::Branch{2}
            return Return(x) ⨟ r1 ⨟ Map(z -> (z, y))
        end
    end
    try1 = ZipSource(r1) ⨟ Map(Branch{1})
    try2 = ZipSource(r2) ⨟ Map(Branch{2})
    return then((try1 | try2) ⨟ Computed(continuation), actr)
end
# TODO: maybe directly define `tryreact`?
# Note: Using `Choice` inside `Both` so that *both* `r1` and `r2` can trigger
# the reaction.

Base.:∘(inner::Reagent, outer::Sequence) = (inner ∘ outer.inner) ∘ outer.outer
Base.:∘(inner::Reagent, outer::Reagent) = Sequence(outer, inner)

# `|` could be a bit misleading since `Choice` is rather `xor`
Base.:|(r1::Reagent, r2::Reagent) = Choice(r1, r2)
Base.:&(r1::Reagent, r2::Reagent) = Both(r1, r2)

#=
Base.:+(r1::Reagent, r2::Reagent) = Choice(r1, r2)
Base.:>>(r1::Reagent, r2::Reagent) = r2 ∘ r1
Base.:*(r1::Reagent, r2::Reagent) = Both(r1, r2)
=#

# Implementation strategy of `WithNack`
#
# `tryreact!(::Reactor{<:WithNack}, ...)` creates the post-command hook that
# needs to be fired when other branch is chosen.  This is propagated upwards by
# returned value `NeedNack` which is similar to `Block`.   In
# `tryreact!(::Reactor{<:Choice}, ...)`, this post-commit hook is merged into
# `rx::Reaction` used for the reaction of the "else" branch.

struct NeedNack <: Reagents.Failure
    postcommithooks::ImmutableList{Any}
end

const SomehowBlocked = Union{NeedNack,Block}

withnackhook(::Block, @nospecialize(f)) = NeedNack(pushfirst(nothing, f))
withnackhook(ans::NeedNack, @nospecialize(f)) = NeedNack(pushfirst(ans.postcommithooks, f))

# Same as `Computed`:
hascas(::WithNack) = true  # maybe
maysync(::WithNack) = true  # maybe

# TODO: Alternative strategy: Disable NACK in this branch via post-commit hook;
# trigger non-disabled NACKs while "bubbling" up.
function tryreact!(actr::Reactor{<:WithNack}, a, rx::Reaction, offer::Union{Offer,Nothing})
    if offer === nothing
        # `WithNack` is likely to invoke a costly function to setup some kind of
        # RPC.  Let's require `offer` to be instantiated so that it can be
        # registered in the communications in this branch.  This is an
        # optimization but the test relies on this behavior.
        return Block()
    end
    (; f) = actr.reagent
    iscancelled = Reagents.Ref{Union{Nothing,Bool}}(nothing)
    send, receive = Reagents.channel(Nothing)
    function cancel!(_)
        if cas!(iscancelled, nothing, true).success
            while Reagents.trysync!(send) !== nothing
            end
        end
    end
    function disable!(_)
        cas!(iscancelled, nothing, false)
    end
    nack = receive | (Read(iscancelled) ⨟ Map(x -> x === true ? nothing : Block()))
    y = f(nack)::Union{Failure,Reagent}
    if y isa Failure
        cancel!(nothing)
        return y
    end
    ans = tryreact!(then(y, actr.continuation), a, withpostcommit(rx, disable!), offer)
    if ans isa SomehowBlocked
        # `cancel!` will be registered into the else branch(es) of `Choice`
        return withnackhook(ans, cancel!)
    elseif ans isa Failure  # i.e., Retry
        cancel!(nothing)
        return ans
    else
        return ans
    end
end

struct UntilBegin{R<:Reactor} <: Reagent
    loop::R
end

hascas(r::UntilBegin) = hascas(r.loop)

struct UntilEnd{F,R<:Reactable} <: Reagent
    f::F
    continuation::R  # used only for `hascas`
end

hascas(r::UntilEnd) = hascas(r.continuation)

struct UntilBreak{T,Rx<:Reaction}
    value::T
    rx::Rx
end

then(r::Until, actr::Reactable) =
    then(UntilBegin(then(r.reagent, then(UntilEnd(r.f, actr), Commit()))), actr)

function tryreact!(
    actr::Reactor{<:UntilBegin},
    a,
    rx::Reaction,
    offer::Union{Offer,Nothing},
)
    (; loop) = actr.reagent
    while true
        ans = tryreact!(loop, a, Reaction(), nothing)
        if ans isa UntilBreak
            return tryreact!(actr.continuation, ans.value, combine(rx, ans.rx), offer)
        elseif ans isa SomehowBlocked
            error("`Until(f, reagent)` does not support blocking `reagent`")
        elseif ans isa Failure
            GC.safepoint()
            # TODO: backoff
        else
            ans::Nothing
        end
    end
end

function tryreact!(actr::Reactor{<:UntilEnd}, a, rx::Reaction, offer::Union{Offer,Nothing})
    (; f) = actr.reagent
    b = f(a)
    if b === nothing
        # Commit the reaction
        return tryreact!(actr.continuation, nothing, rx, offer)
    else
        return UntilBreak(b, rx)
    end
end
