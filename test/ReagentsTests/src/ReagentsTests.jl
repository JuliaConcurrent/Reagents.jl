module ReagentsTests

include("utils.jl")
include("test_immutablelists.jl")
include("test_internal_bags.jl")
include("test_treiberstack.jl")
include("test_msqueue.jl")
include("test_hmlist.jl")
include("test_dualcontainers.jl")
include("test_channels.jl")
include("test_nack.jl")
include("test_cancellablecontainers.jl")
include("test_blocking.jl")
include("test_anchors.jl")
include("test_dissolve.jl")
include("test_locks.jl")
include("test_promises.jl")
include("test_doctest.jl")
include("test_aqua.jl")

end  # module ReagentsTests
