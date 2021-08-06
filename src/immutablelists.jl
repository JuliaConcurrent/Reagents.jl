struct ImmutableListNode{T}
    value::T
    tail::Union{ImmutableListNode{T},Nothing}
end

const ImmutableList{T} = Union{ImmutableListNode{T},Nothing}

@inline pushfirst(list, @nospecialize(value)) = ImmutableListNode(value, list)

Base.convert(::Type{ImmutableListNode{T}}, list::ImmutableListNode) where {T} =
    ImmutableListNode{T}(list.value, list.tail)

ilist(xs...) = foldr(ImmutableListNode, xs; init = nothing)

Base.eltype(::Type{ImmutableListNode{T}}) where {T} = T
Base.IteratorSize(::Type{ImmutableListNode{T}}) where {T} = Base.SizeUnknown()
Base.iterate(list::ImmutableListNode{T}, node = list) where {T} =
    if node === nothing
        node
    else
        (node.value, node.tail)
    end

pushsortedby(_, nothing, value) = ImmutableListNode(value, nothing)
function pushsortedby(f, list::ImmutableListNode{T}, value) where {T}
    if isless(f(value), f(list.value))
        return ImmutableListNode{T}(value, list)
    else
        return ImmutableListNode{T}(list.value, pushsortedby(f, list.tail, value))
    end
end

combinesortedby(_, ::Nothing, ::Nothing) = nothing
combinesortedby(_, xs::ImmutableListNode, ::Nothing) = xs
combinesortedby(_, ::Nothing, ys::ImmutableListNode) = ys
function combinesortedby(f, xs::ImmutableListNode{T}, ys::ImmutableListNode{T}) where {T}
    if isless(f(xs.value), f(ys.value))
        return ImmutableListNode{T}(xs.value, combinesortedby(f, xs.tail, ys))
    else
        return ImmutableListNode{T}(ys.value, combinesortedby(f, xs, ys.tail))
    end
end

combine(::Nothing, ::Nothing) = nothing
combine(list::ImmutableListNode, ::Nothing) = list
combine(::Nothing, list::ImmutableListNode) = list
combine(xs::ImmutableListNode{T}, ys::ImmutableListNode{T}) where {T} =
    ImmutableListNode{T}(xs.value, combine(xs.tail, ys))

has(_list, _x) = false
has(list::ImmutableListNode{T}, x::T) where {T} = list.value === x || has(list.tail, x)
