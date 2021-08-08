struct Pending end
struct Rescinded end
struct Waiting end

const OfferFlags = Union{Pending,Rescinded,Waiting}
const OfferState{T} = Union{Pending,Rescinded,Waiting,T}

struct Offer{T,State<:Reagents.Ref{OfferState{T}}}
    state::State
    task::Base.Task
end

Offer{T}() where {T} =
    Offer(Reagents.Ref{OfferState{T}}(Pending()), current_task())::Offer{T}

offerid(offer::Offer) = objectid(offer.state)
offerid(::Nothing) = UInt(0)

struct Reaction
    caslist::ImmutableList{CAS}
    offers::ImmutableList{Offer}
    postcommithooks::ImmutableList{Any}
end

Reaction() = Reaction(nothing, nothing, nothing)

hascas(rx::Reaction) = rx.caslist !== nothing

uintptr(x) = UInt(pointer_from_objref(x.ref))

withcas(rx::Reaction, cas::CAS) =
    Reaction(pushsortedby(uintptr, rx.caslist, cas), rx.offers, rx.postcommithooks)

withoffer(rx::Reaction, offer::Offer) =
    Reaction(rx.caslist, pushfirst(rx.offers, offer), rx.postcommithooks)

withpostcommit(rx::Reaction, @nospecialize(f)) =
    Reaction(rx.caslist, rx.offers, pushfirst(rx.postcommithooks, f))

combine(rx1::Reaction, rx2::Reaction) = Reaction(
    combinesortedby(uintptr, rx1.caslist, rx2.caslist),
    combine(rx1.offers, rx2.offers),
    combine(rx1.postcommithooks, rx2.postcommithooks),
)

setcasing!(::Nothing) = true
function setcasing!(list::ImmutableListNode{CAS})
    (; ref, old) = list.value
    (_, success) = @atomicreplace ref.value old => CASing()
    success || return false
    if setcasing!(list.tail)
        return true
    else
        @atomic ref.value = old
        return false
    end
end

setall!(::Nothing) = true
function setall!(list::ImmutableListNode{CAS})
    (; ref, new) = list.value
    @atomic ref.value = new
    return setall!(list.tail)
end

commit!(rx::Reaction) = setcasing!(rx.caslist) && setall!(rx.caslist)

struct Commit end

hascas(::Commit) = false

const Reactable = Union{Reactor,Commit}

maysync(actr::Reactor) = maysync(actr.reagent) || maysync(actr.continuation)
maysync(::Commit) = false

maysync(::Reagent) = false
