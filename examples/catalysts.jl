# # [Catalysts](@id catalysts)
#
# A *catalyst* can be introduced by [`Reagents.dissolve`](@ref) for expressing a
# rule under which a certain set of reactions can happen.
#
# As a motivating example, consider writing a program with multiple channels:

function test_catalyst_idea()
    send1, receive1 = Reagents.channel(Int, Nothing)
    send2, receive2 = Reagents.channel(Char, Nothing)
    sendall, receiveall = Reagents.channel(Tuple{Int,Char}, Nothing)

    #=
    Suppose we want to combine the items from the first and the second channels
    into the third channel.  In principle, this can be expressed as a
    "background" task repeatedly executing such reaction (*"catalyst"*):
    =#
    background_task = @async begin
        catalyst = (receive1 & receive2) ⨟ sendall
        while true
            catalyst()
        end
    end

    #=
    The above `background_task` transfers the items that are available in
    `receive1` and `receive2` to to `sendall`.
    =#
    @sync begin
        @async send1(1)
        @async send2('a')
        @test receiveall() == (1, 'a')
    end

    #=
    Since the `background_task` keeps helping the reactions, we can invoke the
    same set of reactions multiple times:
    =#
    @sync begin
        @async send1(2)
        @async send2('b')
        @test receiveall() == (2, 'b')
    end
end

# (Aside: Note the use of **un**[structured
# concurrency](https://en.wikipedia.org/wiki/Structured_concurrency) for
# implementing the `background_task`.  The error happening inside of this task
# cannot be noticed at relevant locations.  This is another motivation for
# avoiding this style.)
#
# A downside of the approach above is that it invokes many context switches
# between tasks. For more efficient and direct style of expressing the idea, we
# can use [`Reagents.dissolve`](@ref).
#
# Let us re-implement the above example:

function test_zip2()
    send1, receive1 = Reagents.channel(Int, Nothing)
    send2, receive2 = Reagents.channel(Char, Nothing)
    sendall, receiveall = Reagents.channel(Tuple{Int,Char}, Nothing)

    #=
    If the items are aviable in `receive1` and `receive2`, the `catalyst`
    reagent automatically tries to pass them to `sendall`:
    =#
    catalyst = (receive1 & receive2) ⨟ sendall
    Reagents.dissolve(catalyst)

    #=
    Just like the `background_task`-based example above, the `catalyst` helps
    invoking the matched set of reactions:
    =#
    @sync begin
        @async send1(1)
        @async send2('a')
        @test receiveall() == (1, 'a')
    end

    #=
    Since the `catalyst` will not be "used up," we can invoke the same reaction
    multiple times:
    =#
    @sync begin
        @async send1(2)
        @async send2('b')
        @test receiveall() == (2, 'b')
    end
end
