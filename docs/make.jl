using Documenter
using Literate
using Markdown
using Reagents

_BANNER_TEXT_ = """
!!! note
    Reagents.jl is still work-in-progress.
"""

_BANNER_ = Markdown.parse(_BANNER_TEXT_)

PAGES = [
    "index.md",
    "Tutorials" => [
        "Treiber stack" => "tutorials/treiberstack.md",
        "Michael and Scott queue" => "tutorials/msqueue.md",
        "Cancellable containers" => "tutorials/cancellablecontainers.md",
        "Catalysts" => "tutorials/catalysts.md",
        "Locks" => "tutorials/locks.md",
        "Negative acknowledgement (NACK)" => "tutorials/nack.md",
        "Promises and Futures" => "tutorials/promises.md",
    ],
    # "How-to guides" => [
    #     "" => "howto/.md",
    # ],
    "Reference" => [
        "API" => "reference/api.md",
        # ...
    ],
    # "Explanation" => [
    #     "Dual data structures" => "explanation/dualcontainers.md",
    # ],
]

function preprocess_example(str)
    output = IOBuffer()

    for ln in eachline(IOBuffer(_BANNER_TEXT_); keep = true)
        print(output, "# ", ln)
    end
    print(output, "\n")

    input = IOBuffer(str)
    while !eof(input)
        ln = readline(input; keep = true)

        # Always treat indented comments as in-code comments
        m = match(r"^( +)# (.*)"s, ln)
        if m !== nothing
            print(output, m[1], "## ", m[2])
            continue
        end

        # De-indent multi-line comments
        m = match(r"^( +)#=\s*$"s, ln)
        if m !== nothing
            nindent = length(m[1])
            print(output, "#=\n")
            while !eof(input)
                ln = readline(input; keep = true)
                m = match(r"^( +)=#\s*$"s, ln)
                if m !== nothing
                    print(output, "=#\n")
                    break
                end
                m = match(Regex("^ {0,$(nindent)}(.*)\$", "s"), ln)
                if m !== nothing
                    print(output, m[1])
                    continue
                end
                print(output, ln)
            end
            continue
        end

        print(output, ln)
    end
    return String(take!(output))
end

let example_dir = joinpath(dirname(@__DIR__), "examples")
    examples = Pair{String,String}[]

    for subpages in PAGES
        subpages isa Pair || continue
        for (_, mdpath) in subpages[2]::Vector
            stem, _ = splitext(basename(mdpath))
            jlpath = joinpath(example_dir, "$stem.jl")
            if !isfile(jlpath)
                @debug "`$jlpath` does not exist. Skipping..."
                continue
            end
            push!(examples, jlpath => joinpath(@__DIR__, "src", dirname(mdpath)))
        end
    end

    @info "Compiling example files" examples
    for (jlpath, dest) in examples
        Literate.markdown(
            jlpath,
            dest;
            preprocess = preprocess_example,
            codefence = "````julia" => "````",
        )
        # Note: Not using Documenter's `@example` since these examples do not
        # have outputs and they are tested via `test/runtests.jl`.
    end
end

makedocs(
    sitename = "Reagents",
    format = Documenter.HTML(),
    modules = [Reagents],
    pages = PAGES,
    doctest = false,  # tested via test/runtests.jl
    checkdocs = :exports,  # ignore complains about `Reagents.:*`
    strict = lowercase(get(ENV, "CI", "false")) == "true",
    # See: https://juliadocs.github.io/Documenter.jl/stable/lib/public/#Documenter.makedocs
)

deploydocs(
    repo = "github.com/tkf/Reagents.jl",
    push_preview = true,
    # See: https://juliadocs.github.io/Documenter.jl/stable/lib/public/#Documenter.deploydocs
)
