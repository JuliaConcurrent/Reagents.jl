    Reagents.PostCommit(f)

Run `f(x)` when the reagent successfully completed its reaction where `x` is the
output of the upstream reagent.

# Examples

```julia
julia> using Reagents

julia> ref = Reagents.Ref(111);

julia> reagent = Reagents.Read(ref) ⨟ Reagents.PostCommit(x -> @show(x));

julia> reagent();
x = 111
```
