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
function def_daa(sets...)
    daa = JuMP.Containers.DenseAxisArray{Union{Float64,VariableRef}}(
        undef, sets...);
    fill!(daa,0.0);

#=     for i in eachindex(sets...)
        if sets...[i] == Sets.Technology & any(x -> x == Sets.Mode_of_operation, sets...[i:end])
            M = findfirst(x -> x == Sets.Mode_of_operation, sets...[i:end])
            
    end
    for x... in sets... =#

    return daa
end

"""
Internal function used in the run process to define the model variables.
"""
function genesysmod_dec(model,Sets, Params,Switch, Maps)

    𝓡 = Sets.Region_full
    𝓕 = Sets.Fuel
    𝓨 = Sets.Year
    𝓣 = Sets.Technology
    𝓔 = Sets.Emission
    𝓜 = Sets.Mode_of_operation
    𝓛 = Sets.Timeslice
    𝓢 = Sets.Storage
    𝓜𝓽 = Sets.ModalType
    𝓢𝓮 = Sets.Sector

    #####################
    # Model Variables #
    #####################

    ############### Capacity Variables ############
    
    NewCapacity = @variable(model, NewCapacity[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    AccumulatedNewCapacity = @variable(model, AccumulatedNewCapacity[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    TotalCapacityAnnual = @variable(model, TotalCapacityAnnual[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)

    ############### Activity Variables #############

    @variable(model, RateOfActivity[𝓨,𝓛,𝓣,𝓜,𝓡] >= 0)
    @variable(model, TotalTechnologyAnnualActivity[𝓨,𝓣,𝓡] >= 0)
    
    @variable(model, TotalAnnualTechnologyActivityByMode[𝓨,𝓣,𝓜,𝓡] >= 0)
    
    @variable(model, ProductionByTechnologyAnnual[𝓨,𝓣,𝓕,𝓡] >= 0)
    
    @variable(model, UseByTechnologyAnnual[𝓨,𝓣,𝓕,𝓡] >= 0)
    
    @variable(model, TotalActivityPerYear[𝓡,𝓛,𝓣,𝓨] >= 0)
    @variable(model, CurtailedEnergyAnnual[𝓨,𝓕,𝓡] >= 0)
    @variable(model, CurtailedCapacity[𝓡,𝓛,𝓣,𝓨] >= 0)
    @variable(model, CurtailedEnergy[𝓨,𝓛,𝓕,𝓡] >= 0)
    @variable(model, DispatchDummy[𝓡,𝓛,𝓣,𝓨] >= 0)

    
    ############### Costing Variables #############

    if Switch.switch_dispatch == 0
        CapitalInvestment = @variable(model, CapitalInvestment[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    else
        CapitalInvestment = nothing
    end

    DiscountedCapitalInvestment = @variable(model, DiscountedCapitalInvestment[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    SalvageValue = @variable(model, SalvageValue[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    DiscountedSalvageValue = @variable(model, DiscountedSalvageValue[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    OperatingCost = @variable(model, OperatingCost[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    DiscountedOperatingCost = @variable(model, DiscountedOperatingCost[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    AnnualVariableOperatingCost = @variable(model, AnnualVariableOperatingCost[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    AnnualFixedOperatingCost = @variable(model, AnnualFixedOperatingCost[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    VariableOperatingCost = @variable(model, VariableOperatingCost[𝓨,𝓛,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    TotalDiscountedCost = @variable(model, TotalDiscountedCost[𝓨,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    TotalDiscountedCostByTechnology = @variable(model, TotalDiscountedCostByTechnology[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)

    AnnualCurtailmentCost = @variable(model, AnnualCurtailmentCost[𝓨,𝓕,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
    DiscountedAnnualCurtailmentCost = @variable(model, DiscountedAnnualCurtailmentCost[𝓨,𝓕,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)

    

    ############### Storage Variables #############

    if Switch.clusters == 0
        StorageLevelTSStart = @variable(model, StorageLevelTSStart[𝓢,𝓨,𝓛,𝓡]>= 0, container=JuMP.Containers.DenseAxisArray)
        StorageLevelYearStart = @variable(model, StorageLevelYearStart[𝓢,𝓨,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray)
        SoC_Inter = nothing
        SoC_Intra = nothing
        SoC_Intra_min = nothing
        SoC_Intra_max = nothing
    else
        StorageLevelTSStart = @variable(model, StorageLevelTSStart[intersect(𝓢, Params.TagTechnologyToSubsets["ShortTermStorage"]),𝓨,1:floor(Int, length(𝓛)/24), 1:25,𝓡]>= 0, container=JuMP.Containers.DenseAxisArray)
        StorageLevelYearStart = nothing
        SoC_Intra_min = @variable(model, SoC_Intra_min[intersect(𝓢, Params.TagTechnologyToSubsets["LongTermStorage"]),𝓨,1:floor(Int, length(𝓛)/24), 𝓡], container=JuMP.Containers.DenseAxisArray)
        SoC_Intra_max = @variable(model, SoC_Intra_max[intersect(𝓢, Params.TagTechnologyToSubsets["LongTermStorage"]),𝓨,1:floor(Int, length(𝓛)/24),𝓡], container=JuMP.Containers.DenseAxisArray)
        SoC_Inter = @variable(model, SoC_Inter[intersect(𝓢, Params.TagTechnologyToSubsets["LongTermStorage"]),𝓨,𝓡,1:366] >= 0, container=JuMP.Containers.DenseAxisArray)     
        SoC_Intra = @variable(model, SoC_Intra[intersect(𝓢, Params.TagTechnologyToSubsets["LongTermStorage"]),𝓨,1:floor(Int, length(𝓛)/24), 1:25,𝓡], container=JuMP.Containers.DenseAxisArray)
    end
    AccumulatedNewStorageCapacity = @variable(model, AccumulatedNewStorageCapacity[𝓢,𝓨,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    NewStorageCapacity = @variable(model, NewStorageCapacity[𝓢,𝓨,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    SalvageValueStorage = @variable(model, SalvageValueStorage[𝓢,𝓨,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    DiscountedSalvageValueStorage = @variable(model, DiscountedSalvageValueStorage[𝓢,𝓨,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    TotalDiscountedStorageCost = @variable(model, TotalDiscountedStorageCost[𝓢,𝓨,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 

    

    ######## Reserve Margin #############

    if Switch.switch_dispatch == 0 || Switch.switch_reserve == 1 || Switch.switch_reserve == 1
        TotalActivityInReserveMargin=@variable(model, TotalActivityInReserveMargin[𝓡,𝓨,𝓛] >= 0, container=JuMP.Containers.DenseAxisArray)
        DemandNeedingReserveMargin=@variable(model, DemandNeedingReserveMargin[𝓨,𝓛,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    else
        TotalActivityInReserveMargin = nothing
        DemandNeedingReserveMargin = nothing
    end

    

    ######## RE Gen Target #############
    TotalREProductionAnnual = @variable(model, TotalREProductionAnnual[𝓨,𝓡,𝓕], container=JuMP.Containers.DenseAxisArray) 
    RETotalDemandOfTargetFuelAnnual = @variable(model, RETotalDemandOfTargetFuelAnnual[𝓨,𝓡,𝓕], container=JuMP.Containers.DenseAxisArray) 
    TotalTechnologyModelPeriodActivity = @variable(model, TotalTechnologyModelPeriodActivity[𝓣,𝓡], container=JuMP.Containers.DenseAxisArray) 

    

    ######## Emissions #############

    AnnualTechnologyEmissionByMode = def_daa(𝓨,𝓣,𝓔,𝓜,𝓡)
    for y ∈ 𝓨 for r ∈ 𝓡 for t ∈ 𝓣 for e ∈ 𝓔 
        for m ∈ Maps.Tech_MO[t]
            AnnualTechnologyEmissionByMode[y,t,e,m,r] = @variable(model, lower_bound = 0, base_name= "AnnualTechnologyEmissionByMode[$y,$t,$e,$m,$r]")
        end
    end end end end 
    AnnualTechnologyEmission = @variable(model, AnnualTechnologyEmission[𝓨,𝓣,𝓔,𝓡], container=JuMP.Containers.DenseAxisArray) 
    AnnualTechnologyEmissionPenaltyByEmission = @variable(model, AnnualTechnologyEmissionPenaltyByEmission[𝓨,𝓣,𝓔,𝓡], container=JuMP.Containers.DenseAxisArray) 
    #AnnualTechnologyEmissionsPenalty = @variable(model, AnnualTechnologyEmissionsPenalty[𝓨,𝓣,𝓡], container=JuMP.Containers.DenseAxisArray) 
    DiscountedTechnologyEmissionsPenalty = @variable(model, DiscountedTechnologyEmissionsPenalty[𝓨,𝓣,𝓡], container=JuMP.Containers.DenseAxisArray) 
    if Switch.switch_emission_penalty == 0
        AnnualEmissions = @variable(model, AnnualEmissions[𝓨,𝓔,𝓡], container=JuMP.Containers.DenseAxisArray) 
        ModelPeriodEmissions = @variable(model, ModelPeriodEmissions[𝓔,𝓡], container=JuMP.Containers.DenseAxisArray)
        if Switch.switch_weighted_emissions == 1 
            WeightedAnnualEmissions = @variable(model, WeightedAnnualEmissions[𝓨,𝓔,𝓡], container=JuMP.Containers.DenseAxisArray)
        else
            WeightedAnnualEmissions = nothing
        end
    else
        AnnualEmissions = nothing
        ModelPeriodEmissions = nothing
        WeightedAnnualEmissions = nothing
    end
    
    ######### SectoralEmissions #############

    #AnnualSectoralEmissions = @variable(model, AnnualSectoralEmissions[𝓨,𝓔,𝓢𝓮,𝓡], container=JuMP.Containers.DenseAxisArray) 

    

    ######### Trade #############

    Import = @variable(model, Import[𝓨,𝓛,𝓕,𝓡,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    Export = @variable(model, Export[𝓨,𝓛,𝓕,𝓡,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 

    TotalTradeCapacity = @variable(model, TotalTradeCapacity[𝓨, Params.TagFuelToSubsets["TradeInv"], 𝓡, 𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    if Switch.switch_dispatch == 0
        NewTradeCapacity = @variable(model, NewTradeCapacity[𝓨, Params.TagFuelToSubsets["TradeInv"], 𝓡, 𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
        NewTradeCapacityCosts = @variable(model, NewTradeCapacityCosts[𝓨, Params.TagFuelToSubsets["TradeInv"], 𝓡, 𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
        DiscountedNewTradeCapacityCosts = @variable(model, DiscountedNewTradeCapacityCosts[𝓨, Params.TagFuelToSubsets["TradeInv"], 𝓡, 𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    
    else
        NewTradeCapacity = nothing
        NewTradeCapacityCosts = nothing
        DiscountedNewTradeCapacityCosts = nothing
    end

    NetTrade = @variable(model, NetTrade[𝓨,𝓛,𝓕,𝓡], container=JuMP.Containers.DenseAxisArray) 
    NetTradeAnnual = @variable(model, NetTradeAnnual[𝓨,𝓕,𝓡], container=JuMP.Containers.DenseAxisArray) 
    AnnualTotalTradeCosts = @variable(model, AnnualTotalTradeCosts[𝓨,𝓡], container=JuMP.Containers.DenseAxisArray) 
    DiscountedAnnualTotalTradeCosts = @variable(model, DiscountedAnnualTotalTradeCosts[𝓨,𝓡], container=JuMP.Containers.DenseAxisArray) 

    ######### Peaking #############
    if Switch.switch_peaking_capacity == 1
        PeakingDemand = @variable(model, PeakingDemand[𝓨,𝓡], container=JuMP.Containers.DenseAxisArray)
        PeakingCapacity = @variable(model, PeakingCapacity[𝓨,𝓡], container=JuMP.Containers.DenseAxisArray)
    else
        PeakingDemand=nothing
        PeakingCapacity=nothing
    end

    ######### Transportation #############


    #TrajectoryLowerLimit(𝓨) 
    #TrajectoryUpperLimit(𝓨) 

    DemandSplitByModalType = @variable(model, DemandSplitByModalType[𝓜𝓽,𝓛,𝓡,Params.TagFuelToSubsets["TransportFuels"],𝓨], container=JuMP.Containers.DenseAxisArray) 
    ProductionSplitByModalType = @variable(model, ProductionSplitByModalType[𝓜𝓽,𝓛,𝓡,Params.TagFuelToSubsets["TransportFuels"],𝓨], container=JuMP.Containers.DenseAxisArray) 

    if Switch.switch_ramping == 1

        ######## Ramping #############    
        ProductionUpChangeInTimeslice = def_daa(𝓨,𝓛,𝓕,𝓣,𝓡)
        ProductionDownChangeInTimeslice = def_daa(𝓨,𝓛,𝓕,𝓣,𝓡)
        for y ∈ 𝓨 for r ∈ 𝓡 for f ∈ 𝓕 for l ∈ 𝓛
            for t ∈ Maps.Fuel_Tech[f]
                ProductionUpChangeInTimeslice[y,l,f,t,r] = @variable(model, lower_bound = 0, base_name= "ProductionUpChangeInTimeslice[$y,$l,$f,$t,$r]")
                ProductionDownChangeInTimeslice[y,l,f,t,r] = @variable(model, lower_bound = 0, base_name= "ProductionDownChangeInTimeslice[$y,$l,$f,$t,$r]")
            end
        end end end end    
        @variable(model, AnnualProductionChangeCost[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
        @variable(model, DiscountedAnnualProductionChangeCost[𝓨,𝓣,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    else
        ProductionUpChangeInTimeslice=nothing
        ProductionDownChangeInTimeslice=nothing
        AnnualProductionChangeCost=nothing
        DiscountedAnnualProductionChangeCost=nothing
    end

    if Switch.switch_intertemporal == 1
        RateOfTotalActivity = @variable(model, RateOfTotalActivity[𝓨,𝓛,𝓣,𝓡], container=JuMP.Containers.DenseAxisArray)
    else
        RateOfTotalActivity=nothing
    end

    if Switch.switch_base_year_bounds == 1
        BaseYearSlack= @variable(model, BaseYearSlack[𝓕], container=JuMP.Containers.DenseAxisArray) 
        BaseYearBounds_TooLow = def_daa(𝓡,𝓣,𝓕,𝓨)
        BaseYearBounds_TooHigh = def_daa(𝓨,𝓡,𝓣,𝓕)
        for y ∈ 𝓨, r ∈ 𝓡, t ∈ 𝓣
            for f ∈ Maps.Tech_Fuel[t]
                BaseYearBounds_TooLow[r,t,f,y] = @variable(model, lower_bound = 0, base_name= "BaseYearBounds_TooLow[$r,$t,$f,$y]")
                BaseYearBounds_TooHigh[y,r,t,f] = @variable(model, lower_bound = 0, base_name= "BaseYearBounds_TooHigh[$y,$r,$t,$f]")
                if Switch.switch_base_year_bounds_debugging == 0
                    JuMP.fix(BaseYearBounds_TooLow[r,t,f,y], 0;force=true)
                    JuMP.fix(BaseYearBounds_TooHigh[y,r,t,f], 0;force=true)
                end
            end
        end 
    else
        BaseYearSlack = nothing
        BaseYearBounds_TooLow = nothing
        BaseYearBounds_TooHigh = nothing
    end

    if Switch.switch_dispatch == 0
        DiscountedSalvageValueTransmission= @variable(model, DiscountedSalvageValueTransmission[𝓨,𝓡] >= 0, container=JuMP.Containers.DenseAxisArray) 
    else
        DiscountedSalvageValueTransmission = nothing
    end


    Vars = GENeSYS_MOD.Variables(NewCapacity,AccumulatedNewCapacity,TotalCapacityAnnual,
    RateOfActivity,TotalAnnualTechnologyActivityByMode,ProductionByTechnologyAnnual,
    UseByTechnologyAnnual,TotalTechnologyAnnualActivity,TotalActivityPerYear,CurtailedEnergyAnnual,
    CurtailedCapacity,CurtailedEnergy,DispatchDummy,CapitalInvestment,DiscountedCapitalInvestment,
    SalvageValue,DiscountedSalvageValue,OperatingCost,DiscountedOperatingCost,AnnualVariableOperatingCost,
    AnnualFixedOperatingCost,VariableOperatingCost,TotalDiscountedCost,TotalDiscountedCostByTechnology,
    AnnualCurtailmentCost,DiscountedAnnualCurtailmentCost,
    StorageLevelYearStart,StorageLevelTSStart,AccumulatedNewStorageCapacity,NewStorageCapacity,SalvageValueStorage,
    DiscountedSalvageValueStorage,TotalDiscountedStorageCost,SoC_Inter,SoC_Intra,TotalActivityInReserveMargin,
    DemandNeedingReserveMargin,TotalREProductionAnnual,
    TotalTechnologyModelPeriodActivity,AnnualTechnologyEmissionByMode,
    AnnualTechnologyEmission,AnnualTechnologyEmissionPenaltyByEmission,
    DiscountedTechnologyEmissionsPenalty,AnnualEmissions,ModelPeriodEmissions,WeightedAnnualEmissions,
    Import,Export,NewTradeCapacity,TotalTradeCapacity,NewTradeCapacityCosts,
    DiscountedNewTradeCapacityCosts,NetTrade,NetTradeAnnual,AnnualTotalTradeCosts,
    DiscountedAnnualTotalTradeCosts,DemandSplitByModalType,ProductionSplitByModalType,
    ProductionUpChangeInTimeslice,ProductionDownChangeInTimeslice,
    RateOfTotalActivity,BaseYearSlack,BaseYearBounds_TooLow,BaseYearBounds_TooHigh, DiscountedSalvageValueTransmission,PeakingDemand,PeakingCapacity,
    AnnualProductionChangeCost,DiscountedAnnualProductionChangeCost, SoC_Intra_min, SoC_Intra_max)
    return Vars
end

