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
Build the dispatch model. A previous run is necessary to allow to read in investment
decisions. For information about the switches, refer to the datastructure documentation
"""
function genesysmod_build_model_dispatch(; solver=nothing, DNLPsolver, year=2018,
        model_region="minimal", data_base_region="DE", data_file="Data_Europe_openENTRANCE_technoFriendly_combined_v00_kl_21_03_2022_new",
        hourly_data_file = "Hourly_Data_Europe_v09_kl_23_02_2022", threads=4, emissionPathway="MinimalExample",
        emissionScenario="globalLimit", socialdiscountrate=0.05,  inputdir="Inputdata\\",resultdir="Results\\",
        switch_investLimit=1, switch_ccs=1, switch_ramping=0,switch_weighted_emissions=1,set_symmetric_transmission=0,
        switch_hydrogen_blending_share = 1, set_storagelevelstart_up = 0.75, set_storagelevelstart_down = 0.25,
        E2P_ratio_deviation_factor = 2, switch_intertemporal=0,
        switch_base_year_bounds = 0,switch_peaking_capacity = 1, set_peaking_slack =1.0, set_peaking_minrun_share =0.15,
        set_peaking_res_cf=0.5, set_peaking_min_thermal=0.5, set_peaking_startyear = 2025, switch_peaking_with_storages = 0, switch_peaking_with_trade = 0,switch_peaking_minrun = 1,
        switch_employment_calculation = 0, switch_endogenous_employment = 0, employment_data_file = "",
        elmod_dunkelflaute = 0, switch_raw_results = CSVResult(), switch_processed_results = 1, switch_LCOE_calc=0,
        switch_dispatch = OneNodeSimple("DE"), extr_str_results = "inv_run", extr_str_dispatch="dispatch_run",
        switch_base_year_bounds_debugging = 0, switch_reserve = 0, switch_iis=1,dispatch_week=nothing)

    elmod_daystep = 0
    elmod_hourstep = 1
    elmod_nthhour = 1
    elmod_starthour = 1
    switch_infeasibility_tech = WithInfeasibilityTechs()
    write_reduced_timeserie = 0

    if !isdir(resultdir)
        mkdir(resultdir)
    end

    switch = Switch(year,
    DNLPsolver,
    model_region,
    data_base_region,
    data_file,
    hourly_data_file,
    threads,
    emissionPathway,
    emissionScenario,
    socialdiscountrate,
    inputdir,
    resultdir,
    switch_infeasibility_tech,
    switch_investLimit,
    switch_ccs,
    switch_ramping,
    switch_weighted_emissions,
    set_symmetric_transmission,
    switch_hydrogen_blending_share,
    set_storagelevelstart_up,
    set_storagelevelstart_down,
    E2P_ratio_deviation_factor,
    switch_intertemporal,
    switch_base_year_bounds,
    switch_base_year_bounds_debugging,
    switch_peaking_capacity,
    set_peaking_slack,
    set_peaking_minrun_share,
    set_peaking_res_cf,
    set_peaking_min_thermal,
    set_peaking_startyear,
    switch_peaking_with_storages,
    switch_peaking_with_trade,
    switch_peaking_minrun,
    switch_employment_calculation,
    switch_endogenous_employment,
    employment_data_file,
    switch_dispatch,
    elmod_nthhour,
    elmod_starthour,
    elmod_dunkelflaute,
    elmod_daystep,
    elmod_hourstep,
    switch_raw_results,
    switch_processed_results,
    write_reduced_timeserie,
    switch_LCOE_calc,
    extr_str_results,
    extr_str_dispatch,
    switch_reserve)

    starttime= Dates.now()
    model= JuMP.Model()

    #
    # ####### Load data from provided excel files and declarations #############
    #

    Sets, Params, Emp_Sets = genesysmod_dataload(switch;dispatch_week=dispatch_week);
    Sets, Params, Region_full, Params_full = aggregate_params(switch, Sets, Params, switch.switch_dispatch);

    Maps = make_mapping(Sets,Params)
    Vars = genesysmod_dec(model,Sets,Params,switch,Maps)

    #
    # ####### Settings for model run (Years, Regions, etc) #############
    #

    Settings=genesysmod_settings(Sets, Params, switch.socialdiscountrate)

    #
    # ####### apply general model bounds #############
    #

    genesysmod_bounds(model,Sets,Params, Vars,Settings,switch,Maps)

    #
    # ####### Fix Investment Variables #############
    #

    storage_ratio = fix_investments!(model, switch, Sets, Params, Maps, Region_full, switch.switch_dispatch)

    #
    # ####### Including Equations #############
    #

    considered_duals = genesysmod_equ(model,Sets,Params, Vars,Emp_Sets,Settings,switch, Maps; storage_ratio = storage_ratio, Params_full= Params_full, Region_Full=Region_full)
    return model, Dict("Sets" => Sets, "Params" => Params, "Switch" => switch, "Vars" => Vars, "Maps" => Maps, "Settings" => Settings, "ConsideredDuals" => considered_duals)
end

"""
Run the simple dispatch model. A previous run is necessary to allow to read in investment
decisions. For information about the switches, refer to the datastructure documentation
"""
function genesysmod_dispatch(; solver, DNLPsolver, year=2018,
        model_region="minimal", data_base_region="DE", data_file="Data_Europe_openENTRANCE_technoFriendly_combined_v00_kl_21_03_2022_new",
        hourly_data_file = "Hourly_Data_Europe_v09_kl_23_02_2022", threads=4, emissionPathway="MinimalExample",
        emissionScenario="globalLimit", socialdiscountrate=0.05,  inputdir="Inputdata\\",resultdir="Results\\",
        switch_investLimit=1, switch_ccs=1, switch_ramping=0,switch_weighted_emissions=1,set_symmetric_transmission=0,
        switch_hydrogen_blending_share = 1, set_storagelevelstart_up = 0.75, set_storagelevelstart_down = 0.25,
         E2P_ratio_deviation_factor = 2, switch_intertemporal=0,
        switch_base_year_bounds = 0,switch_peaking_capacity = 1, set_peaking_slack =1.0, set_peaking_minrun_share =0.15,
        set_peaking_res_cf=0.5, set_peaking_min_thermal=0.5, set_peaking_startyear = 2025, switch_peaking_with_storages = 0, switch_peaking_with_trade = 0,switch_peaking_minrun = 1,
        switch_employment_calculation = 0, switch_endogenous_employment = 0, employment_data_file = "",
        elmod_dunkelflaute = 0, switch_raw_results = CSVResult(), switch_processed_results = 1, switch_LCOE_calc=0,
        switch_dispatch = OneNodeSimple("DE"), extr_str_results = "inv_run", extr_str_dispatch="dispatch_run",
        switch_base_year_bounds_debugging = 0, switch_reserve = 0, switch_iis=1, dispatch_week=nothing)

    starttime= Dates.now()

    model, case = genesysmod_build_model_dispatch(; solver=solver, DNLPsolver=DNLPsolver,
    year=year, model_region=model_region, data_base_region=data_base_region,
    data_file=data_file, hourly_data_file = hourly_data_file,
    threads=threads, emissionPathway=emissionPathway, emissionScenario=emissionScenario,
    socialdiscountrate=socialdiscountrate, inputdir=inputdir, resultdir=resultdir,
    switch_investLimit=switch_investLimit, switch_ccs=switch_ccs,
    switch_ramping=switch_ramping, switch_weighted_emissions=switch_weighted_emissions,
    set_symmetric_transmission=set_symmetric_transmission, switch_hydrogen_blending_share = switch_hydrogen_blending_share,
    set_storagelevelstart_up = set_storagelevelstart_up, set_storagelevelstart_down = set_storagelevelstart_down,
    E2P_ratio_deviation_factor = E2P_ratio_deviation_factor,
    switch_intertemporal=switch_intertemporal, switch_base_year_bounds = switch_base_year_bounds,
    switch_base_year_bounds_debugging = switch_base_year_bounds_debugging,
    switch_peaking_capacity = switch_peaking_capacity, set_peaking_slack = set_peaking_slack,
    set_peaking_minrun_share = set_peaking_minrun_share, set_peaking_res_cf=set_peaking_res_cf,
    set_peaking_min_thermal=set_peaking_min_thermal, set_peaking_startyear = set_peaking_startyear,
    switch_peaking_with_storages = switch_peaking_with_storages, switch_peaking_with_trade = switch_peaking_with_trade,
    switch_peaking_minrun = switch_peaking_minrun,
    switch_employment_calculation = switch_employment_calculation,
    switch_endogenous_employment = switch_endogenous_employment,
    employment_data_file = employment_data_file,
    elmod_dunkelflaute = elmod_dunkelflaute, switch_raw_results = switch_raw_results,
    switch_processed_results = switch_processed_results,
    switch_LCOE_calc=switch_LCOE_calc,
    switch_dispatch=switch_dispatch, switch_reserve = switch_reserve,
    extr_str_results = extr_str_results, extr_str_dispatch=extr_str_dispatch,
    switch_iis=switch_iis,dispatch_week=dispatch_week);
    Sets = case["Sets"]
    Params = case["Params"]
    Vars = case["Vars"]
    Maps = case["Maps"]
    Settings = case["Settings"]
    considered_duals = case["ConsideredDuals"]
    switch = case["Switch"]
    #
    # ####### Solver Options #############
    #

    dispatch_str = replace(string(switch.switch_dispatch), '\"' => "")
    new_resdir = joinpath(switch.resultdir[],string(dispatch_str))
    if !isdir(new_resdir)
        mkdir(new_resdir)
    end
    switch.resultdir[] = new_resdir #update the value inside the ref with the new directory

    set_optimizer(model, solver)

    if solver_name(model) == "Gurobi"
        set_optimizer_attribute(model, "Threads", threads)
        #set_optimizer_attribute(model, "Names", "no")
        set_optimizer_attribute(model, "Method", 2)
        set_optimizer_attribute(model, "BarHomogeneous", 1)
        set_optimizer_attribute(model, "Crossover", 0)
        set_optimizer_attribute(model, "LogFile", joinpath(resultdir,"Run_$(switch.elmod_nthhour)_$(today()).log"))
    elseif solver_name(model) == "CPLEX"
        set_optimizer_attribute(model, "CPX_PARAM_THREADS", threads)
        set_optimizer_attribute(model, "CPX_PARAM_PARALLELMODE", -1)
        set_optimizer_attribute(model, "CPX_PARAM_LPMETHOD", 4)
        set_optimizer_attribute(model, "CPX_PARAM_SOLUTIONTYPE", 2)
        #env = model.moi_backend.optimizer.model.env
        #CPXsetlogfilename(env, joinpath(resultdir,"Run_$(switch.elmod_nthhour)_$(today()).log"), "w+")
        #set_optimizer_attribute(model, "CPX_PARAM_BAROBJRNG", 1e+075)
    elseif solver_name(model) == "HiGHS"
        set_optimizer_attribute(model, "solver", "ipm")
        #set_optimizer_attribute(model, "solver", "pdlp")
        set_optimizer_attribute(model, "run_crossover", "off")
        set_optimizer_attribute(model, "log_file", joinpath(resultdir,"Run_$(switch.elmod_nthhour)_$(today()).log"))
    end

    println("model_region = $model_region")
    println("data_base_region = $data_base_region")
    println("data_file = $data_file")
    println("solver = $solver")
    optimize!(model)

    elapsed = (Dates.now() - starttime)

    #
    # ####### Results #############
    #

    if occursin("INFEASIBLE",string(termination_status(model)))
        if switch_iis == 1
            if occursin("Gurobi",string(solver)) || occursin("CPLEX",string(solver))
                println("Termination status:", termination_status(model), ". Computing IIS")
                compute_conflict!(model)
                println("Saving IIS to file")
                print_iis(model)
            elseif occursin("HiGHS",string(solver))
                println("Termination status:", termination_status(model), ". Printing violations:")
                res = violations(model)
                println("Saving violations to file")
                open(joinpath(resultdir,"IIS_$(today()).txt"), "w") do f
                    for line in res
                        println(f, line)
                    end
                end
            else
                try
                    println("Termination status:", termination_status(model), ". Computing IIS")
                    compute_conflict!(model)
                    println("Saving IIS to file")
                    print_iis(model)
                catch
                    println("IIS computation failed. Please check the model and the solver settings.")
                end
            end
        else
            error("Model infeasible. Turn on 'switch_iis' to compute and write the iis file")
        end

    elseif termination_status(model) == MOI.OPTIMAL
        VarPar = genesysmod_variable_parameter(model, Sets, Params, Vars, Maps)
        if switch_processed_results == 1
            genesysmod_results(model, Sets, Params, VarPar, Vars, switch,
             Settings, Maps, elapsed,switch.extr_str_dispatch)
        end
        genesysmod_results_raw(model, VarPar, Params, switch,switch.extr_str_dispatch,switch.switch_raw_results)
        genesysmod_getspecifiedduals(model,switch,switch.extr_str_dispatch, considered_duals)
    else
        println("Termination status:", termination_status(model), ".")
    end

    return model, Dict("Sets" => Sets, "Params" => Params, "Switch" => switch)
end

function fix_investments!(model, Switch, Sets, Params, Maps, region_full, s_dispatch::OneNodeSimple)
    # read investment results for relevant variables
    tmp_TotalCapacityAnnual, tmp_TotalTradeCapacity, tmp_NewStorageCapacity = read_investments(Sets, Switch, Switch.switch_raw_results)
    #= in_data=CSV.read(joinpath(Switch.resultdir, "NetTradeAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * ".csv"), DataFrame)
    tmp_NetTradeAnnual = create_daa(in_data, "Par_NetTradeAnnual", data_base_region, Sets.Year, Sets.Fuel, Sets.Region_full) =#

    # make constraints fixing investments
    for y ∈ Sets.Year for r ∈ Sets.Region_full
        for t ∈ setdiff(Sets.Technology, Params.Tags.TagTechnologyToSubsets["DummyTechnology"])
            @constraint(model, model[:TotalCapacityAnnual][y,t,r] == tmp_TotalCapacityAnnual[y,t,r],
            base_name="Fix_Investments_$(y)_$(t)_$(r)")
        end
        if Switch.switch_infeasibility_tech == 1
            for t ∈ Params.Tags.TagTechnologyToSubsets["DummyTechnology"]
                @constraint(model, model[:TotalCapacityAnnual][y,t,r] == 99999,
                base_name="Fix_Investments_$(y)_$(t)_$(r)")
            end
        end
        for s ∈ Sets.Storage
            @constraint(model, model[:NewStorageCapacity][s,y,r] == tmp_NewStorageCapacity[s,y,r],
            base_name="Fix_NewStorageCapacity_$(s)_$(y)_$(r)")
        end
    end end
    for y ∈ Sets.Year for (f,r,rr) ∈ Maps.Set_Fuel_Regions
        @constraint(model, model[:TotalTradeCapacity][y,f,r,rr] == tmp_TotalTradeCapacity[y,f,r,rr],
        base_name="Fix_TradeConnection_$(y)_$(f)_$(r)_$(rr)")
    end end
    return 0
end

function fix_investments!(model, Switch, Sets, Params, Maps, region_full, s_dispatch::OneNodeStorage;threshold=1e-5)
    # read investment results for relevant variables (from a run on full Europe)
    tmp_TotalCapacityAnnual, tmp_TotalTradeCapacity, tmp_NewStorageCapacity = read_investments(Sets, Switch, region_full, Switch.switch_raw_results)
    tmp_TotalCapacityAnnual = tmp_TotalCapacityAnnual[:,:,Sets.Region_full]
    tmp_NewStorageCapacity = tmp_NewStorageCapacity[:,:,Sets.Region_full]
    # aggregating the trade capacities from and to DE (for the power), to size the storage
    trade_capacity_in = sum(tmp_TotalTradeCapacity[Sets.Year, "Power",:,Sets.Region_full])

    # make constraints fixing investments
    for y ∈ Sets.Year for r ∈ Sets.Region_full
        for t ∈ setdiff(Sets.Technology, Params.Tags.TagTechnologyToSubsets["DummyTechnology"])
            fix(model[:TotalCapacityAnnual][y,t,r], tmp_TotalCapacityAnnual[y,t,r]!= 0 ? max(threshold,tmp_TotalCapacityAnnual[y,t,r]) : 0; force=true)
        end
        if Switch.switch_infeasibility_tech == 1
            for t ∈ Params.Tags.TagTechnologyToSubsets["DummyTechnology"]
                fix(model[:TotalCapacityAnnual][y,t,r], 99999; force=true)
            end
        end
        # exchange capacity (capacity unit)
        fix(model[:TotalCapacityAnnual][y,"D_Trade_Storage_Power",r], trade_capacity_in != 0 ? max(threshold,trade_capacity_in) : 0; force=true)
        # storage capacity (energy unit)
        fix(model[:NewStorageCapacity]["S_Trade_Storage_Power",y,r], 500; force=true)

        for s ∈ setdiff(Sets.Storage, ["S_Trade_Storage_Power"])
            fix(model[:NewStorageCapacity][s,y,r], tmp_NewStorageCapacity[s,y,r] != 0 ? max(threshold,tmp_NewStorageCapacity[s,y,r]) : 0; force=true)
        end

    end end
    for y ∈ Sets.Year for (f,r,rr) ∈ Maps.Set_Fuel_Regions
        if model[:TotalTradeCapacity][y,f,r,rr] isa VariableRef
            fix(model[:TotalTradeCapacity][y,f,r,rr], 0; force=true)
        end
    end end

    # determining the ratio between charging and discharging the "trade storage" with the import and export
    col_names = ["Year", "Timeslice", "Fuel", "Region", "Value"]
    # in_data_import = CSV.read(joinpath(Switch.resultdir, "Import_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * Switch.extr_str_results * ".csv"), DataFrame, header=col_names, skipto=2)
    # # println(in_data_import[in.(in_data_import.Region2, Ref(Sets.Region_full)) .& (in_data_import.Fuel .== "Power") .& in.(in_data_import.Year, Ref(Sets.Year)),:])
    # sum_import = sum(in_data_import[in.(in_data_import.Region1, Ref(Sets.Region_full)) .& (in_data_import.Fuel .== "Power") .& in.(in_data_import.Year, Ref(Sets.Year)),:].Value)
    # in_data_export = CSV.read(joinpath(Switch.resultdir, "Export_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * Switch.extr_str_results * ".csv"), DataFrame, header=col_names, skipto=2)
    # # println(in_data_export[in.(in_data_export.Region1, Ref(Sets.Region_full)) .& (in_data_export.Fuel .== "Power") .& in.(in_data_export.Year, Ref(Sets.Year)),:])
    # sum_export = sum(in_data_export[in.(in_data_export.Region1, Ref(Sets.Region_full)) .& (in_data_export.Fuel .== "Power") .& in.(in_data_export.Year, Ref(Sets.Year)),:].Value)
    # println("Imports ", sum_import)
    # println("Exports ", sum_export)

    # storage_ratio = sum_export/max(sum_import,0.001)
    in_data_net_trade = CSV.read(joinpath(Switch.resultdir[], "NetTrade_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * Switch.extr_str_results * ".csv"), DataFrame, header=col_names, skipto=2)
    storage_ratio = sum(in_data_net_trade[in.(in_data_net_trade.Year, Ref(Sets.Year)) .& (in_data_net_trade.Fuel .== "Power") .& in.(in_data_net_trade. Region, Ref(Sets.Region_full)),:].Value)
    return storage_ratio
end

function fix_investments!(model, Switch, Sets, Params, Maps, region_full, s_dispatch::TwoNodes)

    tmp_TotalCapacityAnnual, tmp_TotalTradeCapacity, tmp_NewStorageCapacity = read_investments(Sets, Switch, region_full, Switch.switch_raw_results)
    #= in_data=CSV.read(joinpath(Switch.resultdir, "NetTradeAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * ".csv"), DataFrame)
    tmp_NetTradeAnnual = create_daa(in_data, "Par_NetTradeAnnual", data_base_region, Sets.Year, Sets.Fuel, Sets.Region_full) =#
    # make constraints fixing investments
    for y ∈ Sets.Year
        for t ∈ setdiff(Sets.Technology, Params.Tags.TagTechnologyToSubsets["DummyTechnology"])
            fix(model[:TotalCapacityAnnual][y,t,Sets.Region_full[2]], sum(tmp_TotalCapacityAnnual[y,t,re] for re in region_full if re!=Sets.Region_full[1]); force=true)
            fix(model[:TotalCapacityAnnual][y,t,Sets.Region_full[1]], tmp_TotalCapacityAnnual[y,t,Sets.Region_full[1]]; force=true)
            # @constraint(model, model[:TotalCapacityAnnual][y,t,r] == tmp_TotalCapacityAnnual[y,t,r],
            # base_name="Fix_Investments_$(y)_$(t)_$(r)")
        end
        if Switch.switch_infeasibility_tech == 1
            for t ∈ Params.Tags.TagTechnologyToSubsets["DummyTechnology"]
                fix(model[:TotalCapacityAnnual][y,t,Sets.Region_full[1]], 99999; force=true)
                fix(model[:TotalCapacityAnnual][y,t,Sets.Region_full[2]], 99999; force=true)
                # @constraint(model, model[:TotalCapacityAnnual][y,t,r] == 99999,
                # base_name="Fix_Investments_$(y)_$(t)_$(r)")
            end
        end
        for s ∈ Sets.Storage
            fix(model[:NewStorageCapacity][s,y,Sets.Region_full[1]], tmp_NewStorageCapacity[s,y,Sets.Region_full[1]]; force=true)
            fix(model[:NewStorageCapacity][s,y,Sets.Region_full[2]], sum(tmp_NewStorageCapacity[s,y,r] for r in region_full if r!=Sets.Region_full[1]); force=true)
            # @constraint(model, model[:NewStorageCapacity][s,y,r] == tmp_NewStorageCapacity[s,y,r],
            # base_name="Fix_NewStorageCapacity_$(s)_$(y)_$(r)")
        end
    end
    for y ∈ Sets.Year for f ∈ Sets.Fuel
        if Params.Tags.TagCanFuelBeTraded[f] != 0 && model[:TotalTradeCapacity][y,f,Sets.Region_full[1],Sets.Region_full[2]] isa VariableRef
            fix(model[:TotalTradeCapacity][y,f,Sets.Region_full[1],Sets.Region_full[2]], sum(tmp_TotalTradeCapacity[y,f,Sets.Region_full[1],r] for r in region_full if r!=Sets.Region_full[1]); force=true)
        end
        if Params.Tags.TagCanFuelBeTraded[f] != 0 && model[:TotalTradeCapacity][y,f,Sets.Region_full[2],Sets.Region_full[1]] isa VariableRef
            fix(model[:TotalTradeCapacity][y,f,Sets.Region_full[2],Sets.Region_full[1]], sum(tmp_TotalTradeCapacity[y,f,r,Sets.Region_full[1]] for r in region_full if r!=Sets.Region_full[1]); force=true)
        end
            # @constraint(model, model[:TotalTradeCapacity][y,f,r,rr] == tmp_TotalTradeCapacity[y,f,r,rr],
        # base_name="Fix_TradeConnection_$(y)_$(f)_$(r)_$(rr)")
    end end
    return 0
end

function read_investments(Sets, Switch, region_full, s_rawresults::CSVResult)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalCapacityAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalCapacityAnnual = create_daa(in_data, "Par_TotalCapacityAnnual", Sets.Year, Sets.Technology, region_full)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalTradeCapacity_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalTradeCapacity = create_daa(in_data, "Par_TotalTradeCapacity", Sets.Year, Sets.Fuel, region_full, region_full)
    in_data=CSV.read(joinpath(Switch.resultdir[], "NewStorageCapacity_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_NewStorageCapacity = create_daa(in_data, "Par_NewStorageCapacity", Sets.Storage, Sets.Year, region_full)
    return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity
end

function read_investments(Sets, Switch, s_rawresults::CSVResult)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalCapacityAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalCapacityAnnual = create_daa(in_data, "Par_TotalCapacityAnnual", Sets.Year, Sets.Technology, Sets.Region_full)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalTradeCapacity_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalTradeCapacity = create_daa(in_data, "Par_TotalTradeCapacity", Sets.Year, Sets.Fuel, Sets.Region_full, Sets.Region_full)
    in_data=CSV.read(joinpath(Switch.resultdir[], "NewStorageCapacity_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_NewStorageCapacity = create_daa(in_data, "Par_NewStorageCapacity", Sets.Storage, Sets.Year, Sets.Region_full)
    return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity
end

function read_investments(Sets, Switch, region_full, s_rawresults::TXTResult)
    tmp_TotalCapacityAnnual = read_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalCapacityAnnual[", year=Sets.Year, technology=Sets.Technology, region=region_full)
    tmp_TotalTradeCapacity = read_trade_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalTradeCapacity[", year=Sets.Year, technology=Sets.Fuel, region=region_full)
    tmp_NewStorageCapacity = read_storage_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="NewStorageCapacity[", year=Sets.Year, technology=Sets.Storage, region=region_full)
    return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity
end

function read_investments(Sets, Switch, s_rawresults::TXTResult)
    tmp_TotalCapacityAnnual = read_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalCapacityAnnual[", year=Sets.Year, technology=Sets.Technology, region=Sets.Region_full)
    tmp_TotalTradeCapacity = read_trade_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalTradeCapacity[", year=Sets.Year, technology=Sets.Fuel, region=Sets.Region_full)
    tmp_NewStorageCapacity = read_storage_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="NewStorageCapacity[", year=Sets.Year, technology=Sets.Storage, region=Sets.Region_full)
    return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity
end

function read_investments(Sets, Switch, s_rawresults::TXTandCSV)
    try
        tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity = read_investments(Sets, Switch, TXTResult(s_rawresults.filename))
        return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity
    catch
        try
            tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity = read_investments(Sets, Switch, CSVResult())
            return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity
        catch
            return println("Error: Missing result investment result files for dispatch.")
        end
    end
end

function read_investments(Sets, Switch, region_full, s_rawresults::TXTandCSV)
    try
        tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity = read_investments(Sets, Switch, region_full, TXTResult(s_rawresults.filename))
        return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity
    catch
        try
            tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity = read_investments(Sets, Switch, region_full, CSVResult())
            return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_NewStorageCapacity
        catch
            return println("Error: Missing result investment result files for dispatch.")
        end
    end
end

function read_investments(Sets, Switch, s_rawresults)
    return println("Raw Result types not specified or set to NoRawResult, please specify the types
     of the raw results from the investment run between CSVResult and TXTResult.")
end

function read_investments(Sets, Switch, region_full, s_rawresults)
    return println("Raw Result types not specified or set to NoRawResult, please specify the types
     of the raw results from the investment run between CSVResult and TXTResult.")
end
