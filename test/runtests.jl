using GENeSYSMOD
using Test
using JuMP
using HiGHS
using Ipopt

solver = HiGHS.Optimizer

#const TEST_RESULTS_DIR = joinpath(pkgdir(GENeSYSMOD),"test","TestData","Results")
# path to the outputs of the tests
const TEST_RESULTS_DIR = joinpath(pkgdir(GENeSYSMOD),"test","TestData","Results")
# path to the GENeSYS-MOD.data repository (if not already specified in the GENESYSMOD_DATADIR environment variable)
# if you have this already cloned, add the path (e.g. joinpath(pkgdir(GENeSYSMOD),"test","TestData","Results") )
# if left blank, it will clone the GENeSYS-MOD.data repository to the main folder of GENeSYSMOD.jl
const DATA_REPO_DIR = nothing

macro track(name, expr)
    quote
        GC.gc()
        pre_rss = Sys.maxrss()
        stats = @timed $(esc(expr))
        post_rss = Sys.maxrss()
        @info $name time_s=round(stats.time, digits=2) alloc_MiB=round(stats.bytes/1024^2, digits=1) peak_rss_MiB=round(post_rss/1024^2, digits=1) rss_delta_MiB=round((post_rss-pre_rss)/1024^2, digits=1)
    end
end

@testset verbose=true "GENeSYS-MOD" begin
    @testset "Investment Run" begin
        @track "Investment Run" include("test.jl")
    end
    @testset verbose=true "Fetch Input Data" begin
        @track "Fetch Input Data" include("test_fetchdata.jl")
    end
    @testset verbose=true "Dispatch Runs" begin
        @testset "Simple Dispatch" begin
            @track "Simple Dispatch" include("test_dispatch_simple.jl")
        end
        @testset "One Node Storage Dispatch" begin
            @track "One Node Storage Dispatch" include("test_dispatch_onenodestorage.jl")
        end
        @testset "Two Nodes Dispatch" begin
            @track "Two Nodes Dispatch" include("test_dispatch_twonodes.jl")
        end
    end
end


#clean Results folder and subfolders of everything
for (root, dirs, files) in walkdir(TEST_RESULTS_DIR)
    for file in files
        rm(joinpath(root, file); force=true)
    end
end
