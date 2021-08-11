struct Pending end
struct Rescinded end
struct Waiting end

const WaiterFlags = Union{Pending,Rescinded,Waiting}
const WaiterState{T} = Union{Pending,Rescinded,Waiting,T}

struct Waiter{T,State<:Reagents.Ref{WaiterState{T}}}
    state::State
    task::Base.Task
end

Waiter{T}() where {T} =
    Waiter(Reagents.Ref{WaiterState{T}}(Pending()), current_task())::Waiter{T}

const CatalystFlags = Union{Pending,Rescinded}
const CatalystState{T} = Union{Pending,Rescinded,T}

struct Catalyst{T,State<:Reagents.Ref{CatalystState{T}}}
    state::State
end

Catalyst{T}() where {T} = Catalyst(Reagents.Ref{CatalystState{T}}(Pending()))::Catalyst{T}

const Offer{T} = Union{Waiter{T},Catalyst{T}}

offerid(offer::Waiter) = objectid(offer.state)
offerid(::Catalyst) = UInt(1)
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

has_stale_cas(rx::Reaction) = has_stale_cas(rx.caslist)
has_stale_cas(::Nothing) = false
function has_stale_cas(list::ImmutableListNode{CAS})
    (; ref, old) = list.value
    value = @atomic ref.value
    return value !== old
end

struct Commit end

hascas(::Commit) = false

const Reactable = Union{Reactor,Commit}

maysync(actr::Reactor) = maysync(actr.reagent) || maysync(actr.continuation)
maysync(::Commit) = false

maysync(::Reagent) = false
