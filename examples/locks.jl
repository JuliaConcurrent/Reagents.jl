# # Locks
#
# We can quite easily implement various locks based on the [Blocking
# containers](@ref ex-blockingcontainers) we have implemented.

include("cancellablecontainers.jl")
using Reagents: PostCommit, dissolve

using ArgCheck: @argcheck

# ## Simple lock
#
# A simple (non-reentrant) lock can be created as a simple wrapper of a blocking
# container (e.g., a stack):

struct SimpleLock <: Base.AbstractLock
    access::typeof(Blocking(TreiberStack{Nothing}()))
end

# A lock is acquired by emptying the container so that subsequent attempts to
# acquire the lock will block until the element is put back into the container:

acquiring(l::SimpleLock) = taking(l.access)
realeasing(l::SimpleLock) = Return(nothing) ⨟ putting(l.access)

Base.lock(l::SimpleLock) = acquiring(l)()
Base.unlock(l::SimpleLock) = realeasing(l)()

# Thus, when creating a lock with an empty container, it is in the locked state.
# We need to unlock it (i.e., put one element in the container) before start
# using the lock:

function SimpleLock()
    l = SimpleLock(Blocking(TreiberStack{Nothing}()))
    unlock(l)  # start with unlocked state
    return l
end

# Here's how it works:

function test_simplelock()
    l = SimpleLock()
    send, receive = Reagents.channel()
    @sync begin
        child_locked = Threads.Atomic{Bool}(false)
        child_unlocked = Threads.Atomic{Bool}(false)
        lock(l) do
            #=
            While the lock is acquired, the child task cannot lock it:
            =#
            Threads.@spawn begin
                send(:child_started)
                lock(l) do
                    child_locked[] = true
                    send(:child_locked)
                end
                child_unlocked[] = true
                send(:child_unlocked)
            end
            @test receive() === :child_started
            @test !child_locked[]
        end  # lock(l) do
        #=
        After unlocking the lock in the parent task, the child task can acquire
        the lock:
        =#
        @test receive() === :child_locked
        @test child_locked[]
        @test receive() === :child_unlocked
        @test child_unlocked[]
    end
end

# ### Locking with a timeout
#
# Since `SimpleLock` exposes the reagent API, it can be composed with other
# reagents. For example, it is straightforward to add timeout to the lock:

function timeout(seconds::Real)
    send, receive = Reagents.channel(Nothing)
    @async begin
        sleep(seconds)
        send(nothing)
    end
    return receive
end

function try_with_timeout(reagent, seconds::Real)
    reagent = (reagent ⨟ Map(Some)) | timeout(seconds)
    return reagent()
end

# Calling `try_with_timeout(reagent, seconds)` execute `reagent` with the
# timeout `seconds`. It returns `nothing` on timeout. If `reagent` completes its
# reaction with the output `value`, `try_with_timeout` returns `Some(value)`.
# It can be used with arbitrary reagent, including `acquiring(::SimpleLock)`:

function test_simplelock_timeout()
    l = SimpleLock()
    #=
    If the lock is not acquired already, adding timeout does nothing:
    =#
    a1 = try_with_timeout(acquiring(l), 0.1)
    @test a1 isa Some  # successfully acquire
    #=
    If the lock is already acquired, `try_with_timeout` will fail after the
    timeout:
    =#
    a2 = fetch(@async try_with_timeout(acquiring(l), 0.1))
    @test a2 === nothing  # failed to acquire
end

# ### Trying to acquire multiple locks
#
# `SimpleLock` can also be composed with itself. For example, we can use the
# choice combinator [`|`](@ref Reagents.:|) to acquire an available lock:

function test_simplelock_multiple()
    l1 = SimpleLock()
    l2 = SimpleLock()
    #=
    Let us lock `l1` first, so that subsequent lock cannot acquire it:
    =#
    lock(l1) do
        local ans
        @sync begin
            Threads.@spawn begin
                #=
                Since we need to change the action depending on which lock is
                acquired (importantly, which one to unlock), we use
                [`Reagents.Return`](@ref) to associate different returned value
                for each branch of the `|` combinator:
                =#
                ans = (
                    (acquiring(l1) ⨟ Return(1)) |  # try lock l1; will fail
                    (acquiring(l2) ⨟ Return(2))    # try lock l2; will succeeds
                )()
                #=
                Since `l1` is already acquired, we should have `ans == 2` here
                (checked below). But first, let's unlock the corresponding lock:
                =#
                if ans == 1  # unreachable, but demonstrating the generic usage
                    unlock(l1)
                elseif ans == 2
                    unlock(l2)
                end
            end
        end
        #=
        As mentioned above, we expect that `l2` was acquired in the child task:
        =#
        @test ans == 2
    end
end

# Remembering which lock to unlock is rather cumbersome. Let us wrap it in an
# interface that can be used with the `do`-block syntax:

function lockany(f, pairs...)
    acquired, value = mapfoldl(lv -> acquiring(first(lv)) ⨟ Return(lv), |, pairs)()
    try
        f(value)
    finally
        unlock(acquired)
    end
end

# The above code can now be expressed more succinctly:

function test_simplelock_lockany()
    l1 = SimpleLock()
    l2 = SimpleLock()
    local ans
    lock(l1) do
        @sync begin
            Threads.@spawn begin
                lockany(l1 => 1, l2 => 2) do x
                    ans = x
                end
            end
        end
    end
    @test ans == 2
end

# Note: `SimpleLock` and `SimpleSemaphore` are inspired by Turon & Russo (2011).

# ## Semaphore
#
# `SimpleLock` can be extended to a semaphore by just initially fillying more
# than one elements:

struct SimpleSemaphore
    accesses::typeof(Blocking(TreiberStack{Nothing}()))
end

function SimpleSemaphore(n::Integer)
    @argcheck n > 0
    accesses = Blocking(TreiberStack{Nothing}())
    for _ in 1:n
        put!(accesses, nothing)
    end
    return SimpleSemaphore(accesses)
end

acquiring(l::SimpleSemaphore) = taking(l.accesses)
realeasing(l::SimpleSemaphore) = Return(nothing) ⨟ putting(l.accesses)

Base.acquire(l::SimpleSemaphore) = acquiring(l)()
Base.release(l::SimpleSemaphore) = realeasing(l)()

# Unlike `SimpleLock`, we can acquire `SimpleSemaphore(n)` `n` times before
# blocked:

function test_simplesemaphore()
    sem = SimpleSemaphore(2)
    Base.acquire(sem)
    Base.acquire(sem)
    t = @task Base.acquire(sem)
    yield(t)
    @test !istaskdone(t)
    Base.release(sem)
    wait(t)
end

# ## Reader-writer lock
#
# This example is from Turon & Russo (2011) “Scalable Join Patterns.”  As
# mentioned in Turon (2012), the join pattern can be expressed with
# [catalysts](@ref catalysts).
#
# Their reader-writer lock is acquired and released by sending messages to a
# channel. Let us define a simple wrapper type to express this:

struct ChLock <: Base.AbstractLock
    acq::typeof(Reagents.channel(Nothing)[1])
    rel::typeof(Reagents.channel(Nothing)[1])
end

acquiring(l::ChLock) = l.acq
realeasing(l::ChLock) = l.rel

Base.lock(l::ChLock) = acquiring(l)()
Base.unlock(l::ChLock) = realeasing(l)()

# To create two kinds of locks, we create `2 * 2 = 4` channels.  The state of
# the lock is mantained by two blocking data structures (Note: We only need to
# store at most one element. So, a stack is an overkill.  But that's the most
# cheap data structure we have implemented so far in the tutorial):

function reader_writer_lock()
    idle = Blocking(TreiberStack{Nothing}())
    shared = Blocking(TreiberStack{Int}())
    acqr = Reagents.channel(Nothing)
    acqw = Reagents.channel(Nothing)
    relr = Reagents.channel(Nothing)
    relw = Reagents.channel(Nothing)
    dissolve(acqr[2] ⨟ taking(idle) ⨟ PostCommit(_ -> put!(shared, 1)))
    dissolve(acqr[2] ⨟ taking(shared) ⨟ PostCommit(n -> put!(shared, n + 1)))
    dissolve(relr[2] ⨟ taking(shared) ⨟ PostCommit() do n
        if n == 1
            put!(idle, nothing)
        else
            put!(shared, n - 1)
        end
    end)
    dissolve(acqw[2] ⨟ taking(idle))
    dissolve(relw[2] ⨟ PostCommit(_ -> put!(idle, nothing)))
    put!(idle, nothing)
    return ChLock(acqr[1], relr[1]), ChLock(acqw[1], relw[1])
end

# Observe that how the states of the lock are implemented:
#
# * When the reader-writer lock is not acquired, `idle` has a single element.
#   `shared` is empty.
# * When at least one of the reader (shared) lock is acquired, the number of
#   acquired locks are stored in the `shared` container. The `idle` container is
#   empty.
# * When the writer (exclusive) lock is acquired, both the `shared` and `idle`
#   container is empty.
#
# As discussed in [catalysts](@ref catalysts), [`Reagents.dissolve`](@ref) is
# used for expressing the rules that expressing allowed transitions between
# these states.
#
# Here's how it works:

function test_reader_writer_lock()
    s1, r1 = Reagents.channel()
    s2, r2 = Reagents.channel()
    rlock, wlock = reader_writer_lock()
    @sync begin
        #=
        Reader lock can be acquired multiple times:
        =#
        Threads.@spawn begin
            lock(rlock) do
                s1(1)
                s2(:done)
            end
        end
        Threads.@spawn begin
            lock(rlock) do
                s1(2)
                s2(:done)
            end
        end
        @test sort!([r1(), r1()]) == [1, 2]

        #=
        While the reader lock is aquired, the writer lock cannot be acquired:
        =#
        wlocked = Threads.Atomic{Bool}(false)
        Threads.@spawn begin
            lock(wlock) do
                wlocked[] = true
                s1(3)
                s2(:done)
            end
        end
        for _ in 1:3
            sleep(0.1)
            @test !wlocked[]
        end
        @test r2() === r2() === :done  # releaseing `rlock`
        @test r1() == 3
        @test wlocked[]

        #=
        While the writer lock is aquired, the reader lock cannot be acquired:
        =#
        r4locked = Threads.Atomic{Bool}(false)
        r5locked = Threads.Atomic{Bool}(false)
        Threads.@spawn begin
            lock(rlock) do
                r4locked[] = true
                s1(4)
                s2(:done)
            end
        end
        Threads.@spawn begin
            lock(rlock) do
                r5locked[] = true
                s1(5)
                s2(:done)
            end
        end
        for _ in 1:3
            sleep(0.1)
            @test r4locked[] == r5locked[] == false
        end
        @test r2() === :done  # releaseing `wlock`
        @test sort!([r1(), r1()]) == [4, 5]
        @test r4locked[] == r5locked[] == true
        @test r2() === r2() === :done  # releaseing `rlock`
    end
end

# ## References
#
# * Turon, Aaron. “Reagents: Expressing and Composing Fine-Grained Concurrency.”
#   In Proceedings of the 33rd ACM SIGPLAN Conference on Programming Language
#   Design and Implementation, 157–168. PLDI ’12. New York, NY, USA: Association
#   for Computing Machinery, 2012. <https://doi.org/10.1145/2254064.2254084>.
#
# * Turon, Aaron J., and Claudio V. Russo. “Scalable Join Patterns.” In
#   Proceedings of the 2011 ACM International Conference on Object Oriented
#   Programming Systems Languages and Applications, 575–594. OOPSLA ’11. New
#   York, NY, USA: Association for Computing Machinery, 2011.
#   <https://doi.org/10.1145/2048066.2048111>.
