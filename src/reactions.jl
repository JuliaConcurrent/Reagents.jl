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

"""
    Reaction

* `caslist::ImmutableList{CAS}`
* `offers::ImmutableList{Offer}`
* `postcommithooks::ImmutableList{Any}`

* `restart_on_failure::Bool` (default: `false`): A flag controlling if the
  offer should be invalidated on the failure.  Consider `(r | s) ⨟ t` where `s`
  and `t` both contain a `Swap`. When a `Swap` in `s` is triggered from the
  dual, it may indicate that `r` is now reactable (i.e., `s` is used as a
  condition variable).  In this case, it is now required to register the offer
  at `t`.  To support this behavior, `restart_on_failure` is set to `true` in
  the continuations of `Choice` (`|`). Then, in `tryreact!`, the offers of the
  dual messsage in `Swap` with `restart_on_failure` flag set are aborted.  In
  particular, if the state is in `Waiting`, the task is re-scheduled so that
  other branches of `|` can be re-evaluated.
"""
struct Reaction
    caslist::ImmutableList{CAS}
    offers::ImmutableList{Offer}
    postcommithooks::ImmutableList{Any}
    restart_on_failure::Bool
end

Reaction() = Reaction(nothing, nothing, nothing, false)

hascas(rx::Reaction) = rx.caslist !== nothing

uintptr(x) = UInt(pointer_from_objref(x.ref))

withcas(rx::Reaction, cas::CAS) = @set rx.caslist = pushsortedby(uintptr, rx.caslist, cas)
withoffer(rx::Reaction, offer::Offer) = @set rx.offers = pushfirst(rx.offers, offer)
withpostcommit(rx::Reaction, @nospecialize(f)) =
    @set rx.postcommithooks = pushfirst(rx.postcommithooks, f)

combine(rx1::Reaction, rx2::Reaction) = Reaction(
    combinesortedby(uintptr, rx1.caslist, rx2.caslist),
    combine(rx1.offers, rx2.offers),
    combine(rx1.postcommithooks, rx2.postcommithooks),
    rx1.restart_on_failure | rx2.restart_on_failure,
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
