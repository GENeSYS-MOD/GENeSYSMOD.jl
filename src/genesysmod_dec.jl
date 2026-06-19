function def_daa(sets...)
    daa = DenseArray{Union{Float64,VariableRef}}(
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

    NewCapacity = @variable(model, NewCapacity[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    AccumulatedNewCapacity = @variable(model, AccumulatedNewCapacity[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    TotalCapacityAnnual = @variable(model, TotalCapacityAnnual[𝓨,𝓣,𝓡] >= 0, container=DenseArray)

    ############### Activity Variables #############

    RateOfActivity = @variable(model, RateOfActivity[y=𝓨, l=𝓛, t=𝓣, m=𝓜, r=𝓡; (t,m) ∈ Maps.Set_Tech_MO] >= 0)
    TotalAnnualTechnologyActivityByMode = @variable(model, TotalAnnualTechnologyActivityByMode[y=𝓨, t=𝓣, m=𝓜, r=𝓡; (t,m) ∈ Maps.Set_Tech_MO] >= 0)
    ProductionByTechnologyAnnual = @variable(model, ProductionByTechnologyAnnual[y=𝓨, t=𝓣, f=𝓕, r=𝓡; (t,f) ∈ Maps.Set_Tech_FuelOut] >= 0)
    UseByTechnologyAnnual = @variable(model, UseByTechnologyAnnual[y=𝓨, t=𝓣, f=𝓕, r=𝓡; (t,f) ∈ Maps.Set_Tech_FuelIn] >= 0)

    TotalTechnologyAnnualActivity = @variable(model, TotalTechnologyAnnualActivity[𝓨,𝓣,𝓡] >= 0)

    TotalActivityPerYear = @variable(model, TotalActivityPerYear[𝓡,𝓛,𝓣,𝓨] >= 0)
    CurtailedEnergyAnnual = @variable(model, CurtailedEnergyAnnual[𝓨,𝓕,𝓡] >= 0)
    CurtailedCapacity = @variable(model, CurtailedCapacity[𝓡,𝓛,𝓣,𝓨] >= 0)
    CurtailedEnergy = @variable(model, CurtailedEnergy[𝓨,𝓛,𝓕,𝓡] >= 0)
    DispatchDummy = @variable(model, DispatchDummy[𝓡,𝓛,𝓣,𝓨] >= 0)


    ############### Costing Variables #############

    CapitalInvestment = @variable(model, CapitalInvestment[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    DiscountedCapitalInvestment = @variable(model, DiscountedCapitalInvestment[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    SalvageValue = @variable(model, SalvageValue[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    DiscountedSalvageValue = @variable(model, DiscountedSalvageValue[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    OperatingCost = @variable(model, OperatingCost[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    DiscountedOperatingCost = @variable(model, DiscountedOperatingCost[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    AnnualVariableOperatingCost = @variable(model, AnnualVariableOperatingCost[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    AnnualFixedOperatingCost = @variable(model, AnnualFixedOperatingCost[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    VariableOperatingCost = @variable(model, VariableOperatingCost[𝓨,𝓛,𝓣,𝓡] >= 0, container=DenseArray)
    TotalDiscountedCost = @variable(model, TotalDiscountedCost[𝓨,𝓡] >= 0, container=DenseArray)
    TotalDiscountedCostByTechnology = @variable(model, TotalDiscountedCostByTechnology[𝓨,𝓣,𝓡] >= 0, container=DenseArray)

    AnnualCurtailmentCost = @variable(model, AnnualCurtailmentCost[𝓨,𝓕,𝓡] >= 0, container=DenseArray)
    DiscountedAnnualCurtailmentCost = @variable(model, DiscountedAnnualCurtailmentCost[𝓨,𝓕,𝓡] >= 0, container=DenseArray)



    ############### Storage Variables #############

    StorageLevelYearStart = @variable(model, StorageLevelYearStart[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    StorageLevelYearFinish = @variable(model, StorageLevelYearFinish[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    StorageLevelTSStart = @variable(model, StorageLevelTSStart[𝓢,𝓨,𝓛,𝓡] >= 0, container=DenseArray)
    AccumulatedNewStorageCapacity = @variable(model, AccumulatedNewStorageCapacity[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    NewStorageCapacity = @variable(model, NewStorageCapacity[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    TotalStorageCapacityAnnual = @variable(model, TotalStorageCapacityAnnual[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    CapitalInvestmentStorage = @variable(model, CapitalInvestmentStorage[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    DiscountedCapitalInvestmentStorage = @variable(model, DiscountedCapitalInvestmentStorage[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    SalvageValueStorage = @variable(model, SalvageValueStorage[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    DiscountedSalvageValueStorage = @variable(model, DiscountedSalvageValueStorage[𝓢,𝓨,𝓡] >= 0, container=DenseArray)
    TotalDiscountedStorageCost = @variable(model, TotalDiscountedStorageCost[𝓢,𝓨,𝓡] >= 0, container=DenseArray)



    ######## Reserve Margin #############

    if Switch.switch_dispatch isa NoDispatch && Switch.switch_reserve == 1
        TotalActivityInReserveMargin=@variable(model, TotalActivityInReserveMargin[𝓡,𝓨,𝓛] >= 0, container=DenseArray)
        DemandNeedingReserveMargin=@variable(model, DemandNeedingReserveMargin[𝓨,𝓛,𝓡] >= 0, container=DenseArray)
    else
        TotalActivityInReserveMargin = nothing
        DemandNeedingReserveMargin = nothing
    end



    ######## RE Gen Target #############

    TotalREProductionAnnual = @variable(model, TotalREProductionAnnual[𝓨,𝓡,𝓕], container=DenseArray)
    TotalTechnologyModelPeriodActivity = @variable(model, TotalTechnologyModelPeriodActivity[𝓣,𝓡], container=DenseArray)
    RETargetMin = @variable(model, RETargetMin[𝓨,𝓡] >= 0, container=DenseArray)



    ######## Emissions #############

    AnnualTechnologyEmissionByMode = @variable(model, AnnualTechnologyEmissionByMode[y=𝓨, t=𝓣, e=𝓔, m=𝓜, r=𝓡; (t,m) ∈ Maps.Set_Tech_MO])
    AnnualTechnologyEmission = @variable(model, AnnualTechnologyEmission[𝓨,𝓣,𝓔,𝓡], container=DenseArray)
    AnnualTechnologyEmissionPenaltyByEmission = @variable(model, AnnualTechnologyEmissionPenaltyByEmission[𝓨,𝓣,𝓔,𝓡], container=DenseArray)
    AnnualTechnologyEmissionsPenalty = @variable(model, AnnualTechnologyEmissionsPenalty[𝓨,𝓣,𝓡], container=DenseArray)
    DiscountedTechnologyEmissionsPenalty = @variable(model, DiscountedTechnologyEmissionsPenalty[𝓨,𝓣,𝓡], container=DenseArray)
    AnnualEmissions = @variable(model, AnnualEmissions[𝓨,𝓔,𝓡], container=DenseArray)
    ModelPeriodEmissions = @variable(model, ModelPeriodEmissions[𝓡,𝓔], container=DenseArray)
    WeightedAnnualEmissions = @variable(model, WeightedAnnualEmissions[𝓨,𝓔,𝓡], container=DenseArray)


    ######### SectoralEmissions #############

    AnnualSectoralEmissions = @variable(model, AnnualSectoralEmissions[𝓨,𝓔,𝓢𝓮,𝓡], container=DenseArray)


    ######### Trade #############
    imp_exp_sets = isempty(Maps.Set_Fuel_Regions) ? Set([(String("ETS"),String(𝓡[1]),String(𝓡[1]))]) : Maps.Set_Fuel_Regions # dummy to avoid type problems in dispatch if se is empty
    Import = @variable(model, Import[y=𝓨, l=𝓛, f=𝓕, r1=𝓡, r2=𝓡; (f,r1,r2) ∈ imp_exp_sets] >= 0)
    Export = @variable(model, Export[y=𝓨, l=𝓛, f=𝓕, r1=𝓡, r2=𝓡; (f,r1,r2) ∈ imp_exp_sets] >= 0)
    NewTradeCapacity = @variable(model, NewTradeCapacity[y=𝓨, f=𝓕, r1=𝓡, r2=𝓡; (f,r1,r2) ∈ imp_exp_sets] >= 0)
    TotalTradeCapacity = @variable(model, TotalTradeCapacity[y=𝓨, f=𝓕, r1=𝓡, r2=𝓡; (f,r1,r2) ∈ imp_exp_sets] >= 0)
    NewTradeCapacityCosts = @variable(model, NewTradeCapacityCosts[y=𝓨, f=𝓕, r1=𝓡, r2=𝓡; (f,r1,r2) ∈ imp_exp_sets] >= 0)
    DiscountedNewTradeCapacityCosts = @variable(model, DiscountedNewTradeCapacityCosts[y=𝓨, f=𝓕, r1=𝓡, r2=𝓡; (f,r1,r2) ∈ imp_exp_sets] >= 0)
    NetTrade = @variable(model, NetTrade[𝓨,𝓛,𝓕,𝓡], container=DenseArray)
    NetTradeAnnual = @variable(model, NetTradeAnnual[𝓨,𝓕,𝓡], container=DenseArray)
    AnnualTotalTradeCosts = @variable(model, AnnualTotalTradeCosts[𝓨,𝓡], container=DenseArray)
    DiscountedAnnualTotalTradeCosts = @variable(model, DiscountedAnnualTotalTradeCosts[𝓨,𝓡], container=DenseArray)

    ######### Peaking #############
    if Switch.switch_peaking_capacity == 1
        PeakingDemand = @variable(model, PeakingDemand[𝓨,𝓡], container=DenseArray)
        PeakingCapacity = @variable(model, PeakingCapacity[𝓨,𝓡], container=DenseArray)
    else
        PeakingDemand=nothing
        PeakingCapacity=nothing
    end

    ######### Transportation #############


    #TrajectoryLowerLimit(𝓨)
    #TrajectoryUpperLimit(𝓨)

    DemandSplitByModalType = @variable(model, DemandSplitByModalType[𝓜𝓽,𝓛,𝓡,Params.Tags.TagFuelToSubsets["TransportFuels"],𝓨] >= 0, container=DenseArray)
    ProductionSplitByModalType = @variable(model, ProductionSplitByModalType[𝓜𝓽,𝓛,𝓡,Params.Tags.TagFuelToSubsets["TransportFuels"],𝓨] >= 0, container=DenseArray)
    if Switch.switch_ramping == 1
        ######## Ramping #############
        ProductionUpChangeInTimeslice = @variable(model, ProductionUpChangeInTimeslice[y=𝓨, l=𝓛, f=𝓕, t=𝓣, r=𝓡; (t,f) ∈ Maps.Set_Tech_FuelOut] >= 0)
        ProductionDownChangeInTimeslice = @variable(model, ProductionDownChangeInTimeslice[y=𝓨, l=𝓛, f=𝓕, t=𝓣, r=𝓡; (t,f) ∈ Maps.Set_Tech_FuelOut] >= 0)
        AnnualProductionChangeCost = @variable(model, AnnualProductionChangeCost[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
        DiscountedAnnualProductionChangeCost = @variable(model, DiscountedAnnualProductionChangeCost[𝓨,𝓣,𝓡] >= 0, container=DenseArray)
    else
        ProductionUpChangeInTimeslice=nothing
        ProductionDownChangeInTimeslice=nothing
        AnnualProductionChangeCost=nothing
        DiscountedAnnualProductionChangeCost=nothing
    end

    if Switch.switch_intertemporal == 1
        RateOfTotalActivity = @variable(model, RateOfTotalActivity[𝓨,𝓛,𝓣,𝓡], container=DenseArray)
    else
        RateOfTotalActivity=nothing
    end

    # Debug-only slack variables: only declared when switch_base_year_bounds_debugging == 1.
    # Production runs skip them entirely (lean LP, no BigM penalty rows, no fix-to-0 vars).
    if Switch.switch_base_year_bounds_debugging == 1
        BaseYearBounds_TooLow  = @variable(model, BaseYearBounds_TooLow[r=𝓡, t=𝓣, f=𝓕, y=𝓨; (t,f) ∈ Maps.Set_Tech_FuelOut] >= 0)
        BaseYearBounds_TooHigh = @variable(model, BaseYearBounds_TooHigh[r=𝓡, t=𝓣, f=𝓕, y=𝓨; (t,f) ∈ Maps.Set_Tech_FuelOut] >= 0)
        HeatingSlack           = @variable(model, HeatingSlack[𝓡, 𝓨] >= 0, container=DenseArray)
    else
        BaseYearBounds_TooLow  = nothing
        BaseYearBounds_TooHigh = nothing
        HeatingSlack           = nothing
    end

    DiscountedSalvageValueTransmission= @variable(model, DiscountedSalvageValueTransmission[𝓨,𝓡] >= 0, container=DenseArray)

    Vars = GENeSYSMOD.Variables(NewCapacity,AccumulatedNewCapacity,TotalCapacityAnnual,
    RateOfActivity,TotalAnnualTechnologyActivityByMode,ProductionByTechnologyAnnual,
    UseByTechnologyAnnual,TotalTechnologyAnnualActivity,TotalActivityPerYear,CurtailedEnergyAnnual,
    CurtailedCapacity,CurtailedEnergy,DispatchDummy,CapitalInvestment,DiscountedCapitalInvestment,
    SalvageValue,DiscountedSalvageValue,OperatingCost,DiscountedOperatingCost,AnnualVariableOperatingCost,
    AnnualFixedOperatingCost,VariableOperatingCost,TotalDiscountedCost,TotalDiscountedCostByTechnology,
    AnnualCurtailmentCost,DiscountedAnnualCurtailmentCost,
    StorageLevelYearStart,StorageLevelYearFinish,StorageLevelTSStart,AccumulatedNewStorageCapacity,NewStorageCapacity,
    TotalStorageCapacityAnnual,CapitalInvestmentStorage,DiscountedCapitalInvestmentStorage,SalvageValueStorage,
    DiscountedSalvageValueStorage,TotalDiscountedStorageCost,TotalActivityInReserveMargin,
    DemandNeedingReserveMargin,TotalREProductionAnnual,
    TotalTechnologyModelPeriodActivity,RETargetMin,AnnualTechnologyEmissionByMode,
    AnnualTechnologyEmission,AnnualTechnologyEmissionPenaltyByEmission,AnnualTechnologyEmissionsPenalty,
    DiscountedTechnologyEmissionsPenalty,AnnualEmissions,ModelPeriodEmissions,WeightedAnnualEmissions,
    AnnualSectoralEmissions,Import,Export,NewTradeCapacity,TotalTradeCapacity,NewTradeCapacityCosts,
    DiscountedNewTradeCapacityCosts,NetTrade,NetTradeAnnual,AnnualTotalTradeCosts,
    DiscountedAnnualTotalTradeCosts,DemandSplitByModalType,ProductionSplitByModalType,
    ProductionUpChangeInTimeslice,ProductionDownChangeInTimeslice,
    RateOfTotalActivity,BaseYearBounds_TooLow,BaseYearBounds_TooHigh, HeatingSlack, DiscountedSalvageValueTransmission,PeakingDemand,PeakingCapacity,
    AnnualProductionChangeCost,DiscountedAnnualProductionChangeCost)
    return Vars
end
