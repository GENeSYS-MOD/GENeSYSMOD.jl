cp(joinpath(pkgdir(GENeSYSMOD),"CondaPkg.toml"), joinpath(@__DIR__,"CondaPkg.toml"); force=true)
using CondaPkg

# Test for default parameters
if haskey(ENV, "GENESYSMOD_DATADIR")
    datadir = ENV["GENESYSMOD_DATADIR"]
else
    datadir = DATA_REPO_DIR
end

@testset "Fetch Specific Data Release" begin
    @testset "Default values" begin
        fetch_data_release(; dest_dir=TEST_RESULTS_DIR)
        files = readdir(TEST_RESULTS_DIR)
        @test sum([endswith(file,".xlsx") for file in files]) == 2
        @test sum([startswith(file,"RegularParameters") for file in files]) == 1
        @test sum([startswith(file,"Timeseries") for file in files]) == 1
    end
    @testset "Specific older version and dataset" begin
        fetch_data_release(;version_tag="v1.1.0", dataset_name="Europe_EnVis_Green", dest_dir=TEST_RESULTS_DIR)
        files = readdir(TEST_RESULTS_DIR)
        @test sum([startswith(file,"RegularParameters_Europe_EnVis_Green") for file in files]) == 1
        @test sum([startswith(file,"Timeseries_Europe_EnVis_Green") for file in files]) == 1
    end
end

@testset "Data Fetching and Processing" begin
    settings_file = joinpath(@__DIR__,"TestInputFetch","Set_filter_file.xlsx")

    @testset "Default Parameters" begin
        @test update_and_process_data(datadir=datadir)
    end

    # Test for custom result directory
    @testset "Custom Result Directory" begin
        resultdir = mktempdir()
        @test update_and_process_data(resultdir=resultdir,datadir=datadir)
        files = readdir(resultdir)
        @test sum([endswith(file,".xlsx") for file in files]) == 2
        @test sum([startswith(file,"RegularParameters") for file in files]) == 1
        @test sum([startswith(file,"Timeseries") for file in files]) == 1
    end

    # Test for custom settings file directory
    @testset "Custom Settings File" begin
        @test update_and_process_data(settings_file = realpath(settings_file), datadir=datadir)
    end # realpath makes an absolute path to the file from the relative path

    # Test for different processing option
    @testset "Different Processing Option" begin
        resultdir = mktempdir()
        @test update_and_process_data(resultdir=resultdir,processing_option="parameters_only",datadir=datadir)
        files = readdir(resultdir)
        @test sum([endswith(file,".xlsx") for file in files]) == 1
        @test sum([startswith(file,"RegularParameters") for file in files]) == 1
        @test sum([startswith(file,"Timeseries") for file in files]) == 0
        resultdir = mktempdir()
        @test update_and_process_data(resultdir=resultdir,processing_option="timeseries_only",datadir=datadir)
        files = readdir(resultdir)
        @test sum([endswith(file,".xlsx") for file in files]) == 1
        @test sum([startswith(file,"RegularParameters") for file in files]) == 0
        @test sum([startswith(file,"Timeseries") for file in files]) == 1
    end
end
rm(joinpath(@__DIR__,"CondaPkg.toml"))
