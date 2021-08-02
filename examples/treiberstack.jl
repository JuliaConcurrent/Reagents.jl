using Reagents

struct TSNode{T}
    head::T
    tail::Union{TSNode{T},Nothing}
end

const TSList{T} = Union{TSNode{T},Nothing}

struct TreiberStack{T,Ref<:Reagents.Ref{TSList{T}}}
    head::Ref
end

TreiberStack{T}() where {T} =
    TreiberStack(Reagents.Ref{TSList{T}}(nothing))::TreiberStack{T}

Base.eltype(::Type{<:TreiberStack{T}}) where {T} = T

pushing(stack::TreiberStack) =
    Reagents.Update((xs, x) -> (TSNode(x, xs), nothing), stack.head)

trypopping(stack::TreiberStack) =
    Reagents.Update(stack.head) do xs, _
        if xs === nothing
            return (nothing, nothing)
        else
            return (xs.tail, Some(xs.head))
        end
    end

Base.push!(stack::TreiberStack, value) = pushing(stack)(convert(eltype(stack), value))
Base.pop!(stack::TreiberStack) = something(trypopping(stack)())
