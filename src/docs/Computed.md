    Reagents.Computed(f)

Create a reagent dynamically with function `f` which receives the output of the
upstream reagent. The resulting reagent is composed with the downstream reagent.

# Examples

```julia
julia> using Reagents
       using Reagents: Read, CAS, Computed

julia> ref = Reagents.Ref(0);

julia> reagent = Read(ref) ⨟ Computed(old -> CAS(ref, old, old + 1));

julia> reagent();

julia> ref[]
1

julia> reagent();

julia> ref[]
2
```
