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
maysync(r::Return) = r.value isa SomehowBlocked

function tryreact!(actr::Reactor{<:Return}, _, rx::Reaction, offer::Union{Offer,Nothing})
    (; value) = actr.reagent
    value isa Failure && return value
    return tryreact!(actr.continuation, value, rx, offer)
end

hascas(::Map) = false
maysync(::Map) = true  # maybe

function tryreact!(actr::Reactor{<:Map}, a, rx::Reaction, offer::Union{Offer,Nothing})
    (; f) = actr.reagent
    b = f(a)
    b isa Failure && return b
    return tryreact!(actr.continuation, b, rx, offer)
end

Reagents.Map(::Type{T}) where {T} = Reagents.Map{Type{T}}(T)
