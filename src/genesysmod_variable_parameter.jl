"""
Internal function used in the run process after solving to compute aggregated versions of the rate of activity,
    rate of use and demand, on mode of operation, timeslice and technology.
"""
function genesysmod_variable_parameter(model, Sets, Params, Vars, Maps)
    RateOfTotalActivity = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Technology), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Region_full)
    # Sparse: 6D ByMode rates are mostly zero - store only nonzero entries keyed (y,l,t,m,f,r)
    RateOfProductionByTechnologyByMode = Dict{Tuple,Float64}()
    RateOfUseByTechnologyByMode = Dict{Tuple,Float64}()
    RateOfProductionByTechnology = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Technology), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Fuel, Sets.Region_full)
    RateOfUseByTechnology = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Technology), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Fuel, Sets.Region_full)
    ProductionByTechnology = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Technology), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Fuel, Sets.Region_full)
    UseByTechnology = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Technology), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Fuel, Sets.Region_full)
    RateOfProduction = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Fuel, Sets.Region_full)
    RateOfUse = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Fuel, Sets.Region_full)
    Production = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Fuel, Sets.Region_full)
    Use = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Fuel, Sets.Region_full)
    ProductionAnnual = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Fuel, Sets.Region_full)
    UseAnnual = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Fuel, Sets.Region_full)
    CurtailedEnergy = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Fuel), length(Sets.Region_full), length(Sets.Timeslice)), Sets.Year, Sets.Fuel, Sets.Region_full, Sets.Timeslice)
    ModelPeriodCostByRegion = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full)), Sets.Region_full)
    CCSByTechnologyAnnual = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year)), Sets.Region_full,Sets.Technology,Sets.Year)


    LoopSetOutput = Dict()
    LoopSetInput = Dict()
    for y ∈ Sets.Year, f ∈ Sets.Fuel, r ∈ Sets.Region_full
        slice_out = Params.OutputActivityRatio[r,:,f,:,y]
        slice_in  = Params.InputActivityRatio[r,:,f,:,y]

        # Get the original labels from the axes
        out_i_labels = axes(slice_out, 1)
        out_j_labels = axes(slice_out, 2)

        in_i_labels = axes(slice_in, 1)
        in_j_labels = axes(slice_in, 2)

        # Find positions where value > 0
        LoopSetOutput[(r,f,y)] = [(out_i_labels[i[1]], out_j_labels[i[2]]) for i in findall(>(0), slice_out.data)]
        LoopSetInput[(r,f,y)]  = [(in_i_labels[i[1]],  in_j_labels[i[2]])  for i in findall(>(0), slice_in.data)]
    end

    # Materialize solver values once instead of millions of scalar value() lookups
    roa    = JuMP.value.(Vars.RateOfActivity)
    curt   = JuMP.value.(Vars.CurtailedCapacity)
    tatabm = JuMP.value.(Vars.TotalAnnualTechnologyActivityByMode)
    tdc    = JuMP.value.(Vars.TotalDiscountedCost)

    for y ∈ Sets.Year for r ∈ Sets.Region_full
        for l ∈ Sets.Timeslice
            for t ∈ Sets.Technology
                RateOfTotalActivity[y,l,t,r] = sum(roa[y,l,t,m,r] for m ∈ Maps.Tech_MO[t]; init=0.0)
            end
            for f ∈ Sets.Fuel
                for (t,m) ∈ LoopSetOutput[(r,f,y)]
                    prod = roa[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y]
                    if prod != 0
                        RateOfProductionByTechnologyByMode[(y,l,t,m,f,r)] = prod
                    end
                    RateOfProductionByTechnology[y,l,t,f,r] += prod
                    ProductionByTechnology[y,l,t,f,r] += prod * Params.YearSplit[l,y]
                    CurtailedEnergy[y,f,r,l] += curt[r,l,t,y] * Params.OutputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y] * Params.CapacityToActivityUnit[t]
                end
                for (t,m) ∈ LoopSetInput[(r,f,y)]
                    use_rate = roa[y,l,t,m,r]*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y]
                    if use_rate != 0
                        RateOfUseByTechnologyByMode[(y,l,t,m,f,r)] = use_rate
                    end
                    RateOfUseByTechnology[y,l,t,f,r] += use_rate
                    UseByTechnology[y,l,t,f,r] += use_rate * Params.YearSplit[l,y]
                end

                RateOfProduction[y,l,f,r] = sum(RateOfProductionByTechnology[y,l,:,f,r])
                RateOfUse[y,l,f,r] = sum(RateOfUseByTechnology[y,l,:,f,r])
                Production[y,l,f,r] = sum(ProductionByTechnology[y,l,:,f,r])
                Use[y,l,f,r] = sum(UseByTechnology[y,l,:,f,r])
            end
        end
        for f ∈ Sets.Fuel
        ProductionAnnual[y,f,r] = sum(Production[y,:,f,r])
        UseAnnual[y,f,r] = sum(Use[y,:,f,r])
        end
    end end

    for r ∈ Sets.Region_full
        ModelPeriodCostByRegion[r] = sum(tdc[y,r] for y ∈ Sets.Year)
    end

    for r ∈ Sets.Region_full, t ∈ Sets.Technology, y ∈ Sets.Year
        CCSByTechnologyAnnual[r, t, y] = sum(
            tatabm[y,t,m,r]*Params.EmissionContentPerFuel[f,e]*Params.InputActivityRatio[r,t,f,m,y]*YearlyDifferenceMultiplier(y,Sets)* (Params.EmissionActivityRatio[r,t,m,e,y] >= 0 ? 1-Params.EmissionActivityRatio[r,t,m,e,y] : -1 * Params.EmissionActivityRatio[r,t,m,e,y]) for e ∈ Sets.Emission for f ∈ Maps.Tech_Fuel[t] for m ∈ Maps.Tech_MO[t]; init=0)
    end

    VarPar = Variable_Parameters(RateOfTotalActivity, RateOfProductionByTechnologyByMode, RateOfUseByTechnologyByMode, RateOfProductionByTechnology, RateOfUseByTechnology,
    ProductionByTechnology, UseByTechnology, RateOfProduction, RateOfUse, Production, Use, ProductionAnnual, UseAnnual, CurtailedEnergy, ModelPeriodCostByRegion)
    return VarPar
end
