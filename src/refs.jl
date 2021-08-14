function tryreact!(actr::Reactor{<:Read}, _, rx::Reaction, offer::Union{Offer,Nothing})
    (; ref) = actr.reagent
    return tryreact!(actr.continuation, ref[], rx, offer)
end

function tryreact!(actr::Reactor{<:CAS}, a, rx::Reaction, offer::Union{Offer,Nothing})
    (; ref, old, new) = actr.reagent
    if offer === nothing && !hascas(rx) && !hascas(actr.continuation)
        if cas_weak!(ref, old, new).success
            return tryreact!(actr.continuation, a, rx, offer)
        else
            return Retry()
        end
    else
        return tryreact!(actr.continuation, a, withcas(rx, actr.reagent), offer)
    end
end

hascas(::Read) = false
hascas(::CAS) = true

function then(r::Update, actr::Reactable)
    (; ref, f) = r
    function make_cas((x, old),)
        new, y = f(old, x)
        return CAS(ref, old, new) ⨟ Return(y)
    end
    return then(TeeZip(Read(ref)) ⨟ Computed(make_cas), actr)
end

struct NotSet end
struct CASing end

Reagents.Ref{T}() where {T} = GenericRef{T}()
Reagents.Ref{T}(x) where {T} = GenericRef{T}(x)
Reagents.Ref(x::T) where {T} = GenericRef{T}(x)

mutable struct GenericRef{T} <: Reagents.Ref{T}
    @atomic value::Any
end

GenericRef{T}() where {T} = GenericRef{T}(NotSet())

function cas_weak!(ref::GenericRef{T}, expected::Union{T,NotSet}, desired::T) where {T}
    (old, success) = @atomicreplace ref.value expected => desired
    return (; old, success)
end

function cas!(ref::GenericRef{T}, expected::T, desired::T) where {T}
    old, success = cas_weak!(ref, expected, desired)
    while old isa CASing
        old = ref[]
        if old === expected
            old, success = cas_weak!(ref, expected, desired)
        else
            break
        end
    end
    return (; old, success)
end

Base.getindex(ref::GenericRef{T}) where {T} = something(tryget(ref))
function Base.setindex!(ref::GenericRef{T}, x::T) where {T}
    # Using CAS to avoid overwriting `CASing`.
    cas_weak!(ref, something(tryget(ref), NotSet()), x)
    return ref
end

function tryget(ref::GenericRef{T}) where {T}
    while true
        value = @atomic ref.value
        value isa NotSet && return nothing
        value isa CASing || return Some(value)
        GC.safepoint()
        # TODO: backoff?
    end
end

#=
mutable struct InlineRef{T,Storage} <: Reagents.Ref{T}
    @atomic value::Storage
end
=#
