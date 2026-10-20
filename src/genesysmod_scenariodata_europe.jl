module ScenarioDataEurope
    using JuMP
    export genesysmod_scenariodata

    function genesysmod_scenariodata(model,Sets,Params,Maps,Vars,Switch)
        # The EnVis-europe scenario bounds below apply only to the EnVis emission
        # pathways. Other pathways (e.g. MinimalExample, used by the test suite) must
        # skip them, otherwise the forced lower bounds over-constrain the model.
        envis = Switch.emissionPathway ∈ ("NECPEssentials", "REPowerEU", "Green", "Trinity")

        if "X_DAC_HT" ∈ Sets.Technology
            Params.AvailabilityFactor[:,"X_DAC_HT",:] .= 0
        end
        if "X_DAC_LT" ∈ Sets.Technology
            Params.AvailabilityFactor[:,"X_DAC_LT",:] .= 0
        end

        if envis
        # Limit capacity expansion in 2025 to only actually (historically) installed capacities
        # (clamp only when AnnualMinNewCapacity, TotalAnnualMinCapacity and every group minimum
        # covering the technology are 0). Set as a bound so a project scenario overlay can lift it.
        group_min_2025 = Set{Tuple{String,String}}()
        for (ts, techs) ∈ Params.Tags.TagTechnologyToSubsets, (rs, regs) ∈ Params.Tags.TagRegionToSubsets
            Params.GroupTotalAnnualMinCapacity[ts,rs,2025] != 0 || continue
            for t ∈ techs, r ∈ regs
                push!(group_min_2025, (r,t))
            end
        end
        for r ∈ Sets.Region_full, t ∈ Params.Tags.TagTechnologyToSubsets["PowerSupply"]
            if Params.AnnualMinNewCapacity[r,t,2025] == 0 && Params.TotalAnnualMinCapacity[r,t,2025] == 0 && (r,t) ∉ group_min_2025
                JuMP.is_fixed(Vars.NewCapacity[2025,t,r]) || JuMP.set_upper_bound(Vars.NewCapacity[2025,t,r], 0)
            end
        end

        # need to check and move to data
        for r ∈ Sets.Region_full, y ∈ Sets.Year
            @constraint(model, Vars.ProductionByTechnologyAnnual[y,"CHP_WasteToEnergy","Heat_District",r] <= Params.RegionalBaseYearProduction[r,"CHP_WasteToEnergy","Heat_District",2018], base_name="ScenarioData_Europe_CHP_WasdteToEnergy_Heat_District_$(r)_$(y)")
            for f ∈ Sets.Fuel
                Params.OutputActivityRatio[r,"CHP_WasteToEnergy",f,1,y] = 0
            end
            if y > 2018
                @constraint(model, Vars.ProductionByTechnologyAnnual[y,"HD_Heatpump_ExcessHeat","Heat_District",r] <= Params.SpecifiedAnnualDemand[r,"Heat_District",y]*0.08, base_name="ScenarioData_Europe_HD_Heatpump_ExcessHeat_Heat_District_$(r)_$(y)")
            end
            @constraint(model, Vars.ProductionByTechnologyAnnual[y,"HLI_Geothermal","Heat_Low_Industrial",r] <= Params.SpecifiedAnnualDemand[r,"Heat_Low_Industrial",y]*0.25, base_name="ScenarioData_Europe_HLI_Geothermal_Heat_Low_Industrial_$(r)_$(y)")
        end

        # HB_Oil_Boiler 2025 lower bound (GAMS .lo)
        for r ∈ Sets.Region_full
            if Params.RegionalBaseYearProduction[r,"HB_Oil_Boiler","Heat_Buildings",2018] != 0
                @constraint(model, Vars.ProductionByTechnologyAnnual[2025,"HB_Oil_Boiler","Heat_Buildings",r] >= Params.RegionalBaseYearProduction[r,"HB_Oil_Boiler","Heat_Buildings",2018]*0.3, base_name="ScenarioData_Europe_HB_Oil_Boiler_lo_$(r)")
            end
        end

        # Curtailment cost factor (GAMS scalar = 45)
        Params.CurtailmentCostFactor[:,:,:] .= 45
        end
    end
end
