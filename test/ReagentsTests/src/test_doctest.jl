module TestDoctest

using Documenter
using Reagents

test() = doctest(Reagents; manual = false)

end  # module
