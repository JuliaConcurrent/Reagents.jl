struct NotSet end
struct CASing end

Reagents.Ref{T}() where {T} = GenericRef{T}()
Reagents.Ref{T}(x) where {T} = GenericRef{T}(x)
Reagents.Ref(x::T) where {T} = GenericRef{T}(x)

mutable struct GenericRef{T} <: Reagents.Ref{T}
    @atomic value::Any
end

GenericRef{T}() where {T} = GenericRef{T}(NotSet())
