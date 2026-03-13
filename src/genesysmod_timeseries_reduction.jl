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
function timeseries_reduction!(Params, Sets, Switch)

    switch_dunkelflaute = Switch.elmod_dunkelflaute

    keys_mapping = Dict(
        "Power" => "LOAD",
        "P_PV_Utility_Avg" => "PV_AVG",
        "P_PV_Utility_Inf" => "PV_INF",
        "P_PV_Utility_Opt" => "PV_OPT",
        "P_PV_Utility_Tracking" => "PV_TRA",
        "P_Wind_Onshore_Avg" => "WIND_ONSHORE_AVG",
        "P_Wind_Onshore_Inf" => "WIND_ONSHORE_INF",
        "P_Wind_Onshore_Opt" => "WIND_ONSHORE_OPT",
        "P_Wind_Offshore_Transitional" => "WIND_OFFSHORE",
        "P_Wind_Offshore_Deep" => "WIND_OFFSHORE_DEEP",
        "P_Wind_Offshore_Shallow" => "WIND_OFFSHORE_SHALLOW",
        "Heat_Buildings" => "HEAT_LOW",
        "Heat_District" => "HEAT_LOW",
        "Cool_Low_Building" => "COOL_LOW",
        "HB_Heatpump_Aerial" => "HP_AIRSOURCE",
        "HB_Heatpump_Ground" => "HP_GROUNDSOURCE",
        "Mobility_Passenger" => "MOBILITY_PSNG",
        "Mobility_Freight" => "MOBILITY_PSNG",
        "P_Hydro_RoR" => "HYDRO_ROR",
        "Heat_High_Industrial" => "HEAT_HIGH",
        "Heat_MediumLow_Industrial" => "HEAT_HIGH",
        "Heat_MediumHigh_Industrial" => "HEAT_HIGH",
        "Heat_Low_Industrial" => "HEAT_HIGH",
    )

    Country_Data_Entries= unique([keys_mapping[k] for k ∈ intersect(keys(keys_mapping), union(Sets.Fuel, Sets.Technology))])

    sector_to_tech = Dict(
        "Industry"=>"HEAT_HIGH",
        "Buildings"=>"HEAT_LOW",
        "Transportation"=>"MOBILITY_PSNG",
        "Power"=>"LOAD")

    Timeslice_Full = 1:8760

    hourly_data = XLSX.readxlsx(joinpath(Switch.inputdir, Switch.hourly_data_file * ".xlsx"))

    CountryData = Dict()
    for v ∈ Country_Data_Entries
        CountryData[v] = DataFrame(XLSX.gettable(hourly_data["TS_" * v]))
        select!(CountryData[v], Not([:HOUR]))
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
    for s ∈ intersect(Sets.Sector,keys(sector_to_tech)), r ∈ Sets.Region_full
        df_peakingDemand[s] = combine(CountryData[sector_to_tech[s]], names(CountryData[sector_to_tech[s]]) .=> maximum, renamecols=false) ./ x_averageTimeSeriesValue[sector_to_tech[s]]
        Params.x_peakingDemand[r,s] = df_peakingDemand[s][1,r]
    end

    negativeCDE = Dict(x => mapcols(col -> min.(col,0), CountryData[x]) for x ∈ Country_Data_Entries)

    LAST_TIMESLICE = Sets.Timeslice[end]
    FIRST_TIMESLICE = Sets.Timeslice[1]

    i = 1
    j = 0
    lll=0
    #insert the Dunkelflaute
    while i < 24 && lll < 500 #what is the second condition supposed to be?
        lll = (1+j) * (24*Switch.elmod_daystep+Switch.elmod_hourstep) + Switch.elmod_starthour

        for t ∈ intersect(Country_Data_Entries,Params.Tags.TagTechnologyToSubsets["Solar"])
            Dunkelflaute[t][lll,:] .= 0.5
        end

        for t ∈ intersect(Country_Data_Entries, Params.Tags.TagTechnologyToSubsets["Wind"])
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
        if sum(CountryData["LOAD"][l,r] for l ∈ Sets.Timeslice) != 0
            AverageCapacityFactor["LOAD"][1,r] = sum(CountryData["LOAD"][:,r])/8760
            CountryData["LOAD"][!,r] = CountryData["LOAD"][!,r] / AverageCapacityFactor["LOAD"][1,r]
        end

        if "HEAT_LOW" ∈ Country_Data_Entries
            if sum(CountryData["HEAT_LOW"][l,r] for l ∈ Sets.Timeslice) != 0
                AverageCapacityFactor["HEAT_LOW"][1,r] = sum(CountryData["HEAT_LOW"][:,r])/8760
                CountryData["HEAT_LOW"][!,r] = CountryData["HEAT_LOW"][!,r] / AverageCapacityFactor["HEAT_LOW"][1,r]
            end
        end

        if "COOL_LOW" ∈ Country_Data_Entries
            if sum(CountryData["COOL_LOW"][l,r] for l ∈ Sets.Timeslice) != 0
                AverageCapacityFactor["COOL_LOW"][1,r] = sum(CountryData["COOL_LOW"][:,r])/8760
                CountryData["COOL_LOW"][!,r] = CountryData["COOL_LOW"][!,r] / AverageCapacityFactor["COOL_LOW"][1,r]
            end
        end

        for cde ∈ Country_Data_Entries
            if sum(CountryData[cde][l,r] for l ∈ Sets.Timeslice) != 0
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
    smoothing_range["COOL_LOW"] = 3
    smoothing_range["HEAT_HIGH"] = 3
    smoothing_range["HEAT_PUMP_AIR"] = 3
    smoothing_range["HEAT_PUMP_GROUND"] = 3
    smoothing_range["HYDRO_ROR"] = 3

    for cde ∈ Country_Data_Entries
        smoothing_range[cde]=1
    end

    # Full calculation
    if length(Sets.Timeslice) == 8760
        for cde ∈ Country_Data_Entries
            smoothing_range[cde]=0
        end
    end

    # Every 25th hour
    if length(Sets.Timeslice) == 374
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
        smoothing_range["COOL_LOW"] = 3
        smoothing_range["HEAT_HIGH"] = 3
        smoothing_range["HEAT_PUMP_AIR"] = 3
        smoothing_range["HEAT_PUMP_GROUND"] = 3
        smoothing_range["HYDRO_ROR"] = 3
    end

    # Every 49th hour
    if length(Sets.Timeslice) == 191
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
        smoothing_range["COOL_LOW"] = 3
        smoothing_range["HEAT_HIGH"] = 3
        smoothing_range["HEAT_PUMP_AIR"] = 3
        smoothing_range["HEAT_PUMP_GROUND"] = 3
        smoothing_range["HYDRO_ROR"] = 3
    end

    # If very short time-spans are used (e.g. for testing) decrease smoothing range
    for cde ∈ Country_Data_Entries
        if smoothing_range[cde]*2+1 > length(Sets.Timeslice)
            smoothing_range[cde] = max(0, round(length(Sets.Timeslice)/2-2))
        end
    end

    for cde ∈ Country_Data_Entries for r ∈ Sets.Region_full
        if sum(CountryData[cde][:,r]) != 0
            if smoothing_range[cde] == 0
                SmoothedCountryData[cde] = CountryData[cde]
            elseif smoothing_range[cde] > 0
                for j ∈ eachindex(Sets.Timeslice)
                    SmoothedCountryData[cde][Sets.Timeslice[j],r] = sum(CountryData[cde][Sets.Timeslice[k],r]*
                    (1+((switch_dunkelflaute ==1 && Dunkelflaute[cde][Sets.Timeslice[j],r] > 0) ? -1+Dunkelflaute[cde][Sets.Timeslice[j],r] : 0))
                    for k ∈ eachindex(Sets.Timeslice) if ((k >= j - smoothing_range[cde]) && (k <= j + smoothing_range[cde]))) / sum(1 for k ∈ eachindex(Sets.Timeslice) if ((k >= j - smoothing_range[cde]) && (k <= j + smoothing_range[cde])))
                end
            end
        end
    end end

    # Determine minimum and maximum values in timeup and timeup_smoothed
    CountryDataMin         = Dict(cde => combine(CountryData[cde], names(CountryData[cde]) .=> minimum, renamecols=false) for cde ∈ Country_Data_Entries)
    CountryDataMax         = Dict(cde => combine(CountryData[cde], names(CountryData[cde]) .=> maximum, renamecols=false) for cde ∈ Country_Data_Entries)
    SmoothedCountryDataMin = Dict(cde => combine(SmoothedCountryData[cde][Sets.Timeslice,:], names(SmoothedCountryData[cde]) .=> minimum, renamecols=false) for cde ∈ Country_Data_Entries)
    SmoothedCountryDataMax = Dict(cde => combine(SmoothedCountryData[cde][Sets.Timeslice,:], names(SmoothedCountryData[cde]) .=> maximum, renamecols=false) for cde ∈ Country_Data_Entries)

    #Find the t with the highest /lovest value
    set_SmoothedCountryDataMin_tmp = Dict(cde => combine(SmoothedCountryData[cde][Sets.Timeslice,:], names(SmoothedCountryData[cde]) .=> argmin, renamecols=false) for cde ∈ Country_Data_Entries)
    set_SmoothedCountryDataMax_tmp = Dict(cde => combine(SmoothedCountryData[cde][Sets.Timeslice,:], names(SmoothedCountryData[cde]) .=> argmax, renamecols=false) for cde ∈ Country_Data_Entries)

    set_SmoothedCountryDataMin = Dict( cde => DataFrame(Dict(r => Sets.Timeslice[set_SmoothedCountryDataMin_tmp[cde][1,r]] for r in Sets.Region_full)) for cde ∈ Country_Data_Entries)
    set_SmoothedCountryDataMax = Dict( cde => DataFrame(Dict(r => Sets.Timeslice[set_SmoothedCountryDataMax_tmp[cde][1,r]] for r in Sets.Region_full)) for cde ∈ Country_Data_Entries)

    if Switch.elmod_nthhour == 1
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

        N=length(Sets.Timeslice)
        @NLconstraint(model_scaling1, def_scaling_objective, model_scaling1[:scaling_objective] ==
        sum((AverageCapacityFactor[cde][1,r] * N -
        sum(max(0,((((SmoothedCountryData[cde][l,r]-SmoothedCountryDataMin[cde][1,r])/(SmoothedCountryDataMax[cde][1,r]-SmoothedCountryDataMin[cde][1,r])
        )^model_scaling1[:scaling_exponent][r,cde]
        )*(CountryDataMax[cde][1,r] - CountryDataMin[cde][1,r])
        ) + CountryDataMin[cde][1,r]) for l ∈ Sets.Timeslice if (SmoothedCountryData[cde][l,r]-SmoothedCountryDataMin[cde][1,r]) != 0) - sum(max(0,CountryDataMin[cde][1,r]) for l ∈ Sets.Timeslice if (SmoothedCountryData[cde][l,r]-SmoothedCountryDataMin[cde][1,r]) == 0)
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
                for l ∈ Sets.Timeslice
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
        ScaledCountryData[cde] .= round.(ScaledCountryData[cde], digits=6)
    end

    sdp_list=intersect(Sets.Fuel, ["Power","Mobility_Passenger","Mobility_Freight",
        "Heat_Buildings","Heat_District","Heat_Low_Industrial","Heat_Medium_Industrial",
        "Heat_High_Industrial","Heat_MediumLow_Industrial","Heat_MediumHigh_Industrial",
        "Cool_Low_Building"])
    capf_list=intersect(Sets.Technology, ["HB_Heatpump_Aerial","HB_Heatpump_Ground","P_PV_Utility_Opt","P_Wind_Onshore_Opt","P_Wind_Offshore_Transitional","P_Wind_Onshore_Avg","P_Wind_Offshore_Shallow","P_PV_Utility_Inf",
    "P_Wind_Onshore_Inf","P_Wind_Offshore_Deep","P_PV_Utility_Tracking","P_Hydro_RoR", "P_PV_Utility_Avg"])
    #tmp = ScaledCountryData["LOAD"] ./ length(Sets.Timeslice)
    #= for r ∈ Sets.Region_full
        for f ∈ Sets.Fuel
            if sum(Params.SpecifiedAnnualDemand[r,f,:]) != 0
                Params.SpecifiedDemandProfile[r,f,:,Sets.Year[1]] = tmp[Sets.Timeslice,r]
            end
        end
    end =#
#=     for r ∈ Sets.Region_full
        for f ∈ Sets.Fuel
            for y ∈ Sets.Year
                if sum(Params.SpecifiedAnnualDemand[r,f,:]) != 0
                    tmp=ScaledCountryData["LOAD"][!,r] ./ sum(ScaledCountryData["LOAD"][!,r])
                    println(tmp)
                    println(Params.SpecifiedDemandProfile[r,f,:,y])
                    Params.SpecifiedDemandProfile[r,f,:,y] .= ScaledCountryData["LOAD"][!,r] ./ sum(ScaledCountryData["LOAD"][!,r])
                end
            end
        end
    end =#

    tmp=Dict()
    for t ∈ intersect(Country_Data_Entries, ["LOAD", "MOBILITY_PSNG", "HEAT_LOW", "HEAT_HIGH", "COOL_LOW"])
        div = combine(ScaledCountryData[t], names(ScaledCountryData[t]) .=> sum, renamecols=false)
        for col in names(div)
            replace!(div[!, col], 0 => 1)
        end
        tmp[t] = ScaledCountryData[t] ./ div
    end

    end_uses = union(["Power"], Params.Tags.TagFuelToSubsets["HeatFuels"], Params.Tags.TagFuelToSubsets["TransportFuels"])
    for r ∈ Sets.Region_full
        for f ∈ Sets.Fuel
            if sum(Params.SpecifiedAnnualDemand[r,f,:]) != 0
                Params.SpecifiedDemandProfile[r,f,:,Sets.Year[1]] = tmp["LOAD"][Sets.Timeslice,r]
            else
                Params.SpecifiedDemandProfile[r,f,:,Sets.Year[1]] = [0.0 for i ∈ 1:length(Sets.Timeslice)]
            end
        end
        for f ∈ setdiff(end_uses, ["Power"])
            Params.SpecifiedDemandProfile[r,f,:,Sets.Year[1]] = tmp[keys_mapping[f]][Sets.Timeslice,r]
        end
    end

    for r ∈ Sets.Region_full for f ∈ Sets.Fuel for y ∈ Sets.Year[2:end]
        Params.SpecifiedDemandProfile[r,f,:,y] = Params.SpecifiedDemandProfile[r,f,:,Sets.Year[1]]
    end end end

    for y ∈ Sets.Year
        for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["Solar"])
            Params.CapacityFactor[:,t,:,y] .= 0
        end
        for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["Wind"])
            Params.CapacityFactor[:,t,:,y] .= 0
        end
        for r ∈ Sets.Region_full
            if length(Sets.Timeslice) < 8760
                if "HB_Heatpump_Aerial" ∈ capf_list
                    Params.CapacityFactor[r,"HB_Heatpump_Aerial",:,y] .= 1
                    Params.TimeDepEfficiency[r,"HB_Heatpump_Aerial",:,y] = ScaledCountryData["HP_AIRSOURCE"][Sets.Timeslice,r]
                end
                if "HB_Heatpump_Ground" ∈ capf_list
                    Params.CapacityFactor[r,"HB_Heatpump_Ground",:,y] .= 1
                    Params.TimeDepEfficiency[r,"HB_Heatpump_Ground",:,y] = ScaledCountryData["HP_GROUNDSOURCE"][Sets.Timeslice,r]
                end

                for t ∈ setdiff(capf_list, ["HB_Heatpump_Aerial", "HB_Heatpump_Ground"])
                    Params.CapacityFactor[r,t,:,y] = ScaledCountryData[keys_mapping[t]][Sets.Timeslice,r]
                end
            else
                if "HB_Heatpump_Aerial" ∈ capf_list
                    Params.CapacityFactor[r,"HB_Heatpump_Aerial",:,y] .= 1
                    Params.TimeDepEfficiency[r,"HB_Heatpump_Aerial",:,y] = CountryData["HP_AIRSOURCE"][Sets.Timeslice,r]
                end
                if "HB_Heatpump_Ground" ∈ capf_list
                    Params.CapacityFactor[r,"HB_Heatpump_Ground",:,y] .= 1
                    Params.TimeDepEfficiency[r,"HB_Heatpump_Ground",:,y] = CountryData["HP_GROUNDSOURCE"][Sets.Timeslice,r]
                end

                for t ∈ setdiff(capf_list, ["HB_Heatpump_Aerial", "HB_Heatpump_Ground"])
                    Params.CapacityFactor[r,t,:,y] = CountryData[keys_mapping[t]][:,r]
                end
            end
        end
    end


    if Switch.write_reduced_timeserie == 1
        df_SpecifiedDemandProfile = convert_jump_container_to_df(Params.SpecifiedDemandProfile[:,sdp_list,:,:];dim_names=[:Region,:Fuel,:Timeslice,:Year])
        df_CapacityFactor = convert_jump_container_to_df(Params.CapacityFactor[:,capf_list,:,:];dim_names=[:Region,:Technology,:Timeslice,:Year])
        df_x_peakingDemand = convert_jump_container_to_df(Params.x_peakingDemand;dim_names=[:Region,:Sector])
        df_YearSplit = convert_jump_container_to_df(Params.YearSplit;dim_names=[:Timeslice,:Year])

        filename = "$(Switch.inputdir)/input_reduced_timeserie_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(Switch.elmod_nthhour).xlsx"
        if isfile(filename)
            rm(filename)
        end
        XLSX.writetable(filename,
        "SpecifiedDemandProfile" => df_SpecifiedDemandProfile, "CapacityFactor" => df_CapacityFactor, "x_peakingDemand" => df_x_peakingDemand,
        "YearSplit" => df_YearSplit)
    end

end
