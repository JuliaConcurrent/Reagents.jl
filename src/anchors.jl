"""
    anchor(key, [value = nothing])

Define a "manually steppable" point.
"""
anchor

use_anchors() = false

function enable_anchors()
    prev = use_anchors()
    @eval use_anchors() = true
    return prev
end

function disable_anchors()
    prev = use_anchors()
    @eval use_anchors() = false
    return prev
end

function anchor_impl(key, value)
    found = get(task_local_storage(), _ANCHOR_KEY, nothing)
    found === nothing && return
    task, on, enabled = found
    if enabled[] && task isa Task && on(key)
        yieldto(task, Some((key, value)))
    end
    return
end

function anchor(x, value = nothing)
    if use_anchors()
        anchor_impl(x, value)
    end
    return
end

struct AnchorError
    value::Any
end

struct AnchoredTask
    task::Task
    enabled::typeof(Ref(true))
end

always(_) = true

const _ANCHOR_KEY = :REAGENTS_ANCHOR_KEY

function withanchor(f, on = always)
    @nospecialize
    use_anchors() || error("anchors not enabled")
    enabled = Ref(true)
    parent = current_task()
    task = @task try
        task_local_storage(f, _ANCHOR_KEY, (parent, on, enabled))
    catch err
        enabled[] && yieldto(parent, AnchorError(err))
        rethrow()
    end
    return AnchoredTask(task, enabled)
end

function nextanchor!(a::AnchoredTask)
    a.enabled[] || error("`finish!(a)` already called")
    y = yieldto(a.task, nothing)
    if y isa Some
        return something(y)
    elseif y isa AnchorError
        schedule(a.task)
        wait(a.task)::Union{}
    else
        error("unexpected: $y")
    end
end

function finish!(a::AnchoredTask)
    a.enabled[] = false
    schedule(a.task)
    return fetch(a.task)
end
