"""
Internal function used in the run process to load the input data and create the reduced timeseries.
"""
function genesysmod_dataload(Switch; dispatch_week=nothing)

    inputdir = Switch.inputdir

    in_data=XLSX.readxlsx(joinpath(inputdir, Switch.data_file * ".xlsx"))

    Sets = read_sets(in_data, Switch, Switch.switch_infeasibility_tech, Switch.switch_dispatch; dispatch_week=dispatch_week)

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

    Tags = read_tags(in_data, Sets, Switch, Switch.switch_infeasibility_tech, Switch.switch_dispatch)

    # Step 2: Read parameters from regional file  -> now includes World values

    Params, emp_Sets = read_params(in_data, copy(Sets), Switch, Tags) # copy sets to avoid problems when removing from the sets used to indexed the DAA

    # delete world region from region set
    remove_dummy_regions!(𝓡, Switch.switch_dispatch)

    #
    # ####### Assigning TradeRoutes depending on initialized Regions and Year #############
    #

    update_trade_params!(Params, Sets)

    #
    # ####### Load from hourly Data #############
    #

    GENeSYSMOD.timeseries_reduction!(Params, Sets, Switch)

    for i ∈ eachindex(𝓨)[2:end], r ∈ 𝓡, f ∈ setdiff(𝓕, ["H2"])
        Params.SpecifiedAnnualDemand[r,f,𝓨[i]] = Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]] * (1 + Params.SpecifiedDemandDevelopment[r,f,𝓨[i]] * YearlyDifferenceMultiplier(𝓨[i-1],Sets))
    end

    for y ∈ 𝓨 for l ∈ 𝓛 for r ∈ 𝓡
        for f ∈ 𝓕
            Params.RateOfDemand[y,l,f,r] = Params.SpecifiedAnnualDemand[r,f,y]*Params.SpecifiedDemandProfile[r,f,l,y] / Params.YearSplit[l,y]
            Params.Demand[y,l,f,r] = Params.RateOfDemand[y,l,f,r] * Params.YearSplit[l,y]
            if Params.Demand[y,l,f,r] < 0.000001
                Params.Demand[y,l,f,r] = 0
            end
        end
        for t ∈ 𝓣
            if Params.CapacityFactor[r,t,l,y] < 0.000001
                Params.CapacityFactor[r,t,l,y] = 0
            end
        end
    end end end

        #
    # ####### Dummy-Technologies [enable for test purposes, if model runs infeasible] #############
    #

    update_inftechs_params!(Params, Switch.switch_infeasibility_tech, Switch.switch_dispatch)

    return Sets, Params, emp_Sets
end

function remove_dummy_regions!(regions, s_dispatch)
    deleteat!(regions,findall(x->x=="World",regions))
end

function remove_dummy_regions!(regions, s_dispatch::TwoNodes)
    deleteat!(regions,findall(x->x=="World",regions))
    deleteat!(regions,findall(x->x=="Rest",regions))
end

"""
make_mapping(Sets,Params)

Creates a mapping of the allowed combinations of technology and fuel (and revers) and mode of operations.
"""
function make_mapping(Sets,Params)
    Map_Tech_Fuel = Dict(t=>[f for f ∈ Sets.Fuel if (any(Params.OutputActivityRatio[:,t,f,:,:].>0)
    || any(Params.InputActivityRatio[:,t,f,:,:].>0))] for t ∈ Sets.Technology)

   Map_Tech_MO = Dict(t=>[m for m ∈ Sets.Mode_of_operation if (any(Params.OutputActivityRatio[:,t,:,m,:].>0)
    || any(Params.InputActivityRatio[:,t,:,m,:].>0))] for t ∈ Sets.Technology)

   Map_Fuel_Tech = Dict(f=>[t for t ∈ Sets.Technology if (any(Params.OutputActivityRatio[:,t,f,:,:].>0)
    || any(Params.InputActivityRatio[:,t,f,:,:].>0))] for f ∈ Sets.Fuel)

    Set_Tech_MO = Set{Tuple{String,Int8}}([(t,m) for t ∈ Sets.Technology for m ∈ Map_Tech_MO[t]])

    Set_Tech_FuelIn = Set{Tuple{String,String}}([(t,f) for t ∈ Sets.Technology for f ∈ Sets.Fuel if (any(Params.InputActivityRatio[:,t,f,:,:].>0))])

    Set_Tech_FuelOut = Set{Tuple{String,String}}([(t,f) for t ∈ Sets.Technology for f ∈ Sets.Fuel if (any(Params.OutputActivityRatio[:,t,f,:,:].>0))])

    Set_Tech_Fuel = Set_Tech_FuelIn ∪ Set_Tech_FuelOut

    Set_Fuel_Regions = Set{Tuple{String,String,String}}([(f, r1, r2) for f ∈ Sets.Fuel
        for r1 ∈ Sets.Region_full for r2 ∈ Sets.Region_full if (any(x-> x!=0, Params.TradeRoute[r1,r2,f,:])
        && (Params.Tags.TagCanFuelBeTraded[f] != 0))])

    return Maps(Map_Tech_Fuel,Map_Tech_MO,Map_Fuel_Tech, Set_Tech_MO, Set_Tech_FuelIn, Set_Tech_FuelOut, Set_Tech_Fuel, Set_Fuel_Regions)
end

function read_sets(in_data, Switch, s_infeas, s_dispatch; dispatch_week=nothing)
    Timeslice_full = 1:8760

    Emission = DataFrame(XLSX.gettable(in_data["Sets"],"F";first_row=1))[!,"Emission"]
    Technology = DataFrame(XLSX.gettable(in_data["Sets"],"B";first_row=1))[!,"Technology"]
    Fuel = DataFrame(XLSX.gettable(in_data["Sets"],"D";first_row=1))[!,"Fuel"]
    Year = DataFrame(XLSX.gettable(in_data["Sets"],"I";first_row=1))[!,"Year"]
    Mode_of_operation = DataFrame(XLSX.gettable(in_data["Sets"],"E";first_row=1))[!,"Mode_of_operation"]
    Region_full = DataFrame(XLSX.gettable(in_data["Sets"],"A";first_row=1))[!,"Region"]
    Storage = DataFrame(XLSX.gettable(in_data["Sets"],"C";first_row=1))[!,"Storage"]
    ModalType = DataFrame(XLSX.gettable(in_data["Sets"],"G";first_row=1))[!,"ModalType"]
    Sector = DataFrame(XLSX.gettable(in_data["Sets"],"H";first_row=1))[!,"Sector"]

    add_extras_sets!(in_data, Technology, Storage, s_infeas, s_dispatch)
    add_dummy_region!(Region_full, s_dispatch)
    if !isnothing(dispatch_week) && dispatch_week > 0 && dispatch_week <= 52
        Timeslice = [(dispatch_week-1)*168+i for i in 1:168]
    else
        Timeslice = [x for x in Timeslice_full if (x-Switch.elmod_starthour)%(Switch.elmod_nthhour) == 0]
    end

    sets=Sets(Timeslice_full,Emission,Technology,Fuel,
        Year,Timeslice,Mode_of_operation,Region_full,Storage,ModalType,Sector)

    return sets
end

function add_extras_sets!(in_data, Technology, Storage, s_infeas, s_dispatch)
end

function add_extras_sets!(in_data, Technology, Storage, s_infeas::WithInfeasibilityTechs, s_dispatch)
    TagFuelToSubsets = read_subsets(in_data, "Par_TagFuelToSubsets")
    end_uses = union(["Power"], TagFuelToSubsets["HeatFuels"], TagFuelToSubsets["TransportFuels"])
    append!(Technology, ["Infeasibility_$(end_use)" for end_use in end_uses])
end

function add_extras_sets!(in_data, Technology, Storage, s_infeas::WithInfeasibilityTechs, s_dispatch::OneNodeStorage)
    add_extras_sets!(in_data, Technology, Storage, s_infeas, NoDispatch())
    append!(Technology, ["D_Trade_Storage_Power"])
    push!(Storage,"S_Trade_Storage_Power")
end

function add_dummy_region!(Region_full, s_dispatch)
    return
end

function add_dummy_region!(Region_full, s_dispatch::TwoNodes)
    push!(Region_full, "Rest")
end

function read_tags(in_data, Sets, Switch, s_infeas, s_dispatch)
    𝓡 = Sets.Region_full
    𝓕 = Sets.Fuel
    𝓨 = Sets.Year
    𝓣 = Sets.Technology
    𝓔 = Sets.Emission
    𝓜 = Sets.Mode_of_operation
    𝓛 = Sets.Timeslice
    𝓢 = Sets.Storage
    𝓜𝓽 = Sets.ModalType
    #𝓜𝓰 = Sets.ModalGroups
    𝓢𝓮 = Sets.Sector

    update_sectors!(Sets.Sector,s_infeas)

    TagTechnologyToSubsets = read_subsets(in_data, "Par_TagTechnologyToSubsets") #TODO handle the tags consistently: now we have lists of technology in one and DAA of tech, subsets and 1. Some parameters seems also redundant.
    TagFuelToSubsets = read_subsets(in_data, "Par_TagFuelToSubsets")
    TagDemandFuelToSector = create_daa(in_data, "Par_TagDemandFuelToSector", 𝓕, 𝓢𝓮)
    TagElectricTechnology = create_daa(in_data, "Par_TagElectricTechnology", 𝓣)
    TagTechnologyToModalType = create_daa(in_data, "Par_TagTechnologyToModalType", 𝓣, 𝓜, 𝓜𝓽)
    TagTechnologyToSector = create_daa(in_data, "Par_TagTechnologyToSector", 𝓣, 𝓢𝓮)
    RETagTechnology = DenseArray(zeros(length(𝓡), length(𝓣), length(𝓨)), 𝓡, 𝓣, 𝓨)
    RETagFuel = DenseArray(zeros(length(𝓡), length(𝓕), length(𝓨)), 𝓡, 𝓕, 𝓨)
    TagDispatchableTechnology = DenseArray(ones(length(𝓣)), 𝓣)
    #TagModalTypeToModalGroups = create_daa(in_data, "Par_TagModalTypeToModalGroups", 𝓜𝓽, 𝓜𝓰)
    TagModalTypeToModalGroups = create_daa(in_data, "Par_TagModalTypeToModalGroups", 𝓜𝓽, ["TransportModes","ModalSubgroups"])
    TagCanFuelBeTraded = create_daa(in_data, "Par_TagCanFuelBeTraded", 𝓕)

    tags = Tags(TagTechnologyToSubsets,TagFuelToSubsets,TagDemandFuelToSector,TagElectricTechnology,
    TagTechnologyToModalType,TagTechnologyToSector,RETagTechnology,RETagFuel,TagDispatchableTechnology,
    TagModalTypeToModalGroups,TagCanFuelBeTraded)

    add_extras_tags!(in_data, tags, Sets, s_infeas, s_dispatch)

    return tags
end

function add_extras_tags!(in_data, tags::Tags, sets, s_infeas, s_dispatch)
end

function add_extras_tags!(in_data, tags::Tags, sets, s_infeas::WithInfeasibilityTechs, s_dispatch)
    TagFuelToSubsets = read_subsets(in_data, "Par_TagFuelToSubsets")
    end_uses = union(["Power"], TagFuelToSubsets["HeatFuels"], TagFuelToSubsets["TransportFuels"])
    tags.TagTechnologyToSubsets["DummyTechnology"] = intersect(sets.Technology,["Infeasibility_$(end_use)" for end_use in end_uses])
end

function add_extras_tags!(in_data, tags::Tags, sets, s_infeas::WithInfeasibilityTechs, s_dispatch::OneNodeStorage)
    add_extras_tags!(in_data, tags, sets, s_infeas, NoDispatch())
    push!(tags.TagTechnologyToSubsets["DummyTechnology"], "D_Trade_Storage_Power")
    push!(tags.TagTechnologyToSubsets["StorageDummies"], "D_Trade_Storage_Power")
end

function update_inftechs_params!(Params, s_infeas, s_dispatch)
end

function update_inftechs_params!(Params, s_infeas::WithInfeasibilityTechs, s_dispatch)
    Params.Tags.TagTechnologyToSector[Params.Tags.TagTechnologyToSubsets["DummyTechnology"],"Infeasibility"] .= 1
    Params.AvailabilityFactor[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:] .= 0

    end_uses = union(["Power"], Params.Tags.TagFuelToSubsets["HeatFuels"], Params.Tags.TagFuelToSubsets["TransportFuels"])
    for end_use in end_uses
        Params.OutputActivityRatio[:,"Infeasibility_$(end_use)",end_use,1,:] .= 1
    end

    Params.CapacityToActivityUnit[Params.Tags.TagTechnologyToSubsets["DummyTechnology"]] .= 31.56
    Params.TotalAnnualMaxCapacity[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:] .= 999999
    Params.FixedCost[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:] .= 999
    Params.CapitalCost[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:] .= 999
    Params.VariableCost[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:,:] .= 999
    Params.AvailabilityFactor[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:] .= 1
    Params.CapacityFactor[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:,:] .= 1
    Params.OperationalLife[Params.Tags.TagTechnologyToSubsets["DummyTechnology"]] .= 1
    Params.EmissionActivityRatio[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:,:,:] .= 0
    Params.AnnualMaxNewCapacity[:,Params.Tags.TagTechnologyToSubsets["DummyTechnology"],:] .= 99999

    Params.Tags.TagTechnologyToModalType["Infeasibility_Mobility_Passenger",1,"MT_PSNG_ROAD"] .= 1
    Params.Tags.TagTechnologyToModalType["Infeasibility_Mobility_Passenger",1,"MT_PSNG_RAIL"] .= 1
    Params.Tags.TagTechnologyToModalType["Infeasibility_Mobility_Passenger",1,"MT_PSNG_AIR"] .= 1
    Params.Tags.TagTechnologyToModalType["Infeasibility_Mobility_Freight",1,"MT_FRT_ROAD"] .= 1
    Params.Tags.TagTechnologyToModalType["Infeasibility_Mobility_Freight",1,"MT_FRT_RAIL"] .= 1
    Params.Tags.TagTechnologyToModalType["Infeasibility_Mobility_Freight",1,"MT_FRT_SHIP"] .= 1
end

function update_inftechs_params!(Params, s_infeas::WithInfeasibilityTechs, s_dispatch::OneNodeStorage)
    update_inftechs_params!(Params, s_infeas, NoDispatch())

    Params.OutputActivityRatio[:,"D_Trade_Storage_Power","Power",2,:] .= 1
    Params.InputActivityRatio[:,"D_Trade_Storage_Power","Power",1,:] .= 1
    Params.FixedCost[:,"D_Trade_Storage_Power",:] .= 0.0001
    Params.CapitalCost[:,"D_Trade_Storage_Power",:] .= 0.0001
    Params.VariableCost[:,"D_Trade_Storage_Power",:,:] .= 0.0001
    Params.CapitalCostStorage[:,"S_Trade_Storage_Power",:] .= 0.0001
    Params.TechnologyToStorage["D_Trade_Storage_Power", "S_Trade_Storage_Power", 1, :] .= 0.95
    Params.TechnologyFromStorage["D_Trade_Storage_Power", "S_Trade_Storage_Power", 2, :] .= 0.95
    Params.OperationalLifeStorage["S_Trade_Storage_Power"] .= 100
    Params.AnnualMaxNewCapacity[:,"D_Trade_Storage_Power",:] .= 99999
end

function read_params(in_data, Sets, Switch, Tags)
    dbr = Switch.data_base_region

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

    AvailabilityFactor = create_daa(in_data, "Par_AvailabilityFactor", 𝓡, 𝓣, 𝓨; inherit_base_world=true, base_region=dbr)
    InputActivityRatio = create_daa(in_data, "Par_InputActivityRatio", 𝓡, 𝓣, 𝓕, 𝓜, 𝓨; inherit_base_world=true, base_region=dbr)
    OutputActivityRatio = create_daa(in_data, "Par_OutputActivityRatio", 𝓡, 𝓣, 𝓕, 𝓜, 𝓨; inherit_base_world=true, base_region=dbr)

    CapitalCost = create_daa(in_data, "Par_CapitalCost", 𝓡, 𝓣, 𝓨; inherit_base_world=true, base_region=dbr)
    FixedCost = create_daa(in_data, "Par_FixedCost", 𝓡, 𝓣, 𝓨; inherit_base_world=true, base_region=dbr)
    VariableCost = create_daa(in_data, "Par_VariableCost", 𝓡, 𝓣, 𝓜, 𝓨; inherit_base_world=true, base_region=dbr)

    EmissionActivityRatio = create_daa(in_data, "Par_EmissionActivityRatio", 𝓡, 𝓣, 𝓜, 𝓔, 𝓨; inherit_base_world=true, base_region=dbr)
    EmissionsPenalty = create_daa(in_data, "Par_EmissionsPenalty", 𝓡, 𝓔, 𝓨; inherit_base_world=true, base_region=dbr)
    EmissionsPenaltyTagTechnology = create_daa(in_data, "Par_EmissionPenaltyTagTech", 𝓡, 𝓣, 𝓔, 𝓨; inherit_base_world=true, base_region=dbr)

    ReserveMargin = create_daa(in_data,"Par_ReserveMargin", 𝓡, 𝓨; inherit_base_world=true, base_region=dbr)
    ReserveMarginTagFuel = create_daa(in_data, "Par_ReserveMarginTagFuel", 𝓡, 𝓕, 𝓨; inherit_base_world=true, base_region=dbr)
    ReserveMarginTagTechnology = create_daa(in_data, "Par_ReserveMarginTagTechnology", 𝓡, 𝓣, 𝓨;inherit_base_world=true, base_region=dbr)


    CapitalCostStorage = create_daa_init(in_data, "Par_CapitalCostStorage", 0.01, 𝓡, 𝓢, 𝓨;inherit_base_world=true, base_region=dbr)
    MinStorageCharge = create_daa(in_data, "Par_MinStorageCharge", 𝓡, 𝓢, 𝓨; copy_world=true, base_region=dbr)

    #CapacityFactor = create_daa(in_data, "Par_CapacityFactor",dbr, 𝓡, 𝓣, 𝓛, 𝓨)
    CapacityFactor = DenseArray(ones(length.([𝓡, 𝓣, 𝓛, 𝓨])...), 𝓡, 𝓣, 𝓛, 𝓨) #If this syntax works, apply it to other places

    CapacityToActivityUnit = create_daa(in_data, "Par_CapacityToActivityUnit", 𝓣)
    RegionalBaseYearProduction = create_daa(in_data, "Par_RegionalBaseYearProduction", 𝓡, 𝓣, 𝓕, 𝓨)
    SpecifiedAnnualDemand = create_daa(in_data, "Par_SpecifiedAnnualDemand", 𝓡, 𝓕, 𝓨)
    SpecifiedDemandDevelopment = create_daa(in_data, "Par_SpecifiedDemandDevelopment", 𝓡, 𝓕, 𝓨)

    AnnualEmissionLimit = create_daa(in_data,"Par_AnnualEmissionLimit", 𝓔, 𝓨)
    AnnualExogenousEmission = create_daa(in_data,"Par_AnnualExogenousEmission", 𝓡, 𝓔, 𝓨)
    AnnualSectoralEmissionLimit = create_daa(in_data, "Par_AnnualSectoralEmissionLimit", 𝓔, 𝓢𝓮, 𝓨)
    EmissionContentPerFuel = create_daa(in_data, "Par_EmissionContentPerFuel", 𝓕, 𝓔)
    RegionalAnnualEmissionLimit = create_daa(in_data,"Par_RegionalAnnualEmissionLimit", 𝓡, 𝓔, 𝓨; inherit_base_world=true, base_region=dbr)

    GrowthRateTradeCapacity = create_daa(in_data, "Par_GrowthRateTradeCapacity", 𝓡, 𝓡, 𝓕, 𝓨)
    TradeCapacity = create_daa(in_data,"Par_TradeCapacity", 𝓡, 𝓡, 𝓕, 𝓨)
    CommissionedTradeCapacity = create_daa(in_data,"Par_CommissionedTradeCapacity", 𝓡, 𝓡, 𝓕, 𝓨)
    REMinProductionTarget = create_daa(in_data,"Par_REMinProductionTarget", 𝓡, 𝓕, 𝓨)
    SelfSufficiency = create_daa(in_data,"Par_SelfSufficiency", 𝓡, 𝓕, 𝓨)
    ProductionGrowthLimit = create_daa(in_data, "Par_ProductionGrowthLimit", 𝓕, 𝓨)
    Readin_TradeRoute2015 = create_daa(in_data,"Par_TradeRoute", 𝓡, 𝓡, 𝓕)
    TradeRoute = DenseArray(zeros(length.([𝓡, 𝓡, 𝓕, 𝓨])...), 𝓡, 𝓡, 𝓕, 𝓨)
    for y ∈ 𝓨
        TradeRoute[:,:,:,y] = Readin_TradeRoute2015
        for f ∈ 𝓕
            for r ∈ 𝓡 for rr ∈ 𝓡
                if TradeRoute[r,rr,f,y] != TradeRoute[rr,r,f,y]
                    println("TradeRoute is not symmetric for $f in $y: $r -> $rr != $rr -> $r")
                end
            end end
        end
    end
    TradeCapacityGrowthCosts = create_daa(in_data, "Par_TradeCapacityGrowthCosts", 𝓡, 𝓡, 𝓕)
    #TradeCosts = create_daa(in_data,"Par_TradeCosts", 𝓕, 𝓡, 𝓡)
    TradeCostFactor = create_daa(in_data,"Par_TradeCostFactor", 𝓕, 𝓨)


    ResidualCapacity = create_daa(in_data, "Par_ResidualCapacity", 𝓡, 𝓣, 𝓨)

    TotalAnnualMaxCapacity = create_daa(in_data, "Par_TotalAnnualMaxCapacity", 𝓡, 𝓣, 𝓨)
    NewCapacityExpansionStop = create_daa(in_data, "Par_NewCapacityExpansionStop", 𝓡, 𝓣)
    TotalAnnualMinCapacity = create_daa(in_data, "Par_TotalAnnualMinCapacity", 𝓡, 𝓣, 𝓨)
    TotalTechnologyAnnualActivityUpperLimit = create_daa(in_data, "Par_TotalAnnualMaxActivity", 𝓡, 𝓣, 𝓨)
    TotalTechnologyAnnualActivityLowerLimit = create_daa(in_data, "Par_TotalAnnualMinActivity", 𝓡, 𝓣, 𝓨)
    TotalTechnologyModelPeriodActivityUpperLimit = create_daa_init(in_data, "Par_ModelPeriodActivityMaxLimit", 999999, 𝓡, 𝓣)

    OperationalLife = create_daa(in_data, "Par_OperationalLife", 𝓣)

    RegionalCCSLimit = create_daa(in_data, "Par_RegionalCCSLimit", 𝓡)

    OperationalLifeStorage = create_daa(in_data, "Par_OperationalLifeStorage", 𝓢)
    ResidualStorageCapacity = create_daa(in_data, "Par_ResidualStorageCapacity", 𝓡, 𝓢, 𝓨)
    StorageLevelStart = create_daa(in_data, "Par_StorageLevelStart", 𝓡, 𝓢)
    TechnologyToStorage = create_daa(in_data, "Par_TechnologyToStorage", Tags.TagTechnologyToSubsets["StorageDummies"], 𝓢, 𝓜, 𝓨)
    TechnologyFromStorage = create_daa(in_data, "Par_TechnologyFromStorage", Tags.TagTechnologyToSubsets["StorageDummies"], 𝓢, 𝓜, 𝓨)

    ModalSplitByFuelAndModalType = create_daa(in_data, "Par_ModalSplitByFuel", 𝓡, 𝓕, 𝓨, 𝓜𝓽)

    #StorageE2PRatio = nothing
    StorageE2PRatio = create_daa(in_data, "Par_StorageE2PRatio", 𝓢)
    ModelPeriodEmissionLimit = create_daa(in_data, "Par_ModelPeriodEmissionLimit", 𝓔)
    RegionalModelPeriodEmissionLimit = create_daa(in_data, "Par_RegionalModelPeriodEmission", 𝓡, 𝓔)
    ModelPeriodExogenousEmission = create_daa(in_data, "Par_ModelPeriodExogenousEmissio", 𝓡, 𝓔)
    AnnualMinNewCapacity = create_daa(in_data, "Par_AnnualMinNewCapacity", 𝓡, 𝓣, 𝓨)
    AnnualMaxNewCapacity = create_daa(in_data, "Par_AnnualMaxNewCapacity", 𝓡, 𝓣, 𝓨)
    DistrictHeatDemand = create_daa(in_data, "Par_DistrictHeatDemand", 𝓡, 𝓨)
    DistrictHeatSplit = create_daa(in_data, "Par_DistrictHeatSplit", 𝓡, 𝓢𝓮, 𝓨)

    RateOfDemand = DenseArray(zeros(length.([𝓨, 𝓛, 𝓕, 𝓡])...), 𝓨, 𝓛, 𝓕, 𝓡)
    Demand = DenseArray(zeros(length.([𝓨, 𝓛, 𝓕, 𝓡])...), 𝓨, 𝓛, 𝓕, 𝓡)
    StorageMaxCapacity = DenseArray(zeros(length.([𝓡, 𝓢, 𝓨])...), 𝓡, 𝓢, 𝓨)
    TotalAnnualMaxCapacityInvestment = DenseArray(fill(999999, length.([𝓡, 𝓣, 𝓨])...), 𝓡, 𝓣, 𝓨)
    TotalAnnualMinCapacityInvestment = DenseArray(zeros(length.([𝓡, 𝓣, 𝓨])...), 𝓡, 𝓣, 𝓨)
    TotalTechnologyModelPeriodActivityLowerLimit = DenseArray(zeros(length.([𝓡, 𝓣])...), 𝓡, 𝓣)

    CurtailmentCostFactor = DenseArray(fill(0.1,length.([𝓡, 𝓕, 𝓨])...), 𝓡, 𝓕, 𝓨)
    TradeLossFactor = DenseArray(zeros(length.([𝓕, 𝓨])...), 𝓕, 𝓨)
    TradeRouteInstalledCapacity = DenseArray(zeros(length.([𝓡, 𝓡, 𝓕, 𝓨])...), 𝓡, 𝓡, 𝓕, 𝓨)
    TradeLossBetweenRegions = DenseArray(zeros(length.([𝓡, 𝓡, 𝓕, 𝓨])...), 𝓡, 𝓡, 𝓕, 𝓨)

    SpecifiedDemandProfile = DenseArray(zeros(length.([𝓡, 𝓕, 𝓛, 𝓨])...), 𝓡, 𝓕, 𝓛, 𝓨)
    YearSplit = DenseArray(ones(length.([𝓛, 𝓨])...) * 1/length(𝓛), 𝓛, 𝓨)
    TimeDepEfficiency = DenseArray(ones(length.([𝓡, 𝓣, 𝓛, 𝓨])...), 𝓡, 𝓣, 𝓛, 𝓨)
    x_peakingDemand = DenseArray(zeros(length.([𝓡, 𝓢𝓮])...),𝓡, 𝓢𝓮)


    TradeCosts = DenseArray(zeros(length.([𝓡, 𝓕, 𝓨, 𝓡])...), 𝓡, 𝓕, 𝓨, 𝓡)
    for r ∈ 𝓡, f ∈ 𝓕, y ∈ 𝓨, rr ∈ 𝓡
        TradeCosts[r,f,y,rr] = TradeCostFactor[f,y]*TradeRoute[r,rr,f,y]
        if GrowthRateTradeCapacity[r,rr,f,y] == 0
            GrowthRateTradeCapacity[r,rr,f,y] = GrowthRateTradeCapacity[r,rr,f,Switch.StartYear]
        end
    end

    if Switch.switch_ramping == 1
        RampingUpFactor = create_daa(in_data, "Par_RampingUpFactor", 𝓣,𝓨)
        RampingDownFactor = create_daa(in_data, "Par_RampingDownFactor",𝓣,𝓨)
        ProductionChangeCost = create_daa(in_data, "Par_ProductionChangeCost",𝓣,𝓨)
        MinActiveProductionPerTimeslice = DenseArray(zeros(length(𝓨), length(𝓛), length(𝓕), length(𝓣), length(𝓡)), 𝓨, 𝓛, 𝓕, 𝓣, 𝓡)

        MinActiveProductionPerTimeslice[:,:,"Power","RES_Hydro_Large",:] .= 0.1
        MinActiveProductionPerTimeslice[:,:,"Power","RES_Hydro_Small",:] .= 0.05
    else
        RampingUpFactor = nothing
        RampingDownFactor = nothing
        ProductionChangeCost = nothing
        MinActiveProductionPerTimeslice = nothing
    end

    if Switch.switch_employment_calculation == 1
        ########## Dataload of Employment Excel ##########
        employment_data = XLSX.readxlsx(joinpath(inputdir, Switch.employment_data_file * ".xlsx"))

        Technology = DataFrame(XLSX.gettable(employment_data["Sets"],"A";first_row=1)...)[!,"Technology"]
        Year = DataFrame(XLSX.gettable(employment_data["Sets"],"D";first_row=1)...)[!,"Year"]
        Region = DataFrame(XLSX.gettable(employment_data["Sets"],"G";first_row=1)...)[!,"Region"]

        emp_Sets=Emp_Sets(Technology,Year,Region)


        EFactorConstruction = create_daa(employment_data, "Par_EFactorConstruction", emp_Sets.Technology, emp_Sets.Year)
        EFactorOM = create_daa(employment_data, "Par_EFactorOM", emp_Sets.Technology, emp_Sets.Year)
        EFactorManufacturing = create_daa(employment_data, "Par_EFactorManufacturing", emp_Sets.Technology, emp_Sets.Year)
        EFactorFuelSupply = create_daa(employment_data, "Par_EFactorFuelSupply", emp_Sets.Technology, emp_Sets.Year)
        EFactorCoalJobs = create_daa(employment_data, "Par_EFactorCoalJobs", emp_Sets.Technology, emp_Sets.Year)
        CoalSupply = create_daa(employment_data, "Par_CoalSupply", 𝓡, emp_Sets.Year)
        CoalDigging = create_daa(employment_data, "Par_CoalDigging", Switch.model_region,
            emp_Sets.Technology, "$(Switch.emissionPathway)_$(Switch.emissionScenario)", 𝓨)
        RegionalAdjustmentFactor = create_daa(employment_data, "PAR_RegionalAdjustmentFactor", Switch.model_region, emp_Sets.Year)
        LocalManufacturingFactor = create_daa(employment_data, "PAR_LocalManufacturingFactor", Switch.model_region, emp_Sets.Year)
        DeclineRate = create_daa(employment_data, "PAR_DeclineRate", emp_Sets.Technology, emp_Sets.Year)

    else
        EFactorConstruction = nothing
        EFactorOM = nothing
        EFactorManufacturing = nothing
        EFactorFuelSupply = nothing
        EFactorCoalJobs = nothing
        CoalSupply = nothing
        CoalDigging = nothing
        RegionalAdjustmentFactor = nothing
        LocalManufacturingFactor = nothing
        DeclineRate = nothing

        emp_Sets=Emp_Sets(nothing,nothing,nothing)
    end

    Params = Parameters(YearSplit,Tags,SpecifiedAnnualDemand, SpecifiedDemandDevelopment,
    SpecifiedDemandProfile, RateOfDemand,Demand,CapacityToActivityUnit,CapacityFactor,
    AvailabilityFactor,OperationalLife,ResidualCapacity,InputActivityRatio,OutputActivityRatio,
    RegionalBaseYearProduction,TimeDepEfficiency,RegionalCCSLimit,CapitalCost,VariableCost,FixedCost,
    StorageLevelStart,MinStorageCharge,
    OperationalLifeStorage,CapitalCostStorage,ResidualStorageCapacity,TechnologyToStorage,
    TechnologyFromStorage,StorageMaxCapacity,TotalAnnualMaxCapacity, NewCapacityExpansionStop,TotalAnnualMinCapacity,
    AnnualSectoralEmissionLimit,TotalAnnualMaxCapacityInvestment,
    TotalAnnualMinCapacityInvestment,TotalTechnologyAnnualActivityUpperLimit,
    TotalTechnologyAnnualActivityLowerLimit, TotalTechnologyModelPeriodActivityUpperLimit,
    TotalTechnologyModelPeriodActivityLowerLimit,ReserveMarginTagTechnology,
    ReserveMarginTagFuel,ReserveMargin,
    EmissionActivityRatio, EmissionContentPerFuel,EmissionsPenalty,EmissionsPenaltyTagTechnology,
    AnnualExogenousEmission,AnnualEmissionLimit,RegionalAnnualEmissionLimit,
    ModelPeriodExogenousEmission,AnnualMinNewCapacity,AnnualMaxNewCapacity,DistrictHeatDemand,
    DistrictHeatSplit,ModelPeriodEmissionLimit,RegionalModelPeriodEmissionLimit,
    CurtailmentCostFactor,TradeRoute,TradeCosts,
    TradeLossFactor,TradeRouteInstalledCapacity,TradeLossBetweenRegions,
    TradeCapacity, CommissionedTradeCapacity,REMinProductionTarget,TradeCapacityGrowthCosts,GrowthRateTradeCapacity,SelfSufficiency,
    ProductionGrowthLimit, RampingUpFactor,RampingDownFactor,ProductionChangeCost,MinActiveProductionPerTimeslice,
    ModalSplitByFuelAndModalType,EFactorConstruction, EFactorOM,
    EFactorManufacturing, EFactorFuelSupply, EFactorCoalJobs,CoalSupply, CoalDigging,
    RegionalAdjustmentFactor, LocalManufacturingFactor, DeclineRate,x_peakingDemand,
    StorageE2PRatio)

    return Params, emp_Sets
end

function get_aggregate_params(Params_Full, Sets, Sets_full)

    𝓡_full = Sets_full.Region_full
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

#=     AvailabilityFactor = DenseArray(zeros(length.([𝓡, 𝓣, 𝓨])...), 𝓡, 𝓣, 𝓨)
    AvailabilityFactor[𝓡[1],:,:] = Params_Full.AvailabilityFactor[𝓡[1],:,𝓨]
    AvailabilityFactor[𝓡[2],:,:] = Params_Full.AvailabilityFactor[𝓡[3],:,𝓨]
    AvailabilityFactor[𝓡[3],:,:] = Params_Full.AvailabilityFactor[𝓡[3],:,𝓨]
    AvailabilityFactor = inherit_values(Params_Full.AvailabilityFactor, 𝓡, 𝓣, 𝓨) =#
    AvailabilityFactor = Params_Full.AvailabilityFactor[𝓡,:,𝓨]
    InputActivityRatio = Params_Full.InputActivityRatio[𝓡,:,:,:,𝓨]
    OutputActivityRatio = Params_Full.OutputActivityRatio[𝓡,:,:,:,𝓨]
    CapitalCost = Params_Full.CapitalCost[𝓡,:,𝓨]
    FixedCost = Params_Full.FixedCost[𝓡,:,𝓨]
    VariableCost = Params_Full.VariableCost[𝓡,:,:,𝓨]

    EmissionActivityRatio = Params_Full.EmissionActivityRatio[𝓡,:,:,:,𝓨]
    EmissionsPenalty = Params_Full.EmissionsPenalty[𝓡,:,𝓨]
    EmissionsPenaltyTagTechnology = Params_Full.EmissionsPenaltyTagTechnology[𝓡,:,:,𝓨]

    #CapacityFactor = create_daa(in_data, "Par_CapacityFactor",dbr, 𝓡, 𝓣, 𝓛, 𝓨)

    ReserveMargin = Params_Full.ReserveMargin[𝓡,𝓨]
    ReserveMarginTagFuel = Params_Full.ReserveMarginTagFuel[𝓡,:,𝓨]
    ReserveMarginTagTechnology = Params_Full.ReserveMarginTagTechnology[𝓡,:,𝓨]


    CapitalCostStorage = Params_Full.CapitalCostStorage[𝓡,:,𝓨]
    MinStorageCharge = Params_Full.MinStorageCharge[𝓡,:,𝓨]

    CapacityToActivityUnit = Params_Full.CapacityToActivityUnit
    RegionalBaseYearProduction = aggregate_daa(Params_Full.RegionalBaseYearProduction, 𝓡, 𝓡_full, Sum(), 𝓣, 𝓕, 𝓨)
    SpecifiedAnnualDemand = aggregate_daa(Params_Full.SpecifiedAnnualDemand, 𝓡, 𝓡_full, Sum(), 𝓕, 𝓨)
    SpecifiedDemandDevelopment = aggregate_daa(Params_Full.SpecifiedDemandDevelopment, 𝓡, 𝓡_full, Mean(), 𝓕, 𝓨)

    AnnualEmissionLimit = Params_Full.AnnualEmissionLimit[:,𝓨]
    AnnualExogenousEmission = aggregate_daa(Params_Full.AnnualExogenousEmission, 𝓡, 𝓡_full, Sum(), 𝓔, 𝓨)
    AnnualSectoralEmissionLimit = Params_Full.AnnualSectoralEmissionLimit[:,:,𝓨]
    EmissionContentPerFuel = Params_Full.EmissionContentPerFuel
    RegionalAnnualEmissionLimit = aggregate_daa(Params_Full.RegionalAnnualEmissionLimit, 𝓡, 𝓡_full, Sum(), 𝓔, 𝓨)
    AnnualMinNewCapacity = aggregate_daa(Params_Full.AnnualMinNewCapacity, 𝓡, 𝓡_full, Sum(), 𝓣, 𝓨)
    AnnualMaxNewCapacity = aggregate_daa(Params_Full.AnnualMaxNewCapacity, 𝓡, 𝓡_full, Sum(), 𝓣, 𝓨)
    DistrictHeatDemand = aggregate_daa(Params_Full.DistrictHeatDemand, 𝓡, 𝓡_full, Sum(), 𝓨)
    DistrictHeatSplit = aggregate_daa(Params_Full.DistrictHeatSplit, 𝓡, 𝓡_full, Mean(), 𝓢𝓮, 𝓨)

    GrowthRateTradeCapacity = aggregate_cross_daa(Params_Full.GrowthRateTradeCapacity, 𝓡, 𝓡_full, Mean(), 𝓕, 𝓨)
    TradeCapacity = aggregate_cross_daa(Params_Full.TradeCapacity, 𝓡, 𝓡_full, Sum(), 𝓕, 𝓨)
    TradeRoute = aggregate_cross_daa(Params_Full.TradeRoute, 𝓡, 𝓡_full, Mean(), 𝓕, 𝓨)
    TradeCapacityGrowthCosts = aggregate_cross_daa(Params_Full.TradeCapacityGrowthCosts, 𝓡, 𝓡_full, Mean(), 𝓕)
    TradeCosts = JuMP.Containers.DenseAxisArray(
        zeros(length(𝓡),length(𝓕),length(𝓨),length(𝓡)), 𝓡, 𝓕, 𝓨, 𝓡)
    for f in 𝓕 for y in 𝓨
        TradeCosts[𝓡[1],f,y,𝓡[2]] = (sum(Params_Full.TradeCosts[𝓡[1],f,y,r] for r in 𝓡_full) - Params_Full.TradeCosts[𝓡[1],f,y,𝓡[1]])/(length(𝓡_full)-1)
        TradeCosts[𝓡[2],f,y,𝓡[1]] = (sum(Params_Full.TradeCosts[r,f,y,𝓡[1]] for r in 𝓡_full) - Params_Full.TradeCosts[𝓡[1],f,y,𝓡[1]])/(length(𝓡_full)-1)
    end end
    TradeLossBetweenRegions = aggregate_cross_daa(Params_Full.TradeLossBetweenRegions, 𝓡, 𝓡_full, Mean(), 𝓕, 𝓨)

    ResidualCapacity = aggregate_daa(Params_Full.ResidualCapacity, 𝓡, 𝓡_full, Sum(), 𝓣, 𝓨)


    # Correction of the max capacity value
    for r ∈ 𝓡_full for t ∈ 𝓣 for y ∈ 𝓨
        if ((max(Params_Full.TotalAnnualMaxCapacity[r,t,y], Params_Full.ResidualCapacity[r,t,y]) >0 )
            && (max(Params_Full.TotalAnnualMaxCapacity[r,t,y], Params_Full.ResidualCapacity[r,t,y]) < 999999))
            Params_Full.TotalAnnualMaxCapacity[r,t,y] = max(Params_Full.TotalAnnualMaxCapacity[r,t,y], Params_Full.ResidualCapacity[r,t,y])
        end
    end end end
    TotalAnnualMaxCapacity = aggregate_daa(Params_Full.TotalAnnualMaxCapacity, 𝓡, 𝓡_full, Sum(), 𝓣, 𝓨)
    NewCapacityExpansionStop = JuMP.Containers.DenseAxisArray(zeros(length(𝓡),length(𝓣)), 𝓡, 𝓣)

    TotalAnnualMinCapacity = aggregate_daa(Params_Full.TotalAnnualMinCapacity, 𝓡, 𝓡_full, Sum(), 𝓣, 𝓨)
    TotalTechnologyAnnualActivityUpperLimit = aggregate_daa(Params_Full.TotalTechnologyAnnualActivityUpperLimit, 𝓡, 𝓡_full, Sum(), 𝓣, 𝓨)
    TotalTechnologyAnnualActivityLowerLimit = aggregate_daa(Params_Full.TotalTechnologyAnnualActivityLowerLimit, 𝓡, 𝓡_full, Sum(), 𝓣, 𝓨)
    TotalTechnologyModelPeriodActivityUpperLimit = aggregate_daa(Params_Full.TotalTechnologyModelPeriodActivityUpperLimit, 𝓡, 𝓡_full, Sum(), 𝓣)

    OperationalLife = Params_Full.OperationalLife

    RegionalCCSLimit = aggregate_daa(Params_Full.RegionalCCSLimit, 𝓡, 𝓡_full, Sum())

    OperationalLifeStorage = Params_Full.OperationalLifeStorage
    ResidualStorageCapacity = aggregate_daa(Params_Full.ResidualStorageCapacity, 𝓡, 𝓡_full, Sum(), 𝓢, 𝓨)
    StorageLevelStart = aggregate_daa(Params_Full.StorageLevelStart, 𝓡, 𝓡_full, Sum(), 𝓢)
    TechnologyToStorage = Params_Full.TechnologyToStorage[:,:,:,𝓨]
    TechnologyFromStorage = Params_Full.TechnologyFromStorage[:,:,:,𝓨]

    ModalSplitByFuelAndModalType = aggregate_daa(Params_Full.ModalSplitByFuelAndModalType, 𝓡, 𝓡_full, Mean(), 𝓕, 𝓨, 𝓜𝓽)

    StorageE2PRatio = Params_Full.StorageE2PRatio

    RateOfDemand = Params_Full.RateOfDemand[𝓨,:,:,𝓡]
    Demand = Params_Full.Demand[𝓨,:,:,𝓡]
    StorageMaxCapacity = Params_Full.StorageMaxCapacity[𝓡,:,𝓨]
    TotalAnnualMaxCapacityInvestment = Params_Full.TotalAnnualMaxCapacityInvestment[𝓡,:,𝓨]
    TotalAnnualMinCapacityInvestment = Params_Full.TotalAnnualMinCapacityInvestment[𝓡,:,𝓨]
    TotalTechnologyModelPeriodActivityLowerLimit = Params_Full.TotalTechnologyModelPeriodActivityLowerLimit[𝓡,:]

    REMinProductionTarget = Params_Full.REMinProductionTarget[𝓡,:,𝓨]

    ModelPeriodExogenousEmission = Params_Full.ModelPeriodExogenousEmission[𝓡,:]
    ModelPeriodEmissionLimit = Params_Full.ModelPeriodEmissionLimit
    RegionalModelPeriodEmissionLimit = Params_Full.RegionalModelPeriodEmissionLimit[𝓡,:]

    CurtailmentCostFactor = Params_Full.CurtailmentCostFactor[𝓡,:,𝓨]
    TradeLossFactor = Params_Full.TradeLossFactor[:,𝓨]
    TradeRouteInstalledCapacity = Params_Full.TradeRouteInstalledCapacity[𝓡,𝓡,:,𝓨]

    CommissionedTradeCapacity = Params_Full.CommissionedTradeCapacity[𝓡,𝓡,:,𝓨]

    SelfSufficiency = Params_Full.SelfSufficiency[𝓡,:,𝓨]
    ProductionGrowthLimit = Params_Full.ProductionGrowthLimit

    RampingUpFactor = Params_Full.RampingUpFactor
    RampingDownFactor = Params_Full.RampingDownFactor
    ProductionChangeCost = Params_Full.ProductionChangeCost
    MinActiveProductionPerTimeslice = Params_Full.MinActiveProductionPerTimeslice

    EFactorConstruction = Params_Full.EFactorConstruction
    EFactorOM = Params_Full.EFactorOM
    EFactorManufacturing = Params_Full.EFactorManufacturing
    EFactorFuelSupply = Params_Full.EFactorFuelSupply
    EFactorCoalJobs = Params_Full.EFactorCoalJobs
    CoalSupply = Params_Full.CoalSupply
    CoalDigging = Params_Full.CoalDigging
    RegionalAdjustmentFactor = Params_Full.RegionalAdjustmentFactor
    LocalManufacturingFactor = Params_Full.LocalManufacturingFactor
    DeclineRate = Params_Full.DeclineRate

    CapacityFactor = aggregate_daa(Params_Full.CapacityFactor, 𝓡, 𝓡_full, Mean(), 𝓣, 𝓛, 𝓨)
    # no peaking constraint for the dispatch
    x_peakingDemand = aggregate_daa(Params_Full.x_peakingDemand,𝓡, 𝓡_full, Mean(), 𝓢𝓮)
    TimeDepEfficiency = aggregate_daa(Params_Full.TimeDepEfficiency,𝓡, 𝓡_full, Mean(), 𝓣, 𝓛, 𝓨)

    SpecifiedDemandProfile = DenseArray(zeros(length.([𝓡, 𝓕, 𝓛, 𝓨])...), 𝓡, 𝓕, 𝓛, 𝓨)
    YearSplit = DenseArray(ones(length.([𝓛, 𝓨])...) * 1/length(𝓛), 𝓛, 𝓨)

    Params = GENeSYSMOD.Parameters(YearSplit,Params_Full.Tags,SpecifiedAnnualDemand,
    SpecifiedDemandDevelopment,
    SpecifiedDemandProfile,RateOfDemand,Demand,CapacityToActivityUnit,CapacityFactor,
    AvailabilityFactor,OperationalLife,ResidualCapacity,InputActivityRatio,OutputActivityRatio,
    RegionalBaseYearProduction,TimeDepEfficiency,RegionalCCSLimit,CapitalCost,VariableCost,FixedCost,
    StorageLevelStart,MinStorageCharge,
    OperationalLifeStorage,CapitalCostStorage,ResidualStorageCapacity,TechnologyToStorage,
    TechnologyFromStorage,StorageMaxCapacity,TotalAnnualMaxCapacity,
    NewCapacityExpansionStop,TotalAnnualMinCapacity,
    AnnualSectoralEmissionLimit,TotalAnnualMaxCapacityInvestment,
    TotalAnnualMinCapacityInvestment,TotalTechnologyAnnualActivityUpperLimit,
    TotalTechnologyAnnualActivityLowerLimit, TotalTechnologyModelPeriodActivityUpperLimit,
    TotalTechnologyModelPeriodActivityLowerLimit,ReserveMarginTagTechnology,
    ReserveMarginTagFuel,ReserveMargin,
    EmissionActivityRatio, EmissionContentPerFuel,EmissionsPenalty,EmissionsPenaltyTagTechnology,
    AnnualExogenousEmission,AnnualEmissionLimit,RegionalAnnualEmissionLimit,
    ModelPeriodExogenousEmission,AnnualMinNewCapacity,AnnualMaxNewCapacity,DistrictHeatDemand,
    DistrictHeatSplit,ModelPeriodEmissionLimit,RegionalModelPeriodEmissionLimit,
    CurtailmentCostFactor,TradeRoute,TradeCosts,
    TradeLossFactor,TradeRouteInstalledCapacity,TradeLossBetweenRegions,
    TradeCapacity,CommissionedTradeCapacity,REMinProductionTarget,TradeCapacityGrowthCosts,GrowthRateTradeCapacity,SelfSufficiency,
    ProductionGrowthLimit,RampingUpFactor,RampingDownFactor,ProductionChangeCost,MinActiveProductionPerTimeslice,
    ModalSplitByFuelAndModalType,EFactorConstruction, EFactorOM,
    EFactorManufacturing, EFactorFuelSupply, EFactorCoalJobs,CoalSupply, CoalDigging,
    RegionalAdjustmentFactor, LocalManufacturingFactor, DeclineRate,x_peakingDemand,
    StorageE2PRatio)
return Params
end

function update_trade_params!(Params, Sets)
    # setting the following to0 should not be necessary as they should already be at 0.
#=     Params.TradeCapacity[:,"World",:,:] .= 0
    Params.TradeCapacity["World",:,:,:] .= 0 =#
    Params.TradeLossFactor["Power",:] .= 0.00003
#=     Params.TradeRoute[:,"World",:,:] .= 0
    Params.TradeRoute["World",:,:,:] .= 0
    Params.GrowthRateTradeCapacity[:,"World",:,:] .= 0
    Params.GrowthRateTradeCapacity["World",:,:,:] .= 0 =#
    for y ∈ Sets.Year
        for r ∈ Sets.Region_full for rr ∈ Sets.Region_full
            for f ∈ Sets.Fuel
                Params.TradeLossBetweenRegions[r,rr,f,y] = Params.TradeLossFactor[f,y]*Params.TradeRoute[r,rr,f,y]
            end
        end end
    end

    for y ∈ Sets.Year[2:end]
        for r ∈ Sets.Region_full for rr ∈ Sets.Region_full
            Params.GrowthRateTradeCapacity[r,rr,"Power",y] = Params.GrowthRateTradeCapacity[r,rr,"Power",Sets.Year[1]]
        end end
    end
end

function aggregate_params(Switch, Sets_full, Params_full, s_dispatch::TwoNodes)
    considered_regions = [Switch.switch_dispatch.considered_region, "Rest", "World"]
    considered_year = [Switch.StartYear]
    sets = Sets(Sets_full.Timeslice,Sets_full.Emission,Sets_full.Technology,Sets_full.Fuel,
    considered_year,Sets_full.Timeslice,Sets_full.Mode_of_operation,considered_regions,
    Sets_full.Storage,Sets_full.ModalType,Sets_full.Sector)

    𝓡_full = Sets_full.Region_full
    𝓡 = sets.Region_full
    𝓕 = sets.Fuel
    𝓨 = sets.Year
    𝓣 = sets.Technology
    𝓔 = sets.Emission
    𝓜 = sets.Mode_of_operation
    𝓛 = sets.Timeslice
    𝓢 = sets.Storage
    𝓜𝓽 = sets.ModalType
    𝓢𝓮 = sets.Sector

    Params = get_aggregate_params(Params_full, sets, Sets_full)

    deleteat!(𝓡,findall(x->x=="World",𝓡))
    deleteat!(considered_regions,findall(x->x=="World",considered_regions))

    # aggregation of the timeseries data (with ponderation for the demand profile and the peaking demand)
    for f in 𝓕 for l in 𝓛 for y in 𝓨
        sum_demand = sum(Params_full.SpecifiedAnnualDemand[r,f,y] for r in 𝓡_full if r!=considered_regions[1])
        if sum_demand!=0
            Params.SpecifiedDemandProfile[considered_regions[2],f,l,y] =
            sum(Params_full.SpecifiedDemandProfile[r,f,l,y]*Params_full.SpecifiedAnnualDemand[r,f,y] for r in 𝓡_full if r!=considered_regions[1])/sum_demand
        end
        Params.SpecifiedDemandProfile[considered_regions[1],f,l,y] = Params_full.SpecifiedDemandProfile[considered_regions[1],f,l,y]
    end end end

    for y ∈ 𝓨 for l ∈ 𝓛 for r ∈ 𝓡
        for f ∈ 𝓕
            Params.RateOfDemand[y,l,f,r] = Params.SpecifiedAnnualDemand[r,f,y]*Params.SpecifiedDemandProfile[r,f,l,y] / Params.YearSplit[l,y]
            Params.Demand[y,l,f,r] = Params.RateOfDemand[y,l,f,r] * Params.YearSplit[l,y]
            if Params.Demand[y,l,f,r] < 0.000001
                Params.Demand[y,l,f,r] = 0
            end
        end
        for t ∈ 𝓣
            if Params.CapacityFactor[r,t,l,y] < 0.000001
                Params.CapacityFactor[r,t,l,y] = 0
            end
        end
    end end end

    #
    # ####### Dummy-Technologies [enable for test purposes, if model runs infeasible] #############
    #

    update_inftechs_params!(Params, Switch.switch_infeasibility_tech, Switch.switch_dispatch)
    return sets, Params, 𝓡_full, Params_full
end

function aggregate_params(Switch, Sets_full, Params_full, s_dispatch::NoDispatch)
    return Sets_full, Params_full, nothing, nothing
end

function aggregate_params(Switch, Sets_full, Params_full, s_dispatch)
    considered_region = [Switch.switch_dispatch.considered_region]
    considered_year = [Switch.StartYear]
    sets = Sets(Sets_full.Timeslice,Sets_full.Emission,Sets_full.Technology,Sets_full.Fuel,
    considered_year,Sets_full.Timeslice,Sets_full.Mode_of_operation,considered_region,
    Sets_full.Storage,Sets_full.ModalType,Sets_full.Sector)
    return sets, Params_full, Sets_full.Region_full, nothing
end

function update_sectors!(sectors,s_infeas)
end

function update_sectors!(sectors,s_infeas::WithInfeasibilityTechs)
    push!(sectors,"Infeasibility")
end
