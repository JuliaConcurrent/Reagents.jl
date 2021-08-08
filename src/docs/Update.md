    Reagents.Update(f, ref::Reagents.Ref{T})

Given a function of form `(v::T, a) -> (w::T, b)` and a [`Reagents.Ref`](@ref)
holding a value of type `T`, update its value to `w` and pass the output `b` to
the downstream reagent. The function `f` receives the value `v` in `ref` and the
output of `a` of the upstream reagent.

# Example

```julia
julia> using Reagents

julia> ref = Reagents.Ref(0);

julia> add! = Reagents.Update((v, a) -> (v + a, v), ref);

julia> add!(1)  # add 1 and return the old value
0

julia> add!(2)
1

julia> ref[]
3
```
