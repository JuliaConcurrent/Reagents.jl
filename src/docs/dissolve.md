    Reagents.dissolve(catalyst::Reagent)

Register `catalyst` as a persistent reagent that helps other reaction.

The reagent `catalyst` must include a blocking reagent (i.e.,
[`Reagents.channel`](@ref)).

For more information, see [Catalysts](@ref catalysts) section in the manual.

# Examples

```julia
julia> using Reagents

julia> send1, receive1 = Reagents.channel(Int, Nothing)
       send2, receive2 = Reagents.channel(Char, Nothing)
       sendall, receiveall = Reagents.channel(Tuple{Int,Char}, Nothing);

julia> catalyst = (receive1 & receive2) ⨟ sendall;

julia> Reagents.dissolve(catalyst);

julia> @sync begin
           @async send1(1)
           @async send2('a')
           receiveall()
       end
(1, 'a')
```
