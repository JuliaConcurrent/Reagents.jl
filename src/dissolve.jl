function Reagents.dissolve(reagent::Reagent; once = false)
    offer = Catalyst{Any}()  # TODO: narrow type
    actr = then(once ? reagent : reagent ⨟ PostCommit(ReDissolve(reagent)), Commit())
    ans = tryreact!(actr, nothing, Reaction(), offer)

    ntries = 0
    while true
        ans isa Block && return
        (once && !(ans isa Failure)) && return
        if ans isa NeedNack
            error("WithNack reagent cannot be dissolved")
            # ...or is it OK?
        end
        # Otherwise, it means that `reagent` just helped a reaction somewhere or
        # failed with `Retry`.  We need to make sure that there is no more duals
        # waiting for a swap.  However, since the catalyst is already dissolved,
        # we don't need to provide the `offer` here.
        ans = tryreact!(then(reagent, Commit()), nothing, Reaction(), nothing)

        ntries += 1
        should_limit_retries() && ntries > 1000 && error("too many retries")
    end
end
# An approach alternative to executing `redissolve` as above is to keep the
# catalyzing messages in the channel's bags. However, it'd require additional
# mechanism to re-execute pre-blocking reagents (e.g., `cas ⨟ swap`).

# Note: Registering catalysts on both ends of the channel can trigger an
# infinite loop. Is it possible to detect this?

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
        redissolve!(msg.continuation)
    end
end
