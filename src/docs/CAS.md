    Reagents.CAS(ref::Reagents.Ref{T}, expected::T, desired::T)

A reagent for replacing the value in `ref` from `expected` to `desired`.
Multiple CAS reagents are committed atomically.

# Example

```julia
julia> using Reagents

julia> ref1 = Reagents.Ref(111);

julia> ref2 = Reagents.Ref(222);

julia> reagent = Reagents.CAS(ref1, 111, -1) ⨟ Reagents.CAS(ref2, 222, -2);

julia> reagent();

julia> ref1[]
-1

julia> ref2[]
-2
```
