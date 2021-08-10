    Reagents.Map(f)

Transform the output value of the upstream reagent by `f` and pass it to the
downstream reagent.

# Examples

```julia
julia> using Reagents

julia> ref = Reagents.Ref(111);

julia> (Reagents.Read(ref) ⨟ Reagents.Map(string))()
"111"
```

