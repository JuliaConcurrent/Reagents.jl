hascas(::Computed) = true  # maybe
maysync(::Computed) = true  # maybe
# TODO: check if `maysync(::Computed) == maysync(::Map) == true` is required/correct

function tryreact!(actr::Reactor{<:Computed}, a, rx::Reaction, offer::Union{Offer,Nothing})
    (; f) = actr.reagent
    r = f(a)::Union{Nothing,Failure,Reagent}
    if r === nothing
        return Block()
    elseif r isa Reagent
        return tryreact!(then(r, actr.continuation), a, rx, offer)
    else
        return r
    end
end

hascas(::Return) = false
maysync(::Return) = false  # See: maysync(::Map)

function tryreact!(actr::Reactor{<:Return}, _, rx::Reaction, offer::Union{Offer,Nothing})
    (; value) = actr.reagent
    value isa Failure && return value
    return tryreact!(actr.continuation, value, rx, offer)
end

struct ReturnIfBlocked{T} <: Reagent
    value::T
end

hascas(::ReturnIfBlocked) = false
maysync(::ReturnIfBlocked) = false  # See: maysync(::Map)

function tryreact!(
    actr::Reactor{<:ReturnIfBlocked},
    a,
    rx::Reaction,
    offer::Union{Offer,Nothing},
)
    (; value) = actr.reagent
    maysync(actr.continuation) || error("synchronizing continuation is required")
    ans = tryreact!(actr.continuation, a, rx, offer)
    if ans isa SomehowBlocked
        offer === nothing && return Block()  # require `offer` to try other branches
        if ans isa NeedNack
            runpostcommithooks(ans, nothing)
        end
        return value
    elseif ans isa Retry
        # Assuming the continuation has `Swap`, it must eventually return
        # `Block`.  So, retring the reaction should be fine.
        return ans
    else
        return ans
    end
end

hascas(::Map) = false
maysync(::Map) = false
# `Map`, `Return`, etc. may return `Block` for nudging reactions to try other
# branches (and also to indicate that `offer` is required). But these reagents
# themselves do not attempt to sync. It *seems* like retruning `false` in this
# case is more useful; see how `ReturnIfBlocked` use it for deadlock detection.

function tryreact!(actr::Reactor{<:Map}, a, rx::Reaction, offer::Union{Offer,Nothing})
    (; f) = actr.reagent
    b = f(a)
    b isa Failure && return b
    return tryreact!(actr.continuation, b, rx, offer)
end

Reagents.Map(::Type{T}) where {T} = Reagents.Map{Type{T}}(T)
