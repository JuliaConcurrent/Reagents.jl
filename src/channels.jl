function Reagents.channel(::Type{A} = Any, ::Type{B} = A) where {A,B}
    bag1 = Bag{Message{A}}()
    bag2 = Bag{Message{B}}()
    return Swap(bag1, bag2), Swap(bag2, bag1)
end
# TODO: is it better to return `Endpoint` which then lifted to `Swap`?

# mutable struct Message{A,B}
mutable struct Message{A}
    payload::A
    reaction::Reaction
    continuation::Reactable
    offer::Offer
end

function isdeleted(msg::Message)
    offer = msg.offer
    # TODO: don't wait?
    return !(offer.state[] isa Union{Pending,Waiting})
end

struct Swap{A,B} <: Reagent
    msgs::Bag{Message{A}}
    dual::Bag{Message{B}}
end

hascas(::Swap) = true
maysync(::Swap) = true

function tryreact!(
    actr::Reactor{<:Swap{A,B}},
    a,
    rx::Reaction,
    offer::Union{Offer,Nothing},
) where {A,B}
    a = convert(A, a)
    (; msgs, dual) = actr.reagent
    if offer !== nothing  # && !maysync(actr.continuation)
        let m = Message{A}(a, rx, actr.continuation, offer)
            push!(msgs, m)
            @trace(
                label = :pushed_offer,
                offerid = offerid(offer),
                taskid = objectid(current_task()),
                still_in_msg = m in msgs,
                offer,
                msgs,
            )
        end
    end
    retry = false
    for msg in dual
        if msg.offer === offer || has(rx.offers, msg.offer)
            continue
        end
        ans = tryreact_together!(msg, actr.continuation, a, rx, offer)
        @trace(
            label = :done_tryreact_together,
            offerid = offerid(offer),
            taskid = objectid(current_task()),
            msg,
            ans,
            a,
            rx,
            offer,
        )
        if ans isa Retry
            retry = true
        elseif ans isa Block
            # continue
        else
            return ans
        end
    end
    for _ in msgs  # TODO: better cleanup
    end
    return retry ? Retry() : Block()
end

function tryreact_together!(msg::Message, k::Reactable, a, rx, offer)
    dual_offer = msg.offer
    function commit_dual_offer(b)  # `b` is the output of `msg.continuation`
        # TODO: don't wait for `CASing` here?
        old = dual_offer.state[]
        @trace(
            label = :commit_dual_offer,
            offer_state = old,
            taskid = objectid(current_task()),
            dual_taskid = objectid(dual_offer.task),
            offerid = offerid(dual_offer),
        )
        old isa Union{Waiting,Pending} || return Retry()
        function fulfil_dual_offer(old)
            function wake_dual(_)
                @trace(
                    label = :wake_dual,
                    taskid = objectid(current_task()),
                    dual_taskid = objectid(dual_offer.task),
                )
                schedule(dual_offer.task)
            end
            if old isa Pending
                return CAS(dual_offer.state, old, b)
            elseif old isa Waiting
                return CAS(dual_offer.state, old, b) ⨟ PostCommit(wake_dual)
            else
                return Retry()
            end
        end
        return Read(dual_offer.state) ⨟ Computed(fulfil_dual_offer)
    end
    actr = then(
        Reagent(msg.continuation) ⨟  # execute the dual continuation with `a` as the input
        Computed(commit_dual_offer) ⨟  # use `CAS` reagent to set/commit the dual offer
        Return(msg.payload),  # use the dual's value as the input for this continuation `k`
        k,
    )
    return tryreact!(actr, a, withoffer(combine(rx, msg.reaction), msg.offer), offer)
end
