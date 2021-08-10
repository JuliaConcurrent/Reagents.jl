    Reagents.Ref{T}()
    Reagents.Ref{T}(value::T)

Create a reference storing a value of type `T`.

Use reagents such as [`Reagents.Update`](@ref), [`Reagents.CAS`](@ref), and
[`Reagents.Read`](@ref) to manipulate the value.

# Example

```julia
julia> using Reagents

julia> ref = Reagents.Ref{Int}();

julia> ref[] = 111;

julia> ref[]
111

julia> Reagents.try(Reagents.CAS(ref, 111, 222)) !== nothing
true

julia> ref[]
222
```
