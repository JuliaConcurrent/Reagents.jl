function transform_docstring(doc::AbstractString, label)
    output = IOBuffer()
    input = IOBuffer(doc)
    while !eof(input)
        ln = readline(input)
        if startswith(ln, "```julia")
            print(output, "```jldoctest ", label, "\n")
            isrepl = false
            while !eof(input)
                ln = readline(input)
                if startswith(ln, "```")
                    if !isrepl
                        print(
                            output,
                            """
                            nothing
                            # output
                            """,
                        )
                    end
                    print(output, ln, "\n")
                    break
                end
                print(output, ln, "\n")
                if startswith(ln, "julia> ")
                    isrepl = true
                end
            end
        else
            print(output, ln, "\n")
        end
    end
    return String(take!(output))
end

function define_docstrings()
    docstrings = [:Reagents => joinpath(dirname(@__DIR__), "README.md")]
    docsdir = joinpath(@__DIR__, "docs")
    for filename in readdir(docsdir)
        stem, ext = splitext(filename)
        ext == ".md" || continue
        name = Symbol(stem)
        name in names(Reagents, all = true) || continue
        push!(docstrings, name => joinpath(docsdir, filename))
    end
    n_auto_labels = 0
    for (name, path) in docstrings
        label = string(name)
        if match(r"^[a-z0-9_]+$"i, label) === nothing
            label = "reagent$n_auto_labels"
            n_auto_labels += 1
        end

        include_dependency(path)
        doc = read(path, String)
        doc = transform_docstring(doc, label)
        ex = :($Base.@doc $doc $name)
        ex.args[2]::LineNumberNode
        ex.args[2] = LineNumberNode(1, Symbol(path))
        Base.eval(Reagents, ex)
    end
end
