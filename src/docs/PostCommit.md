    Reagents.PostCommit(f)

Run `f(output)` when the reagent successfully completed its reaction with
`output`.

# Examples

```julia
julia> using Reagents

julia> ref = Reagents.Ref(111);

julia> reagent = Reagents.Read(ref) ⨟ Reagents.PostCommit(x -> @show(x));

julia> reagent();
x = 111
```
