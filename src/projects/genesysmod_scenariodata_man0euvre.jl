module ScenarioDataMan0euvre
    ############ Man0EUvRE project scenario overlay ############
    #
    # Country case-study feedback (CS1-CS9) collected in the Man0EUvRE project for
    # the 30-region European model, selected with project_scenario="man0euvre" and
    # loaded after the region scenario data. The overlay is self-contained: the
    # per-pathway blocks and the NECP capacity plans belong here, not in the European
    # scenario data. It applies to the four Man0EUvRE emission pathways only.
    #
    # Reproducibility: this file on its own does not reproduce the published
    # Man0EUvRE runs. Those runs also carried two edits to the core equations that
    # were deliberately not upstreamed, because they hardcoded region names:
    #   - TrC6_SymmetricalTransmissionExpansion skipped the PT-ES pair from 2040 on
    #   - S7a_Add_E2PRatio_up skipped PT / S_Battery_Li-Ion
    # Here the PT-ES convergence is instead expressed as data (commissioned capacity,
    # see below), which keeps PTES_TradeConvergence compatible with the TrC6 band;
    # S9_PT_LiIon_MaxDuration is held at StorageE2PRatio * the deviation factor
    # (6h with the shipped data) rather than the intended 8h.
    #
    using JuMP
    export genesysmod_scenariodata

    function genesysmod_scenariodata(model,Sets,Params,Maps,Vars,Switch)
        𝓨 = Sets.Year
        𝓡 = Sets.Region_full
        𝓣 = Sets.Technology
        𝓕 = Sets.Fuel

        storage_dummies = intersect(𝓣, Params.Tags.TagTechnologyToSubsets["StorageDummies"])

        man0euvre_pathways = ("REPowerEU", "NECPEssentials", "Green", "Trinity")
        pathway_applies = Switch.emissionPathway ∈ man0euvre_pathways
        if !pathway_applies
            @warn "Man0EUvRE scenario data: emissionPathway '$(Switch.emissionPathway)' is none of $(join(man0euvre_pathways, ", ")) - the pathway-specific overlay (HHI scrap-EAF cap, road modal shift, ETS trading, regional peaking slack, NECP capacity plans) is skipped."
        end

        # CS9: PT coal (all sectors, tagged "Coal" in Par_TagTechnologyToSubsets) produces 0
        # energy but ResidualCapacity keeps carrying leftover TotalCapacity beyond 2025 -
        # zero out remaining capacity and block new build
        if "PT" ∈ 𝓡
            for t ∈ intersect(𝓣, get(Params.Tags.TagTechnologyToSubsets, "Coal", String[])), y ∈ 𝓨
                y >= 2025 || continue
                Params.ResidualCapacity["PT",t,y] = 0
                JuMP.is_fixed(Vars.NewCapacity[y,t,"PT"]) || JuMP.set_upper_bound(Vars.NewCapacity[y,t,"PT"], 0)
                JuMP.fix(Vars.TotalCapacityAnnual[y,t,"PT"], 0; force=true)
            end
        end

        # Emission-pathway branches. Each sets the HHI scrap-EAF cap, the annual road
        # modal-split decrement, disables ETS trading, and adds the regional peaking
        # slack. PeakingSlackAdd is declared alongside PeakingSlack and read by
        # PC3 / PC3b; scenario data only assigns it. Regions not in the dataset are skipped.
        hhi_factor = 0.0
        modal_decrement = 0.0
        add_peaking_slack!(r, value) = r ∈ 𝓡 && (Params.PeakingSlackAdd[r] = value)

        if Switch.emissionPathway == "REPowerEU"
            hhi_factor = 0.65
            modal_decrement = 0.002
            add_peaking_slack!("FR", 0.0190)

        elseif Switch.emissionPathway == "NECPEssentials"
            hhi_factor = 0.6
            modal_decrement = 0.00175
            add_peaking_slack!("FR", 0.0251)

        elseif Switch.emissionPathway == "Green"
            hhi_factor = 0.75
            modal_decrement = 0.00225
            add_peaking_slack!("FR", 0.0323)
            add_peaking_slack!("CH", 0.0837)
            add_peaking_slack!("IE", 0.1555)
            add_peaking_slack!("UK", 0.0470)
            add_peaking_slack!("FI", 0.0209)

        elseif Switch.emissionPathway == "Trinity"
            hhi_factor = 0.5
            modal_decrement = 0.001
            add_peaking_slack!("FR", 0.0198)
        end

        if pathway_applies
            for r ∈ 𝓡, y ∈ 𝓨
                if ("HHI_Scrap_EAF","Heat_High_Industrial") ∈ Maps.Set_Tech_FuelOut
                    @constraint(model, Vars.ProductionByTechnologyAnnual[y,"HHI_Scrap_EAF","Heat_High_Industrial",r] <= Params.SpecifiedAnnualDemand[r,"Heat_High_Industrial",y]*hhi_factor,
                    base_name="ScenarioData_Man0EUvRE_HHI_Scrap_EAF_Heat_High_Industrial|$(r)|$(y)")
                end
                # Each modal type is guarded by its own value.
                for f ∈ 𝓕
                    if y > 2025 && Params.ModalSplitByFuelAndModalType[r,f,y,"MT_PSNG_ROAD"] != 0
                        Params.ModalSplitByFuelAndModalType[r,f,y,"MT_PSNG_ROAD"] = Params.ModalSplitByFuelAndModalType[r,f,2025,"MT_PSNG_ROAD"] - modal_decrement*(y-2025)
                    end
                    if y > 2025 && Params.ModalSplitByFuelAndModalType[r,f,y,"MT_FRT_ROAD"] != 0
                        Params.ModalSplitByFuelAndModalType[r,f,y,"MT_FRT_ROAD"] = Params.ModalSplitByFuelAndModalType[r,f,2025,"MT_FRT_ROAD"] - modal_decrement*(y-2025)
                    end
                end
            end
            Params.Tags.TagCanFuelBeTraded["ETS"] = 0
        end

        # Increase the lower and upper battery duration for Portugal.
        # The total storage capacity is spelled out as in S1, so the rows do not depend
        # on TotalStorageCapacityAnnual being linked in this run.
        if "PT" ∈ 𝓡 && "S_Battery_Li-Ion" ∈ Sets.Storage
            s = "S_Battery_Li-Ion"
            charge_tm = [(t,m) for t ∈ storage_dummies for m ∈ Maps.Tech_MO[t]
                         if any(Params.TechnologyToStorage[t,s,m,y] != 0 for y ∈ 𝓨)]
            for y ∈ 𝓨
                storage_cap = sum(Vars.NewStorageCapacity[s,yy,"PT"] for yy ∈ 𝓨
                                  if (Params.OperationalLifeStorage[s] >= y-yy && y-yy >= 0); init=0) +
                              Params.ResidualStorageCapacity["PT",s,y]
                charge_cap = sum(Vars.TotalCapacityAnnual[y,t,"PT"] for (t,m) ∈ charge_tm
                                 if Params.TechnologyToStorage[t,s,m,y] != 0; init=0)
                @constraint(model, storage_cap >= charge_cap * 4 * 0.0036,
                base_name="S8_PT_LiIon_MinDuration|$(s)|$(y)|PT")
                @constraint(model, storage_cap <= charge_cap * 8 * 0.0036,
                base_name="S9_PT_LiIon_MaxDuration|$(s)|$(y)|PT")
            end
        end

        # Convergence of interconnection capacity ES <-> PT
        if ("Power","PT","ES") ∈ Maps.Set_Fuel_Regions && ("Power","ES","PT") ∈ Maps.Set_Fuel_Regions
            for y ∈ 𝓨
                y >= 2040 || continue
                @constraint(model, Vars.TotalTradeCapacity[y,"Power","PT","ES"] == Vars.TotalTradeCapacity[y,"Power","ES","PT"],
                base_name="PTES_TradeConvergence|Power|$(y)|PT|ES")
            end

            # the ES->PT direction is 0.7 GW larger after the 2025 commissioning; LNEG feedback is that grid
            # reinforcement brings PT->ES to parity by 2040, so the difference is commissioned exogenously.
            # Totals are recursive (TrC2b), which makes PTES_TradeConvergence feasible under the TrC6 band.
            if 2040 ∈ 𝓨
                Params.CommissionedTradeCapacity["PT","ES","Power",2040] += 0.7
            end
        end

        # Germany: Klimaschutzgesetz par. 3 as regional annual limit incl. exogenous emissions
        # (2025: UBA emission data; 2035 interpolated)
        if "DE" ∈ 𝓡 && "CO2" ∈ Sets.Emission
            DE_CO2_limit = Dict(2025 => 649.0, 2030 => 438.0, 2035 => 294.0, 2040 => 150.0)
            for y ∈ 𝓨
                if haskey(DE_CO2_limit, y)
                    Params.RegionalAnnualEmissionLimit["DE","CO2",y] = DE_CO2_limit[y]
                elseif y >= 2045
                    Params.RegionalAnnualEmissionLimit["DE","CO2",y] = 0
                end
            end
        end

        # Germany: CCS only in high-temperature industry and BECCS
        if "DE" ∈ 𝓡
            beccs = get(Params.Tags.TagTechnologyToSubsets, "BECCS", String[])
            for t ∈ intersect(𝓣, get(Params.Tags.TagTechnologyToSubsets, "CCS", String[]))
                (t ∈ beccs || t == "HHI_BF_BOF_CCS" || t == "HHI_DRI_EAF_CCS") && continue
                Params.AvailabilityFactor["DE",t,:] .= 0
            end
        end

        if Switch.emissionPathway == "NECPEssentials"
            necp_subsets = ["Solar","Onshore","Offshore"]
            NECPCapacityPlans = Dict{Tuple{String,String,Int},Float64}()

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

            # Lift the 2025 historic-capacity lock for the planned RES technologies in
            # every region with a 2025 plan.
            powersupply = Params.Tags.TagTechnologyToSubsets["PowerSupply"]
            if 2025 ∈ 𝓨
                necp_techs = intersect(𝓣, powersupply,
                    union((get(Params.Tags.TagTechnologyToSubsets, sub, String[]) for sub ∈ necp_subsets)...))
                for r ∈ 𝓡
                    sum(get(NECPCapacityPlans, (r,sub,2025), 0.0) for sub ∈ necp_subsets) != 0 || continue
                    for t ∈ necp_techs
                        JuMP.has_upper_bound(Vars.NewCapacity[2025,t,r]) && JuMP.delete_upper_bound(Vars.NewCapacity[2025,t,r])
                    end
                end
            end
            for ((r,sub,y), plan) ∈ NECPCapacityPlans
                plan == 0 && continue
                (r ∈ 𝓡 && y ∈ 𝓨) || continue
                techs = intersect(get(Params.Tags.TagTechnologyToSubsets, sub, String[]), powersupply)
                isempty(techs) && continue
                @constraint(model, sum(Vars.TotalCapacityAnnual[y,t,r] for t ∈ techs) == plan,
                base_name="NECPCapacityExpansion|$(r)|$(sub)|$(y)")
            end
        end
    end

end
