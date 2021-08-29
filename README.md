# Reagents.jl: Towards composable and extensible nonblocking programming for Julia

[![docs dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tkf.github.io/Reagents.jl/dev)

Reagents.jl implements and extends *reagents* by Turon (2012). It provides
higher-order concurrency primitives for expressing *nonblocking*¹ algorithms and
*synchronizations* of concurrent tasks in a composable manner.

For example, `op1 | op2` is the *choice* combinator that combines the "lazy"
representation of operations (called *reagents*) and expresses that only one of
the operations take place. This is similar to the `select` statement
[popularized by Go](https://tour.golang.org/concurrency/5) as a mechanism for
expressing rich [concurrency
patterns](https://talks.golang.org/2012/concurrency.slide).  This is a form of
the *selective communication* that are implemented by numerous other languages
(and libraries²) such as Erlang ([`receive`
expression](https://www.erlang.org/course/concurrent-programming)), occam
([`ALT` statement](https://en.wikipedia.org/wiki/Occam_(programming_language))),
and Concurrent ML² ([`select`
expression](http://cml.cs.uchicago.edu/pages/cml.html#SIG:CML.select:VAL)), to
name a few.  However, unlike [Go that only supports synchronization of channels
in `select`](https://golang.org/ref/spec#Select_statements)³ or [Erlang that
only supports selecting incoming
messages](https://erlang.org/doc/reference_manual/expressions.html#receive),
Reagents.jl's choice combinator supports arbitrary user-defined data structures.
Furthermore, it provides other [combinators such as `⨟` and
`&`](https://tkf.github.io/Reagents.jl/dev/reference/api/#Reagent-Combinators)
for declaring atomicity of the operations, similar to the [software
transactional
memory](https://en.wikipedia.org/wiki/Software_transactional_memory) mechanism.

Reagents.jl is a foundation of [Julio.jl](https://github.com/tkf/Julio.jl), an
implementation of [structured
concurrency](https://en.wikipedia.org/wiki/Structured_concurrency) for Julia.
Reagents.jl extends the original description of reagents (Turon, 2012) by adding
more primitives such as `WithNack` from [Concurrent
ML](https://en.wikipedia.org/wiki/Concurrent_ML) (which is a natural extension
due to the influence of Concurrent ML on reagents, as Turon (2012) noted).

---

¹ Due to the simplistic implementation of the k-CAS, Reagents.jl is not yet
nonblocking in the strict sense.  However, as discussed in Turon (2012), it
should be straightforward to switch to a k-CAS algorithm with more strict
guarantee.

² This includes other languages such as
[Racket](https://docs.racket-lang.org/reference/sync.html) and [GNU
Guile](https://github.com/wingo/fibers) that implemented the Concurrent ML
primitives.

³ But perhaps [for good
reasons](https://www.youtube.com/watch?v=VoS7DsT1rdM&t=2328s) for Go.

## Example: Treiber stack

Let us implement [Treiber stack](https://en.wikipedia.org/wiki/Treiber_stack)
which can be represented as an atomic reference to an immutable list:

```julia
using Reagents

struct Node{T}
    head::T
    tail::Union{Node{T},Nothing}
end

const List{T} = Union{Node{T},Nothing}

struct TreiberStack{T,Ref<:Reagents.Ref{List{T}}}
    head::Ref
end

TreiberStack{T}() where {T} = TreiberStack(Reagents.Ref{List{T}}(nothing))
```

The push and pop operations can be expressed as reagents:

```julia
pushing(stack::TreiberStack) =
    Reagents.Update((xs, x) -> (Node(x, xs), nothing), stack.head)

popping(stack::TreiberStack) =
    Reagents.Update(stack.head) do xs, _
        if xs === nothing
            return (nothing, nothing)
        else
            return (xs.tail, xs.head)
        end
    end
```

The execution ("reaction") of the reagent can be invoked by just calling the
reagent object.  So, it's straightforward to wrap it in the standard function
API:

```julia
Base.push!(stack::TreiberStack, value) = pushing(stack)(value)
Base.pop!(stack::TreiberStack) = popping(stack)()
```

These user-defined reagents can be composed just like pre-defined reagents.
For example, we can move an element from one stack to another by using
the sequencing combinator `⨟`:

```julia
s1 = TreiberStack{Int}()
s2 = TreiberStack{Int}()
push!(s1, 1)
(popping(s1) ⨟ pushing(s2))()
@assert pop!(s2) == 1
```

Here, the element in the stack `s1` is popped and then pushed to the stack `s2`
*atomically*. Similar code works with arbitrary pair of containers, possibly
of different types.

For more examples, read [**the documentation**](https://tkf.github.io/Reagents.jl/dev)
or see the [`examples` directory](https://github.com/tkf/Reagents.jl/tree/master/examples).

## Resources

* Turon, Aaron. 2012. “Reagents: Expressing and Composing Fine-Grained
  Concurrency.” In Proceedings of the 33rd ACM SIGPLAN Conference on Programming
  Language Design and Implementation, 157–168. PLDI ’12. New York, NY, USA:
  Association for Computing Machinery. <https://doi.org/10.1145/2254064.2254084>.

* The original implementation by Turon (2012):
  <https://github.com/aturon/ChemistrySet>

* Sivaramakrishnan, KC, and Théo Laurent. “Lock-Free Programming for the
  Masses,” <https://kcsrk.info/papers/reagents_ocaml16.pdf>

* [LDN Functionals #8 KC Sivaramakrishnan: OCaml multicore and programming with
  Reagents - YouTube](https://www.youtube.com/watch?v=qRWTws_YPBA)

* Reagent implementation for OCaml:
  <https://github.com/ocaml-multicore/reagents>
