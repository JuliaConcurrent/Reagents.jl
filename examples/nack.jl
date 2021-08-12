# # [Negative acknowledgement (NACK)](@id nack)

using Reagents
using Reagents: WithNack, Return
using Test

# Reagents.jl provides so-called *negative acknowledgement* (NACK) reagent
# [`Reagents.WithNack`](@ref) which is taken from [Concurrent
# ML](https://en.wikipedia.org/wiki/Concurrent_ML).  This is useful for writing
# "client-server" style of code where the client can abort the request.
#
# !!! note
#
#     Concurrent ML provides composable synchronizable operations called
#     *events* which are similar to [`Reagent`](@ref Reagents.Reagent).  Turon
#     (2012) discussed influences of Concurrent ML on reagents.
#
#     See also:
#     * [Concurrent ML's manual on `withNack`](http://cml.cs.uchicago.edu/pages/cml.html#SIG:CML.withNack:VAL)
#     * [Racket's manual on `nack-guard-evt`](https://docs.racket-lang.org/reference/sync.html#%28def._%28%28quote._~23~25kernel%29._nack-guard-evt%29%29)
#
# ## How it works
#
# Let us set up a demo.

function nack_demo()
    #=
    [`Reagents.WithNack`](@ref) has non-trivial effect only when used inside the
    choice combinator which possibly blocking branches.  Thus, to selectively
    trigger two branches in the choice combinator, we create two channels:
    =#
    s1, r1 = Reagents.channel()
    s2, r2 = Reagents.channel()
    #=
    To receive the negative acknowledgement, we craete one more channel:
    =#
    send_gotnack, receive_gotnack = Reagents.channel()
    #=
    The first branch `br1` (below) uses [`Reagents.WithNack`](@ref).  It passes
    the negative acknowledgement reagent `nack` to the user-defined function
    (the `do` block; it returns a reagent).  The reagent `nack` blocks until
    this branch `br1` is cancelled (i.e., another branch of `|` is chosen).
    =#
    br1 = WithNack() do nack
        @async (nack ⨟ Return(:gotnack) ⨟ send_gotnack)()
        return r1
    end
    #=
    We just use a channel endpoint for another branch:
    =#
    br2 = r2
    #=
    These two reagents are composed with the choice combinator `|`:
    =#
    choice = br1 | br2
    #=
    Returning the reagents so that they can be invoked differently for trying
    differnt scenarios:
    =#
    return (; choice, s1, s2, receive_gotnack)
end

# ### Scenario 1: `nack` is triggered

function test_nack_demo_1()
    (; choice, s2, receive_gotnack) = nack_demo()
    @sync begin
        #=
        Let us choose the second branch `br2` which does *not* include
        `WithNack`:
        =#
        @async s2(222)
        @test choice() == 222
    end
    #=
    Since the branch `br1` with `WithNack` is not chosen, we get the negative
    acknowledgement:
    =#
    @test receive_gotnack() == :gotnack
end

# ### Scenario 2: `nack` is not triggered

function test_nack_demo_2()
    (; choice, s1, receive_gotnack) = nack_demo()
    @sync begin
        #=
        This time, we choose the first branch `br1` which includes `WithNack`:
        =#
        @async s1(111)
        @test choice() == 111
    end
    #=
    Since we chose the `WithNack`'s branch, `nack` is not triggered this time:
    =#
    @test Reagents.try(receive_gotnack) === nothing
end

# ## Client-server pattern
#
# `WithNack` is useful for writing "client-server" pattern. As an example, we'll
# create an in-process "server" that issues unique IDs. That is to say, we'd
# like to have the following API:

function test_unique_id_provider_api()
    with_unique_id_provider() do unique_id
        @test unique_id() == 0
        @test unique_id() == 1
    end
end

# Here, `unique_id` is a reagent for communicating with a server created in
# `with_unique_id_provider`.
#
# ### `unique_id_provider!`
#
# Let us start from the event loop of the server.  The server listens to ID
# requests from `request_receive` and a shutdown request from
# `shutdown_receive`.

function unique_id_provider!(request_receive, shutdown_receive)
    #=
    It keeps the current available ID as its local variable:
    =#
    id = 0
    while true
        #=
        First, the server listens to both `request_receive` and
        `shutdown_receive`. The latter returns `nothing` upon shutdown request.
        =#
        receive_request_or_shutdown = request_receive | shutdown_receive
        #=
        When the `shutdown_receive` reagent is chosen (i.e., the reaction result
        is `nothing`), the short-circuting `@something` evaluates the `break`
        statement so that the server exits the loop:
        =#
        (; reply, abort) = @something(receive_request_or_shutdown(), break)
        #=
        The client (see below) sends `reply` and `abort` channel endpoints.  The
        server tries to send the ID with `Return(id) ⨟ reply` while also
        listening to the abort (NACK) and shutdown requests:
        =#
        try_reply = (
            (Return(id) ⨟ reply ⨟ Return(true)) |  # try sending the id
            (abort ⨟ Return(false)) |              # or wait for the abort (NACK)
            shutdown_receive                       # or wait for shutdown
        )
        #=
        The server only increments the ID when the client received the ID.
        =#
        if @something(try_reply(), break)
            id += 1
        end
    end  # while true
end  # function unique_id_provider!

# (For an ID server, this property is probably not required. But consider, e.g.,
# a lock server, where it is important to know that the client received the
# reply.)
#
# ### `with_unique_id_provider`
#
# The channels connecting the server and client are set up in the function
# below. The client API can be invoked inside the function `f` passed as the
# argument:

function with_unique_id_provider(f)
    request_send, request_receive = Reagents.channel()
    shutdown_send, shutdown_receive = Reagents.channel(Nothing)

    #=
    For each request, the client creates the channel (`reply`) for receiving the
    ID and also the negative acknowledgement reaagent `abort` for communicating
    that the request is aborted:
    =#
    unique_id = WithNack() do abort
        reply, receive = Reagents.channel(Int, Nothing)
        request_send((; reply, abort))
        return receive
    end

    #=
    Finally, we start the server in a task and execute the client's code `f`:
    =#
    @sync begin
        @async unique_id_provider!(request_receive, shutdown_receive)
        try
            f(unique_id)
        finally
            shutdown_send()
        end
    end
end

# ### Testing the ID server

function test_unique_id_provider()
    with_unique_id_provider() do unique_id
        #=
        When used alone, `unique_id` simply sends a request and wait for a
        reply from the ID server:
        =#
        @test unique_id() == 0
        @test unique_id() == 1

        #=
        Demonstrating the behavior of aborting the request is a bit more
        involved. First, we create a task that tries to send the "cancellation"
        request via a channel:
        =#
        send, receive = Reagents.channel(Nothing)
        canceller = @task send()
        yield(canceller)
        #=
        Since we don't know when `send()` will be invoked, we'll try it in a
        loop. The variable `prev` keeps track of the last `id` issued by the
        server:
        =#
        prev = unique_id()
        while true
            #=
            Then invoke `unique_id` and `receive` together. If this reaction
            takes choose the branch of `receive` ("cancellation"), it returns a
            `nothing`:
            =#
            ans = (unique_id | receive)()
            if ans === nothing
                #=
                Here, we have attempted to invoke the `unique_id` reagent but it
                was aborted by another reagent `receive`.  Since this triggers
                the nack reagent `abort`, this reaction did not update the
                server's state (the variable `id`). So, the next call to
                `unique_id` should increment the ID only by one:
                =#
                @test unique_id() == prev + 1
                break
                #=
                If `receive` was not tirggered, we keep the id `ans` so that it
                can be used in the next iteration:
                =#
            else
                prev = ans::Int
            end
        end
    end
end
