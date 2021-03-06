(r::Reagent)() = r(nothing)
function (r::Reagent)(a::A) where {A}
    @trace(label = :begin_react, taskid = objectid(current_task()))
    # backoff = Backoff()
    actr = then(r, Commit())
    ntries = 0

    # without offer
    while true
        ans = tryreact!(actr, a, Reaction(), nothing)
        @trace(
            label = :tryreact_without_offer,
            taskid = objectid(current_task()),
            offerid = offerid(nothing),
            ans
        )
        anchor(:tryreact_without_offer, (; ans))
        if ans isa SomehowBlocked
            if ans isa NeedNack
                runpostcommithooks(ans, nothing)
            end
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
        should_limit_retries() && ntries > 1000 && error("too many retries")
    end

    # with offer
    while true
        offer = Waiter{Any}()  # TODO: narrow type
        ans = tryreact!(actr, a, Reaction(), offer)
        @trace(
            label = :tryreact_with_offer,
            taskid = objectid(current_task()),
            offerid = offerid(offer),
            ans
        )
        anchor(:tryreact_with_offer, (; ans, offer))
        if ans isa SomehowBlocked
            wait(offer)
        elseif ans isa Retry
            yield()  # once(backoff)?
        else
            return ans
        end
        y = rescind!(offer)
        if ans isa NeedNack
            runpostcommithooks(ans, nothing)
        end
        y === nothing || return something(y)
        ntries += 1
        should_limit_retries() && ntries > 1000 && error("too many retries")
    end
end

Reagents.try!(r::Reagent, a = nothing) = ((r ⨟ Map(Some)) | Return(nothing))(a)
Reagents.trysync!(r::Reagent, a = nothing) = Reagents.trysyncing(r)(a)
Reagents.trysyncing(r::Reagent) = ReturnIfBlocked(nothing) ⨟ r ⨟ Map(Some)

hascas(actr::Reactor) = hascas(actr.reagent) || hascas(actr.continuation)

function Base.wait(offer::Waiter)
    if cas_weak!(offer.state, Pending(), Waiting()).success
        @trace(
            label = :start_wait,
            taskid = objectid(current_task()),
            offerid = offerid(offer),
        )
        wait()
        @trace(label = :stop_wait, taskid = objectid(current_task()))
    end
    return
end

function tryput!(offer::Waiter{T}, value::T) where {T}
    old, success = cas_weak!(offer.state, Pending(), value)
    success && return true
    old isa Rescinded && return false
    if old isa Waiting
        (_, success) = cas_weak!(offer.state, Waiting(), value)
        if success
            @trace(
                label = :tryput_wake_dual,
                taskid = objectid(current_task()),
                dual_taskid = objectid(offer.task),
            )
            schedule(offer.task)
        end
        return success
    else
        return false
    end
end

rescind!(::Nothing) = nothing
function rescind!(offer::Waiter)
    (old, success) = cas!(offer.state, Pending(), Rescinded())
    # success && return nothing
    old isa WaiterFlags && return nothing
    return Some(old)
end

function tryreact!(::Commit, a, rx::Reaction, offer::Union{Offer,Nothing})
    if offer isa Waiter
        ans = offer.state[]
        if ans isa Pending
            # Rescinding `offer` as part of commit, to keep the `offer` alive
            # until the last moment. This is required when CASes and channel
            # swaps are in multiple branches of `Choice`.
            # TODO: Check if this is OK. It's different from the paper.
            rx = withcas(rx, CAS(offer.state, Pending(), Rescinded()))
        elseif ans isa WaiterFlags
            return Retry()
        else
            @trace(
                label = :took_offer,
                taskid = objectid(current_task()),
                offerid = offerid(offer),
                ans,
            )
            return ans
        end
    end
    anchor(:commit, (; offer, rx))
    issuccess = commit!(rx)
    @trace(
        label = :commit,
        taskid = objectid(current_task()),
        offerid = offerid(offer),
        offer,
        rx,
        ans = a,
        issuccess,
    )
    if issuccess
        runpostcommithooks(rx, a)
        return a
    else
        return Retry()
    end
end

function runpostcommithooks(rx, @nospecialize(a))
    hooks = rx.postcommithooks
    if hooks !== nothing
        for f in hooks
            f(a)
        end
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
    after_commit(_) = f(a)
    return tryreact!(actr.continuation, a, withpostcommit(rx, after_commit), offer)
end
