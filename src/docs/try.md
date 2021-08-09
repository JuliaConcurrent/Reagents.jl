    Reagents.try(reagent::Reagent, [value = nothing])

Invoke `reagent` with `value`. If it succeeds with an `output`, return
`Some(output)`. If it is blocked, return `nothing`.
