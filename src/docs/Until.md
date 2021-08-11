    Reagents.Until(f, loop::Reagent)

Keep reacting with reagent while `f` returns `nothing` on the output of `loop`.
The reaction of `loop` will be *committed* if `f` returns `nothing` but without
the reaction of the reagent upstream to `Until`; i.e., they are still put on
hold.  Once `f` returns non-`nothing`, the upstream reaction (from reagents
before the `loop`), the reaction of the `loop`, and the downstream reactions are
committed together, like other type of reagents.

# Examples

```julia
julia> using Reagents

julia> ref1 = Reagents.Ref(10);
       ref2 = Reagents.Ref(111);

julia> reagent = Reagents.Until(Reagents.Update((x, _) -> (x - 1, x), ref1)) do x
           if x > 1
               nothing
           else
               Some(x)
           end
       end ⨟ Reagents.Update((x, _) -> (x + 1, x), ref2);

julia> reagent()
111

julia> ref1[]
0

julia> ref2[]
112
```
