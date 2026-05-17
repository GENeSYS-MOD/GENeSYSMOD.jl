# GENeSYS-MOD v3.1 [Global Energy System Model]  ~ March 2022
#
# #############################################################
#
# Copyright 2020 Technische Universit�t Berlin && DIW Berlin
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
# See the License for the specific language governing permissions &&
# limitations under the License.
#
# #############################################################

"""
Internal function used in the run pårocess to compute results. 
It also runs the functions for processing emissions and levelized costs.
"""
function merge_df(df, dict_col_value, final_df, colnames)
    for (col, value) in dict_col_value
        df[!,col] .= value
    end
    if !isempty(df)
        select!(df,colnames)
        append!(final_df, df)
    end
end

function resourcecosts_from_duals(model, Sets, Switch, Settings, extr_str)
    df_duals = genesysmod_getdualsbyname(model,Switch,extr_str, "EB2_EnergyBalanceEachTS")

    cols = [:constraint_type, :year, :timestep, :fuel, :region]
    transform!(df_duals, :names => ByRow(x -> split(x, '|')) => cols)

    select!(df_duals, Not(:names,:constraint_type))
    select!(df_duals, [:region, :fuel, :year, :timestep, :values])
    df_duals=combine(groupby(df_duals, [:region, :fuel, :year]), :values => mean => :y)

    df_duals.year = parse.(Int64,df_duals.year)

    resourcecosts = create_daa(df_duals,"","", Sets.Region_full, Sets.Fuel,  Sets.Year)
    return resourcecosts
end

function genesysmod_results(model,Sets, Params, VarPar, Vars, Switch, Settings, Maps, elapsed, extr_str)
    LoopSetOutput = Dict()
    LoopSetInput = Dict()
    for y ∈ Sets.Year for f ∈ Sets.Fuel for r ∈ Sets.Region_full
      LoopSetOutput[(r,f,y)] = [(x[1],x[2]) for x in keys(Params.OutputActivityRatio[r,:,f,:,y]) if Params.OutputActivityRatio[r,x[1],f,x[2],y] > 0]
      LoopSetInput[(r,f,y)] = [(x[1],x[2]) for x in keys(Params.InputActivityRatio[r,:,f,:,y]) if Params.InputActivityRatio[r,x[1],f,x[2],y] > 0]
    end end end

    z_fuelcosts = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Fuel),length(Sets.Year),length(Sets.Region_full)), Sets.Fuel, Sets.Year, Sets.Region_full)
    for y ∈ Sets.Year for r ∈ Sets.Region_full
        z_fuelcosts["Hardcoal",y,r] = Params.VariableCost[r,"Z_Import_Hardcoal",1,y]
        z_fuelcosts["Lignite",y,r] = Params.VariableCost[r,"R_Coal_Lignite",1,y]
        z_fuelcosts["Nuclear",y,r] = Params.VariableCost[r,"R_Nuclear",1,y]
        z_fuelcosts["Biomass",y,r] = sum(Params.VariableCost[r,f,1,y] for f ∈ Params.TagTechnologyToSubsets["Biomass"])/length(Params.TagTechnologyToSubsets["Biomass"]) 
        z_fuelcosts["Gas_Natural",y,r] = Params.VariableCost[r,"Z_Import_Gas",1,y]
        z_fuelcosts["Oil",y,r] = Params.VariableCost[r,"Z_Import_Oil",1,y]
        z_fuelcosts["H2",y,r] = Params.VariableCost[r,"Z_Import_H2",1,y]
    end end

    if Switch.switch_LCOE_calc == 1
        resourcecosts, output_emissionintensity = genesysmod_levelizedcosts(model,Sets, Params, VarPar, Vars, Switch, Settings, z_fuelcosts, LoopSetOutput, LoopSetInput, extr_str)
    else
        resourcecosts = resourcecosts_from_duals(model, Sets, Switch, Settings, extr_str)
    end
    
    ### parameter output_energy_balance(*,*,*,*,*,*,*,*,*,*) & parameter output_energy_balance_annual(*,*,*,*,*,*,*,*)
    colnames = [:Region, :Sector, :Technology, :Mode_of_operation, :Fuel, :Timeslice, :Type, :Unit, :PathwayScenario, :Year, :Value]
    output_energy_balance = DataFrame([name => [] for name in colnames])

    colnames2 = [:Region, :Sector, :Technology, :Fuel, :Type, :Unit, :PathwayScenario, :Year, :Value]
    output_energy_balance_annual = DataFrame([name => [] for name in colnames2])

    tmp = VarPar.RateOfProductionByTechnologyByMode
    for y ∈ Sets.Year for l ∈ Sets.Timeslice
        tmp[y,l,:,:,:,:] = tmp[y,l,:,:,:,:] * Params.YearSplit[l,y]
    end end

    df_energy_balance = convert_jump_container_to_df(tmp;dim_names=[:Year, :Timeslice, :Technology, :Mode_of_operation, :Fuel, :Region])
    df_energy_balance[!,:Type] .= "Production"
    df_energy_balance[!,:Unit] .= "PJ"
    df_energy_balance[!,:PathwayScenario] .= "$(Switch.emissionPathway)_$(Switch.emissionScenario)"

    for se ∈ setdiff(Sets.Sector,"Transportation")
       
        tmp_techs = [t_ for t_ ∈ Sets.Technology if Params.TagTechnologyToSector[t_,se] >0]
        
        if tmp_techs != []
            subset_df = df_energy_balance[in.(df_energy_balance.Technology, Ref(tmp_techs)),:]
            subset_df[!,:Sector] .= se
            if !isempty(subset_df)
                select!(subset_df,colnames)
                append!(output_energy_balance, subset_df)
                append!(output_energy_balance_annual, combine(groupby(subset_df, [:Region, :Sector, :Technology, :Fuel, :Type, :Unit, :PathwayScenario, :Year]), :Value=> sum; renamecols=false))
            end
        end
    end

    tmp_techs = [t_ for t_ ∈ Sets.Technology if Params.TagTechnologyToSector[t_,"Transportation"] >0]
    df_tmp = convert_jump_container_to_df(tmp[:,:,tmp_techs,:,:,:];dim_names=[:Year, :Timeslice, :Technology, :Mode_of_operation, :Fuel, :Region])
    dict_col_value = Dict(:Sector=>"Transportation", :Type=>"Production", :Unit=>"billion km",
                            :PathwayScenario=>"$(Switch.emissionPathway)_$(Switch.emissionScenario)")

    merge_df(df_tmp, dict_col_value, output_energy_balance, colnames)
    append!(output_energy_balance_annual, combine(groupby(df_tmp, [:Region, :Sector, :Technology, :Fuel, :Type, :Unit, :PathwayScenario, :Year]), :Value=> sum; renamecols=false))

    tmp = VarPar.RateOfUseByTechnologyByMode
    for y ∈ Sets.Year for l ∈ Sets.Timeslice
        tmp[y,l,:,:,:,:] = (-1) * tmp[y,l,:,:,:,:] * Params.YearSplit[l,y]
    end end

    dict_col_value = Dict(:Sector=>"Transportation", :Type=>"Use", :Unit=>"PJ",
    :PathwayScenario=>"$(Switch.emissionPathway)_$(Switch.emissionScenario)")

    for se ∈ Sets.Sector
        tmp_techs = [t_ for t_ ∈ Sets.Technology if Params.TagTechnologyToSector[t_,se] >0]
        if tmp_techs != []
            df_tmp = convert_jump_container_to_df(tmp[:,:,tmp_techs,:,:,:];dim_names=[:Year, :Timeslice, :Technology, :Mode_of_operation, :Fuel, :Region])
            setindex!(dict_col_value, se, :Sector)
            merge_df(df_tmp, dict_col_value, output_energy_balance, colnames)
            if !isempty(df_tmp)
                append!(output_energy_balance_annual, combine(groupby(df_tmp, [:Region, :Sector, :Technology, :Fuel, :Type, :Unit, :PathwayScenario, :Year]), :Value=> sum; renamecols=false))
            end
        end
    end

    dict_col_value = Dict(:Sector=>"Demand", :Type=>"Use", :Unit=>"PJ",
    :PathwayScenario=>"$(Switch.emissionPathway)_$(Switch.emissionScenario)", :Technology=>"Demand", :Mode_of_operation=>1)

    df_dem= convert_jump_container_to_df(Params.Demand[:,:,:,:];dim_names=[:Year, :Timeslice, :Fuel, :Region])
    for se ∈ setdiff(Sets.Sector,"Transportation")
        for f ∈ [f_ for f_ ∈ Sets.Fuel if Params.TagDemandFuelToSector[f_,se] >0]
            df_tmp = df_dem[(df_dem.Fuel .== f) .&& (df_dem.Value .> 0),:]            
            df_tmp[:,:Value]= (-1) * df_tmp[:,:Value]
            
            merge_df(df_tmp, dict_col_value, output_energy_balance, colnames)
            # df_tmp[!,:Sector] .= "Demand"
            # df_tmp[!,:Technology] .= "Demand"
            # df_tmp[!,:Mode_of_operation] .= 1
            # df_tmp[!,:Type] .= "Use"
            # df_tmp[!,:Unit] .= "PJ"
            # df_tmp[!,:PathwayScenario] .= "$(Switch.emissionPathway)_$(Switch.emissionScenario)"
            # select!(df_tmp,colnames)
            # append!(output_energy_balance, df_tmp)
            if !isempty(df_tmp)
                append!(output_energy_balance_annual, combine(groupby(df_tmp, [:Region, :Sector, :Technology, :Fuel, :Type, :Unit, :PathwayScenario, :Year]), :Value=> sum; renamecols=false))
            end
        end
    end

    for f ∈ [f_ for f_ ∈ Sets.Fuel if Params.TagDemandFuelToSector[f_,"Transportation"] >0]
        df_tmp= df_dem[(df_dem.Fuel .== f) .&& (df_dem.Value .> 0),:]
        df_tmp[:,:Value]= (-1) * df_tmp[:,:Value]
        df_tmp[!,:Sector] .= "Demand"
        df_tmp[!,:Technology] .= "Demand"
        df_tmp[!,:Mode_of_operation] .= 1
        df_tmp[!,:Type] .= "Use"
        df_tmp[!,:Unit] .= "billion km"
        df_tmp[!,:PathwayScenario] .= "$(Switch.emissionPathway)_$(Switch.emissionScenario)"
        select!(df_tmp,colnames)
        append!(output_energy_balance, df_tmp)
        append!(output_energy_balance_annual, combine(groupby(df_tmp, [:Region, :Sector, :Technology, :Fuel, :Type, :Unit, :PathwayScenario, :Year]), :Value=> sum; renamecols=false))
    end

    df_imp= convert_jump_container_to_df(value.(Vars.Import);dim_names=[:Year, :Timeslice, :Fuel, :Region, :Region2])
    df_tmp = combine(groupby(df_imp, [:Year, :Timeslice, :Fuel, :Region]), :Value => sum; renamecols=false)
    
    dict_col_value = Dict(:Sector=>"Trade", :Type=>"Import", :Unit=>"PJ",
    :PathwayScenario=>"$(Switch.emissionPathway)_$(Switch.emissionScenario)", :Technology=>"Trade", :Mode_of_operation=>1)
    merge_df(df_tmp, dict_col_value, output_energy_balance, colnames)
    if !isempty(df_tmp)
        append!(output_energy_balance_annual, combine(groupby(df_tmp, [:Region, :Sector, :Technology, :Fuel, :Type, :Unit, :PathwayScenario, :Year]), :Value=> sum; renamecols=false))
    end

    df_exp= convert_jump_container_to_df(-(1) * value.(Vars.Export);dim_names=[:Year, :Timeslice, :Fuel, :Region, :Region2])
    df_tmp = combine(groupby(df_exp, [:Year, :Timeslice, :Fuel, :Region]), :Value => sum; renamecols=false)
    setindex!(dict_col_value, "Export", :Type)
    merge_df(df_tmp, dict_col_value, output_energy_balance, colnames)
    if !isempty(df_tmp)
        append!(output_energy_balance_annual, combine(groupby(df_tmp, [:Region, :Sector, :Technology, :Fuel, :Type, :Unit, :PathwayScenario, :Year]), :Value=> sum; renamecols=false))
    end

    ### parameter CapacityUsedByTechnologyEachTS, PeakCapacityByTechnology
    CapacityUsedByTechnologyEachTS = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Timeslice),length(Sets.Technology),length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Region_full)
    PeakCapacityByTechnology = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    for y ∈ Sets.Year for t ∈ Sets.Technology for r ∈ Sets.Region_full
        for l ∈ Sets.Timeslice
            if Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t]*Params.CapacityFactor[r,t,l,y] != 0
                CapacityUsedByTechnologyEachTS[y,l,t,r] = value(VarPar.RateOfProductionByTechnology[y,l,t,"Power",r]) * Params.YearSplit[l,y]/(Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t]*Params.CapacityFactor[r,t,l,y])
            end
        end
        if sum(CapacityUsedByTechnologyEachTS[y,:,t,r]) != 0
            PeakCapacityByTechnology[r,t,y] = maximum(CapacityUsedByTechnologyEachTS[y,:,t,r])
        end
    end end end
    
    ### parameter output_capacity(*,*,*,*,*,*)
    colnames = [:Region, :Sector, :Technology, :Type, :PathwayScenario, :Year, :Value]
    output_capacity = DataFrame([name => [] for name ∈ colnames])

    df_peak_capacity = convert_jump_container_to_df(PeakCapacityByTechnology;dim_names=[:Region, :Technology, :Year])
    df_peak_capacity[!,:Type] .= "PeakCapacity"
    df_peak_capacity[!,:PathwayScenario] .= "$(Switch.emissionPathway)_$(Switch.emissionScenario)"

    df_new_capacity = convert_jump_container_to_df((value.(Vars.NewCapacity));dim_names=[:Year, :Technology, :Region])
    df_new_capacity[!,:Type] .= "NewCapacity"
    df_new_capacity[!,:PathwayScenario] .= "$(Switch.emissionPathway)_$(Switch.emissionScenario)"

    df_residual_capacity = convert_jump_container_to_df(Params.ResidualCapacity;dim_names=[:Region, :Technology, :Year])
    df_residual_capacity[!,:Type] .= "ResidualCapacity"
    df_residual_capacity[!,:PathwayScenario] .= "$(Switch.emissionPathway)_$(Switch.emissionScenario)"

    df_total_capacity = convert_jump_container_to_df(value.(Vars.TotalCapacityAnnual[:,tmp_techs,:]);dim_names=[:Year, :Technology, :Region])
    df_total_capacity[!,:Type] .= "TotalCapacity"
    df_total_capacity[!,:PathwayScenario] .= "$(Switch.emissionPathway)_$(Switch.emissionScenario)"

    dict_col_value = Dict()
    for se ∈ Sets.Sector
        tmp_techs = [t_ for t_ ∈ Sets.Technology if Params.TagTechnologyToSector[t_,se] != 0]
        if tmp_techs != []
            subset_peak_capacity = df_peak_capacity[in.(df_peak_capacity.Technology, Ref(tmp_techs)),:]
            subset_peak_capacity[!,:Sector] .= se
            merge_df(subset_peak_capacity, dict_col_value, output_capacity, colnames)

            subset_new_capacity = df_new_capacity[in.(df_new_capacity.Technology, Ref(tmp_techs)),:]
            subset_new_capacity[!,:Sector] .= se
            merge_df(subset_new_capacity, dict_col_value, output_capacity, colnames)

            subset_residual_capacity = df_residual_capacity[in.(df_residual_capacity.Technology, Ref(tmp_techs)),:]
            subset_residual_capacity[!,:Sector] .= se
            merge_df(subset_residual_capacity, dict_col_value, output_capacity, colnames)

            subset_total_capacity = df_total_capacity[in.(df_total_capacity.Technology, Ref(tmp_techs)),:]
            subset_total_capacity[!,:Sector] .= se
            merge_df(subset_total_capacity, dict_col_value, output_capacity, colnames)           
        end
    end

    ### parameter output_emissions(*,*,*,*,*,*,*)
    colnames = [:Region, :Sector, :Emission, :Technology, :Type, :PathwayScenario, :Year, :Value]
    output_emissions = DataFrame([name => [] for name in colnames])

    df_technology_emission = convert_jump_container_to_df(value.(Vars.AnnualTechnologyEmission);dim_names=[:Year, :Technology, :Emission, :Region])
    df_technology_emission[!,:Type] .= "Emissions"
    df_technology_emission[!,:PathwayScenario] .= "$(Switch.emissionPathway)_$(Switch.emissionScenario)"

    for se ∈ Sets.Sector 
        tmp_techs = [t_ for t_ in Sets.Technology if Params.TagTechnologyToSector[t_,se] != 0]
        if tmp_techs != []
            subset_df = df_technology_emission[in.(df_technology_emission.Technology, Ref(tmp_techs)),:]
            subset_df[!,:Sector] .= se
            merge_df(subset_df, dict_col_value, output_emissions, colnames)
        end
    end
    df_tmp = convert_jump_container_to_df(Params.AnnualExogenousEmission;dim_names=[:Region, :Emission, :Year])
    dict_col_value = Dict(:Sector=>"ExogenousEmissions", :Type=>"ExogenousEmissions",
                            :PathwayScenario=>"$(Switch.emissionPathway)_$(Switch.emissionScenario)", :Technology=>"ExogenousEmissions")
    merge_df(df_tmp, dict_col_value, output_emissions, colnames) 

    ### parameter output_model(*,*,*,*)
    colnames = [:Type, :PathwayScenario, :Pathway, :Scenario, :Value]
    output_model = DataFrame([name => [] for name in colnames])
    push!(output_model, [name => val for (name,val) in zip(colnames,["Objective Value","$(Switch.emissionPathway)_$(Switch.emissionScenario)","$(Switch.emissionPathway)","$(Switch.emissionScenario)", JuMP.objective_value(model)])])
    push!(output_model, [name => val for (name,val) in zip(colnames,["Elapsed Time","$(Switch.emissionPathway)_$(Switch.emissionScenario)","$(Switch.emissionPathway)","$(Switch.emissionScenario)", elapsed])])

    ### parameter z_maxgenerationperyear(r_full,t,y_full)
    z_maxgenerationperyear = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    for r ∈ Sets.Region_full for t ∈ Sets.Technology for y ∈ Sets.Year
        z_maxgenerationperyear[r,t,y] = Params.CapacityToActivityUnit[t]*maximum(Params.AvailabilityFactor[r,t,:])*sum(Params.CapacityFactor[r,t,:,y]/length(Sets.Timeslice))
    end end end

    ### parameter output_technology_costs_detailed
    colnames = [:Region, :Technology, :Fuel, :Type, :Unit, :Year, :Value]
    output_technology_costs_detailed = DataFrame([name => [] for name in colnames])

    cc = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    fc = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    vc_wo_fc = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    vc_w_fc = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    lc_em = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    lc_cap = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    lc_gen = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    lc_tot_w_em = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    lc_tot_wo_em = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)
    lc_tot_st = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Fuel)

    for r ∈ Sets.Region_full for t ∈ Sets.Technology for y ∈ Sets.Year
        for f ∈ Sets.Fuel 
            if Params.TagTechnologyToSector[t,"Power"] != 0 && sum(Params.InputActivityRatio[r,t,f,:,y]) != 0
                cc[r,t,y,f] = Params.CapitalCost[r,t,y]
                fc[r,t,y,f] = Params.FixedCost[r,t,y]
                if z_maxgenerationperyear[r,t,y] > 0
                    vc_wo_fc[r,t,y,f] = sum(Params.VariableCost[r,t,m,y] for m ∈ Sets.Mode_of_operation if Params.InputActivityRatio[r,t,f,m,y]>0)
                    vc_w_fc[r,t,y,f] = sum(Params.VariableCost[r,t,m,y] + Params.InputActivityRatio[r,t,f,m,y]*resourcecosts[r,f,y] for m ∈ Sets.Mode_of_operation if Params.InputActivityRatio[r,t,f,m,y]>0)
                    lc_em[r,t,y,f] = Params.EmissionsPenalty[r,"CO2",y]*sum(Params.InputActivityRatio[r,t,f,m,y]*Params.EmissionContentPerFuel[f,"CO2"]*Params.EmissionActivityRatio[r,t,m,"CO2",y] for m ∈ Sets.Mode_of_operation if Params.InputActivityRatio[r,t,f,m,y]>0)
                    lc_cap[r,t,y,f] = Params.CapitalCost[r,t,y]/(z_maxgenerationperyear[r,t,y]*Params.OperationalLife[t])
                    lc_gen[r,t,y,f] = sum(Params.VariableCost[r,t,m,y] + Params.InputActivityRatio[r,t,f,m,y]*resourcecosts[r,f,y] for m ∈ Sets.Mode_of_operation if Params.InputActivityRatio[r,t,f,m,y]>0)
                    lc_tot_w_em[r,t,y,f] = lc_cap[r,t,y,f] + lc_gen[r,t,y,f] + lc_em[r,t,y,f]
                    lc_tot_wo_em[r,t,y,f] = lc_cap[r,t,y,f] + lc_gen[r,t,y,f]
                end
            end
            if  Params.TagTechnologyToSector[t,"Storages"] != 0 && Params.OutputActivityRatio[r,t,"Power",2,y] != 0 && sum(Params.InputActivityRatio[r,t,f,:,y]) != 0
                lc_tot_st[r,t,y,f] = Params.VariableCost[r,t,1,y]*5
            end
        end
    end end end

    dict_col_value = Dict(:Type=>"Capital Costs", :Unit=>"MEUR/GW")

    df_tmp = convert_jump_container_to_df(cc;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)
    
    setindex!(dict_col_value, "Fixed Costs", :Type)
    df_tmp = convert_jump_container_to_df(fc;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Variable Costs [excl. Fuel Costs]", :Type)
    setindex!(dict_col_value, "MEUR/PJ", :Unit)
    df_tmp = convert_jump_container_to_df(vc_wo_fc;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Total]", :Type)
    df_tmp = convert_jump_container_to_df(lc_tot_st;dim_names=[:Region, :Technology, :Fuel, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)
    

    setindex!(dict_col_value, "Variable Costs [incl. Fuel Costs]", :Type)
    df_tmp = convert_jump_container_to_df(vc_w_fc;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Emissions]", :Type)
    df_tmp = convert_jump_container_to_df(lc_em;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Capex]", :Type)
    df_tmp = convert_jump_container_to_df(lc_cap;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Generation]", :Type)
    df_tmp = convert_jump_container_to_df(lc_gen;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Total]", :Type)
    df_tmp = convert_jump_container_to_df(lc_tot_w_em;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Total w/o Emissions]", :Type)
    df_tmp = convert_jump_container_to_df(lc_tot_wo_em;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Total]", :Type)
    setindex!(dict_col_value, "EUR/MWh", :Unit)
    df_tmp = convert_jump_container_to_df(lc_tot_w_em*3.6;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Total w/o Emissions]", :Type)
    df_tmp = convert_jump_container_to_df(lc_tot_wo_em*3.6;dim_names=[:Region, :Technology, :Year, :Fuel])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Total]", :Type)
    df_tmp = convert_jump_container_to_df(lc_tot_st*3.6;dim_names=[:Region, :Technology, :Fuel, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    dict_col_value = Dict(:Type=>"Carbon Price", :Unit=>"EUR/t CO2", :Technology=>"Carbon")
    df_tmp = convert_jump_container_to_df(Params.EmissionsPenalty[:,["CO2"],:];dim_names=[:Region, :Fuel, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    ## For Renewables, since they don"t have an input fuel

    cc = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    fc = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    vc_wo_fc = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    vc_w_fc = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    lc_cap = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    lc_gen = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    lc_tot_w_em = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    lc_tot_wo_em = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)

    for r ∈ Sets.Region_full for t ∈ Sets.Technology for y ∈ Sets.Year
        if Params.TagTechnologyToSector[t,"Power"] != 0 && sum(Params.InputActivityRatio[r,t,:,:,y]) == 0
            cc[r,t,y] = Params.CapitalCost[r,t,y]
            fc[r,t,y] = Params.FixedCost[r,t,y]
            if z_maxgenerationperyear[r,t,y] > 0
                vc_wo_fc[r,t,y] = Params.VariableCost[r,t,1,y]
                vc_w_fc[r,t,y] = Params.VariableCost[r,t,1,y]
                lc_cap[r,t,y] = Params.CapitalCost[r,t,y]/(z_maxgenerationperyear[r,t,y]*Params.OperationalLife[t])
                lc_gen[r,t,y] = Params.VariableCost[r,t,1,y]
                lc_tot_w_em[r,t,y] = lc_cap[r,t,y] + lc_gen[r,t,y]
                lc_tot_wo_em[r,t,y] = lc_cap[r,t,y] + lc_gen[r,t,y]
            end
        end
    end end end

    dict_col_value = Dict(:Type=>"Capital Costs", :Fuel=>"None", :Unit=>"MEUR/GW")

    df_tmp = convert_jump_container_to_df(cc;dim_names=[:Region, :Technology, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Fixed Costs", :Type)
    df_tmp = convert_jump_container_to_df(fc;dim_names=[:Region, :Technology, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Variable Costs [excl. Fuel Costs]", :Type)
    setindex!(dict_col_value, "MEUR/PJ", :Unit)
    df_tmp = convert_jump_container_to_df(vc_wo_fc;dim_names=[:Region, :Technology, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Variable Costs [incl. Fuel Costs]", :Type)
    df_tmp = convert_jump_container_to_df(vc_w_fc;dim_names=[:Region, :Technology, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Capex]", :Type)
    df_tmp = convert_jump_container_to_df(lc_cap;dim_names=[:Region, :Technology, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)
    
    setindex!(dict_col_value, "Levelized Costs [Generation]", :Type)
    df_tmp = convert_jump_container_to_df(lc_gen;dim_names=[:Region, :Technology, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Total w/o Emissions]", :Type)
    df_tmp = convert_jump_container_to_df(lc_tot_wo_em;dim_names=[:Region, :Technology, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    df_tmp[!,:Value] .= df_tmp[!,:Value]*3.6
    setindex!(dict_col_value, "EUR/MWh", :Unit)
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    setindex!(dict_col_value, "Levelized Costs [Total]", :Type)
    setindex!(dict_col_value, "MEUR/PJ", :Unit)
    df_tmp = convert_jump_container_to_df(lc_tot_w_em;dim_names=[:Region, :Technology, :Year])
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    df_tmp[!,:Value] .= df_tmp[!,:Value]*3.6
    setindex!(dict_col_value, "EUR/MWh", :Unit)
    merge_df(df_tmp, dict_col_value, output_technology_costs_detailed, colnames)

    ### parameter output_exogenous_costs
    colnames = [:Region, :Technology, :Type, :Year, :Value]
    output_exogenous_costs = DataFrame([name => [] for name in colnames])

    df_tmp = convert_jump_container_to_df(Params.CapitalCost[:,:,:];dim_names=[:Region, :Technology, :Year])
    df_tmp[!,:Type] .= "Capital Costs"
    select!(df_tmp,colnames)
    append!(output_exogenous_costs, df_tmp)

    df_tmp = convert_jump_container_to_df(Params.FixedCost[:,:,:];dim_names=[:Region, :Technology, :Year])
    df_tmp[!,:Type] .= "Fixed Costs"
    select!(df_tmp,colnames)
    append!(output_exogenous_costs, df_tmp)

    tmp= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Year)
    for r ∈ Sets.Region_full for t ∈ Sets.Technology for y ∈ Sets.Year
        tmp[r,t,y] = Params.VariableCost[r,t,1,y] + sum(Params.InputActivityRatio[r,t,f,1,y]*z_fuelcosts[f,y,r] for f ∈ Sets.Fuel)
    end end end
    df_tmp = convert_jump_container_to_df(tmp;dim_names=[:Region, :Technology, :Year])
    df_tmp[!,:Type] .= "Variable Costs"
    select!(df_tmp,colnames)
    append!(output_exogenous_costs, df_tmp)

    df_tmp = convert_jump_container_to_df(Params.EmissionsPenalty[:,["CO2"],:];dim_names=[:Region, :Technology, :Year])
    df_tmp[!,:Type] .= "Carbon Price"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_exogenous_costs, df_tmp)
    end

    ### parameter output_trade_capacity

    colnames = [:Region, :Region2, :Type, :Year, :Value]
    output_trade_capacity = DataFrame([name => [] for name in colnames])

    df_tmp = convert_jump_container_to_df(value.(Vars.TotalTradeCapacity[:,["Power"],:,:]);dim_names=[:Year, :Fuel, :Region, :Region2])
    df_tmp[!,:Type] .= "Power Transmissions Capacity"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_trade_capacity, df_tmp)
    end

    tmp= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full),length(Sets.Region_full)), Sets.Year, Sets.Region_full, Sets.Region_full)
    for y ∈ Sets.Year for r ∈ Sets.Region_full for rr ∈ Sets.Region_full
        tmp[y,r,rr] = Params.TradeCapacityGrowthCosts[r,rr,"Power"]*Params.TradeRoute[r,rr,"Power",y]
    end end end
    df_tmp = convert_jump_container_to_df(tmp;dim_names=[:Year, :Region, :Region2])
    df_tmp[!,:Type] .= "Transmission Expansion Costs in MEUR/GW"
    if !isempty(df_tmp)
         select!(df_tmp,colnames)
        append!(output_trade_capacity, df_tmp)
    end

    r2 = (length(Sets.Region_full) > 1 ? 2 : 1)
    df_tmp = DataFrame(Dict(:Region => "General", :Region2 => "General",:Type => "Transmission Expansion Costs in MEUR/GW/km",:Year => "General",:Value => Params.TradeCapacityGrowthCosts[Sets.Region_full[1],Sets.Region_full[r2],"Power"]))
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_trade_capacity, df_tmp)
    end

    ### parameters SelfSufficiencyRate,ElectrificationRate,output_other
    SelfSufficiencyRate = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Year)), Sets.Region_full, Sets.Year)
    ElectrificationRate = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Sector),length(Sets.Year)), Sets.Sector, Sets.Year)
    
    for y ∈ Sets.Year
        for r ∈ Sets.Region_full 
            SelfSufficiencyRate[r,y] = VarPar.ProductionAnnual[y,"Power",r]/(Params.SpecifiedAnnualDemand[r,"Power",y]+VarPar.UseAnnual[y,"Power",r])
        end
        for se ∈ Sets.Sector
            if sum(( Params.TagDemandFuelToSector[f,se]>0 ? Params.TagDemandFuelToSector[f,se]*VarPar.ProductionAnnual[y,f,r] : 0) for f ∈ Sets.Fuel for r ∈ Sets.Region_full ) > 0
                ElectrificationRate[se,y] = sum(Params.TagDemandFuelToSector[f,se]*Params.TagElectricTechnology[t]*value(Vars.ProductionByTechnologyAnnual[y,t,f,r])  for f ∈ Sets.Fuel for t ∈ Sets.Technology for r ∈ Sets.Region_full if value(Vars.ProductionByTechnologyAnnual[y,t,f,r]) > 0)/sum(Params.TagDemandFuelToSector[f,se]*VarPar.ProductionAnnual[y,f,r] for f ∈ Sets.Fuel for r ∈ Sets.Region_full if Params.TagDemandFuelToSector[f,se]>0)
            end
        end
    end

    FinalEnergy = [
    "Power",
    "Biomass",
    "Hardcoal",
    "Lignite",
    "H2",
    "Gas_Natural",
    "Oil",
    "Nuclear"]

    notEU27 = [
    "World",
    "CH",
    "NO",
    "NONEU_Balkan",
    "TR",
    "UK"]

    EU27 = setdiff(Sets.Region_full, notEU27)

    FinalDemandSector =[
        "Power",
        "Transportation",
        "Industry",
        "Buildings",
        "CHP"]

    colnames = [:Type, :Region, :Dim1, :Dim2, :Year, :Value]
    output_other = DataFrame([name => [] for name in colnames])

    df_tmp = convert_jump_container_to_df(SelfSufficiencyRate[:,:];dim_names=[:Region, :Year])
    df_tmp[!,:Type] .= "SelfSufficiencyRate"
    df_tmp[!,:Dim1] .= "X"
    df_tmp[!,:Dim2] .= "X"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_other, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(ElectrificationRate[:,:];dim_names=[:Dim1, :Year])
    df_tmp[!,:Type] .= "ElectrificationRate"
    df_tmp[!,:Region] .= "Total"
    df_tmp[!,:Dim2] .= "X"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_other, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(value.(Vars.UseByTechnologyAnnual[:,:,:,:])/3.6;dim_names=[:Year, :Dim1, :Dim2, :Region])
    df_tmp[!,:Type] .= "FinalEnergyConsumption"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_other, df_tmp)
    end

    for f ∈ Sets.Fuel
        if f ∈ Params.TagTechnologyToSubsets["Transport"]
            df_tmp = convert_jump_container_to_df(Params.SpecifiedAnnualDemand[:,[f],:];dim_names=[:Region, :Dim2, :Year])
        else
            df_tmp = convert_jump_container_to_df(Params.SpecifiedAnnualDemand[:,[f],:]/3.6;dim_names=[:Region, :Dim2, :Year])
        end
        if !isempty(df_tmp)
            df_tmp[!,:Type] .= "FinalEnergyConsumption"
            df_tmp[!,:Dim1] .= "InputDemand"
            select!(df_tmp,colnames)
            append!(output_other, df_tmp)
        end
    end

    tmp= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full)), Sets.Year, Sets.Region_full)
    tmp2= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year)), Sets.Year)
    tmp3= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year)), Sets.Year)
    for y ∈ Sets.Year for r ∈ Sets.Region_full
        tmp[y,r] = (VarPar.UseAnnual[y,"Power",r] + Params.SpecifiedAnnualDemand[r,"Power",y]) /  (sum(VarPar.UseAnnual[y,x,r] for x ∈ FinalEnergy)+ Params.SpecifiedAnnualDemand[r,"Power",y])
        tmp2[y] += (VarPar.UseAnnual[y,"Power",r] + Params.SpecifiedAnnualDemand[r,"Power",y])
        tmp3[y] +=   (sum(VarPar.UseAnnual[y,x,r] for x ∈ FinalEnergy)+ Params.SpecifiedAnnualDemand[r,"Power",y])
    end end
    df_tmp = convert_jump_container_to_df(tmp;dim_names=[:Year, :Region])
    df_tmp[!,:Type] .= "ElectricityShareOfFinalEnergy"
    df_tmp[!,:Dim1] .= "X"
    df_tmp[!,:Dim2] .= "X"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_other, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(tmp2./tmp3;dim_names=[:Year])
    df_tmp[!,:Type] .= "ElectricityShareOfFinalEnergy"
    df_tmp[!,:Region] .= "Total"
    df_tmp[!,:Dim1] .= "X"
    df_tmp[!,:Dim2] .= "X"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_other, df_tmp)
    end

    ### parameter output_energydemandstatistics
    colnames = [:Type, :Sector, :Region, :Fuel, :Year, :Value]
    output_energydemandstatistics = DataFrame([name => [] for name in colnames])

    ## Final Energy for all regions per sector
    fed= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel),length(Sets.Region_full),length(Sets.Sector)), Sets.Year, Sets.Fuel, Sets.Region_full, Sets.Sector)
    for se ∈ FinalDemandSector for y ∈ Sets.Year for f ∈ Sets.Fuel for r ∈ Sets.Region_full
        if f ∉ ["Area_Rooftop_Residential","Area_Rooftop_Commercial","Heat_District"]
            fed[y,f,r,se] = sum(value(Vars.UseByTechnologyAnnual[y,t,f,r]) for t ∈ Sets.Technology if Params.TagTechnologyToSector[t,se] != 0)/3.6
        end
    end end end end

    df_tmp = convert_jump_container_to_df(fed;dim_names=[:Year, :Fuel, :Region, :Sector])
    df_tmp[!,:Type] .= "Final Energy Demand [TWh]"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    df_tmp = convert_jump_container_to_df(Params.SpecifiedAnnualDemand[:,["Power"],:]/3.6;dim_names=[:Region, :Fuel, :Year])
    df_tmp[!,:Type] .= "Final Energy Demand [TWh]"
    df_tmp[!,:Sector] .= "Exogenous"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_energydemandstatistics, df_tmp)
    end

    ## Final Energy per sector regional aggregates

    df_tmp = convert_jump_container_to_df(fed;dim_names=[:Year, :Fuel, :Region, :Sector])
    df_tmp1 = combine(groupby(df_tmp, [:Year, :Fuel, :Sector]), :Value=> sum; renamecols=false)
    df_tmp1[!,:Type] .= "Final Energy Demand [TWh]"
    df_tmp1[!,:Region] .= "Total"
    select!(df_tmp1,colnames)
    append!(output_energydemandstatistics, df_tmp1)

    df_tmp2 = df_tmp[in(EU27).(df_tmp.Region),:]
    df_tmp2 = combine(groupby(df_tmp2, [:Year, :Fuel, :Sector]), :Value=> sum; renamecols=false)
    df_tmp2[!,:Type] .= "Final Energy Demand [TWh]"
    df_tmp2[!,:Region] .= "EU27"
    select!(df_tmp2,colnames)
    append!(output_energydemandstatistics, df_tmp2)

    df_tmp = convert_jump_container_to_df(Params.SpecifiedAnnualDemand[:,["Power"],:]/3.6;dim_names=[:Region, :Fuel, :Year])
    df_tmp1 = combine(groupby(df_tmp, [:Fuel, :Year]), :Value=> sum; renamecols=false)
    df_tmp1[!,:Type] .= "Final Energy Demand [TWh]"
    df_tmp1[!,:Region] .= "Total"
    df_tmp1[!,:Sector] .= "Exogenous"
    select!(df_tmp1,colnames)
    append!(output_energydemandstatistics, df_tmp1)

    df_tmp2 = df_tmp[in(EU27).(df_tmp.Region),:]
    df_tmp2 = combine(groupby(df_tmp2, [:Fuel, :Year]), :Value=> sum; renamecols=false)
    df_tmp2[!,:Type] .= "Final Energy Demand [TWh]"
    df_tmp2[!,:Region] .= "EU27"
    df_tmp2[!,:Sector] .= "Exogenous"
    select!(df_tmp2,colnames)
    append!(output_energydemandstatistics, df_tmp2)

    ## Final Energy aggregation across region & sector
    tmp= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel)), Sets.Year, Sets.Fuel)
    tmp2= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel)), Sets.Year, Sets.Fuel)
    tmp_p= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel)), Sets.Year, Sets.Fuel)
    tmp2_p= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel)), Sets.Year, Sets.Fuel)
    for f ∈ Sets.Fuel for y ∈ Sets.Year
        tmp[y,f] = sum(fed[y,f,r,se] for r ∈ Sets.Region_full for se ∈ Sets.Sector) + sum(Params.SpecifiedAnnualDemand[r,"Power",y]/3.6 for r ∈ Sets.Region_full)
        tmp2[y,f] = sum(fed[y,f,r,se] for r ∈ EU27 for se ∈ Sets.Sector) + sum(Params.SpecifiedAnnualDemand[r,"Power",y]/3.6 for r ∈ EU27)
        tmp_p[y,f] = tmp[y,f]/sum(tmp[y,:])
        tmp2_p[y,f] = tmp2[y,f]/sum(tmp2[y,:])
    end end
    df_tmp = convert_jump_container_to_df(tmp;dim_names=[:Year, :Fuel])
    df_tmp[!,:Type] .= "Final Energy Demand [TWh]"
    df_tmp[!,:Region] .= "Total"
    df_tmp[!,:Sector] .= "Total"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    df_tmp = convert_jump_container_to_df(tmp2;dim_names=[:Year, :Fuel])
    df_tmp[!,:Type] .= "Final Energy Demand [TWh]"
    df_tmp[!,:Region] .= "EU27"
    df_tmp[!,:Sector] .= "Total"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    ## Share of Fuel in Final Energy
    df_tmp = convert_jump_container_to_df(tmp_p;dim_names=[:Year, :Fuel])
    df_tmp[!,:Type] .= "Final Energy Demand [% of Total]"
    df_tmp[!,:Region] .= "Total"
    df_tmp[!,:Sector] .= "Total"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    df_tmp = convert_jump_container_to_df(tmp2_p;dim_names=[:Year, :Fuel])
    df_tmp[!,:Type] .= "Final Energy Demand [% of Total]"
    df_tmp[!,:Region] .= "EU27"
    df_tmp[!,:Sector] .= "Total"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    ## Primary Energy Demand

    pe= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel),length(Sets.Region_full)), Sets.Year, Sets.Fuel, Sets.Region_full)
    pe_p= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel),length(Sets.Region_full)), Sets.Year, Sets.Fuel, Sets.Region_full)
    for y ∈ Sets.Year for f ∈ Sets.Fuel for r ∈ Sets.Region_full
        if f ∉ ["Area_Rooftop_Residential","Area_Rooftop_Commercial"]
            pe[y,f,r] = sum(value(Vars.ProductionByTechnologyAnnual[y,t,f,r]) for t ∈ Sets.Technology if sum(Params.InputActivityRatio[r,t,:,:,y]) == 0)/3.6
            pe_p[y,f,r] = pe[y,f,r] / sum(pe[y,:,r])
        end
    end end end

    df_tmp = convert_jump_container_to_df(pe;dim_names=[:Year, :Fuel, :Region])
    df_tmp1 = df_tmp
    df_tmp[!,:Type] .= "Primary Energy [TWh]"
    df_tmp[!,:Sector] .= "Total"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    df_tmp2 = combine(groupby(df_tmp1, [:Year, :Fuel]), :Value=> sum; renamecols=false)
    df_tmp2[!,:Type] .= "Primary Energy [TWh]"
    df_tmp2[!,:Sector] .= "Total"
    df_tmp2[!,:Region] .= "Total"
    select!(df_tmp2,colnames)
    append!(output_energydemandstatistics, df_tmp2)

    df_tmp2 = df_tmp1[in(EU27).(df_tmp1.Region),:]
    df_tmp2 = combine(groupby(df_tmp2, [:Year, :Fuel]), :Value=> sum; renamecols=false)
    df_tmp2[!,:Type] .= "Primary Energy [TWh]"
    df_tmp2[!,:Sector] .= "Total"
    df_tmp2[!,:Region] .= "EU27"
    select!(df_tmp2,colnames)
    append!(output_energydemandstatistics, df_tmp2)

    ## Primary Energy Demand Shares
    df_tmp = convert_jump_container_to_df(pe_p;dim_names=[:Year, :Fuel, :Region])
    df_tmp1 = df_tmp
    df_tmp[!,:Type] .= "Primary Energy [% of Total]"
    df_tmp[!,:Sector] .= "Total"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    df_tmp2 = combine(groupby(df_tmp1, [:Year, :Fuel]), :Value=> sum; renamecols=false)
    df_tmp2[!,:Type] .= "Primary Energy [% of Total]"
    df_tmp2[!,:Sector] .= "Total"
    df_tmp2[!,:Region] .= "Total"
    select!(df_tmp2,colnames)
    append!(output_energydemandstatistics, df_tmp2)

    df_tmp2 = df_tmp1[in(EU27).(df_tmp1.Region),:]
    df_tmp2 = combine(groupby(df_tmp2, [:Year, :Fuel]), :Value=> sum; renamecols=false)
    df_tmp2[!,:Type] .= "Primary Energy [% of Total]"
    df_tmp2[!,:Sector] .= "Total"
    df_tmp2[!,:Region] .= "EU27"
    select!(df_tmp2,colnames)
    append!(output_energydemandstatistics, df_tmp2)

    ## Share of Fuel in Electricity Mix

    eg= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel),length(Sets.Region_full)), Sets.Year, Sets.Fuel, Sets.Region_full)
    eg_p= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel),length(Sets.Region_full)), Sets.Year, Sets.Fuel, Sets.Region_full)
    eg_s= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full)), Sets.Year, Sets.Region_full)
    eg_w= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full)), Sets.Year, Sets.Region_full)
    eg_h= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full)), Sets.Year, Sets.Region_full)
    eg_s_p= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full)), Sets.Year, Sets.Region_full)
    eg_w_p= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full)), Sets.Year, Sets.Region_full)
    eg_h_p= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full)), Sets.Year, Sets.Region_full)
    eg_o_p= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full)), Sets.Year, Sets.Region_full)

    for y ∈ Sets.Year for r ∈ Sets.Region_full
        div= sum(value(Vars.ProductionByTechnologyAnnual[y,t,"Power",r]) for t ∈ Sets.Technology if Params.TagTechnologyToSector[t,"Storages"]==0)/3.6

        eg_temp = Dict{Tuple, Float64}()
        for t in Sets.Technology
            if Params.TagTechnologyToSector[t, "Storages"] == 0
                for f in Maps.Tech_Fuel[t]
                    for m in Maps.Tech_MO[t]
                        if Params.InputActivityRatio[r, t, f, m, y] != 0
                            for l in Sets.Timeslice
                                key = (y, f, r)
                                eg_temp[key] = get(eg_temp, key, 0.0) + value(VarPar.RateOfProductionByTechnologyByMode[y, l, t, m, "Power", r]) * Params.YearSplit[l, y] / 3.6
                            end
                        end
                    end
                end
            end
        end

        for (key, val) in eg_temp
            eg[key...] = val
            eg_p[key...] = val / div
        end

        eg_s[y,r] = sum(value(Vars.ProductionByTechnologyAnnual[y,t,"Power",r]) for t ∈ Params.TagTechnologyToSubsets["Solar"]) /3.6
        eg_w[y,r] = sum(value(Vars.ProductionByTechnologyAnnual[y,t,"Power",r]) for t ∈ Params.TagTechnologyToSubsets["Wind"]) /3.6
        eg_h[y,r] = sum(value(Vars.ProductionByTechnologyAnnual[y,t,"Power",r]) for t ∈ Params.TagTechnologyToSubsets["Hydro"]) /3.6
        eg_s_p[y,r] = eg_s[y,r]/div
        eg_w_p[y,r] = eg_w[y,r]/div
        eg_h_p[y,r] = eg_h[y,r]/div
        eg_o_p[y,r] = 1 - sum(eg_p[y,:,r]) - eg_s_p[y,r] - eg_w_p[y,r] - eg_h_p[y,r]
    end end

    df_tmp = convert_jump_container_to_df(eg;dim_names=[:Year, :Fuel, :Region])
    df_tmp[!,:Type] .= "Electricity Generation [TWh]"
    df_tmp[!,:Sector] .= "Power"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    df_tmp = convert_jump_container_to_df(eg_s;dim_names=[:Year, :Region])
    df_tmp[!,:Type] .= "Electricity Generation [TWh]"
    df_tmp[!,:Sector] .= "Power"
    df_tmp[!,:Fuel] .= "Solar"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_energydemandstatistics, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(eg_w;dim_names=[:Year, :Region])
    df_tmp[!,:Type] .= "Electricity Generation [TWh]"
    df_tmp[!,:Sector] .= "Power"
    df_tmp[!,:Fuel] .= "Wind"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_energydemandstatistics, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(eg_h;dim_names=[:Year, :Region])
    df_tmp[!,:Type] .= "Electricity Generation [TWh]"
    df_tmp[!,:Sector] .= "Power"
    df_tmp[!,:Fuel] .= "Hydro"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_energydemandstatistics, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(eg_p;dim_names=[:Year, :Fuel, :Region])
    df_tmp[!,:Type] .= "Electricity Mix [%]"
    df_tmp[!,:Sector] .= "Power"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    df_tmp = convert_jump_container_to_df(eg_s_p;dim_names=[:Year, :Region])
    df_tmp[!,:Type] .= "Electricity Mix [%]"
    df_tmp[!,:Sector] .= "Power"
    df_tmp[!,:Fuel] .= "Solar"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_energydemandstatistics, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(eg_w_p;dim_names=[:Year, :Region])
    df_tmp[!,:Type] .= "Electricity Mix [%]"
    df_tmp[!,:Sector] .= "Power"
    df_tmp[!,:Fuel] .= "Wind"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_energydemandstatistics, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(eg_h_p;dim_names=[:Year, :Region])
    df_tmp[!,:Type] .= "Electricity Mix [%]"
    df_tmp[!,:Sector] .= "Power"
    df_tmp[!,:Fuel] .= "Hydro"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_energydemandstatistics, df_tmp)
    end

    df_tmp = convert_jump_container_to_df(eg_o_p;dim_names=[:Year, :Region])
    df_tmp[!,:Type] .= "Electricity Mix [%]"
    df_tmp[!,:Sector] .= "Power"
    df_tmp[!,:Fuel] .= "Other"
    if !isempty(df_tmp)
        select!(df_tmp,colnames)
        append!(output_energydemandstatistics, df_tmp)
    end

    ## Imports as Share of Primary Energy

    ispe= JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Fuel),length(Sets.Region_full)), Sets.Year, Sets.Fuel, Sets.Region_full)

    for y ∈ Sets.Year for r ∈ Sets.Region_full
        for f ∈ Sets.Fuel
            if sum(Params.OutputActivityRatio[r,t,f,m,y] for t ∈ Params.TagTechnologyToSubsets["ImportTechnology"] for m ∈ Sets.Mode_of_operation) != 0
                ispe[y,f,r] = (sum(value(Vars.ProductionByTechnologyAnnual[y,t,f,r]) for t ∈ Params.TagTechnologyToSubsets["ImportTechnology"])/3.6)/sum(pe[y,:,r])
            end
        end
    end end

    df_tmp = convert_jump_container_to_df(ispe;dim_names=[:Year, :Fuel, :Region])
    df_tmp1 = df_tmp
    df_tmp[!,:Type] .= "Import Share of Primary Energy [%]"
    df_tmp[!,:Sector] .= "Total"
    select!(df_tmp,colnames)
    append!(output_energydemandstatistics, df_tmp)

    df_tmp2 = combine(groupby(df_tmp1, [:Year, :Fuel]), :Value=> sum; renamecols=false)
    df_tmp2[!,:Type] .= "Import Share of Primary Energy [%]"
    df_tmp2[!,:Region] .= "Total"
    df_tmp2[!,:Sector] .= "Total"
    select!(df_tmp2,colnames)
    append!(output_energydemandstatistics, df_tmp2)

    df_tmp2 = df_tmp1[in(EU27).(df_tmp1.Region),:]
    df_tmp2 = combine(groupby(df_tmp2, [:Year, :Fuel]), :Value=> sum; renamecols=false)
    df_tmp2[!,:Type] .= "Import Share of Primary Energy [%]"
    df_tmp2[!,:Region] .= "EU27"
    df_tmp2[!,:Sector] .= "Total"
    select!(df_tmp2,colnames)
    append!(output_energydemandstatistics, df_tmp2)

    ####
    #### Excel Output Sheet Definition and Export of GDX
    ####

    CSV.write(joinpath(Switch.resultdir,"output_production_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_energy_balance[output_energy_balance.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_annual_production_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_energy_balance_annual[output_energy_balance_annual.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_capacity_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_capacity[output_capacity.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_emission_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_emissions[output_emissions.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_other_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_other[output_other.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_model_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_model[output_model.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_technology_costs_detailed_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_technology_costs_detailed[output_technology_costs_detailed.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_exogenous_costs_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_exogenous_costs[output_exogenous_costs.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_trade_capacity_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_trade_capacity[output_trade_capacity.Value .!= 0, :])
    CSV.write(joinpath(Switch.resultdir,"output_energydemandstatistics_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_energydemandstatistics[output_energydemandstatistics.Value .!= 0, :])
end