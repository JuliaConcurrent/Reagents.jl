# Reagents.jl: Towards composable and extensible nonblocking programming for Julia

[![docs dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tkf.github.io/Reagents.jl/dev)

Reagents.jl implements *reagents* (Turon, 2012) which provides higher-order
concurrency primitives for expressing *nonblocking* algorithms and concurrent
*synchronizations* in a composable manner.

For example, `op1 | op2` is the combinator that combines the "lazy"
representation of operations (called *reagents*) and expresses that only one of
the operations take place. This is similar to [Go's `select` statement on
channels](https://tour.golang.org/concurrency/5) (Ref:
[specification](https://golang.org/ref/spec#Select_statements)) but Reagents.jl
has other combinators and is extensible to any user-defined data structures.

Note: Due to the simplistic implementation of the k-CAS, Reagents.jl is not yet
nonblocking in the strict sense.  However, as discussed in Turon (2012), it
should be straightforward to switch to a k-CAS algorithm with more strict
guarantee.

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
