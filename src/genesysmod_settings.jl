"""
Internal function used in the run process to set run settings such as dicount rates.
"""
function genesysmod_settings(Sets, Params, socialdiscountrate)

    DepreciationMethod=JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full)), Sets.Region_full)
    GeneralDiscountRate=JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full)), Sets.Region_full)
    TechnologyDiscountRate=JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full), length(Sets.Technology)), Sets.Region_full, Sets.Technology)
    SocialDiscountRate=JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full)), Sets.Region_full)
    for r ∈ Sets.Region_full
        DepreciationMethod[r] = 1
        GeneralDiscountRate[r] = Float64(0.05)
        for t ∈ setdiff(Sets.Technology,Params.Tags.TagTechnologyToSubsets["Households"])
            TechnologyDiscountRate[r,t] = Float64(0.05)
        end
        for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["Households"])
            TechnologyDiscountRate[r,t] = Float64(0.05)
        end
        SocialDiscountRate[r] = socialdiscountrate
    end

    InvestmentLimit = Float64(1.9)  #Freedom for investment choices to spread across periods. A value of 1 would mean equal share for each period.
    NewRESCapacity = Float64(0.1)
    #ProductionGrowthLimit=JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Fuel)), Sets.Year, Sets.Fuel)
    #= for y ∈ Sets.Year for f ∈ Sets.Fuel
        if f ∈ vcat(["Power"],Params.Tags.TagFuelToSubsets["HeatFuels"],Params.Tags.TagFuelToSubsets["TransportFuels"])
            Params.ProductionGrowthLimit[y,f] = Float64(0.05)
        end
        if f == "Air"
            Params.ProductionGrowthLimit[y,f] = Float64(0.025)
        end
    end end =#
    StorageLimitOffset = Float64(0.015)

    Trajectory2020UpperLimit = 3
    Trajectory2020LowerLimit = Float64(0.7)

    BaseYearSlack = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Fuel)), Sets.Fuel)
    BaseYearSlack[Sets.Fuel] .= 0.035
    BaseYearSlack["Power"] = 0.035

    PhaseOut = Dict(2020=>3, 2025=>3, 2030=>3, 2035=>2.5, 2040=>2.5 ,2045=>2, 2050=>2 ,2055=>1.5, 2060=>1.25)# this is an upper limit for fossil generation based on the previous year - to remove choose large value

    PhaseIn = Dict(2020=>1, 2025=>0.8, 2030=>0.8, 2035=>0.8, 2040=>0.8, 2045=>0.8, 2050=>0.6, 2055=>0.5, 2060=>0.5) # this is a lower bound for renewable integration based on the previous year - to remove choose 0

    #StorageLevelYearStartUpperLimit = Switch.set_storagelevelstart_up
    #StorageLevelYearStartLowerLimit = Switch.set_storagelevelstart_down


    Settings=GENeSYSMOD.Settings(DepreciationMethod,GeneralDiscountRate,TechnologyDiscountRate,SocialDiscountRate,InvestmentLimit,NewRESCapacity,
    StorageLimitOffset,Trajectory2020UpperLimit,Trajectory2020LowerLimit, BaseYearSlack, PhaseIn, PhaseOut)
    return Settings
end
