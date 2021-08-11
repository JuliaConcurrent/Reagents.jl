    Reagents.Return(value)

Pass `value` to the downstream reagent.

# Examples

```julia
julia> using Reagents

julia> Reagents.Return(1)()
1

julia> ref = Reagents.Ref(111);

julia> (Reagents.Return(222) ⨟ Reagents.Update((old, inc) -> (old + inc, old), ref))()
111

julia> ref[]
333
```
