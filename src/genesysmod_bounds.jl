"""
Internal function used in the run process to modify batches of input data.
"""
function genesysmod_bounds(model,Sets,Params, Vars,Settings,Switch,Maps)

    #
    # ####### Default Values #############
    #

    end_uses = union(["Power"], Params.Tags.TagFuelToSubsets["HeatFuels"], Params.Tags.TagFuelToSubsets["TransportFuels"])
    #sub=["Power", "Heat_Low_Residential", "Heat_Low_Industrial", "Heat_Medium_Industrial",
    # "Heat_High_Industrial", "Heat_MediumLow_Industrial", "Heat_MediumHigh_Industrial",
    #  "Heat_Buildings"]

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for t ∈ intersect(Sets.Technology,Params.Tags.TagTechnologyToSubsets["EmergingTechnologies"])
            Params.Tags.RETagTechnology[r,t,y] = 1
        end
        for f ∈ intersect(Sets.Fuel,end_uses)
            Params.Tags.RETagFuel[r,f,y] = 1
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
        for t ∈ setdiff(Params.Tags.TagTechnologyToSubsets["FossilFuelGeneration"],["R_Nuclear"])
            if Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] == 999999
                Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] = 0
            end
    end end

    for r ∈ Sets.Region_full
        for rr ∈ Sets.Region_full
            for y ∈ Sets.Year
                if Params.TradeCosts[r,"ETS",y,rr] == 0
                    Params.TradeCosts[r,"ETS",y,rr] = 0.01
    end end end end

    for r ∈ Sets.Region_full for m ∈ Sets.Mode_of_operation for y ∈ Sets.Year
        for t ∈ Sets.Technology
            if t == "Power"
                if Params.VariableCost[r,t,m,y]==0
                    Params.VariableCost[r,t,m,y] = 0.001
                end
            else
                if Params.VariableCost[r,t,m,y]==0
                    Params.VariableCost[r,t,m,y] = 0.01
                end
            end
    end end end end

    #
    # ####### Dummy-Technologies [enable for test purposes, if model runs infeasible] #############
    #

    if Switch.switch_infeasibility_tech == 1
        subset = setdiff(Params.Tags.TagTechnologyToSubsets["DummyTechnology"],Params.Tags.TagTechnologyToSubsets["TradeStorageDummies"])
        Params.Tags.TagTechnologyToSector[subset,"Infeasibility"] .= 1

        #output_activity_dict = Dict(
        #    "Infeasibility_HLI" => "Heat_Low_Industrial",
        #    "Infeasibility_HMI" => ["Heat_MediumHigh_Industrial","Heat_MediumLow_Industrial"],
        #    "Infeasibility_HHI" => "Heat_High_Industrial",
        #    "Infeasibility_HRI" => "Heat_Buildings",
        #    "Infeasibility_Power" => "Power",
        #    "Infeasibility_Mob_Passenger" => "Mobility_Passenger",
        #    "Infeasibility_Mob_Freight" => "Mobility_Freight",
        #    "Infeasibility_H2" => "H2",
        #    "Infeasibility_Natural_Gas" => "Gas_Natural",)
        #
        #for (k,v) ∈ output_activity_dict
        #    try
        #        Params.OutputActivityRatio[:,k,v,1,:] .= 1
        #    catch
        #       # Error is ignored intentionally
        #    end
        #end

        for end_use ∈ end_uses
            Params.OutputActivityRatio[:,"Infeasibility_$(end_use)",end_use,1,:] .= 1
        end
        
        Params.CapacityToActivityUnit[subset] .= 31.536
        Params.TotalAnnualMaxCapacity[:,subset,:] .= 999999
        Params.FixedCost[:,subset,:] .= 999
        Params.CapitalCost[:,subset,:] .= 999
        Params.VariableCost[:,subset,:,:] .= 999
        Params.AvailabilityFactor[:,subset,:] .= 1
        Params.CapacityFactor[:,subset,:,:] .= 1
        Params.OperationalLife[subset] .= 1
        Params.EmissionActivityRatio[:,subset,:,:,:] .= 0

    end

    #
    # ####### Bounds for non-supply technologies #############
    #

    for r ∈ Sets.Region_full
        for t ∈ Sets.Technology
            if t ∈ vcat(Params.Tags.TagTechnologyToSubsets["Transformation"],Params.Tags.TagTechnologyToSubsets["FossilPower"],Params.Tags.TagTechnologyToSubsets["FossilFuelGeneration"],
                Params.Tags.TagTechnologyToSubsets["CHP"],Params.Tags.TagTechnologyToSubsets["Transport"],Params.Tags.TagTechnologyToSubsets["ImportTechnology"],Params.Tags.TagTechnologyToSubsets["Biomass"],"P_Biomass")
                for y ∈ Sets.Year
                    if Params.TotalAnnualMaxCapacity[r,t,y] == 0
                        Params.TotalAnnualMaxCapacity[r,t,y] = 999999
                    end
                end
            end
    end end

#=     for r ∈ Sets.Region_full
        for t ∈ Params.Tags.TagTechnologyToSubsets["ImportTechnology"]
            for y ∈ Sets.Year
                Params.AvailabilityFactor[r,t,y] = 1
    end end end =#

    let import_techs = intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["ImportTechnology"])
        isempty(import_techs) || (Params.CapacityFactor[:, import_techs, :, :] .= 1)
    end

    for r ∈ Sets.Region_full
        for t ∈ Params.Tags.TagTechnologyToSubsets["ImportTechnology"]
                Params.OperationalLife[t] = 1
        end
    end

    for r ∈ Sets.Region_full
        for t ∈ Params.Tags.TagTechnologyToSubsets["ImportTechnology"]
            Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] = 999999
        end
    end

    #
    # ####### Bounds for storage technologies #############
    #


    #
    # ####### Capacity factor for heat technologies #############
    #
    # TO DO: ask konstantin for reason behind this and possibility to simplify
    #CapacityFactor(r,Heat,l,y)$(sum(ll,CapacityFactor(r,Heat,ll,y)) = 0) = 1;
    #Params.CapacityFactor[[x ∈ Subsets.Heat for x ∈ Params.CapacityFactor[!,:Technology]], :Value] .= 1

    for r ∈ Sets.Region_full, l ∈ Sets.Timeslice, y ∈ Sets.Year, t ∈ intersect(Sets.Technology, ["HLI_Solar_Thermal", "HB_Solar_Thermal", "HD_Solar_Thermal", "P_PV_Rooftop_Residential"])
        Params.CapacityFactor[r,t,l,y] = Params.CapacityFactor[r,"P_PV_Rooftop_Commercial",l,y]
    end
    #
    # ####### No new capacity construction in 2015 #############
    #
    if Switch.switch_dispatch isa NoDispatch
        for r ∈ Sets.Region_full
            for t ∈ intersect(Sets.Technology, vcat(Params.Tags.TagTechnologyToSubsets["Transformation"],
                Params.Tags.TagTechnologyToSubsets["PowerSupply"], Params.Tags.TagTechnologyToSubsets["SectorCoupling"],
                Params.Tags.TagTechnologyToSubsets["StorageDummies"], Params.Tags.TagTechnologyToSubsets["CHP"],
                Params.Tags.TagTechnologyToSubsets["Transport"]))
                JuMP.fix(Vars.NewCapacity[Switch.StartYear,t,r],0; force=true)
            end
            for t ∈ intersect(Sets.Technology, vcat(Params.Tags.TagTechnologyToSubsets["Biomass"],["D_Gas_Methane", "X_SMR"]))
                if JuMP.is_fixed(Vars.NewCapacity[Switch.StartYear,t,r])
                    JuMP.unfix(Vars.NewCapacity[Switch.StartYear,t,r])
                end
            end
        end

        #= if "CHP" ∈ Sets.Sector
            for t ∈ Sets.Technology
                if Params.Tags.TagTechnologyToSector[t,"CHP"] == 1
                    for r ∈ Sets.Region_full
                        if JuMP.is_fixed(model[:NewCapacity][Switch.StartYear,t,r])
                            JuMP.unfix(model[:NewCapacity][Switch.StartYear,t,r])
                        end
                    end
                end
            end
        end =#
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
    #= for r ∈ Sets.Region_full for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["Transport"])
        Params.VariableCost[r,t,:,:] .= 0.09
    end end =#

    #
    # ####### Dispatch and Curtailment #############
    #
    subs = vcat(intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["Solar"]), intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["Wind"]), ["P_Hydro_RoR"])
    Params.Tags.TagDispatchableTechnology[subs] = zeros(length(intersect(Sets.Technology,subs)))
    Params.CurtailmentCostFactor == 0.1

    for r ∈ Sets.Region_full, t ∈ intersect(Sets.Technology,Params.Tags.TagTechnologyToSubsets["Solar"])
        Params.AvailabilityFactor[r,t,:] .= 1
    end

    for e ∈ Sets.Emission for s ∈ Sets.Sector for y ∈ Sets.Year
        if Params.AnnualSectoralEmissionLimit[e,s,y] == 0
            Params.AnnualSectoralEmissionLimit[e,s,y] = 999999
        end
    end end end

    #
    # ####### CCS #############
    #

    if Switch.switch_ccs == 1
        for r ∈ Sets.Region_full for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["CCS"])
            Params.AvailabilityFactor[r,t,:] .= 0
            Params.TotalAnnualMaxCapacity[r,t,:] .= 99999
            Params.TotalTechnologyAnnualActivityUpperLimit[r,t,:] .= 99999
        end end

        for y ∈ Sets.Year for r ∈ Sets.Region_full
            if (y > 2020) && (Params.RegionalCCSLimit[r] > 0)
                for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["CCS"])
                    Params.AvailabilityFactor[r,t,y] = 0.95
                end
            else
                for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["CCS"])
                    fuels = (y for (x,y) ∈ Maps.Set_Tech_FuelOut if x == t)
                    Params.TotalAnnualMaxCapacity[r,t,y] = 0
                    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] = 0
                    for f ∈ fuels
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
        for y ∈ Sets.Year for r ∈ Sets.Region_full for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["CCS"])
            fuels = (y for (x,y) ∈ Maps.Set_Tech_FuelOut if x == t)
            Params.AvailabilityFactor[r,t,y] = 0
            Params.TotalAnnualMaxCapacity[r,t,y] = 0
            for f ∈ fuels
                JuMP.fix(Vars.ProductionByTechnologyAnnual[y,t,f,r], 0; force = true)
            end
        end end end
    end


    #
    # ####### Ramping #############
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
            for t ∈ Params.Tags.TagTechnologyToSubsets["PowerBiomass"]
                Params.RampingUpFactor[t,y] = 0.04
                Params.RampingDownFactor[t,y] = 0.04
                Params.ProductionChangeCost[r,t,y] = 100/3.6
            end
            for t ∈ Params.Tags.TagTechnologyToSubsets["FossilPower"]
                Params.RampingUpFactor[t,y] = 0.04
                Params.RampingDownFactor[t,y] = 0.04
                Params.ProductionChangeCost[r,t,y] = 100/3.6
            end
            for t ∈ Params.Tags.TagTechnologyToSubsets["Coal"]
                Params.RampingUpFactor[t,y] = 0.02
                Params.RampingDownFactor[t,y] = 0.02
                Params.ProductionChangeCost[r,t,y] = 50/3.6
            end
            for t ∈ Params.Tags.TagTechnologyToSubsets["Gas"]
                Params.RampingUpFactor[t,y] = 0.2
                Params.RampingDownFactor[t,y] = 0.2
                Params.ProductionChangeCost[r,t,y] = 20/3.6
            end
            for t ∈ Params.Tags.TagTechnologyToSubsets["HeatSlowRamper"]
                Params.RampingUpFactor[t,y] = 0.1
                Params.RampingDownFactor[t,y] = 0.1
                Params.ProductionChangeCost[r,t,y] = 100/3.6
            end
            for t ∈ Params.Tags.TagTechnologyToSubsets["HeatQuickRamper"]
                Params.RampingUpFactor[t,y] = 0
                Params.RampingDownFactor[t,y] = 0
                Params.ProductionChangeCost[r,t,y] = 0
            end =#
            for l ∈ Sets.Timeslice
                Params.MinActiveProductionPerTimeslice[y,l,"Power","P_Hydro_Reservoir",r] = 0.1
                Params.MinActiveProductionPerTimeslice[y,l,"Power","P_Hydro_RoR",r] = 0.05
            end
        end end
    end

    #marginal costs for better numerical stability
    for r ∈ Sets.Region_full for t ∈ Sets.Technology for y ∈ Sets.Year
        if Params.CapitalCost[r,t,y] == 0
            Params.CapitalCost[r,t,y] = 0.01
        end
    end end end


    for r ∈ Sets.Region_full for i ∈ 1:length(Sets.Timeslice) for y ∈ Sets.Year
        if Switch.switch_dispatch isa NoDispatch
            for s in intersect(Sets.Storage, ["S_Battery_Li-Ion","S_Battery_Redox","S_Heat_HB_Tank_Small", "S_Heat_HLI_Tank_Large", "S_CAES"])
                if (i-1 + Switch.elmod_starthour/Switch.elmod_hourstep) % (24/Switch.elmod_hourstep) == 0
                    JuMP.fix(Vars.StorageLevelTSStart[s,y,Sets.Timeslice[i],r], 0; force = true)
                end
            end
        end
        if "P_CSP" ∈ Sets.Technology
            try
                Params.CapacityFactor[r,"P_CSP",Sets.Timeslice[i],y] = Params.CapacityFactor[r,"P_PV_Utility_Opt",Sets.Timeslice[i],y]
            catch e
                if isa(e, KeyError)
                    Params.CapacityFactor[r,"P_CSP",Sets.Timeslice[i],y] = Params.CapacityFactor[r,"P_PV_Utility_Avg",Sets.Timeslice[i],y]
                end
            end
        end

        for t ∈ intersect(Sets.Technology, ["HLI_Solar_Thermal", "HB_Solar_Thermal", "HD_Solar_Thermal", "P_PV_Rooftop_Commercial", "P_PV_Rooftop_Residential"])
            Params.CapacityFactor[r,t,Sets.Timeslice[i],y] = Params.CapacityFactor[r,"P_PV_Utility_Avg",Sets.Timeslice[i],y]
        end
    end end end

    for r ∈ Sets.Region_full for s in Sets.Storage for y ∈ Sets.Year
        Params.CapitalCostStorage[r,s,y] = max(round(Params.CapitalCostStorage[r,s,y]/365*8760/Switch.elmod_nthhour/(24/Switch.elmod_hourstep),sigdigits=4),0.01)
    end end end

end

function YearlyDifferenceMultiplier(y,Sets);
    i = findfirst(Sets.Year.== y)
    if i < length(Sets.Year)
        return max(1,Sets.Year[i+1]-Sets.Year[i])
    else
        return 1
    end
end
