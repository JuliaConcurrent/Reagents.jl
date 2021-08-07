mutable struct BagNode{T}
    @atomic next::Union{BagNode{T},Nothing}
    value::T

    BagNode{T}() where {T} = new{T}(nothing)
    BagNode{T}(next::Union{BagNode{T},Nothing}, value::T) where {T} = new{T}(next, value)
end

# TODO: find a proper/better bag algorithm?
mutable struct Bag{T}
    @atomic next::Union{BagNode{T},Nothing}
end

Bag() = Bag{Any}()
Bag{T}() where {T} = Bag{T}(nothing)

Base.eltype(::Type{Bag{T}}) where {T} = T
Base.IteratorSize(::Type{<:Bag}) = Base.SizeUnknown()

function isdeleted end

function Base.iterate(bag::Bag, (prev, curr) = (bag, @atomic bag.next))
    curr === nothing && return nothing
    next = @atomic curr.next
    while isdeleted(curr.value)
        if curr.value isa Message
            @trace(
                label = :cleaning_offer,
                offerid = offerid(curr.value.offer),
                taskid = objectid(current_task()),
                offer = curr.value.offer,
                msgs = bag,
            )
        end
        # `prev` may be phisically removed while `curr` is phisically removed.
        # But this is OK since `curr` is already logically removed.
        # TODO: check this
        curr, ok = @atomicreplace(prev.next, curr => next)
        if ok
            curr = next
        end
        curr === nothing && return nothing
        next = @atomic curr.next
    end
    return (curr.value, (curr, next))
end

function Base.push!(bag::Bag{T}, v) where {T}
    v = convert(T, v)
    next = @atomic bag.next
    node = BagNode{T}(next, v)
    while true
        next, success = @atomicreplace(bag.next, next => node)
        success && return bag
        node = BagNode{T}(next, v)
    end
end

function Base.in(v::T, bag::Bag{T}) where {T}
    for x in bag
        x === v && return true
    end
    return false
end

function tryremove!(bag::Bag{T}, item::T) where {T}
    prev = bag
    y = iterate(bag)
    while true
        y === nothing && return false
        value, (curr, next) = y
        if value === item
            @atomicreplace(prev.next, curr => next)
            return true
        end
        prev = curr
        y = iterate(bag, (curr, next))
    end
end
