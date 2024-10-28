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
InputClass - Abstract type for the inputs
"""
abstract type InputClass end

"""
All the parameters read for a model run

# Extended
# Fields
- **`StartYear ::Int64`** First year of the study horizon.\n
- **`YearSplit ::JuMP.Containers.DenseAxisArray`** Weighting factors of the each timeslice,
     i.e. how much of the whole year is represented by a given tiomeslice. \n 
- **`SpecifiedAnnualDemand ::JuMP.Containers.DenseAxisArray`** Total specified demand for a year.\n
- **`SpecifiedDemandProfile ::JuMP.Containers.DenseAxisArray`** Annual fraction of 
    energy-service or commodity demand that is required in each time slice. For each
    year, all the defined SpecifiedDemandProfile input values should sum up to 1.\n
- **`RateOfDemand ::JuMP.Containers.DenseAxisArray`** Rate of Demand in each timeslice.\n
- **`Demand ::JuMP.Containers.DenseAxisArray`** Amount of demand in each timeslice.\n
- **`CapacityToActivityUnit ::JuMP.Containers.DenseAxisArray`** Conversion factor relating
    the energy that would be produced when one unit of capacity is fully used in one year.\n
- **`CapacityFactor ::JuMP.Containers.DenseAxisArray`** Capacity available per each
    TimeSlice expressed as a fraction of the total installed capacity, with values ranging
    from 0 to 1. It gives the possibility to account for forced outages or variable renewable generation. \n
- **`AvailabilityFactor ::JuMP.Containers.DenseAxisArray`** Maximum time a technology can
    run in the whole year, as a fraction of the year ranging from 0 to 1. It gives the
    possibility to account for planned outages.\n
- **`OperationalLife ::JuMP.Containers.DenseAxisArray`** Useful lifetime of a technology,
    expressed in years.\n
- **`ResidualCapacity ::JuMP.Containers.DenseAxisArray`** Amount of capacity from the capacity
existing in the system in the start year to remain in the given year.\n
- **`InputActivityRatio ::JuMP.Containers.DenseAxisArray`** Rate of use of a fuel by a
    technology, as a ratio of the rate of activity. Used to express technology efficiencies.\n
- **`OutputActivityRatio ::JuMP.Containers.DenseAxisArray`** Rate of fuel output from a
    technology, as a ratio of the rate of activity.\n
- **`TagDispatchableTechnology ::JuMP.Containers.DenseAxisArray`** Tag defining if a technology 
can be dispatched.\n 
- **`RegionalBaseYearProduction ::JuMP.Containers.DenseAxisArray`** Amount of energy produced by 
technologies in the start year. Used if switch_base_year_bounds is set to 1.\n
- **`RegionalCCSLimit ::JuMP.Containers.DenseAxisArray`** Total amount of storeable emissions
    in a certain region over the entire modelled period.\n
- **`CapitalCost ::JuMP.Containers.DenseAxisArray`** Capital investment cost of a technology,
    per unit of capacity.\n
- **`VariableCost ::JuMP.Containers.DenseAxisArray`** Cost of a technology for a given mode
    of operation (e.g., Variable O&M cost, fuel costs, etc.), per unit of activity.\n
- **`FixedCost ::JuMP.Containers.DenseAxisArray`** Fixed O&M cost of a technology, per unit
    of capacity.\n
- **`StorageLevelStart ::JuMP.Containers.DenseAxisArray`** Level of storage at the beginning
    of first modelled year, in units of activity.\n
- **`MinStorageCharge ::JuMP.Containers.DenseAxisArray`** Sets a lower bound to the amount
    of energy stored, as a fraction of the maximum, with a number ranging between 0 and 1.
    The storage facility cannot be emptied below this level.\n
- **`OperationalLifeStorage ::JuMP.Containers.DenseAxisArray`** Useful lifetime of the
    storage facility.\n
- **`CapitalCostStorage ::JuMP.Containers.DenseAxisArray`** Binary parameter linking a 
    technology to the storage facility it charges. It has value 0 if the technology and the
    storage facility are not linked, 1 if they are.\n
- **`ResidualStorageCapacity ::JuMP.Containers.DenseAxisArray`** Binary parameter linking a
    storage facility to the technology it feeds. It has value 0 if the technology and the
    storage facility are not linked, 1 if they are.\n
- **`TechnologyToStorage ::JuMP.Containers.DenseAxisArray`** Binary parameter linking a 
    technology to the storage facility it charges. It has value 1 if the technology and the
    storage facility are linked, 0 otherwise.\n
- **`TechnologyFromStorage ::JuMP.Containers.DenseAxisArray`** Binary parameter linking a
    storage facility to the technology it feeds. It has value 1 if the technology and the
    storage facility are linked, 0 otherwise.\n
- **`StorageMaxCapacity ::JuMP.Containers.DenseAxisArray`** Maximum storage capacity.\n
- **`TotalAnnualMaxCapacity ::JuMP.Containers.DenseAxisArray`** Total maximum existing 
    (residual plus cumulatively installed) capacity allowed for a technology in a specified
    year.\n
- **`TotalAnnualMinCapacity ::JuMP.Containers.DenseAxisArray`** Total minimum existing 
    (residual plus cumulatively installed) capacity allowed for a technology in a specified
    year.\n
- **`TagTechnologyToSector ::JuMP.Containers.DenseAxisArray`** Links technologies to sectors. \n
- **`AnnualSectoralEmissionLimit ::JuMP.Containers.DenseAxisArray`** Annual upper limit for
    a specific emission generated in a certain sector for the whole modelled region.\n
- **`TotalAnnualMaxCapacityInvestment ::JuMP.Containers.DenseAxisArray`** Maximum capacity of
    a technology, expressed in power units.\n
- **`TotalAnnualMinCapacityInvestment ::JuMP.Containers.DenseAxisArray`** Minimum capacity of
    a technology, expressed in power units.\n
- **`TotalTechnologyAnnualActivityUpperLimit ::JuMP.Containers.DenseAxisArray`** Total maximum
    level of activity allowed for a technology in one year.\n
- **`TotalTechnologyAnnualActivityLowerLimit ::JuMP.Containers.DenseAxisArray`** Total minimum 
    level of activity allowed for a technology in one year.\n
- **`TotalTechnologyModelPeriodActivityUpperLimit ::JuMP.Containers.DenseAxisArray`** Total 
    maximum level of activity allowed for a technology in the entire modelled period.\n
- **`TotalTechnologyModelPeriodActivityLowerLimit ::JuMP.Containers.DenseAxisArray`** Total 
    minimum level of activity allowed for a technology in the entire modelled period.\n
- **`ReserveMarginTagTechnology ::JuMP.Containers.DenseAxisArray`** Binary parameter tagging
    the technologies that are allowed to contribute to the reserve margin. It has value 1 
    for the technologies allowed, 0 otherwise.\n
- **`ReserveMarginTagFuel ::JuMP.Containers.DenseAxisArray`** Binary parameter tagging the
    fuels to which the reserve margin applies. It has value 1 if the reserve margin applies
    to the fuel, 0 otherwise.\n
- **`ReserveMargin ::JuMP.Containers.DenseAxisArray`** Minimum level of the reserve margin
    required to be provided for all the tagged commodities, by the tagged technologies. 
    If no reserve margin is required, the parameter will have value 1; if, for instance, 20%
    reserve margin is required, the parameter will have value 1.2.\n
- **`RETagTechnology ::JuMP.Containers.DenseAxisArray`** Tag to identify renewable technologies.\n
- **`RETagFuel ::JuMP.Containers.DenseAxisArray`** Tag to identify renewable fuels.\n
- **`REMinProductionTarget ::JuMP.Containers.DenseAxisArray`** Minimum production from renewable
    technologies.\n
- **`EmissionActivityRatio ::JuMP.Containers.DenseAxisArray`** Emission factor of a 
    technology per unit of activity, per mode of operation.\n
- **`EmissionContentPerFuel ::JuMP.Containers.DenseAxisArray`** Defines the emission contents 
    per fuel.\n
- **`EmissionsPenalty ::JuMP.Containers.DenseAxisArray`** Monetary penalty per unit of emission.\n
- **`EmissionsPenaltyTagTechnology ::JuMP.Containers.DenseAxisArray`** Activates or deactivates
    emission penalties for specific technologies.\n
- **`AnnualExogenousEmission ::JuMP.Containers.DenseAxisArray`** Additional annual emissions,
    on top of those computed endogenously by the model.\n
- **`AnnualEmissionLimit ::JuMP.Containers.DenseAxisArray`** Annual upper limit for a specific
    emission generated in the whole modelled region.\n
- **`RegionalAnnualEmissionLimit ::JuMP.Containers.DenseAxisArray`** Annual upper limit for
    a specific emission generated in a certain modelled region.\n
- **`ModelPeriodExogenousEmission ::JuMP.Containers.DenseAxisArray`** Additional emissions 
    over the entire modelled period, on top of those computed endogenously by the model.\n
- **`ModelPeriodEmissionLimit ::JuMP.Containers.DenseAxisArray`** Total model period upper 
    limit for a specific emission generated in the whole modelled region.\n
- **`RegionalModelPeriodEmissionLimit ::JuMP.Containers.DenseAxisArray`** Total model period
    upper limit for a specific emission generated in a certain modelled region.\n
- **`CurtailmentCostFactor ::JuMP.Containers.DenseAxisArray`** Costs per curtailed unit of
    activity for certain fuels and years.\n
- **`TradeRoute ::JuMP.Containers.DenseAxisArray`** Sets the distance in km from one region
    to another. Also controls the ability to trade on fuel from a region to another.\n
- **`TradeCosts ::JuMP.Containers.DenseAxisArray`** Costs for trading one unit of energy from
    one region to another.\n
- **`TradeLossFactor ::JuMP.Containers.DenseAxisArray`** Factor for the amount of losses per
    kilometer of a given fuel\n
- **`TradeRouteInstalledCapacity ::JuMP.Containers.DenseAxisArray`** Installed transmission 
    capacity between nodes.\n
- **`TradeLossBetweenRegions ::JuMP.Containers.DenseAxisArray`** Percentage loss of traded 
    fuel from one region to another. Used to model losses in power transmission networks.\n
- **`CommissionedTradeCapacity ::JuMP.Containers.DenseAxisArray`** Transmission line already 
    commissioned.\n
- **`TradeCapacity ::JuMP.Containers.DenseAxisArray`** Initial capacity for trading fuels 
    from one region to another.\n
- **`TradeCapacityGrowthCosts ::JuMP.Containers.DenseAxisArray`** Costs for adding one unit 
    of additional trade capacity per km from one region to another.\n
- **`GrowthRateTradeCapacity ::JuMP.Containers.DenseAxisArray`** Upper limit for adding 
    additional trade capacities. Given as maximal percentage increase of installed capacity.\n
- **`SelfSufficiency ::JuMP.Containers.DenseAxisArray`** Lower bound that limits the imports 
    of fuels in as specific year and region.\n
- **`RampingUpFactor ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** Defines how much of 
    the built capacity can be activated each timeslice.\n
- **`RampingDownFactor ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** Defines how much 
    of the built capacity can be deactivated each timeslice.\n
- **`ProductionChangeCost ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** Cost per unit 
    of activated or deactivated capacity per timeslice.\n
- **`MinActiveProductionPerTimeslice ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** 
    Minimum fuel production from specific technologies in a certain timeslice. Represents 
    minimum active capacity requirements.\n
- **`ModalSplitByFuelAndModalType ::JuMP.Containers.DenseAxisArray`** Lower bound of 
    production of certain fuels by specific modal types.\n
- **`TagTechnologyToModalType ::JuMP.Containers.DenseAxisArray`** Links technology production 
    by mode of operation to modal stype.\n
- **`EFactorConstruction ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`EFactorOM ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`EFactorManufacturing ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`EFactorFuelSupply ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`EFactorCoalJobs ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`CoalSupply ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`CoalDigging ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`RegionalAdjustmentFactor ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`LocalManufacturingFactor ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`DeclineRate ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** \n TODO
- **`x_peakingDemand ::Union{Nothing,JuMP.Containers.DenseAxisArray}`** Peak demand in the 
    original timeseries. Used for the peaking constraints.\n
- **`TagDemandFuelToSector ::JuMP.Containers.DenseAxisArray`** Tag to link fuels to sectors.\n
- **`TagElectricTechnology ::JuMP.Containers.DenseAxisArray`** Indicate if a technology is
    considered to be "direct electrification".\n 
"""
struct Parameters <: InputClass
    StartYear ::Int64
    YearSplit ::JuMP.Containers.DenseAxisArray

    SpecifiedAnnualDemand ::JuMP.Containers.DenseAxisArray
    SpecifiedDemandProfile ::JuMP.Containers.DenseAxisArray
    RateOfDemand ::JuMP.Containers.DenseAxisArray
    Demand ::JuMP.Containers.DenseAxisArray

    CapacityToActivityUnit ::JuMP.Containers.DenseAxisArray
    CapacityFactor ::JuMP.Containers.DenseAxisArray
    AvailabilityFactor ::JuMP.Containers.DenseAxisArray
    OperationalLife ::JuMP.Containers.DenseAxisArray
    ResidualCapacity ::JuMP.Containers.DenseAxisArray
    InputActivityRatio ::JuMP.Containers.DenseAxisArray
    OutputActivityRatio ::JuMP.Containers.DenseAxisArray
    TagDispatchableTechnology ::JuMP.Containers.DenseAxisArray
    RegionalBaseYearProduction ::JuMP.Containers.DenseAxisArray
    TimeDepEfficiency ::JuMP.Containers.DenseAxisArray

    RegionalCCSLimit ::JuMP.Containers.DenseAxisArray

    CapitalCost ::JuMP.Containers.DenseAxisArray
    VariableCost ::JuMP.Containers.DenseAxisArray
    FixedCost ::JuMP.Containers.DenseAxisArray

    StorageLevelStart ::JuMP.Containers.DenseAxisArray
    MinStorageCharge ::JuMP.Containers.DenseAxisArray
    OperationalLifeStorage ::JuMP.Containers.DenseAxisArray
    CapitalCostStorage ::JuMP.Containers.DenseAxisArray
    ResidualStorageCapacity ::JuMP.Containers.DenseAxisArray
    TechnologyToStorage ::JuMP.Containers.DenseAxisArray
    TechnologyFromStorage ::JuMP.Containers.DenseAxisArray

    StorageMaxCapacity ::JuMP.Containers.DenseAxisArray

    TotalAnnualMaxCapacity ::JuMP.Containers.DenseAxisArray
    TotalAnnualMinCapacity ::JuMP.Containers.DenseAxisArray

    TagTechnologyToSector ::JuMP.Containers.DenseAxisArray
    AnnualSectoralEmissionLimit ::JuMP.Containers.DenseAxisArray

    TotalAnnualMaxCapacityInvestment ::JuMP.Containers.DenseAxisArray
    TotalAnnualMinCapacityInvestment ::JuMP.Containers.DenseAxisArray

    TotalTechnologyAnnualActivityUpperLimit ::JuMP.Containers.DenseAxisArray
    TotalTechnologyAnnualActivityLowerLimit ::JuMP.Containers.DenseAxisArray
    TotalTechnologyModelPeriodActivityUpperLimit ::JuMP.Containers.DenseAxisArray
    TotalTechnologyModelPeriodActivityLowerLimit ::JuMP.Containers.DenseAxisArray

    ReserveMarginTagTechnology ::JuMP.Containers.DenseAxisArray
    ReserveMarginTagFuel ::JuMP.Containers.DenseAxisArray
    ReserveMargin ::JuMP.Containers.DenseAxisArray

    RETagTechnology ::JuMP.Containers.DenseAxisArray
    RETagFuel ::JuMP.Containers.DenseAxisArray
    REMinProductionTarget ::JuMP.Containers.DenseAxisArray

    EmissionActivityRatio ::JuMP.Containers.DenseAxisArray
    EmissionContentPerFuel ::JuMP.Containers.DenseAxisArray
    EmissionsPenalty ::JuMP.Containers.DenseAxisArray
    EmissionsPenaltyTagTechnology ::JuMP.Containers.DenseAxisArray
    AnnualExogenousEmission ::JuMP.Containers.DenseAxisArray
    AnnualEmissionLimit ::JuMP.Containers.DenseAxisArray
    RegionalAnnualEmissionLimit ::JuMP.Containers.DenseAxisArray
    ModelPeriodExogenousEmission ::JuMP.Containers.DenseAxisArray
    ModelPeriodEmissionLimit ::JuMP.Containers.DenseAxisArray
    RegionalModelPeriodEmissionLimit ::JuMP.Containers.DenseAxisArray
    CurtailmentCostFactor ::JuMP.Containers.DenseAxisArray

    TradeRoute ::JuMP.Containers.DenseAxisArray
    TradeCosts ::JuMP.Containers.DenseAxisArray
    TradeLossFactor ::JuMP.Containers.DenseAxisArray
    TradeRouteInstalledCapacity ::JuMP.Containers.DenseAxisArray
    TradeLossBetweenRegions ::JuMP.Containers.DenseAxisArray


    CommissionedTradeCapacity ::JuMP.Containers.DenseAxisArray
    TradeCapacity ::JuMP.Containers.DenseAxisArray
    TradeCapacityGrowthCosts ::JuMP.Containers.DenseAxisArray
    GrowthRateTradeCapacity ::JuMP.Containers.DenseAxisArray

    SelfSufficiency ::JuMP.Containers.DenseAxisArray

    RampingUpFactor ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    RampingDownFactor ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    ProductionChangeCost ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    MinActiveProductionPerTimeslice ::Union{Nothing,JuMP.Containers.DenseAxisArray}

    ModalSplitByFuelAndModalType ::JuMP.Containers.DenseAxisArray
    TagTechnologyToModalType ::JuMP.Containers.DenseAxisArray

    EFactorConstruction ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    EFactorOM ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    EFactorManufacturing ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    EFactorFuelSupply ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    EFactorCoalJobs ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    CoalSupply ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    CoalDigging ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    RegionalAdjustmentFactor ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    LocalManufacturingFactor ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    DeclineRate ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    x_peakingDemand ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    
    TagDemandFuelToSector ::JuMP.Containers.DenseAxisArray
    TagElectricTechnology ::JuMP.Containers.DenseAxisArray

    TagTechnologyToSubsets ::Dict{String,Array}
    TagFuelToSubsets ::Dict{String,Array}
    StorageE2PRatio ::Union{Nothing,JuMP.Containers.DenseAxisArray}
end

struct Variables
    NewCapacity ::JuMP.Containers.DenseAxisArray
    AccumulatedNewCapacity ::JuMP.Containers.DenseAxisArray
    TotalCapacityAnnual ::JuMP.Containers.DenseAxisArray

    RateOfActivity ::JuMP.Containers.DenseAxisArray
    TotalAnnualTechnologyActivityByMode ::JuMP.Containers.DenseAxisArray
    ProductionByTechnologyAnnual ::JuMP.Containers.DenseAxisArray
    UseByTechnologyAnnual ::JuMP.Containers.DenseAxisArray
    TotalTechnologyAnnualActivity ::JuMP.Containers.DenseAxisArray
    TotalActivityPerYear ::JuMP.Containers.DenseAxisArray
    CurtailedEnergyAnnual ::JuMP.Containers.DenseAxisArray
    CurtailedCapacity ::JuMP.Containers.DenseAxisArray
    CurtailedEnergy ::JuMP.Containers.DenseAxisArray
    DispatchDummy ::JuMP.Containers.DenseAxisArray

    CapitalInvestment ::JuMP.Containers.DenseAxisArray
    DiscountedCapitalInvestment ::JuMP.Containers.DenseAxisArray
    SalvageValue ::JuMP.Containers.DenseAxisArray
    DiscountedSalvageValue ::JuMP.Containers.DenseAxisArray
    OperatingCost ::JuMP.Containers.DenseAxisArray
    DiscountedOperatingCost ::JuMP.Containers.DenseAxisArray
    AnnualVariableOperatingCost ::JuMP.Containers.DenseAxisArray
    AnnualFixedOperatingCost ::JuMP.Containers.DenseAxisArray
    VariableOperatingCost ::JuMP.Containers.DenseAxisArray
    TotalDiscountedCost ::JuMP.Containers.DenseAxisArray
    TotalDiscountedCostByTechnology ::JuMP.Containers.DenseAxisArray
    AnnualCurtailmentCost ::JuMP.Containers.DenseAxisArray
    DiscountedAnnualCurtailmentCost ::JuMP.Containers.DenseAxisArray

    StorageLevelYearStart ::JuMP.Containers.DenseAxisArray
    StorageLevelYearFinish ::JuMP.Containers.DenseAxisArray
    StorageLevelTSStart ::JuMP.Containers.DenseAxisArray
    AccumulatedNewStorageCapacity ::JuMP.Containers.DenseAxisArray
    NewStorageCapacity ::JuMP.Containers.DenseAxisArray
    CapitalInvestmentStorage ::JuMP.Containers.DenseAxisArray
    DiscountedCapitalInvestmentStorage ::JuMP.Containers.DenseAxisArray
    SalvageValueStorage ::JuMP.Containers.DenseAxisArray
    DiscountedSalvageValueStorage ::JuMP.Containers.DenseAxisArray
    TotalDiscountedStorageCost ::JuMP.Containers.DenseAxisArray

    TotalActivityInReserveMargin ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    DemandNeedingReserveMargin ::Union{Nothing,JuMP.Containers.DenseAxisArray}

    TotalREProductionAnnual ::JuMP.Containers.DenseAxisArray
    RETotalDemandOfTargetFuelAnnual ::JuMP.Containers.DenseAxisArray
    TotalTechnologyModelPeriodActivity ::JuMP.Containers.DenseAxisArray
    RETargetMin ::JuMP.Containers.DenseAxisArray

    AnnualTechnologyEmissionByMode ::JuMP.Containers.DenseAxisArray
    AnnualTechnologyEmission ::JuMP.Containers.DenseAxisArray
    AnnualTechnologyEmissionPenaltyByEmission ::JuMP.Containers.DenseAxisArray
    AnnualTechnologyEmissionsPenalty ::JuMP.Containers.DenseAxisArray
    DiscountedTechnologyEmissionsPenalty ::JuMP.Containers.DenseAxisArray
    AnnualEmissions ::JuMP.Containers.DenseAxisArray
    ModelPeriodEmissions ::JuMP.Containers.DenseAxisArray
    WeightedAnnualEmissions ::JuMP.Containers.DenseAxisArray

    AnnualSectoralEmissions ::JuMP.Containers.DenseAxisArray

    Import ::JuMP.Containers.DenseAxisArray
    Export ::JuMP.Containers.DenseAxisArray
    NewTradeCapacity ::JuMP.Containers.DenseAxisArray
    TotalTradeCapacity ::JuMP.Containers.DenseAxisArray
    NewTradeCapacityCosts ::JuMP.Containers.DenseAxisArray
    DiscountedNewTradeCapacityCosts ::JuMP.Containers.DenseAxisArray
    NetTrade ::JuMP.Containers.DenseAxisArray
    NetTradeAnnual ::JuMP.Containers.DenseAxisArray
    TotalTradeCosts ::JuMP.Containers.DenseAxisArray
    AnnualTotalTradeCosts ::JuMP.Containers.DenseAxisArray
    DiscountedAnnualTotalTradeCosts ::JuMP.Containers.DenseAxisArray

    DemandSplitByModalType ::JuMP.Containers.DenseAxisArray
    ProductionSplitByModalType ::JuMP.Containers.DenseAxisArray
    ProductionUpChangeInTimeslice ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    ProductionDownChangeInTimeslice ::Union{Nothing,JuMP.Containers.DenseAxisArray}

    RateOfTotalActivity ::Union{Nothing,JuMP.Containers.DenseAxisArray}

    BaseYearSlack ::JuMP.Containers.DenseAxisArray
    BaseYearBounds_TooLow ::JuMP.Containers.DenseAxisArray
    BaseYearBounds_TooHigh ::JuMP.Containers.DenseAxisArray

    DiscountedSalvageValueTransmission ::JuMP.Containers.DenseAxisArray

    PeakingDemand ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    PeakingCapacity ::Union{Nothing,JuMP.Containers.DenseAxisArray}

    AnnualProductionChangeCost ::Union{Nothing,JuMP.Containers.DenseAxisArray}
    DiscountedAnnualProductionChangeCost ::Union{Nothing,JuMP.Containers.DenseAxisArray}
end

"""
Model settings necessary for running the model

# Fields
- **`DepreciationMethod ::JuMP.Containers.DenseAxisArray`** Parameter defining the type of
    depreciation to be applied in each region. It has value 1 for sinking fund depreciation,
    value 2 for straight-line depreciation.\n
- **`GeneralDiscountRate ::JuMP.Containers.DenseAxisArray`** TODO.\n
- **`TechnologyDiscountRate ::JuMP.Containers.DenseAxisArray`** TODO.\n
- **`SocialDiscountRate ::JuMP.Containers.DenseAxisArray`** TODO.\n
- **`InvestmentLimit`** TODO.\n
- **`NewRESCapacity ::Float64`** TODO.\n
- **`ProductionGrowthLimit ::JuMP.Containers.DenseAxisArray`** This parameter controls the
    maximal increase between two years of a specific fuel production from renewable energy
    sources.\n
- **`StorageLimitOffset  ::Float64`** TODO.\n
- **`Trajectory2020UpperLimit ::Float64`** TODO.\n
- **`Trajectory2020LowerLimit ::Float64`** TODO.\n
- **`BaseYearSlack`** The allowed slack from the defined RegionalBaseYearProduction. 
    Value between 0 and 1. Used only if switch_base_year_bounds is set to 1.\n
- **`PhaseIn ::Dict`** TODO.\n
- **`PhaseOut ::Dict`** TODO.\n
- **`StorageLevelYearStartUpperLimit ::Float64`** TODO.\n
- **`StorageLevelYearStartLowerLimit ::Float64`** TODO.\n
"""
struct Settings <: InputClass
    DepreciationMethod ::JuMP.Containers.DenseAxisArray
    GeneralDiscountRate ::JuMP.Containers.DenseAxisArray
    TechnologyDiscountRate ::JuMP.Containers.DenseAxisArray
    SocialDiscountRate ::JuMP.Containers.DenseAxisArray
    InvestmentLimit ::Float64
    NewRESCapacity ::Float64
    ProductionGrowthLimit ::JuMP.Containers.DenseAxisArray
    StorageLimitOffset  ::Float64
    Trajectory2020UpperLimit ::Float64
    Trajectory2020LowerLimit ::Float64
    BaseYearSlack ::JuMP.Containers.DenseAxisArray
    PhaseIn ::Dict
    PhaseOut ::Dict
    StorageLevelYearStartUpperLimit ::Float64
    StorageLevelYearStartLowerLimit ::Float64
end 

"""
Sets used for the model run

# Fields

- **`Timeslice_full ::Array`** Represents all timeslices within a Year. This usally means
    8760 elements.\n
- **`Emission ::Array`** Represents potential emissions that can be derived by the operation
    of certain Technologies. Typically this includes atmospheric emissions, such as CO2.\n
- **`Technology ::Array`** Represents the main elements of the energy system that produce,
    convert, or transform energy (carriers) and their proxies. Technologies can represent
    specific individual technology options, such as a "Natural Gas CCGT". They can also 
    represent abstracted or aggregated collection of technologies used for accounting purposes
    (e.g., stock of cars).\n
- **`Fuel ::Array`** Represents energy carriers, energy services, or proxies that are
    consumed, produced, or transformed by Technologies. These can represent individual energy
    carriers, aggregated groups, or artificial commodities, required by the analysis to be
    carried out.\n
- **`Year ::Array`** Represents the time-frame of the model. This set contains all years
    to be considered in the corresponding analysis.\n
- **`Timeslice ::Array`** Represents the temporal resolution within a Year of the 
    analysis. This set contains (reduced) consecutive hourly time-series. Each Year has the
    same amount of timeslices assigned.\n
- **`Mode_of_operation ::Array`** Represents the different modes in which a technologies can be
    operated by. A technology can have different inputs and/or outputs for each mode of
    operation to represent fuel-switching. E.g., a CHP can produce electricity in one mode
    and heat in another one.\n
- **`Region_full ::Array`** Represents the regional scope of the model. This set can usually
    contains aggregated global regions, individual countries, or subcountry regions and states.\n
- **`Storage ::Array`** Represents storage facilities in the model. Storages can store
    FUELS and are linked to specific TECHNOLOGIES.\n
- **`ModalType ::Array`** Represents a modal type (e.g., rail-transportation) used in the
    transportation sector of the model. These are used to control modal shifting to a
    certain degree.\n
- **`Sector ::Array`** Represents different sectors in the energy system. Used for 
    aggregation and accounting purposes.\n
"""
struct Sets <: InputClass
    Timeslice_full ::UnitRange{Int64}
    Emission ::Vector{String}
    Technology ::Vector{String}
    Fuel ::Vector{String}
    Year ::Vector{Int}
    Timeslice ::Vector{Int}
    Mode_of_operation ::Vector{Int}
    Region_full ::Vector{String}
    Storage ::Vector{String}
    ModalType ::Vector{String}
    Sector ::Vector{String}
end

"""
Sets necessary for the employment calculations. The set elements may be different from
the sets in the model.
"""
struct Emp_Sets <: InputClass
    Technology ::Union{Nothing,Array}
    Year ::Union{Nothing,Array}
    Region ::Union{Nothing,Array}
end

"""
Subsets of the Sets used to define in more detail the characteristics of some members the sets.

# Fields

- **`Solar`** Solar technologies.\n
- **`Wind`** Wind technologies.\n
- **`Renewables`** Non-fossil technologies\n
- **`CCS`** Technologies linked to varbon capture and storage (CCS).\n
- **`Transformation`** TODO.\n
- **`RenewableTransformation`** TODO.\n
- **`FossilFuelGeneration`** Sources of fossil fuel.\n 
- **`FossilFuels`** \n
- **`FossilPower`** Technology using fossil fuels to produce power.\n
- **`CHPs`** Combined heat and power technologies.\n
- **`RenewableTransport`** Non-fossil transportation technologies.\n
- **`Transport`** Transportation technologies.\n
- **`Passenger`** Transportation technologies for passengers.\n
- **`Freight`** Transportation technologies for freight.\n
- **`TransportFuels`** Elements of the Fuel set corresponding to transport demand.\n 
- **`ImportTechnology`** Technologies corresponding to the import of resources.\n
- **`Heat`** Technologies producing heat.\n
- **`PowerSupply`** Technologies producing power.\n
- **`PowerBiomass`** Technologies producing powerfrom biomass.\n
- **`Coal`** Technologies consuming coal.\n
- **`Lignite`** Technologies consuming lignite.\n
- **`Gas`** Technologies consuming gas.\n
- **`StorageDummies`** Technologies corresponding to the defined storages.\n
- **`SectorCoupling`** TODO.\n 
- **`HeatFuels`** Elements of the Fuel set corresponding to heat demand.\n
- **`ModalGroups`** Overarching groups of modal types.\n
- **`PhaseInSet`** Technologies that can be subject to a phase in constraint, i.e. for which
    the production in a given year must be at least as much as the production from the 
    previous year times a factor combining the evolution of demand and user input (<1).\n
- **`PhaseOutSet`** Technologies that can be subject to a phase out constraint, i.e. for which
    the production in a given year must be at most equal to the production from the 
    previous year times a factor combining the evolution of demand and user factor (>1).\n
- **`HeatSlowRamper`** Heating technologies with long ramp up time.\n
- **`HeatQuickRamper`** Heating technologies with short ramp up time.\n
- **`Hydro`** Hydropower technologies.\n
- **`Geothermal`** Geothermal technologies.\n
- **`Onshore`** Onshore wind technologies.\n 
- **`Offshore`** Offshore wind technologies.\n
- **`SolarUtility`** Utility scale solar technologies.\n
- **`Oil`** Technologies consuming oil.\n
- **`HeatLowRes`** Technologies that can produce the fuel Heat Low Residential.\n
- **`HeatLowInd`** Technologies that can produce the fuel Heat Low Industrial.\n
- **`HeatMedInd`** Technologies that can produce the fuel Heat Medium Industrial.\n
- **`HeatHighInd`** Technologies that can produce the fuel Heat High Industrial.\n
- **`Biomass`** Technologies producing the fuel biomass.\n
- **`Households`** Technologies at the residential scale.\n
- **`Companies`** Technoologies not at the residential scale.\n
- **`HydrogenTechnologies`** Hydrogen technologies.\n
- **`DummyTechnology`** Dummy technoliges used to debug when getting infeasible model.\n
"""
struct SubsetsIni <: InputClass
    Solar ::Array
    Wind ::Array
    Renewables ::Array
    CCS ::Array
    Transformation ::Array
    RenewableTransformation ::Array
    FossilFuelGeneration ::Array 
    FossilFuels ::Array
    FossilPower ::Array
    CHPs ::Array
    RenewableTransport ::Array
    Transport ::Array
    Passenger ::Array
    Freight ::Array
    TransportFuels ::Array 
    ImportTechnology ::Array
    Heat ::Array
    PowerSupply ::Array
    PowerBiomass ::Array
    Coal ::Array
    Lignite ::Array
    Gas ::Array
    StorageDummies ::Array
    SectorCoupling ::Array 
    HeatFuels ::Array
    ModalGroups ::Array
    PhaseInSet ::Array
    PhaseOutSet ::Array
    HeatSlowRamper ::Array
    HeatQuickRamper ::Array
    Hydro ::Array
    Geothermal ::Array
    Onshore ::Array 
    Offshore ::Array
    SolarUtility ::Array
    Oil ::Array
    HeatLowRes ::Array
    HeatLowInd ::Array
    HeatMedInd ::Array
    HeatHighInd ::Array
    Biomass ::Array
    Households ::Array
    Companies ::Array
    HydrogenTechnologies ::Array
    DummyTechnology ::Array
end

"""
Switches used to define a model run.

The switches corresponds to various elements and define for instance the input files and
folders, as well as the inclusion or not of various features.

# Fields

- **`StartYear :: Int16`** First year of the study horizon.\n
- **`solver `** Solver to be used to solve the LP. The corresponding package must be called.
 For instance: using Gurobi, then the solver is Gurobi.Optimizer. \n
- **`DNLPsolver`** Solver used for the time reduction algorithm. The recommended solver 
is Ipopt as it is open but other commercial solvers with a julia integration can be used.\n
- **`model_region ::String`** Name of the modelled region. It will be used in naming files.\n
- **`data_base_region ::String`** Default region of the model. The missing data will be copied
from the default region.\n
- **`data_file ::String`** Path to the main input data file.\n
- **`hourly_data_file ::String`** Path to the input data file containing the timeseries.\n
- **`threads ::Int16`** Number of threads to use for solving the model. Default is 4. To 
automatically use th emaximum available number of threads, use the value 0.\n
- **`emissionPathway ::String`** Name of the emission pathway. Used in naming files.\n
- **`emissionScenario ::String`** Name of the emission scenario. Used in naming files.\n
- **`socialdiscountrate ::Float64`** Sets the value of the setting social discount rate.\n
- **`inputdir ::String`** Directory containing the input files.\n
- **`resultdir ::String`** Directory where the results files will be written.\n
- **`switch_infeasibility_tech :: Int8`** Switch used to include the infeasibility 
technologies in the model. These technologies are used to debug an infeasible model and 
allow the model to run feasible by relaxing the problem with slack production technologies.\n
- **`switch_investLimit ::Int16`** Used to enable Investment limits. This activates phase in
constraints for renewable technologies, phase out constraints for fossil technologies. 
It also activates a constraint smoothing the investment and to prevent large investment in
a single period. It also activates a constraint limiting the investment in renewable each year to 
a percentage of the total technical potential.\n
- **`switch_ccs ::Int16`** Used to enable CCS technologies.\n
- **`switch_ramping ::Int16`** Used to enable ramping constraints.\n
- **`switch_weighted_emissions ::Int16`** TODO.\n
- **`switch_intertemporal ::Int16`** TODO.\n
- **`switch_base_year_bounds ::Int16`** Used to enable base year bounds. This enforces the
annual production of the different technologies in the start year.\n
- **`switch_peaking_capacity ::Int16`** TODO.\n
- **`set_peaking_slack ::Float16`** TODO.\n
- **`set_peaking_minrun_share ::Float16`** TODO.\n
- **`set_peaking_res_cf ::Float16`** TODO.\n
- **`set_peaking_startyear ::Int16`** Year in which the peaking constraint becomes active.\n
- **`switch_peaking_with_storages ::Int16`** Enables to fulfill the peaking constraint with storages.\n
- **`switch_peaking_with_trade ::Int16`** Enables to fulfill the peaking constraint with trade.\n
- **`switch_peaking_minrun ::Int16`** TODO.\n
- **`switch_employment_calculation ::Int16`** TODO.\n
- **`switch_endogenous_employment ::Int16`** TODO.\n
- **`employment_data_file ::String`** TODO.\n
- **`switch_dispatch ::Int8`** Used to enable the dispatch run.\n
- **`elmod_nthhour ::Int16`** Step size in hour for the sampling in the time reduction algorithm.
The default is 0 since the preferred method is to define daystep and hourstep instead.
It corresponds to 24*daystep + hourstep.\n
- **`elmod_starthour ::Int16`** Starting hour for the sampling in the time reduction algorithm.\n
- **`elmod_dunkelflaute ::Int16`** Enables the addition of a period with very low wind and 
sun in the winter during the time reduction algorithm.\n
- **`elmod_daystep ::Int16`** Number of days between each sample during the time reduction algorithm.\n
- **`elmod_hourstep ::Int16`** Number of hours in addition tothe day step between each sample.\n
- **`switch_raw_results ::Int8`** Used to enable the writing of raw results after a model run.
The raw results dumps the content of all variables into CSVs.\n
- **`switch_processed_results ::Int8`** Used to produce processed result files containing 
additional metrics not part of the raw results.\n
- **`write_reduced_timeserie ::Int8`** Used to enable the writing of a file containing the
 results of the time reduction algorithm.\n
 - **`switch_reserve ::Int16`** Used to enable reserve margin constraints\n 
"""
struct Switch <: InputClass
    StartYear :: Int16
    solver 
    DNLPsolver
    model_region ::String
    data_base_region ::String
    data_file ::String
    hourly_data_file ::String
    threads ::Int16
    emissionPathway ::String
    emissionScenario ::String
    socialdiscountrate ::Float64
    inputdir ::String
    resultdir ::String
    switch_infeasibility_tech ::Int8
    switch_investLimit ::Int16
    switch_ccs ::Int16
    switch_ramping ::Int16
    switch_weighted_emissions ::Int16
    set_symmetric_transmission ::Float16
    switch_intertemporal ::Int16
    switch_base_year_bounds ::Int16
    switch_base_year_bounds_debugging ::Int8
    switch_peaking_capacity ::Int16
    set_peaking_slack ::Float16
    set_peaking_minrun_share ::Float16
    set_peaking_res_cf ::Float16
    set_peaking_min_thermal ::Float16
    set_peaking_startyear ::Int16
    switch_peaking_with_storages ::Int16
    switch_peaking_with_trade ::Int16
    switch_peaking_minrun ::Int16
    switch_employment_calculation ::Int16
    switch_endogenous_employment ::Int16
    employment_data_file ::String
    switch_dispatch ::Int8
    elmod_nthhour ::Int16
    elmod_starthour ::Int16
    elmod_dunkelflaute ::Int16
    elmod_daystep ::Int16
    elmod_hourstep ::Int16
    switch_raw_results ::Int8
    switch_processed_results ::Int8
    write_reduced_timeserie ::Int8
    switch_LCOE_calc ::Int8
    switch_reserve ::Int16
end

"""
Intermediary variables calculated after the model run

The intermediary variables are used to ex-post aggregate the activity, demand and use by time,
technology, mod of operation and/or region.
"""
struct Variable_Parameters <: InputClass
    RateOfTotalActivity ::JuMP.Containers.DenseAxisArray
    RateOfProductionByTechnologyByMode ::JuMP.Containers.DenseAxisArray
    RateOfUseByTechnologyByMode ::JuMP.Containers.DenseAxisArray
    RateOfProductionByTechnology ::JuMP.Containers.DenseAxisArray
    RateOfUseByTechnology ::JuMP.Containers.DenseAxisArray
    ProductionByTechnology ::JuMP.Containers.DenseAxisArray
    UseByTechnology ::JuMP.Containers.DenseAxisArray
    RateOfProduction ::JuMP.Containers.DenseAxisArray
    RateOfUse ::JuMP.Containers.DenseAxisArray
    Production ::JuMP.Containers.DenseAxisArray
    Use ::JuMP.Containers.DenseAxisArray
    ProductionAnnual ::JuMP.Containers.DenseAxisArray
    UseAnnual ::JuMP.Containers.DenseAxisArray
    CurtailedEnergy ::JuMP.Containers.DenseAxisArray
    ModelPeriodCostByRegion ::JuMP.Containers.DenseAxisArray 
end

"""
Structure containing the mappings of sets combinations
"""
struct Maps <: InputClass
    Tech_Fuel ::Dict
    Tech_MO ::Dict
    Fuel_Tech ::Dict
end