    Reagents.channel(A::Type, B::Type = A) -> (a2b, b2a)

Create a pair of swap endpoints for exchanging a value `a` of type `A` and a
value `b` of type `B` *synchronously*.

The endpoints `a2b` and `b2a` are reagents.

# Example

```julia
julia> using Reagents

julia> a2b, b2a = Reagents.channel(Int, Symbol);

julia> t = @async b2a(:hello);

julia> a2b(123)
:hello

julia> fetch(t)
123
```
