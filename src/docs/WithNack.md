    Reagents.WithNack(f)

Dynamically create a reagent with negative acknowledgement (*nack*) reagent.

Function `f` takes a reagent `nack` that is blocked until the reaction of this
reagent is cancelled (i.e., another branch of `|` is selected). Function `f`
must return a reagent.
