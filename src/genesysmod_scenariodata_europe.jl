module ScenarioDataEurope
    using JuMP
    export genesysmod_scenariodata

    function genesysmod_scenariodata(model,Sets,Params,Maps,Vars,Switch)
        if "X_DAC_HT" ∈ Sets.Technology
            Params.AvailabilityFactor[:,"X_DAC_HT",:] .= 0
        end
        if "X_DAC_LT" ∈ Sets.Technology
            Params.AvailabilityFactor[:,"X_DAC_LT",:] .= 0
        end

        for r ∈ Sets.Region_full, t ∈ Sets.Technology, y ∈ Sets.Year
            if Params.TotalAnnualMaxCapacity[r,t,y] < Params.TotalAnnualMinCapacity[r,t,2025]
                println("TotalAnnualMaxCapacity[$r,$t,$y] is lower than TotalAnnualMinCapacity[$r,$t,2025], check the data! Setting the value to TotalAnnualMinCapacity[$r,$t,2025].")
                Params.TotalAnnualMaxCapacity[r,t,y] = Params.TotalAnnualMinCapacity[r,t,2025]
            end
        end

        # NECP capacity plans (NECPEssentials only). Built before the 2025 clamp so
        # the planned RES techs can be exempted from it (mirrors GAMS where the
        # NewCapacity.up = +INF assignment overwrites the earlier .up = 0 bound).
        NECPCapacityPlans = Dict{Tuple{String,String,Int},Float64}()
        necp_released = Set{Tuple{String,String}}()
        if Switch.emissionPathway == "NECPEssentials"
            NECPCapacityPlans[("ES","Solar",2025)]   = 44.197
            NECPCapacityPlans[("ES","Solar",2030)]   = 71.473
            NECPCapacityPlans[("ES","Onshore",2025)] = 36.149
            NECPCapacityPlans[("ES","Onshore",2030)] = 62.054

            NECPCapacityPlans[("FR","Solar",2025)]   = 26.9
            NECPCapacityPlans[("FR","Solar",2030)]   = 54.4
            NECPCapacityPlans[("FR","Solar",2035)]   = 68.4
            NECPCapacityPlans[("FR","Solar",2050)]   = 82.4
            NECPCapacityPlans[("FR","Solar",2055)]   = 86.4
            NECPCapacityPlans[("FR","Solar",2060)]   = 90.4
            NECPCapacityPlans[("FR","Onshore",2025)] = 25.2
            NECPCapacityPlans[("FR","Onshore",2030)] = 34.2
            NECPCapacityPlans[("FR","Onshore",2035)] = 40.7
            NECPCapacityPlans[("FR","Onshore",2050)] = 47.2
            NECPCapacityPlans[("FR","Onshore",2055)] = 49.5
            NECPCapacityPlans[("FR","Onshore",2060)] = 51.9
            NECPCapacityPlans[("FR","Offshore",2025)] = 3.003
            NECPCapacityPlans[("FR","Offshore",2030)] = 3.6
            NECPCapacityPlans[("FR","Offshore",2035)] = 8.6
            NECPCapacityPlans[("FR","Offshore",2050)] = 13.6
            NECPCapacityPlans[("FR","Offshore",2055)] = 15.5
            NECPCapacityPlans[("FR","Offshore",2060)] = 17.7

            NECPCapacityPlans[("GR","Solar",2025)]   = 8.5
            NECPCapacityPlans[("GR","Solar",2030)]   = 13.5
            NECPCapacityPlans[("GR","Solar",2035)]   = 18.5
            NECPCapacityPlans[("GR","Solar",2040)]   = 26.0
            NECPCapacityPlans[("GR","Solar",2045)]   = 30.0
            NECPCapacityPlans[("GR","Solar",2050)]   = 35.1
            NECPCapacityPlans[("GR","Onshore",2025)] = 7.0
            NECPCapacityPlans[("GR","Onshore",2030)] = 8.9
            NECPCapacityPlans[("GR","Onshore",2035)] = 9.5
            NECPCapacityPlans[("GR","Onshore",2040)] = 11.0
            NECPCapacityPlans[("GR","Onshore",2045)] = 13.0
            NECPCapacityPlans[("GR","Onshore",2050)] = 13.0
            NECPCapacityPlans[("GR","Offshore",2025)] = 0.0
            NECPCapacityPlans[("GR","Offshore",2030)] = 1.9
            NECPCapacityPlans[("GR","Offshore",2035)] = 3.9
            NECPCapacityPlans[("GR","Offshore",2040)] = 5.8
            NECPCapacityPlans[("GR","Offshore",2045)] = 8.2
            NECPCapacityPlans[("GR","Offshore",2050)] = 11.8

            NECPCapacityPlans[("DE","Solar",2025)]   = 117.7
            NECPCapacityPlans[("DE","Solar",2030)]   = 215.0
            NECPCapacityPlans[("DE","Solar",2040)]   = 400.0
            NECPCapacityPlans[("DE","Onshore",2025)] = 64.0
            NECPCapacityPlans[("DE","Onshore",2030)] = 115.0
            NECPCapacityPlans[("DE","Onshore",2040)] = 160.0
            NECPCapacityPlans[("DE","Offshore",2025)] = 9.215
            NECPCapacityPlans[("DE","Offshore",2030)] = 30.0
            NECPCapacityPlans[("DE","Offshore",2035)] = 40.0
            NECPCapacityPlans[("DE","Offshore",2045)] = 70.0

            necp_subsets = ["Solar","Onshore","Offshore"]
            necp_techs = String[]
            for sub ∈ necp_subsets
                append!(necp_techs, get(Params.Tags.TagTechnologyToSubsets, sub, String[]))
            end
            for r ∈ Sets.Region_full
                if any(get(NECPCapacityPlans,(r,sub,2025),0.0) != 0 for sub ∈ necp_subsets)
                    for t ∈ necp_techs
                        push!(necp_released, (r,t))
                    end
                end
            end
        end

        # Limit capacity expansion in 2025 to only actually (historically) installed capacities
        # (matches GAMS: clamp only when BOTH AnnualMinNewCapacity and TotalAnnualMinCapacity are 0).
        # NECP-planned RES techs are exempt (GAMS NewCapacity.up = +INF).
        for r ∈ Sets.Region_full, t ∈ Params.Tags.TagTechnologyToSubsets["PowerSupply"]
            if Params.AnnualMinNewCapacity[r,t,2025] == 0 && Params.TotalAnnualMinCapacity[r,t,2025] == 0 && !((r,t) ∈ necp_released)
                @constraint(model, Vars.NewCapacity[2025,t,r] <= 0, base_name="ScenarioData_Europe_NewCapacity_2025_$(t)_$(r)")
            end
        end

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

        # Scenario-specific: HHI scrap-EAF cap, modal shift away from road, ETS not tradable.
        # Each modal type is guarded by its own value (matches GAMS' two separate $-conditions).
        modal_decrement = Dict("REPowerEU"=>0.002, "NECPEssentials"=>0.00175, "Green"=>0.00225, "Trinity"=>0.001)
        hhi_factor = Dict("REPowerEU"=>0.65, "NECPEssentials"=>0.6, "Green"=>0.75, "Trinity"=>0.5)
        if haskey(modal_decrement, Switch.emissionPathway)
            dec = modal_decrement[Switch.emissionPathway]
            hhi = hhi_factor[Switch.emissionPathway]
            for r ∈ Sets.Region_full, y ∈ Sets.Year
                @constraint(model, Vars.ProductionByTechnologyAnnual[y,"HHI_Scrap_EAF","Heat_High_Industrial",r] <= Params.SpecifiedAnnualDemand[r,"Heat_High_Industrial",y]*hhi, base_name="ScenarioData_Europe_HHI_Scrap_EAF_Heat_High_Industrial_$(r)_$(y)")
                for f ∈ Sets.Fuel
                    if y > 2025 && Params.ModalSplitByFuelAndModalType[r,f,y,"MT_PSNG_ROAD"] != 0
                        Params.ModalSplitByFuelAndModalType[r,f,y,"MT_PSNG_ROAD"] = Params.ModalSplitByFuelAndModalType[r,f,2025,"MT_PSNG_ROAD"] - dec*(y-2025)
                    end
                    if y > 2025 && Params.ModalSplitByFuelAndModalType[r,f,y,"MT_FRT_ROAD"] != 0
                        Params.ModalSplitByFuelAndModalType[r,f,y,"MT_FRT_ROAD"] = Params.ModalSplitByFuelAndModalType[r,f,2025,"MT_FRT_ROAD"] - dec*(y-2025)
                    end
                end
            end
            Params.Tags.TagCanFuelBeTraded["ETS"] = 0
        end

        # HB_Oil_Boiler 2025 lower bound (GAMS .lo)
        for r ∈ Sets.Region_full
            if Params.RegionalBaseYearProduction[r,"HB_Oil_Boiler","Heat_Buildings",2018] != 0
                @constraint(model, Vars.ProductionByTechnologyAnnual[2025,"HB_Oil_Boiler","Heat_Buildings",r] >= Params.RegionalBaseYearProduction[r,"HB_Oil_Boiler","Heat_Buildings",2018]*0.3, base_name="ScenarioData_Europe_HB_Oil_Boiler_lo_$(r)")
            end
        end

        # Curtailment cost factor (GAMS scalar = 45)
        Params.CurtailmentCostFactor[:,:,:] .= 45

        for r ∈ Sets.Region_full, y ∈ Sets.Year
            if Params.DistrictHeatDemand[r,y] != 0
                @constraint(model, sum(Vars.ProductionByTechnologyAnnual[y,t,"Heat_District",r] for t ∈ [t_ for (t_,f_) ∈ Maps.Set_Tech_FuelOut if f_ == "Heat_District"]) >= Params.DistrictHeatDemand[r,y]*Params.InputActivityRatio[r,"X_Convert_HD","Heat_District",1,y]*0.95,
                base_name="DistrictHeatProductionAnnualLowerLimit|$(r)|Heat_District|$(y)")
                @constraint(model, sum(Vars.ProductionByTechnologyAnnual[y,t,"Heat_District",r] for t ∈ [t_ for (t_,f_) ∈ Maps.Set_Tech_FuelOut if f_ == "Heat_District"]) <= Params.DistrictHeatDemand[r,y]*Params.InputActivityRatio[r,"X_Convert_HD","Heat_District",1,y]*1.05,
                base_name="DistrictHeatProductionAnnualUpperLimit|$(r)|Heat_District|$(y)")
            end

            for se ∈ Sets.Sector
                if Params.DistrictHeatSplit[r,se,y] != 0
                    @constraint(model,sum(Vars.ProductionByTechnologyAnnual[y,t,f,r] for (t,f) ∈ Maps.Set_Tech_FuelOut if (Params.Tags.TagDemandFuelToSector[f,se] != 0 && t ∈ Params.Tags.TagTechnologyToSubsets["Convert"])) >= Params.DistrictHeatDemand[r,y]*Params.DistrictHeatSplit[r,se,y],
                    base_name="DistrictHeatProductionSplit|$(r)|$(se)|$(y)")
                end
            end
        end

        # NECP capacity expansion: pin planned RES capacities (NECPEssentials only)
        if Switch.emissionPathway == "NECPEssentials"
            powersupply = Params.Tags.TagTechnologyToSubsets["PowerSupply"]
            for ((r,sub,y), plan) ∈ NECPCapacityPlans
                plan == 0 && continue
                techs = intersect(get(Params.Tags.TagTechnologyToSubsets, sub, String[]), powersupply)
                isempty(techs) && continue
                @constraint(model, sum(Vars.TotalCapacityAnnual[y,t,r] for t ∈ techs) == plan, base_name="NECPCapacityExpansion|$(r)|$(sub)|$(y)")
            end
        end
    end
end
