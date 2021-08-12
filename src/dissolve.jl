function Reagents.dissolve(reagent::Reagent)
    offer = Catalyst{Any}()  # TODO: narrow type
    actr = then(reagent ⨟ PostCommit(ReDissolve(reagent)), Commit())
    ans = tryreact!(actr, nothing, Reaction(), offer)
    if ans isa NeedNack
        error("WithNack reagent cannot be dissolved")
    elseif !(ans isa Block)
        error("non-blocking reagent cannot be dissolved")
    end
end
# An approach alternative to executing `redissolve` as above is to keep the
# catalyzing messages in the channel's bags. However, it'd require additional
# mechanism to re-execute pre-blocking reagents (e.g., `cas ⨟ swap`).

struct ReDissolve{R<:Reagent}
    reagent::R
end

(f::ReDissolve)(_) = Reagents.dissolve(f.reagent)

redissolve!(_) = false
redissolve!(actr::Reactor) = redissolve!(actr.continuation)
function redissolve!(actr::Reactor{<:PostCommit{<:ReDissolve}})
    actr.reagent.f(nothing)
    return true
end

"""
    maybe_redissolve!(msg::Message)

This is called via `tryreact!(::Reactor{<:Swap}, ...)` when the reaction result
involving `msg` is `Retry()`. This could be due to that there is a stale CAS in
`msg.reaction`. We need to refresh these CASes to avoid deadlock.

TODO: better propagation of what CASes failed, to avoid reloading?
"""
function maybe_redissolve!(msg::Message)
    offer = msg.offer
    offer isa Catalyst || return
    has_stale_cas(msg.reaction) || return
    if cas!(offer.state, Pending(), Rescinded()).success
        ok = redissolve!(msg.continuation)
        @assert ok
    end
end
