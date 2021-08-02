(r::Reagent)() = r(nothing)
function (r::Reagent)(a::A) where {A}
    # backoff = Backoff()
    actr = then(r, Commit())
    ntries = 0

    # without offer
    while true
        ans = tryreact!(actr, a, Reaction(), nothing)
        if ans isa Block
            break
        elseif ans isa Retry
            GC.safepoint()  # once(backoff)?
            if maysync(r)
                break
            end
        else
            return ans
        end
        ntries += 1
        istracing() && ntries > 1000 && error("too many retries")
        ntries > 1000 && error("too many retries")
    end

    # with offer
    while true
        offer = Offer{Any}()  # TODO: narrow type
        ans = tryreact!(actr, a, Reaction(), offer)
        if ans isa Block
            wait(offer)
        elseif ans isa Retry
            yield()  # once(backoff)?
        else
            return ans
        end
        let ans = rescind!(offer)
            ans === nothing || return something(ans)
        end
        ntries += 1
        istracing() && ntries > 1000 && error("too many retries")
    end
end

Reagents.try(r::Reagent, a = nothing) = ((r ⨟ Map(Some)) | Return(nothing))(a)

hascas(actr::Reactor) = hascas(actr.reagent) || hascas(actr.continuation)

function Base.wait(offer::Offer)
    if cas_weak!(offer.state, Pending(), Waiting()).success
        @trace(
            label = :start_wait,
            taskid = objectid(current_task()),
            offerid = objectid(offer.state),
        )
        wait()
        @trace(label = :stop_wait, taskid = objectid(current_task()))
    end
    return
end

#=
function putting(offer::Offer{T}, value::T) where {T}
    Read(offer.state) ⨟ Computed() do old
        if old isa Pending
        elseif old isa Waiting
        else
            Retry()
        end
    end
end
=#

function tryput!(offer::Offer{T}, value::T) where {T}
    old, success = cas_weak!(offer.state, Pending(), value)
    success && return true
    old isa Rescinded && return false
    if old isa Waiting
        (_, success) = cas_weak!(offer.state, Waiting(), value)
        if success
            schedule(offer.task)
        end
        return success
    else
        return false
    end
end

rescind!(::Nothing) = nothing
function rescind!(offer::Offer)
    (old, success) = cas!(offer.state, Pending(), Rescinded())
    # success && return nothing
    old isa OfferFlags && return nothing
    return Some(old)
end

function tryreact!(::Commit, a, rx::Reaction, offer::Union{Offer,Nothing})
    let ans = rescind!(offer)
        ans === nothing || return something(ans)
    end
    @trace(label = :commit, taskid = objectid(current_task()), rx)
    if commit!(rx)
        hooks = rx.postcommithooks
        if hooks !== nothing
            for f in hooks
                f(a)
            end
        end
        return a
    else
        return Retry()
    end
end

hascas(::PostCommit) = false

function tryreact!(
    actr::Reactor{<:PostCommit},
    a,
    rx::Reaction,
    offer::Union{Offer,Nothing},
)
    (; f) = actr.reagent
    return tryreact!(actr.continuation, a, withpostcommit(rx, f), offer)
end
