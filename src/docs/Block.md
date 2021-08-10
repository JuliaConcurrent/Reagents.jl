    Reagents.Block()

A value indicating that the reaction is blocked.

Reagents such as [`Reagents.Computed`](@ref) and [`Reagents.Map`](@ref) can
return this value to indicate that other branches of the choice combinator
[`|`](@ref Reagents.:|) should be used.
