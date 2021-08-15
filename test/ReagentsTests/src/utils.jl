module Utils

using Test

function with_log_on_error(f, name = f)
    try
        return f()
    catch err
        @error "Error from `$name`" exception = (err, catch_backtrace())
        rethrow()
    end
end

concurrently(functions...; kwargs...) = run_concurrently(collect(functions); kwargs...)

"""
    run_concurrently(thunks; [spawn = false])

Run `thunks` concurrently.
"""
function run_concurrently(functions::AbstractVector; spawn = false)
    tasks = Task[]
    Base.Experimental.@sync begin  # OK for testing
        for f in functions[1:end-1]
            t = if spawn
                Threads.@spawn with_log_on_error(f)
            else
                @async with_log_on_error(f)
            end
            push!(tasks, t)
        end
        global TASKS = tasks  # for debugging
        functions[end]()
    end
end

# This use of `schedule` is wrong but it's handy when debugging implementation
# of concurrent program that is wrong.
function cancel_tasks(tasks = TASKS)
    for t in tasks
        istaskdone(t) && continue
        schedule(t, ErrorException("!!! cancel !!!"); error = true)
    end
    return tasks
end

function random_sleep(spawn::Bool = true)
    if rand() < 0.1
        # no sleep
    elseif spawn && rand(Bool)
        nspins = rand(0:10000)
        for _ in 1:nspins
            GC.safepoint()
            ccall(:jl_cpu_pause, Cvoid, ())
        end
    else
        sleep(rand() / 1_000_000)
    end
end

macro spawn_named(name, spawn, ex = undef)
    if ex === undef
        ex = spawn
        spawn = true
    end
    quote
        if $spawn
            $Threads.@spawn $with_log_on_error($name) do
                $ex
            end
        else
            $Base.@async $with_log_on_error($name) do
                $ex
            end
        end
    end |> esc
end

macro test_error(expr)
    @gensym err tmp
    quote
        local $err = nothing
        $Test.@test try
            $expr
            false
        catch $tmp
            $err = $tmp
            true
        end
        $err
    end |> esc
end

const ⊏ = occursin

end  # module
