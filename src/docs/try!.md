    Reagents.try!(reagent::Reagent, [value = nothing])

Invoke `reagent` with `value`. If it succeeds with an `output`, return
`Some(output)`. If it fails to react, return `nothing`.

It is guaranteed to return even if `reagent` is unsatisfiable (e.g.,
`Reagents.CAS(Reagents.Ref(0), 1, 2)`).
