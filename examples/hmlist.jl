using Reagents
using Reagents: Computed, Return, CAS, PostCommit

struct HMNode{T,R}
    next::R
    data::T
    HMNode{T,R}(next) where {T,R} = new{T,R}(next)
    HMNode{T,R}(next, data) where {T,R} = new{T,R}(next, data)
end

struct Deleted{T}
    value::T
end

const HMNodeRef{T} =
    Reagents.Ref{Union{Nothing,HMNode{T},Deleted{<:Union{Nothing,HMNode{T}}}}}

HMNode(next::HMNodeRef{T}) where {T} = HMNode{T,typeof(next)}(next)
HMNode(next::HMNodeRef{T}, data) where {T} = HMNode{T,typeof(next)}(next, data)

struct HMList{T,K,R<:HMNodeRef{T}}
    key::K
    head::R
    function HMList{T}(key = identity) where {T}
        head = HMNodeRef{T}(nothing)
        return new{T,typeof(key),typeof(head)}(key, head)
    end
end

Base.eltype(::Type{<:HMList{T}}) where {T} = T

function search(list::HMList{T}, x::T) where {T}
    needle = list.key(x)
    while true
        prev = list.head
        curr = prev[]
        while true
            curr === nothing && return false, prev, nothing, nothing
            next = curr.next[]
            prev[] === curr || break
            if next isa Deleted
                if Reagents.try(CAS(prev, curr, next.value)) === nothing
                    break
                end
                curr = next.value
            else
                ckey = list.key(curr.data)
                if !isless(ckey, needle)
                    return isequal(ckey, needle), prev, curr, next
                end
                prev = curr.next
                curr = next
            end
        end
    end
end

pushing(list::HMList{T}) where {T} =
    Computed() do x
        found, prev, curr, _next = search(list, x)
        if found
            Return(false)
        else
            node = HMNode(HMNodeRef{T}(curr), x)
            CAS(prev, curr, node) ⨟ Return(true)
        end
    end

trydeleting(list::HMList) =
    Computed() do x
        found, prev, curr, next = search(list, x)
        if found
            deleted = Deleted(next)
            CAS(curr.next, next, deleted) ⨟ PostCommit() do _
                Reagents.try(CAS(prev, curr, next))
            end
        else
            Return(false)
        end
    end

function Base.push!(list::HMList, x)
    pushing(list)(convert(eltype(list), x))
    return list
end

function Base.delete!(list::HMList, x)
    trydeleting(list)(convert(eltype(list), x))
    return list
end

Base.in(x, list::HMList) = search(list, convert(eltype(list), x))[1]
