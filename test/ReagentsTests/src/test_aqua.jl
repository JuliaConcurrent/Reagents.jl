module TestAqua

using Aqua
using Reagents

test() = Aqua.test_all(Reagents; unbound_args = false)

end  # module
