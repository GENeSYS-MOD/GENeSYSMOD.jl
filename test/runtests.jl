using GENeSYSMOD
using Test
using JuMP
using HiGHS
using Ipopt

solver = HiGHS.Optimizer

const TEST_RESULTS_DIR = joinpath(pkgdir(GENeSYSMOD),"test","TestData","Results")

@testset "GENeSYS-MOD" begin
    @testset "Investment Run" begin
        include("test.jl")
    end
    @testset "Fetch Input Data" begin
        include("test_fetchdata.jl")
    end
    @testset "Dispatch Runs" begin
        @testset "Simple Dispatch" begin
            include("test_dispatch_simple.jl")
        end
        @testset "One Node Storage Dispatch" begin
            include("test_dispatch_onenodestorage.jl")
        end
        @testset "Two Nodes Dispatch" begin
            include("test_dispatch_twonodes.jl")
        end
    end
end

#clean Results folder and subfolders of everything
for (root, dirs, files) in walkdir(TEST_RESULTS_DIR)
    for file in files
        rm(joinpath(root, file))
    end
end
