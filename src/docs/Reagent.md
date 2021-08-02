    Reagents.Reagent

Composable description for nonblocking and synchronous operations.

Reagents can be composed with `∘` although it is recommended to use the opposite
composition operator `⨟`.  A composed Reagent can be called, just like a
function, to actually execute the side-effects.

# Example

```julia
julia> using Reagents

julia> reagent = Reagents.Return(1) ⨟ Reagents.Map(string);

julia> reagent()
"1"
```
