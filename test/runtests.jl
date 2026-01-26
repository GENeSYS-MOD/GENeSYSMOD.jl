using GENeSYS_MOD
using Test
using JuMP
using HiGHS
using Ipopt

solver = HiGHS.Optimizer

@testset "GENeSYS-MOD" begin
    include("test.jl")
    include("test_dispatch_simple.jl")
    include("test_dispatch_onenodestorage.jl")
    include("test_dispatch_twonodes.jl")
end
