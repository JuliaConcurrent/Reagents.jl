# API

```@eval
Main._BANNER_
```

```@index
```

## Reagents

```@docs
Reagents.Reagent
```

```@autodocs
Modules = [Reagents]
Filter = t -> t isa Type && t <: Reagents.Reagent && t !== Reagents.Reagent
```

```@docs
Reagents.channel
```

## Reagent Combinators

```@docs
Reagents.:|
Reagents.:&
Reagents.:⨟
```

## Reaction failures

```@docs
Reagents.Block
Reagents.Retry
```

## Misc

```@autodocs
Modules = [Reagents]
Filter = t -> !(
    (t isa Type && t <: Union{Reagents.Reagent,Reagents.Failure}) ||
    t isa Module ||
    t in ((|), (&), (Reagents.:⨟), Reagents.channel)
)
```
