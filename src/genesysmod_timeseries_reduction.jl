# GENeSYS-MOD v3.1 [Global Energy System Model]  ~ March 2022
#
# #############################################################
#
# Copyright 2020 Technische Universität Berlin and DIW Berlin
#
# Licensed under the Apache License, Version 2.0 (the "License")
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# #############################################################

"""
Internal function used in the run process after reading the input data to reduce the hourly
timeseries for the whole year to a given number of timeslices. The algorithm maintain the max
and min value and also fit the new timeserie to minimise deviation from the mean of the original timeseire.
"""
function create_daa_hourly(in_data, tab_name, els...)
    df = DataFrame(XLSX.gettable(in_data[tab_name]))
    long_df = stack(df,3:ncol(df)) # 3 because data starts at column 3, 1 is the hours and 2 is the timeslice

    select!(long_df, Not(:TIMESLICE)) #remove the timeslice column

    A = JuMP.Containers.DenseAxisArray(
        zeros(length.(els)...), els...)
    # Fill in values from Excel
    for r in eachrow(long_df)
        try
            A[r[1:end-1]...] = r.value 
        catch err
            @debug err
        end
    end
    return A
end

"""

"""
function create_df_hourly(in_data, tab_name)
    df = DataFrame(XLSX.gettable(in_data[tab_name]))
    long_df = stack(df,3:ncol(df)) # 3 because data starts at column 3, 1 is the hours and 2 is the timeslice

    select!(long_df, Not(:TIMESLICE)) #remove the timeslice column

    return long_df
end

"""

"""
function timeseries_reduction(Sets, TagTechnologyToSubsets, Switch, SpecifiedAnnualDemand)
    starttime = Dates.now()
    switch_dunkelflaute = Switch.elmod_dunkelflaute

    keys_mapping = Dict(
        "Power" => "LOAD",
        "RES_PV_Utility_Avg" => "PV_AVG",
        "RES_PV_Utility_Inf" => "PV_INF",
        "RES_PV_Utility_Opt" => "PV_OPT",
        "RES_PV_Utility_Tracking" => "PV_TRA",
        "RES_Wind_Onshore_Avg" => "WIND_ONSHORE_AVG",
        "RES_Wind_Onshore_Inf" => "WIND_ONSHORE_INF",
        "RES_Wind_Onshore_Opt" => "WIND_ONSHORE_OPT",
        "RES_Wind_Offshore_Transitional" => "WIND_OFFSHORE",
        "RES_Wind_Offshore_Deep" => "WIND_OFFSHORE_DEEP",
        "RES_Wind_Offshore_Shallow" => "WIND_OFFSHORE_SHALLOW",
        "Heat_Low_Residential" => "HEAT_LOW",
        "HLR_Heatpump_Aerial" => "HP_AIRSOURCE",
        "HLR_Heatpump_Ground" => "HP_GROUNDSOURCE",
        "Mobility_Passenger" => "MOBILITY_PSNG",
        "RES_Hydro_Small" => "HYDRO_ROR",
        "Heat_High_Industrial" => "HEAT_HIGH",
    )

    Country_Data_Entries= [keys_mapping[k] for k ∈ intersect(keys(keys_mapping), union(Sets.Fuel, Sets.Technology))]

    sector_to_tech = Dict(
        "Industry"=>"HEAT_HIGH",
        "Buildings"=>"HEAT_LOW",
        "Transportation"=>"MOBILITY_PSNG",
        "Power"=>"LOAD")

    hourly_data = XLSX.readxlsx(joinpath(Switch.inputdir, Switch.hourly_data_file * ".xlsx"))

    CountryData = Dict()
    for v ∈ Country_Data_Entries
        CountryData[v] = DataFrame(XLSX.gettable(hourly_data["TS_" * v]))
        select!(CountryData[v], Not([:HOUR]))
        select!(CountryData[v], Sets.Region_full)
    end

    Dunkelflaute = Dict(x => mapcols(col -> col*0.0, CountryData[x]) for x ∈ Country_Data_Entries)
    SmoothedCountryData = Dict(x => mapcols(col -> col*0.0, CountryData[x]) for x ∈ Country_Data_Entries)
    ScaledCountryData = Dict(x => mapcols(col -> col*0.0, CountryData[x]) for x ∈ Country_Data_Entries)
    AverageCapacityFactor = Dict(x => mapcols(col -> 0.0, CountryData[x]) for x ∈ Country_Data_Entries)

    x_averageTimeSeriesValue = Dict()
    for cde ∈ Country_Data_Entries
        x_averageTimeSeriesValue[cde] = combine(CountryData[cde], names(CountryData[cde]) .=> DataFrames.mean, renamecols=false)
    end

    df_peakingDemand = Dict()
    x_peakingDemand = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full), length(Sets.Sector)),Sets.Region_full, Sets.Sector)

    for s ∈ intersect(Sets.Sector,keys(sector_to_tech)), r ∈ Sets.Region_full
        df_peakingDemand[s] = combine(CountryData[sector_to_tech[s]], names(CountryData[sector_to_tech[s]]) .=> maximum, renamecols=false) ./ x_averageTimeSeriesValue[sector_to_tech[s]]
        x_peakingDemand[r,s] = df_peakingDemand[s][1,r]
    end

    Timeslice_full = 1:8760
    switch_dunkelflaute = 0

    if Switch.switch_dispatch == 1
        Timeslice = 1:8760
        elmod_nthhour = 1
    else
        elmod_nthhour = floor(Int, (8760/(Switch.elmod_nthhour*24)))
        lenth_must = Switch.elmod_nthhour * 24
        Timeslice = [x for x in Timeslice_full if (x-Switch.elmod_starthour)%(elmod_nthhour) == 0][1:lenth_must]
    end


    
    # check if nan value otherwise increase resolution by 1
    k=-1
    j = true
    while j == true
        k+=1
        ScaledCountryData = time_series_optimization(Sets, TagTechnologyToSubsets, Switch, SpecifiedAnnualDemand, k,CountryData, Country_Data_Entries,x_peakingDemand,Dunkelflaute,SmoothedCountryData,ScaledCountryData,AverageCapacityFactor)
        j = false 
        for cde ∈ Country_Data_Entries, r ∈ Sets.Region_full 
            if sum(SmoothedCountryData[cde][:,r]) == 0
                j = true
                break
            end
        end                      
    end


    YearSplit = JuMP.Containers.DenseAxisArray(ones(length(Timeslice), length(Sets.Year)) * 1/length(Timeslice), Timeslice, Sets.Year)

    sdp_list=intersect(Sets.Fuel, ["Power","Mobility_Passenger","Mobility_Freight","Heat_Low_Residential","Heat_Low_Industrial","Heat_Medium_Industrial","Heat_High_Industrial"])
    capf_list=intersect(Sets.Technology, ["HLR_Heatpump_Aerial","HLR_Heatpump_Ground","RES_PV_Utility_Opt","RES_Wind_Onshore_Opt","RES_Wind_Offshore_Transitional","RES_Wind_Onshore_Avg","RES_Wind_Offshore_Shallow","RES_PV_Utility_Inf",
    "RES_Wind_Onshore_Inf","RES_Wind_Offshore_Deep","RES_PV_Utility_Tracking","RES_Hydro_Small", "RES_PV_Utility_Avg"])
    SpecifiedDemandProfile = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full), length(Sets.Fuel), length(Timeslice), length(Sets.Year)), Sets.Region_full, Sets.Fuel, Timeslice, Sets.Year)
    CapacityFactor = JuMP.Containers.DenseAxisArray(ones(length(Sets.Region_full), length(Sets.Technology), length(Timeslice), length(Sets.Year)), Sets.Region_full, Sets.Technology, Timeslice, Sets.Year)

    tmp = ScaledCountryData["LOAD"] ./ length(Timeslice)
    for r ∈ Sets.Region_full
        for f ∈ Sets.Fuel
            if sum(SpecifiedAnnualDemand[r,f,:]) != 0
                SpecifiedDemandProfile[r,f,:,Sets.Year[1]] = tmp[Timeslice,r]
            end
        end
    end

    tmp=Dict()
    for t ∈ intersect(Country_Data_Entries, ["MOBILITY_PSNG", "HEAT_LOW", "HEAT_HIGH"])
        println(combine(ScaledCountryData[t], names(ScaledCountryData[t]) .=> sum, renamecols=false))
        tmp[t] = ScaledCountryData[t] ./ combine(ScaledCountryData[t], names(ScaledCountryData[t]) .=> sum, renamecols=false)
    end

    for r ∈ Sets.Region_full, (k,v) ∈ Dict("Mobility_Passenger" => "MOBILITY_PSNG", "Mobility_Freight" => "MOBILITY_PSNG", "Heat_Low_Residential" => "HEAT_LOW", "Heat_Low_Industrial"=>"HEAT_HIGH", "Heat_Medium_Industrial"=>"HEAT_HIGH","Heat_High_Industrial"=>"HEAT_HIGH") 
        if k ∈ sdp_list
            SpecifiedDemandProfile[r,k,:,Sets.Year[1]] = tmp[v][Timeslice,r]
            for l ∈ Timeslice
                if isnan(SpecifiedDemandProfile[r,k,l,Sets.Year[1]])
                    println(k,r,v)
                end
            end
        end
    end

    for r ∈ Sets.Region_full for f ∈ Sets.Fuel for y ∈ Sets.Year[2:end]
        SpecifiedDemandProfile[r,f,:,y] = SpecifiedDemandProfile[r,f,:,Sets.Year[1]]
    end end end
    
    TimeDepEfficiency = JuMP.Containers.DenseAxisArray(ones(length(Sets.Region_full), length(Sets.Technology), length(Sets.Timeslice), length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Timeslice, Sets.Year)

    for y ∈ Sets.Year
        for t ∈ intersect(Sets.Technology, TagTechnologyToSubsets["Solar"])
            CapacityFactor[:,t,:,y] .= 0
        end
        for t ∈ intersect(Sets.Technology, TagTechnologyToSubsets["Wind"])
            CapacityFactor[:,t,:,y] .= 0
        end
        for r ∈ Sets.Region_full 
            if length(Timeslice) < 8760
                if "HLR_Heatpump_Aerial" ∈ capf_list
                    CapacityFactor[r,"HLR_Heatpump_Aerial",:,y] .= 1
                    TimeDepEfficiency[r,"HLR_Heatpump_Aerial",:,y] = ScaledCountryData["HP_AIRSOURCE"][Timeslice,r]
                end
                if "HLR_Heatpump_Ground" ∈ capf_list
                    CapacityFactor[r,"HLR_Heatpump_Ground",:,y] .= 1
                    TimeDepEfficiency[r,"HLR_Heatpump_Ground",:,y] = ScaledCountryData["HP_GROUNDSOURCE"][Timeslice,r]
                end

                for t ∈ setdiff(capf_list, ["HLR_Heatpump_Aerial", "HLR_Heatpump_Ground"])
                    CapacityFactor[r,t,:,y] = ScaledCountryData[keys_mapping[t]][Timeslice,r]
                end
            else
                if "HLR_Heatpump_Aerial" ∈ capf_list
                    CapacityFactor[r,"HLR_Heatpump_Aerial",:,y] = CountryData["HP_AIRSOURCE"][:,r]
                end
                if "HLR_Heatpump_Ground" ∈ capf_list
                    CapacityFactor[r,"HLR_Heatpump_Ground",:,y] = CountryData["HP_GROUNDSOURCE"][:,r]
                end

                for t ∈ setdiff(capf_list, ["HLR_Heatpump_Aerial", "HLR_Heatpump_Ground"])
                    CapacityFactor[r,t,:,y] = ScaledCountryData[keys_mapping[t]][:,r]
                end
            end
        end
    end
    total = Dates.now() - starttime
    open(joinpath("/cluster/home/danare/git/dana/results/spatial/time.txt"), "a") do file
        write(file, "$(Switch.hoffmann);$(length(Timeslice)/24);$(length(Timeslice)) $(Switch.warping_window); 0; 0; 0; 0; $total\n")
    end

    if Switch.write_reduced_timeserie == 1
        df_SpecifiedDemandProfile = convert_jump_container_to_df(SpecifiedDemandProfile[:,sdp_list,:,:];dim_names=[:Region,:Fuel,:Timeslice,:Year])
        df_CapacityFactor = convert_jump_container_to_df(CapacityFactor[:,capf_list,:,:];dim_names=[:Region,:Technology,:Timeslice,:Year])
        df_x_peakingDemand = convert_jump_container_to_df(x_peakingDemand;dim_names=[:Region,:Sector])
        df_YearSplit = convert_jump_container_to_df(YearSplit;dim_names=[:Timeslice,:Year])
        
        filename = "$(Switch.inputdir)/input_reduced_timeserie_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(Switch.elmod_nthhour).xlsx"
        if isfile(filename)
            rm(filename)
        end
        XLSX.writetable(filename,
        "SpecifiedDemandProfile" => df_SpecifiedDemandProfile, "CapacityFactor" => df_CapacityFactor, "x_peakingDemand" => df_x_peakingDemand,
        "YearSplit" => df_YearSplit)
    end

    return SpecifiedDemandProfile, CapacityFactor, x_peakingDemand, YearSplit, TimeDepEfficiency
end

function time_series_optimization(Sets, TagTechnologyToSubsets, Switch, SpecifiedAnnualDemand, k,CountryData, Country_Data_Entries,x_peakingDemand,Dunkelflaute,SmoothedCountryData,ScaledCountryData,AverageCapacityFactor)

    # choose every %elmod_nthhour% hour starting with the %elmod_starthour%

    Timeslice_full = 1:8760
    switch_dunkelflaute = 0
    if Switch.switch_dispatch == 1
        elmod_nthhour = 1
        Timeslice = 1:8760
    else
        elmod_nthhour = floor(Int, (8760/(Switch.elmod_nthhour*24 + k)))
        lenth_must = Switch.elmod_nthhour * 24 + k
        Timeslice = [x for x in Timeslice_full if (x-Switch.elmod_starthour)%(elmod_nthhour) == 0][1:lenth_must]
    end
    
    LAST_TIMESLICE = Timeslice[end]
    FIRST_TIMESLICE = Timeslice[1]

    i = 1
    j = 0
    lll=0
    #insert the Dunkelflaute
    while i < 24 && lll < 500 #what is the second condition supposed to be?
        lll = (1+j) * (24*Switch.elmod_daystep+Switch.elmod_hourstep) + Switch.elmod_starthour
        
        for t ∈ intersect(Country_Data_Entries,TagTechnologyToSubsets["Solar"])
            Dunkelflaute[t][lll,:] .= 0.5
        end

        for t ∈ intersect(Country_Data_Entries, TagTechnologyToSubsets["Wind"])
            Dunkelflaute[t][lll,:] .= 0.1
        end

        j+=1
        #Depending on the length of the total time set the length of the dunkelflaute are included
        if Switch.elmod_daystep == 0
            i+= 1
        else
            i += Switch.elmod_daystep * 2
        end
    end

    for r ∈ Sets.Region_full
        if sum(CountryData["LOAD"][l,r] for l ∈ Timeslice) != 0 
            AverageCapacityFactor["LOAD"][1,r] = sum(CountryData["LOAD"][:,r])/8760
        end
        CountryData["LOAD"][!,r] = CountryData["LOAD"][!,r] / AverageCapacityFactor["LOAD"][1,r]

        if "HEAT_LOW" ∈ Country_Data_Entries
            if sum(CountryData["HEAT_LOW"][l,r] for l ∈ Timeslice) != 0 
                AverageCapacityFactor["HEAT_LOW"][1,r] = sum(CountryData["HEAT_LOW"][:,r])/8760
            end
            CountryData["HEAT_LOW"][!,r] = CountryData["HEAT_LOW"][!,r] / AverageCapacityFactor["HEAT_LOW"][1,r]
        end
        
        for cde ∈ Country_Data_Entries
            if sum(CountryData[cde][l,r] for l ∈ Timeslice) != 0 
                AverageCapacityFactor[cde][1,r] = sum(CountryData[cde][:,r])/8760
            end
        end
    end

    smoothing_range = Dict()
    smoothing_range["LOAD"] = 3
    smoothing_range["PV_INF"] = 1
    smoothing_range["WIND_ONSHORE_INF"] = 2
    smoothing_range["PV_AVG"] = 1
    smoothing_range["WIND_ONSHORE_AVG"] = 2
    smoothing_range["PV_OPT"] = 1
    smoothing_range["PV_TRACKING"] = 1
    smoothing_range["WIND_ONSHORE_OPT"] = 2
    smoothing_range["WIND_OFFSHORE"] = 2
    smoothing_range["WIND_OFFSHORE_SHALLOW"] = 2
    smoothing_range["WIND_OFFSHORE_DEEP"] = 2
    smoothing_range["MOBILITY_PSNG"] = 3
    smoothing_range["HEAT_LOW"] = 3
    smoothing_range["HEAT_HIGH"] = 3
    smoothing_range["HEAT_PUMP_AIR"] = 3
    smoothing_range["HEAT_PUMP_GROUND"] = 3
    smoothing_range["HYDRO_ROR"] = 3

    for cde ∈ Country_Data_Entries
        smoothing_range[cde]=1
    end

    # Full calculation
    if length(Timeslice) == 8760
        for cde ∈ Country_Data_Entries
            smoothing_range[cde]=0
        end
    end 

    # Every 25th hour
    if length(Timeslice) == 374
        smoothing_range["LOAD"] = 3
        smoothing_range["PV_INF"] = 1
        smoothing_range["WIND_ONSHORE_INF"] = 4
        smoothing_range["PV_AVG"] = 1
        smoothing_range["WIND_ONSHORE_AVG"] = 4
        smoothing_range["PV_OPT"] = 1
        smoothing_range["PV_TRACKING"] = 1
        smoothing_range["WIND_ONSHORE_OPT"] = 4
        smoothing_range["WIND_OFFSHORE"] = 4
        smoothing_range["WIND_OFFSHORE_SHALLOW"] = 4
        smoothing_range["WIND_OFFSHORE_DEEP"] = 4
        smoothing_range["MOBILITY_PSNG"] = 3
        smoothing_range["HEAT_LOW"] = 3
        smoothing_range["HEAT_HIGH"] = 3
        smoothing_range["HEAT_PUMP_AIR"] = 3
        smoothing_range["HEAT_PUMP_GROUND"] = 3
        smoothing_range["HYDRO_ROR"] = 3
    end

    # Every 49th hour
    if length(Timeslice) == 191
        smoothing_range["LOAD"] = 3
        smoothing_range["PV_INF"] = 1
        smoothing_range["WIND_ONSHORE_INF"] = 3
        smoothing_range["PV_AVG"] = 1
        smoothing_range["WIND_ONSHORE_AVG"] = 3
        smoothing_range["PV_OPT"] = 1
        smoothing_range["PV_TRACKING"] = 1
        smoothing_range["WIND_ONSHORE_OPT"] = 3
        smoothing_range["WIND_OFFSHORE"] = 3
        smoothing_range["WIND_OFFSHORE_SHALLOW"] = 3
        smoothing_range["WIND_OFFSHORE_DEEP"] = 3
        smoothing_range["MOBILITY_PSNG"] = 3
        smoothing_range["HEAT_LOW"] = 3
        smoothing_range["HEAT_HIGH"] = 3
        smoothing_range["HEAT_PUMP_AIR"] = 3
        smoothing_range["HEAT_PUMP_GROUND"] = 3
        smoothing_range["HYDRO_ROR"] = 3
    end

    # If very short time-spans are used (e.g. for testing) decrease smoothing range
    for cde ∈ Country_Data_Entries
        if smoothing_range[cde]*2+1 > length(Timeslice)
            smoothing_range[cde] = max(0, round(length(Timeslice)/2-2))
        end
    end

    for cde ∈ Country_Data_Entries for r ∈ Sets.Region_full
        if sum(CountryData[cde][:,r]) != 0
            if smoothing_range[cde] == 0 
                SmoothedCountryData[cde] = CountryData[cde]
            elseif smoothing_range[cde] > 0
                for j ∈ eachindex(Timeslice)
                    SmoothedCountryData[cde][Timeslice[j],r] = sum(CountryData[cde][Timeslice[k],r]*
                    (1+((switch_dunkelflaute ==1 && Dunkelflaute[cde][Timeslice[j],r] > 0) ? -1+Dunkelflaute[cde][Timeslice[j],r] : 0)) 
                    for k ∈ eachindex(Timeslice) if ((k >= j - smoothing_range[cde]) && (k <= j + smoothing_range[cde]))) / sum(1 for k ∈ eachindex(Timeslice) if ((k >= j - smoothing_range[cde]) && (k <= j + smoothing_range[cde])))
                end
            end
        end
    end end

    # Determine minimum and maximum values in timeup and timeup_smoothed
    CountryDataMin         = Dict(cde => combine(CountryData[cde], names(CountryData[cde]) .=> minimum, renamecols=false) for cde ∈ Country_Data_Entries)
    CountryDataMax         = Dict(cde => combine(CountryData[cde], names(CountryData[cde]) .=> maximum, renamecols=false) for cde ∈ Country_Data_Entries)
    SmoothedCountryDataMin = Dict(cde => combine(SmoothedCountryData[cde][Timeslice,:], names(SmoothedCountryData[cde]) .=> minimum, renamecols=false) for cde ∈ Country_Data_Entries)
    SmoothedCountryDataMax = Dict(cde => combine(SmoothedCountryData[cde][Timeslice,:], names(SmoothedCountryData[cde]) .=> maximum, renamecols=false) for cde ∈ Country_Data_Entries)

    #Find the t with the highest /lovest value
    set_SmoothedCountryDataMin_tmp = Dict(cde => combine(SmoothedCountryData[cde][Timeslice,:], names(SmoothedCountryData[cde]) .=> argmin, renamecols=false) for cde ∈ Country_Data_Entries)
    set_SmoothedCountryDataMax_tmp = Dict(cde => combine(SmoothedCountryData[cde][Timeslice,:], names(SmoothedCountryData[cde]) .=> argmax, renamecols=false) for cde ∈ Country_Data_Entries)

    set_SmoothedCountryDataMin = Dict( cde => DataFrame(Dict(r => Timeslice[set_SmoothedCountryDataMin_tmp[cde][1,r]] for r in Sets.Region_full)) for cde ∈ Country_Data_Entries)
    set_SmoothedCountryDataMax = Dict( cde => DataFrame(Dict(r => Timeslice[set_SmoothedCountryDataMax_tmp[cde][1,r]] for r in Sets.Region_full)) for cde ∈ Country_Data_Entries)
    
    if elmod_nthhour == 1
        scaling_exponent = JuMP.Containers.DenseAxisArray(ones(length(Sets.Region_full), length(Country_Data_Entries)), Sets.Region_full, Country_Data_Entries)
        scaling_multiplicator = JuMP.Containers.DenseAxisArray(ones(length(Sets.Region_full), length(Country_Data_Entries)), Sets.Region_full, Country_Data_Entries)
        scaling_addition = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full), length(Country_Data_Entries)), Sets.Region_full, Country_Data_Entries)

        ScaledCountryData = CountryData
    else
        # SCALING
        model_scaling1 = JuMP.Model()

        @variable(model_scaling1, scaling_objective)
        @variable(model_scaling1, scaling_exponent[Sets.Region_full,Country_Data_Entries], start=1)
        @variable(model_scaling1, scaling_multiplicator[Sets.Region_full,Country_Data_Entries])
        @variable(model_scaling1, scaling_addition[Sets.Region_full,Country_Data_Entries])

        @NLconstraint(model_scaling1, def_scaling_max[r = Sets.Region_full, cde = Country_Data_Entries ; AverageCapacityFactor[cde][1,r] != 0 && (SmoothedCountryDataMax[cde][1,r] - SmoothedCountryDataMin[cde][1,r]) != 0],
        CountryDataMax[cde][1,r] - CountryDataMin[cde][1,r] == model_scaling1[:scaling_multiplicator][r,cde])
        @NLconstraint(model_scaling1, def_scaling_min[r = Sets.Region_full, cde = Country_Data_Entries ; AverageCapacityFactor[cde][1,r] != 0 && (SmoothedCountryDataMax[cde][1,r] - SmoothedCountryDataMin[cde][1,r]) != 0],
        CountryDataMin[cde][1,r] == model_scaling1[:scaling_addition][r,cde])

        N=length(Timeslice)
        @NLconstraint(model_scaling1, def_scaling_objective, model_scaling1[:scaling_objective] == 
        sum((AverageCapacityFactor[cde][1,r] * N - 
        sum(max(0,((((SmoothedCountryData[cde][l,r]-SmoothedCountryDataMin[cde][1,r])/(SmoothedCountryDataMax[cde][1,r]-SmoothedCountryDataMin[cde][1,r])
        )^model_scaling1[:scaling_exponent][r,cde]
        )*(CountryDataMax[cde][1,r] - CountryDataMin[cde][1,r])
        ) + CountryDataMin[cde][1,r]) for l ∈ Timeslice if (SmoothedCountryData[cde][l,r]-SmoothedCountryDataMin[cde][1,r]) != 0) - sum(max(0,CountryDataMin[cde][1,r]) for l ∈ Timeslice if (SmoothedCountryData[cde][l,r]-SmoothedCountryDataMin[cde][1,r]) == 0)
        )^2 for r ∈ Sets.Region_full for cde ∈ Country_Data_Entries if (AverageCapacityFactor[cde][1,r] != 0 && (SmoothedCountryDataMax[cde][1,r] - SmoothedCountryDataMin[cde][1,r]) != 0)))


        for r ∈ Sets.Region_full for cde ∈ Country_Data_Entries
            JuMP.set_lower_bound(model_scaling1[:scaling_exponent][r,cde], 0)
            JuMP.set_upper_bound(model_scaling1[:scaling_exponent][r,cde], 10)
        end end

        @objective(model_scaling1, MOI.MIN_SENSE, model_scaling1[:scaling_objective])
        set_optimizer(model_scaling1, Switch.DNLPsolver)
        optimize!(model_scaling1)

        for cde ∈ Country_Data_Entries for r ∈ Sets.Region_full
            if SmoothedCountryDataMax[cde][1,r] - SmoothedCountryDataMin[cde][1,r] != 0
                for l ∈ Timeslice
                ScaledCountryData[cde][l,r] = max(0, (
                    ((((SmoothedCountryData[cde][l,r] - SmoothedCountryDataMin[cde][1,r]) / (SmoothedCountryDataMax[cde][1,r] - SmoothedCountryDataMin[cde][1,r])
                    )^max(0,JuMP.value(model_scaling1[:scaling_exponent][r,cde]))
                    )
                    ) * JuMP.value(model_scaling1[:scaling_multiplicator][r,cde])
                    ) + JuMP.value(model_scaling1[:scaling_addition][r,cde]))
                end
            end
        end end
    end

    for cde ∈ Country_Data_Entries
        ScaledCountryData[cde] .= round.(ScaledCountryData[cde], digits=11)
    end

    return ScaledCountryData
end



function hierarchical_clustering(Sets, TagTechnologyToSubsets, Switch, SpecifiedAnnualDemand)

    starttime = Dates.now()

    keys_mapping = Dict(
        "Power" => "TS_LOAD",
        "RES_PV_Utility_Avg" => "TS_PV_AVG",
        "RES_PV_Utility_Inf" => "TS_PV_INF",
        "RES_PV_Utility_Opt" => "TS_PV_OPT",
        "RES_PV_Utility_Tracking" => "TS_PV_TRA",
        "RES_Wind_Onshore_Avg" => "TS_WIND_ONSHORE_AVG",
        "RES_Wind_Onshore_Inf" => "TS_WIND_ONSHORE_INF",
        "RES_Wind_Onshore_Opt" => "TS_WIND_ONSHORE_OPT",
        "RES_Wind_Offshore_Transitional" => "TS_WIND_OFFSHORE",
        "RES_Wind_Offshore_Deep" => "TS_WIND_OFFSHORE_DEEP",
        "RES_Wind_Offshore_Shallow" => "TS_WIND_OFFSHORE_SHALLOW",
        "Heat_Low_Residential" => "TS_HEAT_LOW",
        "HLR_Heatpump_Aerial" => "TS_HP_AIRSOURCE",
        "HLR_Heatpump_Ground" => "TS_HP_GROUNDSOURCE",
        "Mobility_Passenger" => "TS_MOBILITY_PSNG",
        "RES_Hydro_Small" => "TS_HYDRO_ROR",
        "Heat_High_Industrial" => "TS_HEAT_HIGH",
    )

    map_load = 
    [
        "Heat_Low_Industrial" => "Heat_High_Industrial",
        "Mobility_Freight" => "Mobility_Passenger",
        "Heat_Medium_Industrial" => "Heat_High_Industrial",
    ]

    # profiles based on medoid
    seasonal = intersect(collect(keys(keys_mapping)), ["RES_Hydro_Small","Mobility_Passenger","HLR_Heatpump_Ground","Heat_High_Industrial" ])

    #### config ########
    config = Dict()
    config["SCTOLERANCE"] = 10.0e-6
    config["Country_Data_Entries"] = 𝓣 = intersect(collect(keys(keys_mapping)), vcat(Sets.Fuel, Sets.Technology))
    config["countries"] = 𝓡 = [x for x in  Sets.Region_full if x != "World"]
    config["Load"] = load = intersect(Sets.Fuel, ["Mobility_Freight", "Heat_Low_Industrial","Heat_High_Industrial", "Mobility_Passenger", "Heat_Medium_Industrial", "Heat_Low_Residential", "Power"])
    res = setdiff(config["Country_Data_Entries"], load)


    ### Iterate over the keys mapping and create DataFrames
    hourly_data = XLSX.readxlsx(joinpath(Switch.inputdir, Switch.hourly_data_file * ".xlsx"))
    CountryData = Dict(t => DataFrame(XLSX.gettable(hourly_data[keys_mapping[t]])) for t ∈ 𝓣)

    for t ∈ 𝓣
        select!(CountryData[t], 𝓡)
        if t ∈ load
            for r ∈ 𝓡
                CountryData[t][:,r]  = CountryData[t][:,r] / 8760
            end
        end
    end

    # prepare data in vector format
    data_clustering_org = TSClustering.create_clustering_matrix(technology=𝓣, CountryData=CountryData)
    data = TSClustering.normalize_data(config=config, CountryData=CountryData)

    # use pca data if available
    if length(Switch.pca_path) >= 1
        println("PCA")
        data_clustering = TSClustering.create_clustering_matrix(technology=["PCA"], CountryData=Dict("PCA" => DataFrame(XLSX.readtable(Switch.pca_path, 1))))
    else
        data_clustering = TSClustering.create_clustering_matrix(technology=𝓣, CountryData=data)
        # without the daily profile
        if occursin("02_Medoid_withoutdaily", Switch.resultdir)
            data_clustering = TSClustering.create_clustering_matrix(technology=setdiff(𝓣, seasonal), CountryData=data)
        end
    end

    a = Dates.now()
    datapr = (a - starttime)
    # define distance matrix 
    D = TSClustering.define_distance(w=Switch.warping_window, data_clustering=data_clustering, fast_dtw=false)
    b = Dates.now()
    dtw = (b - a)

    extremes = false 
    days = [58,204,365]
    number_extremes = 0
    ############# CLUSTERING #############
    
    if occursin("Kmeans", Switch.resultdir)
        println("kmeans")
        R = kmeans(data_clustering, Switch.clusters; maxiter=200, display=:iter)
        cl = assignments(R) 
    else
        result = hclust(D, linkage=:ward)
        cl = cutree(result, k=Switch.clusters)
    end

    println("TS Length")
    println(cl)

    c = Dates.now()
    clustering = (c - b)
    if extremes
        for (j,i) in enumerate(days)
            cl[i] = Switch.clusters + j
        end
    end
    
    
    #calculate weights
    weights = Dict{Int64, Int64}()
    for i ∈ cl
        weights[i] = get(weights, i, 0) + 1
    end
    
    # read input data again because of Jump memory issues
    CountryData = Dict(key => DataFrame(XLSX.gettable(hourly_data[keys_mapping[key]])) for key ∈ 𝓣)
    for cde ∈ 𝓣
        select!(CountryData[cde], 𝓡)
        if cde ∈ load
            for r ∈ 𝓡
                CountryData[cde][:,r]  = CountryData[cde][:,r] / 8760
            end
        end
    end

    if Switch.hoffmann
        println("Hoffmann is selected")
        sc = JuMP.Containers.DenseAxisArray(zeros(length(𝓡), length(𝓣), Switch.clusters, 24), 𝓡, 𝓣, 1:Switch.clusters, 1:24) 
        if extremes
            for d ∈ Switch.clusters-number_extremes:Switch.clusters, k ∈ days
                for c ∈ 𝓡, t ∈ 𝓣
                    sc[c,t,d,:] = CountryData[t][(k-1)*24+1:k*24,c]
                end
            end
        end
        sc1 = TSClustering.calculate_representative_value_distribution(data_org=filter(kv -> kv[1] ∉ seasonal, CountryData), cl=cl, config=config, K=(Switch.clusters)-number_extremes);

        for t ∈ keys(filter(kv -> kv[1] ∉ seasonal, CountryData)), c ∈ 𝓡
            b = vcat([vec(sc1[c, t, i, :]) for i in 1:(Switch.clusters)]...)
            #sg = savitzky_golay(b, 3, 1)  
            for d ∈ 1:(Switch.clusters)-number_extremes
                #sc[c,t,d,:] = sg.y[(24*(d-1))+1:24*d]
                sc[c,t,d,:] = sc1[c,t,d,:]
                for h ∈ 1:24
                   if sc[c,t,d,h] <0
                      sc[c,t,d,h] = 0
                   end
                end
            end
        end
        ## medoid for seasonal profiles with missing data
        cluster_dict_org = TSClustering.calculate_medoid(data_org=CountryData,cl=cl,config=config,K=(Switch.clusters-number_extremes), technology=seasonal)
        sc2 = TSClustering.scaling(data_org=CountryData, scaled_clusters=cluster_dict_org, k=(Switch.clusters-number_extremes), weights=weights, config=config, technology=seasonal);
        for t ∈ seasonal, c ∈ 𝓡, k ∈ 1:(Switch.clusters-number_extremes)
            sc[c,t,k,:] = sc2[c,t,k,:]
            for h ∈ 1:24
                if sc[c,t,k,h] < 0
                    sc[c,t,k,h] = 0
                end
            end
        end

    else
        # calculate the medoids & bring into JumP formata
        if occursin("Centroid", Switch.resultdir)
            println("Centroid")
            cluster_dict_org = TSClustering.calculate_centroid(data_org=CountryData,cl=cl,config=config,K=Switch.clusters, technology=𝓣)
        else
            cluster_dict_org = TSClustering.calculate_medoid(data_org=CountryData,cl=cl,config=config,K=Switch.clusters, technology=𝓣)
        end
        sc = TSClustering.scaling(data_org=CountryData, scaled_clusters=cluster_dict_org, k=Switch.clusters, weights=weights, config=config, technology=𝓣);
    end
    d = Dates.now()
    repres = (d - c)

    CapacityFactor = JuMP.Containers.DenseAxisArray(ones(length(𝓡), length(Sets.Technology), length(Sets.Timeslice), length(Sets.Year)), 𝓡, Sets.Technology, Sets.Timeslice, Sets.Year)
    SpecifiedDemandProfile = JuMP.Containers.DenseAxisArray(zeros(length(𝓡), length(Sets.Fuel), length(Sets.Timeslice), length(Sets.Year)), 𝓡, Sets.Fuel, Sets.Timeslice, Sets.Year)
    TimeDepEfficiency = JuMP.Containers.DenseAxisArray(ones(length(𝓡), length(Sets.Technology), length(Sets.Timeslice), length(Sets.Year)), 𝓡, Sets.Technology, Sets.Timeslice, Sets.Year)

    for y ∈ Sets.Year, r ∈ 𝓡
        for t ∈ res
            if t ∈ ["HLR_Heatpump_Aerial", "HLR_Heatpump_Ground"]
                TimeDepEfficiency[r,t,:,y] =  vec(reshape(sc[r, t,:,:]', 1, :))
                CapacityFactor[r,t,:,y] .=  1
            else
                CapacityFactor[r,t,:,y] = vec(reshape(sc[r, t,:,:]', 1, :))
            end
        end
        for t ∈ intersect(load,  keys(keys_mapping))
            SpecifiedDemandProfile[r,t,:,y] = vec(reshape(sc[r, t,:,:]', 1, :))
            for c ∈ 1:Switch.clusters
                tmp_sum = 0
                for i ∈ 1:24
                    tmp_sum += SpecifiedDemandProfile[r,t,(c-1)*24+i,y]
                end
                for i ∈ 1:24
                    SpecifiedDemandProfile[r,t,((c-1)*24)+i,y] = (SpecifiedDemandProfile[r,t,((c-1)*24)+i,y] / tmp_sum)*(weights[c]/365)
                end 
            end 
            # tmp_sum = sum(SpecifiedDemandProfile[r,t,:,y])
            # for c ∈ 1:Switch.clusters
            #     for i ∈ 1:24
            #         SpecifiedDemandProfile[r,t,((c-1)*24)+i,y] = SpecifiedDemandProfile[r,t,((c-1)*24)+i,y] / tmp_sum
            #     end
            # end
        end

        
        # include profiles based on another profile
        for (k,v) ∈ map_load
            SpecifiedDemandProfile[r,k,:,y] = SpecifiedDemandProfile[r,v,:,y]
        end
    end


    # assign the weights
    weights_yrl = vcat([fill(weights[key] / 8760, 24) for key in 1:Switch.clusters]...)
    YearSplit = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Timeslice), length(Sets.Year)), Sets.Timeslice, Sets.Year)
    YearSplit[:,:] = repeat(weights_yrl, length(Sets.Year))

    # define empty array for peaking demand
    x_peakingDemand = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full), length(Sets.Sector)),Sets.Region_full, Sets.Sector)

    if Switch.write_reduced_timeserie == 1
        df_SpecifiedDemandProfile = convert_jump_container_to_df(SpecifiedDemandProfile[:,load,:,:];dim_names=[:Region,:Fuel,:Timeslice,:Year])
        df_CapacityFactor = convert_jump_container_to_df(CapacityFactor[:,res,:,:];dim_names=[:Region,:Technology,:Timeslice,:Year])
        df_YearSplit = convert_jump_container_to_df(YearSplit;dim_names=[:Timeslice,:Year])
        df_TimeDepEfficiency = convert_jump_container_to_df(TimeDepEfficiency[:,["HLR_Heatpump_Aerial", "HLR_Heatpump_Ground"], :,:])

        
        filename = "$(Switch.inputdir)/input_reduced_timeserie_$(Switch.clusters)_$(replace(split(Switch.resultdir, "/")[end], ".xlsx" => "")).xlsx"
        if isfile(filename)
            rm(filename)
        end
        XLSX.writetable(filename,
        "SpecifiedDemandProfile" => df_SpecifiedDemandProfile, 
        "CapacityFactor" => df_CapacityFactor, 
        "TimeDepEfficiency" => df_TimeDepEfficiency,
        "YearSplit" => df_YearSplit)
    end

    ## save the computational burden
    total=datapr+dtw+clustering+repres
    open(joinpath("/cluster/home/danare/git/dana/results/spatial/time.txt"), "a") do file
        write(file, "$(Switch.hoffmann);$(Switch.clusters); 0; $(Switch.warping_window); $datapr; $dtw; $clustering; $repres; $total\n")
    end

    return SpecifiedDemandProfile, CapacityFactor, x_peakingDemand, YearSplit, cl, weights, TimeDepEfficiency
end
