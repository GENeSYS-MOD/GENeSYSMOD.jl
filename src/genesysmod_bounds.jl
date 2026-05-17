# GENeSYS-MOD v3.1 [Global Energy System Model]  ~ March 2022
#
# #############################################################
#
# Copyright 2020 Technische Universität Berlin and DIW Berlin
#
# Licensed under the Apache License, Version 2.0 (the "License");
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
Internal function used in the run process to modify batches of input data.
"""
function genesysmod_bounds(model,Sets,Params, Vars,Settings,Switch,Maps)

    #
    # ####### Default Values #############
    #

    sub=["Power", "Heat_Low_Residential", "Heat_Low_Industrial", "Heat_Medium_Industrial",
     "Heat_High_Industrial"]

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for t ∈ intersect(Sets.Technology,Params.TagTechnologyToSubsets["Renewables"])
            Params.RETagTechnology[r,t,y] = 1
        end
        for f ∈ intersect(Sets.Fuel,sub)
            Params.RETagFuel[r,f,y] = 1
        end
    end end

    #
    # ####### Default Values #############
    #
    
    for r ∈ Sets.Region_full
        for t ∈ Sets.Technology
            for y ∈ Sets.Year
                if Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] == 0
                        Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] = 999999
                end
            end
        end
    end

#=     for r ∈ Sets.Region_full
        for t ∈ Sets.Technology
            Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] = 999999
    end end  =#

    for r ∈ Sets.Region_full
        for t ∈ setdiff(Params.TagTechnologyToSubsets["FossilFuelGeneration"],["R_Nuclear"])
            if Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] == 999999
                Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] = 0
            end
    end end

    f="ETS"
    for r ∈ Sets.Region_full
        for rr ∈ Sets.Region_full
            if Params.TradeCosts[f,r,rr] == 0
                Params.TradeCosts[f,r,rr] = 0.01
    end end end

    f = "H2"
    for r ∈ Sets.Region_full, rr ∈ Sets.Region_full
        Params.TradeCosts[f,r,rr] = 0.01
    end

    for r ∈ Sets.Region_full
        for t ∈ Sets.Technology
            for m ∈ Sets.Mode_of_operation
                for y ∈ Sets.Year
                    if Params.VariableCost[r,t,m,y]==0
                        Params.VariableCost[r,t,m,y] = 0.01
    end end end end end 

    #
    # ####### Dummy-Technologies [enable for test purposes, if model runs infeasible] #############
    #

    if Switch.switch_infeasibility_tech == 1
        Params.TagTechnologyToSector[Params.TagTechnologyToSubsets["DummyTechnology"],"Infeasibility"] .= 1
        Params.AvailabilityFactor[:,Params.TagTechnologyToSubsets["DummyTechnology"],:] .= 0

        output_activity_dict = Dict(
            "Infeasibility_HLI" => "Heat_Low_Industrial",
            "Infeasibility_HMI" => "Heat_Medium_Industrial",
            "Infeasibility_HHI" => "Heat_High_Industrial",
            "Infeasibility_HRI" => "Heat_Low_Residential",
            "Infeasibility_Power" => "Power",
            "Infeasibility_Mob_Passenger" => "Mobility_Passenger",
            "Infeasibility_Mob_Freight" => "Mobility_Freight")

        for (k,v) ∈ output_activity_dict
            try
                Params.OutputActivityRatio[:,k,v,1,:] .= 1
            catch
               # Error is ignored intentionally
            end
        end
        
        Params.CapacityToActivityUnit[Params.TagTechnologyToSubsets["DummyTechnology"]] .= 31.56
        Params.TotalAnnualMaxCapacity[:,Params.TagTechnologyToSubsets["DummyTechnology"],:] .= 999999
        Params.FixedCost[:,Params.TagTechnologyToSubsets["DummyTechnology"],:] .= 999
        Params.CapitalCost[:,Params.TagTechnologyToSubsets["DummyTechnology"],:] .= 999
        Params.VariableCost[:,Params.TagTechnologyToSubsets["DummyTechnology"],:,:] .= 999
        Params.AvailabilityFactor[:,Params.TagTechnologyToSubsets["DummyTechnology"],:] .= 1
        Params.CapacityFactor[:,Params.TagTechnologyToSubsets["DummyTechnology"],:,:] .= 1 
        Params.OperationalLife[Params.TagTechnologyToSubsets["DummyTechnology"]] .= 1 
        Params.EmissionActivityRatio[:,Params.TagTechnologyToSubsets["DummyTechnology"],:,:,:] .= 0

    end

    #
    # ####### Bounds for non-supply technologies #############
    #

    for r ∈ Sets.Region_full, y ∈ Sets.Year
        for t ∈ intersect(Sets.Technology, vcat(Params.TagTechnologyToSubsets["Transformation"],Params.TagTechnologyToSubsets["FossilPower"],Params.TagTechnologyToSubsets["FossilFuelGeneration"],
        Params.TagTechnologyToSubsets["CHP"],Params.TagTechnologyToSubsets["Transport"],Params.TagTechnologyToSubsets["ImportTechnology"],Params.TagTechnologyToSubsets["Biomass"],"P_Biomass"))
            if t ∉ ["P_Nuclear"]
                Params.TotalAnnualMaxCapacity[r,t,y] = 999999
            end
        end
    end

    for r ∈ Sets.Region_full
        for t ∈ Params.TagTechnologyToSubsets["ImportTechnology"]
            for y ∈ Sets.Year
                Params.AvailabilityFactor[r,t,y] = 1
    end end end

    for r ∈ Sets.Region_full
        for t ∈ Sets.Technology
            if t ∈ Params.TagTechnologyToSubsets["ImportTechnology"]
                for l ∈ Sets.Timeslice
                    for y ∈ Sets.Year
                        Params.CapacityFactor[r,t,l,y] = 1
                end end
    end end end

    for r ∈ Sets.Region_full
        for t ∈ Params.TagTechnologyToSubsets["ImportTechnology"]
                Params.OperationalLife[t] = 1    
        end
    end

    for r ∈ Sets.Region_full
        for t ∈ Params.TagTechnologyToSubsets["ImportTechnology"]
            Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] = 999999
    end end

   # ####### No new capacity construction in 2015 #############
    #
    if Switch.switch_dispatch == 0
        for r ∈ Sets.Region_full
            if length(Sets.Year) != 1
                for t ∈ intersect(Sets.Technology, vcat(Params.TagTechnologyToSubsets["Transformation"],Params.TagTechnologyToSubsets["PowerSupply"], Params.TagTechnologyToSubsets["SectorCoupling"], Params.TagTechnologyToSubsets["StorageDummies"]))
                    JuMP.fix(Vars.NewCapacity[Switch.StartYear,t,r],0; force=true)
                end
            end
            for t ∈ intersect(Sets.Technology, vcat(Params.TagTechnologyToSubsets["Biomass"],Params.TagTechnologyToSubsets["CHP"],["HLR_Gas_Boiler","HLI_Gas_Boiler","HHI_BF_BOF",
                "HHI_Bio_BF_BOF","HHI_Scrap_EAF","HHI_DRI_EAF", "D_Gas_Methane"]))
                if JuMP.is_fixed(Vars.NewCapacity[Switch.StartYear,t,r])
                    JuMP.unfix(Vars.NewCapacity[Switch.StartYear,t,r])
                end
            end
        end

        if "CHP" ∈ Sets.Sector
            for t ∈ Sets.Technology 
                if Params.TagTechnologyToSector[t,"CHP"] == 1
                    for r ∈ Sets.Region_full
                        if JuMP.is_fixed(model[:NewCapacity][Switch.StartYear,t,r])
                            JuMP.unfix(model[:NewCapacity][Switch.StartYear,t,r])
                        end
                    end
                end
            end
        end
    end


    ### ReserveMargin initialization 

    for r ∈ Sets.Region_full for t ∈ Sets.Technology for y ∈ Sets.Year
        if ((max(Params.TotalAnnualMaxCapacity[r,t,y], Params.ResidualCapacity[r,t,y]) >0 )
            && (max(Params.TotalAnnualMaxCapacity[r,t,y], Params.ResidualCapacity[r,t,y]) < 999999))
            Params.TotalAnnualMaxCapacity[r,t,y] = max(Params.TotalAnnualMaxCapacity[r,t,y], Params.ResidualCapacity[r,t,y])
        end
    end end end

    ### Adds (negligible) variable costs to transport technologies, since they only had fuel costs before
    ### This is to combat strange "curtailment" effects of some transportation technologies
    for r ∈ Sets.Region_full for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["Transport"])
        Params.VariableCost[r,t,:,:] .= 0.09
    end end

    #
    # ####### Dispatch and Curtailment #############
    #
    subs = vcat(intersect(Sets.Technology, Params.TagTechnologyToSubsets["Solar"]), intersect(Sets.Technology, Params.TagTechnologyToSubsets["Wind"]), ["RES_Hydro_Small"])
    Params.TagDispatchableTechnology[subs] = zeros(length(intersect(Sets.Technology,subs)))
    Params.CurtailmentCostFactor == 0

    for r ∈ Sets.Region_full, t ∈ intersect(Sets.Technology,Params.TagTechnologyToSubsets["Solar"])
        Params.AvailabilityFactor[r,t,:] .= 1
    end

    # for e ∈ Sets.Emission for s ∈ Sets.Sector for y ∈ Sets.Year
    #     if Params.AnnualSectoralEmissionLimit[e,s,y] == 0
    #         Params.AnnualSectoralEmissionLimit[e,s,y] = 999999
    #     end
    # end end end

    #
    # ####### CCS #############
    #

    if Switch.switch_ccs == 1
        for r ∈ Sets.Region_full for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["CCS"])
            Params.AvailabilityFactor[r,t,:] .= 0
            Params.TotalAnnualMaxCapacity[r,t,:] .= 99999
            Params.TotalTechnologyAnnualActivityUpperLimit[r,t,:] .= 99999
        end end

        for y ∈ Sets.Year for r ∈ Sets.Region_full 
            if (y > 2020) && (Params.RegionalCCSLimit[r] > 0)
                for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["CCS"])
                    Params.AvailabilityFactor[r,t,y] = 0.95
                end
            else 
                for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["CCS"])
                    Params.TotalAnnualMaxCapacity[r,t,y] = 0
                    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] = 0
                    for f ∈ Maps.Tech_Fuel[t]
                        JuMP.fix(Vars.ProductionByTechnologyAnnual[y,t,f,r],0; force=true)
                    end
                end 
            end
        end end 

        Params.TotalAnnualMaxCapacity[Sets.Region_full,"A_Air",:] .= 99999
        Params.TotalTechnologyAnnualActivityUpperLimit[Sets.Region_full,"A_Air",:] .= 99999

        for t ∈ intersect(Sets.Technology, ["X_DAC_HT","X_DAC_LT"])
            Params.EmissionActivityRatio[Sets.Region_full,t,:,:,:] .= -1
        end


    else
        for y ∈ Sets.Year for r ∈ Sets.Region_full for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["CCS"])
            Params.AvailabilityFactor[r,t,y] = 0
            Params.TotalAnnualMaxCapacity[r,t,y] = 0
            for f ∈ Maps.Tech_Fuel[t]
                JuMP.fix(Vars.ProductionByTechnologyAnnual[y,t,f,r], 0; force = true)
            end
        end end end
    end
    #
    # ####### Ramping ############
    #
    #$ontext
    if Switch.switch_ramping == 1
        for r ∈ Sets.Region_full for y ∈ Sets.Year
#=             Params.RampingUpFactor["RES_Hydro_Large",y] = 0.25
            Params.RampingUpFactor["P_Nuclear",y] = 0.01
            Params.RampingDownFactor["RES_Hydro_Large",y] = 0.25
            Params.RampingDownFactor["P_Nuclear",y] = 0.01
            Params.ProductionChangeCost[r,"RES_Hydro_Large",y] = 50/3.6
            Params.ProductionChangeCost[r,"P_Nuclear",y] = 200/3.6
            for t ∈ Params.TagTechnologyToSubsets["PowerBiomass"]
                Params.RampingUpFactor[t,y] = 0.04
                Params.RampingDownFactor[t,y] = 0.04
                Params.ProductionChangeCost[r,t,y] = 100/3.6
            end
            for t ∈ Params.TagTechnologyToSubsets["FossilPower"]
                Params.RampingUpFactor[t,y] = 0.04
                Params.RampingDownFactor[t,y] = 0.04
                Params.ProductionChangeCost[r,t,y] = 100/3.6
            end
            for t ∈ Params.TagTechnologyToSubsets["Coal"]
                Params.RampingUpFactor[t,y] = 0.02
                Params.RampingDownFactor[t,y] = 0.02
                Params.ProductionChangeCost[r,t,y] = 50/3.6
            end
            for t ∈ Params.TagTechnologyToSubsets["Gas"]
                Params.RampingUpFactor[t,y] = 0.2
                Params.RampingDownFactor[t,y] = 0.2
                Params.ProductionChangeCost[r,t,y] = 20/3.6
            end
            for t ∈ Params.TagTechnologyToSubsets["HeatSlowRamper"]
                Params.RampingUpFactor[t,y] = 0.1
                Params.RampingDownFactor[t,y] = 0.1
                Params.ProductionChangeCost[r,t,y] = 100/3.6
            end
            for t ∈ Params.TagTechnologyToSubsets["HeatQuickRamper"]
                Params.RampingUpFactor[t,y] = 0
                Params.RampingDownFactor[t,y] = 0
                Params.ProductionChangeCost[r,t,y] = 0
            end =#
            for l ∈ Sets.Timeslice
                Params.MinActiveProductionPerTimeslice[y,l,"Power","RES_Hydro_Large",r] = 0.1
                Params.MinActiveProductionPerTimeslice[y,l,"Power","RES_Hydro_Small",r] = 0.05
            end
        end end
    end

    

    #marginal costs for better numerical stability
    for r ∈ Sets.Region_full for t ∈ Sets.Technology for y ∈ Sets.Year
        if Params.CapitalCost[r,t,y] == 0
            Params.CapitalCost[r,t,y] = 0.01
        end
        if occursin("Wind", t)
            Params.CapitalCost[r,t,y] = Params.CapitalCost[r,t,y] * 0.7
        end
    end end end


    for r ∈ Sets.Region_full, i ∈ 1:length(Sets.Timeslice), y ∈ Sets.Year
        # for s in intersect(Sets.Storage, ["S_Battery_Li-Ion","S_Battery_Redox","S_Heat_HLR", "S_Heat_HLI"])
        #     if (i-1 + Switch.elmod_starthour/Switch.elmod_hourstep) % (24/Switch.elmod_hourstep) == 0
        #         JuMP.fix(Vars.StorageLevelTSStart[s,y,Sets.Timeslice[i],r], 0; force = true)
        #     end
#=         for s in intersect(Sets.Storage, ["S_CAES"])
            if (i-1 + Switch.elmod_starthour/Switch.elmod_hourstep) % (48/Switch.elmod_hourstep) == 0
                JuMP.fix(Vars.StorageLevelTSStart[s,y,Sets.Timeslice[i],r], 0; force = true)
            end =#
        #end
        if "RES_CSP" ∈ Sets.Technology
            try
                Params.CapacityFactor[r,"RES_CSP",Sets.Timeslice[i],y] = Params.CapacityFactor[r,"RES_PV_Utility_Opt",Sets.Timeslice[i],y]
            catch e
                if isa(e, KeyError)
                    Params.CapacityFactor[r,"RES_CSP",Sets.Timeslice[i],y] = Params.CapacityFactor[r,"RES_PV_Utility_Avg",Sets.Timeslice[i],y]
                end
            end
        end
        for t ∈ intersect(Sets.Technology, ["HLI_Solar_Thermal", "HLR_Solar_Thermal", "RES_PV_Rooftop_Commercial", "RES_PV_Rooftop_Residential"])
            Params.CapacityFactor[r,t,Sets.Timeslice[i],y] = Params.CapacityFactor[r,"RES_PV_Utility_Avg",Sets.Timeslice[i],y]
        end
    end

    #Params.ResidualCapacity["DE", "D_Battery_Li-Ion",2050] = 35.14547901648507
    #Params.ResidualStorageCapacity["DE", "S_Gas_H2", 2050] =  18.297023209681292
    #Params.ResidualStorageCapacity["DE", "S_Battery_Li-Ion",2050] = 3.37426120517831




    #for r ∈ Sets.Region_full for s in Sets.Storage for y ∈ Sets.Year
        #Params.CapitalCostStorage[r,s,y] = CapitalCostStorage[r,s,y]/365*8760/Switch.elmod_nthhour/(24/Switch.elmod_hourstep)

        #@constraint(model, Vars.StorageUpperLimit[s,y,r] <= sum(Params.TotalCapacityAnnual[y,t,r] * Partams.StorageE2PRatio[s] * 0.0036 * 3 for t in Sets.Technology for m in Sets.Mode_of_operation if Params.TechnologyToStorage[t,s,m,y] != 0),
        #base_name="Add_E2PRatio_up|$(s)|$(y)|$(r)")
        #@constraint(model, Vars.StorageUpperLimit[s,y,r] >= sum(Params.TotalCapacityAnnual[y,t,r] * Partams.StorageE2PRatio[s] * 0.0036 * 0.5 for t in Sets.Technology for m in Sets.Mode_of_operation if Params.TechnologyToStorage[t,s,m,y] != 0),
        #base_name="Add_E2PRatio_low|$(s)|$(y)|$(r)")
end

function YearlyDifferenceMultiplier(y,Sets);
    i = findfirst(Sets.Year.== y)
    if i < length(Sets.Year)
        return max(1,Sets.Year[i+1]-Sets.Year[i])
    else 
        return 1
    end
end