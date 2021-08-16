    Reagents.trysync!(reagent::Reagent, [value = nothing]) -> Some(output) or nothing

Invoke synchronizing `reagent` with `value`. If it succeeds with an `output`,
return `Some(output)`. If it is blocked, return `nothing`.

This function is guaranteed to return if the `reagent` eventually succeeds or
synchronizes.  Supplying unsatisfiable `reagent` (e.g.,
`Reagents.CAS(Reagents.Ref(0), 1, 2)`) is unsupported (it is likely to
deadlock).
