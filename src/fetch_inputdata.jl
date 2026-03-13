"""
    update_and_process_data(; settings_file=nothing, scenario_option="Europe_EnVis_Green",
                            datadir=nothing, resultdir=nothing, output_format="long", processing_option="both")
Fetches the latest changes from the GENeSYS_MOD.data repository, merges them, and processes the data using a Python function.
# Arguments
- `settings_file::Union{String, Nothing}`: Absolute path to the settings file. If `nothing`, defaults to "Set_filter_file.xlsx" in the current directory.
- `scenario_option::String`: Scenario option for the processing function. Default is "Europe_EnVis_Green".
- `datadir::Union{String, Nothing}`: Directory of the data repository. If `nothing`, defaults to "GENeSYS_MOD.data" in the current directory.
- `resultdir::Union{String, Nothing}`: Directory to save the output files. If `nothing`, the files are not moved and can be found in GENeSYS_MOD.data/Output.
- `output_format::String`: Format of the output data, "long" or "wide". Default is "long".
- `processing_option::String`: Specifies what data to process. Options are "parameters_only", "timeseries_only", or "both". Default is "both".
- `debugging_output::Bool`: Specifies if there should be more information in case of a code error. Default is `false`.
- `data_base_region::String`: Specifies the base region using a country code. If values are missing in other regions, the base region's values will be used as fallback. Default is "DE".
# Returns
- `result::Bool`: `true` if the process completes successfully.
# Description
1. Fetches the latest changes from the `GENeSYS_MOD.data` repository.
2. Attempts to merge the changes up to 3 times.
3. Calls the Python `master_function` to process the data.
4. Moves the output files to the specified `resultdir` if provided and based on the `processing_option`.
5. Returns `true` if the process completes successfully.
# Example
```julia
result = update_and_process_data(settings_file="path/to/Set_filter_file.xlsx", scenario_option="Test_Scenario",
                                 datadir="path/to/data", resultdir="path/to/save", output_format="wide",
                                 processing_option="parameters_only")
```
"""
function update_and_process_data(;settings_file = nothing, scenario_option = "Europe_EnVis_Green",
     datadir = nothing, resultdir = nothing, output_format = "long", processing_option = "both", debugging_output = false, data_base_region = "DE")
    # Pull latest changes
    if isnothing(datadir)
        start_dir = pwd()
        repo_dir = joinpath(@__DIR__,"..","..","GENeSYS_MOD.data")
        cd(repo_dir)
        println("Using present data directory")
    else
        start_dir = datadir
        repo_dir = start_dir
        cd(start_dir)
        println("Using data directory: $datadir")
    end

    repo = LibGit2.GitRepo(repo_dir)
    println("Fetch Successful")
    LibGit2.fetch(repo)
    limit = 3
    for i in 1:limit
        try
            LibGit2.merge!(repo)
            println("Merge Successful")
            break
        catch e
            if i != limit
                println("Retrying... ($i/$limit)")
                sleep(3)
            else
                println(e)
                println("Merge Failed! Continuing without merging.")
            end
        end
    end

    # Call Python processing function
    @pyexec """
import sys
import os
from pathlib import Path
import subprocess

cwd = Path(os.getcwd())
script_path = str(cwd/'Conversion Script')
if script_path not in sys.path:
    sys.path.append(script_path)
from functions.function_import import master_function
"""
    cd(joinpath(pwd(), "Conversion Script"))
    master_function = PythonCall.pyimport("functions.function_import").master_function

    output_file_format = "excel"
    if isnothing(settings_file)
        settings_file = joinpath(pwd(),"Set_filter_file.xlsx")
    end

    result = master_function(settings_file,output_file_format, output_format, processing_option, scenario_option, debugging_output, data_base_region)

    _time = Dates.format(now(), "dd_mm_yyyy_THHMM")
    if !isnothing(resultdir)
        if processing_option ∈ ["parameters_only", "both"]
            mv(joinpath("..","Output","output_excel","RegularParameters_$scenario_option.xlsx"),
            joinpath(resultdir,"RegularParameters_$(scenario_option)_$(_time).xlsx"))
        end
        if processing_option ∈ ["timeseries_only", "both"]
            mv(joinpath("..","Output","output_excel","Timeseries_$scenario_option.xlsx"),
            joinpath(resultdir,"Timeseries_$(scenario_option)_$(_time).xlsx"))
        end
    end

    cd(start_dir)
    return true
end

"""
    fetch_data_release(; version_tag::String="latest", dataset_name::String="MiddleEarth", dest_dir::AbstractString=pwd())

Download GENeSYS-MOD input data files from a GitHub release of the data repository.

# Arguments
- `version_tag::String`: The version tag of the data release to download. Defaults to "latest", which uses `LATEST_DATA_VERSION`.
- `dataset_name::String`: The name of the dataset to download. Defaults to "MiddleEarth".
- `dest_dir::AbstractString`: The destination directory where the files will be saved. Defaults to the current working directory.

# Downloads
- `RegularParameters_<dataset_name>.xlsx`: Regular parameters file for the specified dataset
- `Timeseries_<dataset_name>.xlsx`: Timeseries data file for the specified dataset

# Errors
Throws an error if either file fails to download, including the URL and error details.

# Examples
```julia
fetch_data_release(version_tag="v1.0.5", dataset_name="Europe_EnVis_Green", dest_dir="path/to/save")
```
"""
function fetch_data_release(;version_tag::String="latest", dataset_name::String="MiddleEarth", dest_dir::AbstractString=pwd())
    if version_tag == "latest"
        version_tag = LATEST_DATA_VERSION
    end

    regpar_file_url = "https://github.com/GENeSYS-MOD/GENeSYS_MOD.data/releases/download/$version_tag/RegularParameters_$dataset_name.xlsx"
    timeserie_file_url = "https://github.com/GENeSYS-MOD/GENeSYS_MOD.data/releases/download/$version_tag/Timeseries_$dataset_name.xlsx"

    try
        Downloads.download(regpar_file_url, joinpath(dest_dir, "RegularParameters_$dataset_name.xlsx"))
    catch e
        error("Failed to download Regular Parameters file from $regpar_file_url. Error: $e")
    end
    try
        Downloads.download(timeserie_file_url, joinpath(dest_dir, "Timeseries_$dataset_name.xlsx"))
    catch e
        error("Failed to download Timeseries file from $timeserie_file_url. Error: $e")
    end

end
