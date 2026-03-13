"""
Return all variables in the model
"""
function _registered_variables(model)
    collect(keys(object_dictionary(model)))
end

"""
Write the values of each variable in the model to CSV files.
"""
function genesysmod_results_raw(model, VarPar, Params, Switch,extr_str, s_rawresults::CSVResult)
    vars = _registered_variables(model)
    Threads.@threads for v in vars
        if v ∉ [:cost, :z]
            @debug "Saving " v
            fn = joinpath(Switch.resultdir[], string(v) * "_" * Switch.model_region * "_"
             * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * extr_str * ".csv")
            CSV.write(fn, JuMP.Containers.rowtable(value, model[v]))
        end
    end
    for field in fieldnames(typeof(VarPar))
        daa = getfield(VarPar, field)
        if isa(daa, DenseArray)
            fn = joinpath(Switch.resultdir[], string(field) * "_" * Switch.model_region * "_" *
                          Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * extr_str * ".csv")
            CSV.write(fn, JuMP.Containers.rowtable(value, daa))
        end
    end
    fn = joinpath(Switch.resultdir[], "RateOfDemand_" * Switch.model_region * "_" *
                          Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * extr_str * ".csv")
    CSV.write(fn, JuMP.Containers.rowtable(value, Params.RateOfDemand))
    fn = joinpath(Switch.resultdir[], "Demand_" * Switch.model_region * "_" *
            Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * extr_str * ".csv")
    CSV.write(fn, JuMP.Containers.rowtable(value, Params.Demand))
end

function genesysmod_results_raw(model, VarPar, Params, Switch,extr_str, s_rawresults::NoRawResult)
end

function genesysmod_results_raw(model, VarPar, Params, Switch, extr_str, s_rawresults::TXTResult)
    open(joinpath(Switch.resultdir[], "$(s_rawresults.filename)_$(extr_str).txt"), "w") do file
        objective = objective_value(model)
        println(file, "Objective = $objective")
        for v in all_variables(model)
            if value.(v) > 0
                val = value.(v)
                str = string(v)
                println(file, "$str = $val")
            end
        end
        for y ∈ axes(VarPar.ProductionByTechnology)[1], l ∈ axes(VarPar.ProductionByTechnology)[2], t ∈ axes(VarPar.ProductionByTechnology)[3], f ∈ axes(VarPar.ProductionByTechnology)[4], r ∈ axes(VarPar.ProductionByTechnology)[5]
            value = VarPar.ProductionByTechnology[y,l,t,f,r]
            if value > 0
                println(file, "ProductionByTechnology[$y,$l,$t,$f,$r] = $value")
            end
        end
        for y ∈ axes(Params.RateOfDemand)[1], l ∈ axes(Params.RateOfDemand)[2], f ∈ axes(Params.RateOfDemand)[3], r ∈ axes(Params.RateOfDemand)[4]
            value = Params.Demand[y,l,f,r] *  Params.YearSplit[l,y]
            if value > 0
                println(file, "RateOfDemand[$y,$l,$f,$r] = $value")
                println(file, "Demand[$y,$l,$f,$r] = $(Params.Demand[y,l,f,r])")
            end
        end
    end
end

function genesysmod_results_raw(model, VarPar, Params, Switch,extr_str, s_rawresults::TXTandCSV)
    genesysmod_results_raw(model, VarPar, Params, Switch,extr_str, CSVResult())
    genesysmod_results_raw(model, VarPar, Params, Switch,extr_str, TXTResult(s_rawresults.filename))
end

function genesysmod_getduals(model,Switch,extr_str)
    df=DataFrames.DataFrame(names=[],values=[])
    for (F, S) in list_of_constraint_types(model)
        for con in all_constraints(model, F, S)
            if dual(con) != 0 && name(con) != ""
                push!(df,(name(con),dual(con)))
            end
        end
    end
    fn = joinpath(Switch.resultdir[], "Duals" * "_" * Switch.model_region * "_"
             * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * extr_str * ".csv")
    CSV.write(fn, df)
end

function genesysmod_getspecifiedduals(model,Switch,extr_str, specified_constraints)
    df=DataFrames.DataFrame(names=[],values=[])
    for con in specified_constraints
        if dual(constraint_by_name(model,con)) != 0 && name(constraint_by_name(model,con)) != ""
            push!(df,(name(constraint_by_name(model,con)),dual(constraint_by_name(model,con))))
        end
    end
    date = Dates.now()
    formatted_date = Dates.format(date, "mmdd_HHMM")
    fn = joinpath(Switch.resultdir[], "Selected_Duals" * "_" * Switch.model_region * "_"
             * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * extr_str * ".csv")
    CSV.write(fn, df)
end

function genesysmod_getdualsbyname(model,Switch,extr_str, constr_name)
    df=DataFrames.DataFrame(names=[],values=[])
    constr_list=[]
    for (F, S) in list_of_constraint_types(model)
        for con in all_constraints(model, F, S)
            if occursin(constr_name, name(con))
                push!(constr_list,con)
            end
        end
    end
    for con in constr_list
        if dual(con) != 0
            push!(df,(name(con),dual(con)))
        end
    end
    date = Dates.now()
    formatted_date = Dates.format(date, "mmdd_HHMM")
    fn = joinpath(Switch.resultdir[], constr_name * "_" * Switch.model_region * "_"
             * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * extr_str * ".csv")
    CSV.write(fn, df)

    return df
end
