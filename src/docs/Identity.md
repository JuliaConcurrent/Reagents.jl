    Reagents.Identity()

The identity reagent.  This is the identity element of [`⨟`](@ref) (hence of
`∘`).

# Examples

```julia
julia> using Reagents

julia> reagent = Reagents.Map(string) ⨟ Reagents.Identity();

julia> reagent(111)
"111"
```
