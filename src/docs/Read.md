    Reagents.Read(ref::Reagents.Ref)

A reagent that reads the value in `ref`.

# Example

```julia
julia> using Reagents

julia> ref = Reagents.Ref(111);

julia> reagent = Reagents.Read(ref);

julia> reagent()
111
```
