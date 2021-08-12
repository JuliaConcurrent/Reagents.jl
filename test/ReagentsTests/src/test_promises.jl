module TestPromises

using Base.Experimental: @sync
using Reagents
using Test

include("../../../examples/promises.jl")

function Base.show(io::IO, mime::MIME"text/plain", @nospecialize(p::Promise{T})) where {T}
    show(io, Promise)
    print(io, '{')
    show(io, T)
    print(io, '}')
    println(io, ":")
    print(io, "  value: ")
    show(IOContext(io, :typeinfo => typeof(p.value)), mime, p.value)
    println(io)
    print(io, "  send: ")
    show(io, mime, p.send)
    println(io)
    print(io, "  receive: ")
    show(io, mime, p.receive)
end

end  # module
