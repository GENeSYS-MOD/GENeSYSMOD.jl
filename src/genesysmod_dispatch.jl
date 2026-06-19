"""
Build the dispatch model. A previous run is necessary to allow to read in investment
decisions. For information about the switches, refer to the datastructure documentation
"""
function genesysmod_build_model_dispatch(;elmod_nthhour = 1, elmod_starthour=1, solver=nothing, DNLPsolver, year=2018,
        model_region="minimal", data_base_region="DE", data_file="Data_Europe_openENTRANCE_technoFriendly_combined_v00_kl_21_03_2022_new",
        hourly_data_file = "Hourly_Data_Europe_v09_kl_23_02_2022", threads=4, emissionPathway="MinimalExample",
        emissionScenario="globalLimit", socialdiscountrate=0.05,  inputdir="Inputdata\\",resultdir="Results\\",
        switch_investLimit=1, switch_ccs=1, switch_ramping=0,switch_weighted_emissions=1,set_symmetric_transmission=0.9,
        switch_hydrogen_blending_share = 1, set_storagelevelstart_up = 0.75, set_storagelevelstart_down = 0.25,
        E2P_ratio_deviation_factor = 2, switch_intertemporal=0,
        switch_base_year_bounds = 0,switch_peaking_capacity = 1, set_peaking_slack =1.0, set_peaking_minrun_share =0.15,
        set_peaking_res_cf=0.5, set_peaking_min_thermal=0.25, set_peaking_startyear = 2030, switch_peaking_with_storages = 1, switch_peaking_with_trade = 1,switch_peaking_minrun = 0,
        switch_employment_calculation = 0, switch_endogenous_employment = 0, employment_data_file = "",
        elmod_dunkelflaute = 0, switch_raw_results = CSVResult(), switch_processed_results = 1, switch_LCOE_calc=0,
        switch_dispatch = OneNodeSimple("DE"), extr_str_results = "inv_run", extr_str_dispatch="dispatch_run",
        switch_base_year_bounds_debugging = 0, switch_reserve = 0, switch_iis=1,dispatch_week=nothing,
        switch_errorcheck=2, switch_results_db=0, switch_endogenous_specifieddemandforecasting=1)

    elmod_daystep = elmod_nthhour ÷ 24
    elmod_hourstep = elmod_nthhour % 24
    if elmod_daystep != 0 || elmod_hourstep != 1
        @warn  "You are running the dispatch model with a nth-hour different from one ($(elmod_nthhour))! This will not run the dispatch for every hour of the year!"
    end
    if elmod_starthour != 1
        @warn  "You are running the dispatch model with a start hour different from one ($(elmod_starthour))! Make sure this is correct!"
    end

    switch_infeasibility_tech = WithInfeasibilityTechs()
    write_reduced_timeserie = 0
    load_reduced_timeserie = 0

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
    load_reduced_timeserie,
    switch_LCOE_calc,
    extr_str_results,
    extr_str_dispatch,
    switch_reserve,
    switch_errorcheck,
    switch_results_db,
    switch_endogenous_specifieddemandforecasting)

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

    # NOTE: genesysmod_errorcheck is intentionally NOT run in the dispatch path.
    # Dispatch slices the timeslices to the dispatch window in dataload and
    # aggregates storage links, so the full-year input invariants (demand-profile
    # / YearSplit normalization, storage charge/discharge pairing) would produce
    # false positives here. Input data is validated in the investment build.

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
function genesysmod_dispatch(;elmod_nthhour = 1, elmod_starthour = 1, solver, DNLPsolver, year=2018,
        model_region="minimal", data_base_region="DE", data_file="Data_Europe_openENTRANCE_technoFriendly_combined_v00_kl_21_03_2022_new",
        hourly_data_file = "Hourly_Data_Europe_v09_kl_23_02_2022", threads=4, emissionPathway="MinimalExample",
        emissionScenario="globalLimit", socialdiscountrate=0.05,  inputdir="Inputdata\\",resultdir="Results\\",
        switch_investLimit=1, switch_ccs=1, switch_ramping=0,switch_weighted_emissions=1,set_symmetric_transmission=0.9,
        switch_hydrogen_blending_share = 1, set_storagelevelstart_up = 0.75, set_storagelevelstart_down = 0.25,
         E2P_ratio_deviation_factor = 2, switch_intertemporal=0,
        switch_base_year_bounds = 0,switch_peaking_capacity = 1, set_peaking_slack =1.0, set_peaking_minrun_share =0.15,
        set_peaking_res_cf=0.5, set_peaking_min_thermal=0.25, set_peaking_startyear = 2030, switch_peaking_with_storages = 1, switch_peaking_with_trade = 1,switch_peaking_minrun = 0,
        switch_employment_calculation = 0, switch_endogenous_employment = 0, employment_data_file = "",
        elmod_dunkelflaute = 0, switch_raw_results = CSVResult(), switch_processed_results = 1, switch_LCOE_calc=0,
        switch_dispatch = OneNodeSimple("DE"), extr_str_results = "inv_run", extr_str_dispatch="dispatch_run",
        switch_base_year_bounds_debugging = 0, switch_reserve = 0, switch_iis=1, dispatch_week=nothing, solver_log=true, solver_attr=Dict())

    starttime= Dates.now()

    model, case = genesysmod_build_model_dispatch(;elmod_nthhour=elmod_nthhour, elmod_starthour=elmod_starthour, solver=solver, DNLPsolver=DNLPsolver,
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
        if solver_log
            set_optimizer_attribute(model, "LogFile", joinpath(resultdir,"Run_$(switch.elmod_nthhour)_$(today()).log"))
        end
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
        if solver_log
            set_optimizer_attribute(model, "log_file", joinpath(resultdir,"Run_$(switch.elmod_nthhour)_$(today()).log"))
        end
    end

    for (k,v) in solver_attr
        try
            set_optimizer_attribute(model, k, v)
        catch e
            println("Warning: Could not set solver attribute $k to $v. Error: $e")
        end
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

    elseif primal_status(model) == MOI.FEASIBLE_POINT   # feasible (incl. sub-optimal barrier), not only certified OPTIMAL
        termination_status(model) == MOI.OPTIMAL ||
            @warn "Solver did not certify optimality ($(termination_status(model))); writing dispatch results from the feasible solution."
        VarPar = genesysmod_variable_parameter(model, Sets, Params, Vars, Maps)
        # CSVs gated by switch_processed_results, database by switch_results_db
        # (gating inside genesysmod_results); purge once before any db writes.
        if switch.switch_results_db == 1
            _db_attempt(() -> db_purge_scenario(switch, switch.extr_str_dispatch),
                "scenario purge '$(switch.extr_str_dispatch)'")
        end
        if switch_processed_results == 1 || switch.switch_results_db == 1
            genesysmod_results(model, Sets, Params, VarPar, Vars, switch,
             Settings, Maps, elapsed,switch.extr_str_dispatch)
        end
        genesysmod_results_raw(model, VarPar, Params, Sets, switch,switch.extr_str_dispatch,switch.switch_raw_results)
        if switch.switch_results_db == 1
            _db_attempt(() -> write_raw_results_db(model, VarPar, Params, Sets, switch, switch.extr_str_dispatch),
                "raw results (scenario '$(switch.extr_str_dispatch)')")
        end
        genesysmod_getspecifiedduals(model,switch,switch.extr_str_dispatch, considered_duals)
    else
        println("Termination status:", termination_status(model), ".")
    end

    # Checkpoint the .wal and free the DuckDB file locks for external readers.
    release_dbs()

    return model, Dict("Sets" => Sets, "Params" => Params, "Switch" => switch)
end

function fix_investments!(model, Switch, Sets, Params, Maps, region_full, s_dispatch::OneNodeSimple)
    # read investment results for relevant variables
    tmp_TotalCapacityAnnual, tmp_TotalTradeCapacity, tmp_TotalStorageCapacityAnnual = read_investments(Sets, Switch, Switch.switch_raw_results)
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
            @constraint(model, model[:TotalStorageCapacityAnnual][s,y,r] == tmp_TotalStorageCapacityAnnual[s,y,r],
            base_name="Fix_TotalStorageCapacity_$(s)_$(y)_$(r)")
        end
    end end
    for y ∈ Sets.Year for (f,r,rr) ∈ Maps.Set_Fuel_Regions
        @constraint(model, model[:TotalTradeCapacity][y,f,r,rr] == tmp_TotalTradeCapacity[y,f,r,rr],
        base_name="Fix_TradeConnection_$(y)_$(f)_$(r)_$(rr)")
    end end
    # Update Regional Annual Emission Limits
    tmp_AnnualEmissions = read_emissions(Sets, Switch, Switch.switch_raw_results)
    for y ∈ Sets.Year for r ∈ Sets.Region_full for e ∈ Sets.Emission
        Params.RegionalAnnualEmissionLimit[r,e,y] = tmp_AnnualEmissions[y,e,r] + Params.AnnualExogenousEmission[r,e,y]
    end end end
    return 0
end

function fix_investments!(model, Switch, Sets, Params, Maps, region_full, s_dispatch::OneNodeStorage;threshold=1e-5)
    # read investment results for relevant variables (from a run on full Europe)
    tmp_TotalCapacityAnnual, tmp_TotalTradeCapacity, tmp_TotalStorageCapacityAnnual = read_investments(Sets, Switch, region_full, Switch.switch_raw_results)
    tmp_TotalCapacityAnnual = tmp_TotalCapacityAnnual[:,:,Sets.Region_full]
    tmp_TotalStorageCapacityAnnual = tmp_TotalStorageCapacityAnnual[:,:,Sets.Region_full]

    # determining the ratio between charging and discharging the "trade storage" with the import and export
    tmp_NetTradeAnnual = read_nettrade(Sets, Switch, region_full, Switch.switch_raw_results)
    tmp_NetTradeAnnual.data .= ifelse.(abs.(tmp_NetTradeAnnual.data) .< threshold, 0, tmp_NetTradeAnnual.data)
    storage_ratio = tmp_NetTradeAnnual

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
        for f in Sets.Fuel
            if Params.Tags.TagCanFuelBeTraded[f] != 0
                if sum(Params.TradeCapacityGrowthCosts[:,Sets.Region_full,f]) > 0 #Some fuels like Biomass can be traded freely because of TrC7 and having no TradeCapacityGrowthCosts
                    trade_cap = sum(tmp_TotalTradeCapacity[Sets.Year, f,:,Sets.Region_full])
                else
                    trade_cap = 99999 #convert to GWh, assume it can be discharged in one timestep
                end
                # exchange capacity (capacity unit)
                fix(model[:TotalCapacityAnnual][y,"D_Trade_Storage_$f",r], trade_cap != 0 ? max(threshold,trade_cap) : 0; force=true)
                # storage capacity (energy unit)
                fix(model[:NewStorageCapacity]["S_Trade_Storage_$f",y,r], 5000; force=true)
            end
        end

        for s ∈ setdiff(Sets.Storage, ["S_Trade_Storage_$f" for f in Sets.Fuel])
            fix(model[:TotalStorageCapacityAnnual][s,y,r], tmp_TotalStorageCapacityAnnual[s,y,r] != 0 ? max(threshold,tmp_TotalStorageCapacityAnnual[s,y,r]) : 0; force=true)
        end

    end end
    for y ∈ Sets.Year for (f,r,rr) ∈ Maps.Set_Fuel_Regions
        if model[:TotalTradeCapacity][y,f,r,rr] isa VariableRef
            fix(model[:TotalTradeCapacity][y,f,r,rr], 0; force=true)
        end
    end end

    # Update Regional Annual Emission Limits
    tmp_AnnualEmissions = read_emissions(Sets, Switch, region_full, Switch.switch_raw_results)
    for y ∈ Sets.Year for r ∈ Sets.Region_full for e ∈ Sets.Emission
        Params.RegionalAnnualEmissionLimit[r,e,y] = (tmp_AnnualEmissions[y,e,r] + Params.AnnualExogenousEmission[r,e,y])
    end end end

    #in_data_net_trade = CSV.read(joinpath(Switch.resultdir[], "NetTrade_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" * Switch.extr_str_results * ".csv"), DataFrame, header=col_names, skipto=2)
    #storage_ratio = sum(in_data_net_trade[in.(in_data_net_trade.Year, Ref(Sets.Year)) .& (in_data_net_trade.Fuel .== "Power") .& in.(in_data_net_trade. Region, Ref(Sets.Region_full)),:].Value)
    return storage_ratio
end

function fix_investments!(model, Switch, Sets, Params, Maps, region_full, s_dispatch::TwoNodes)

    tmp_TotalCapacityAnnual, tmp_TotalTradeCapacity, tmp_TotalStorageCapacityAnnual = read_investments(Sets, Switch, region_full, Switch.switch_raw_results)
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
            fix(model[:TotalStorageCapacityAnnual][s,y,Sets.Region_full[1]], tmp_TotalStorageCapacityAnnual[s,y,Sets.Region_full[1]]; force=true)
            fix(model[:TotalStorageCapacityAnnual][s,y,Sets.Region_full[2]], sum(tmp_TotalStorageCapacityAnnual[s,y,r] for r in region_full if r!=Sets.Region_full[1]); force=true)
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
    # Update Regional Annual Emission Limits
    tmp_AnnualEmissions = read_emissions(Sets, Switch, region_full, Switch.switch_raw_results)
    for y ∈ Sets.Year for e ∈ Sets.Emission
        r2 = Sets.Region_full[2]
        r1 = Sets.Region_full[1]
        Params.RegionalAnnualEmissionLimit[r2,e,y] = sum(tmp_AnnualEmissions[y,e,r] for r in region_full if r != r1) + Params.AnnualExogenousEmission[r2,e,y]
        Params.RegionalAnnualEmissionLimit[r1,e,y] = tmp_AnnualEmissions[y,e,r1] + Params.AnnualExogenousEmission[r1,e,y]
    end end
    return 0
end

function read_investments(Sets, Switch, region_full, s_rawresults::CSVResult)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalCapacityAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalCapacityAnnual = create_daa(in_data, "", Sets.Year, Sets.Technology, region_full)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalTradeCapacity_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalTradeCapacity = create_daa(in_data, "", Sets.Year, Sets.Fuel, region_full, region_full)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalStorageCapacityAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalStorageCapacityAnnual = create_daa(in_data, "", Sets.Storage, Sets.Year, region_full)
    return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual
end

function read_investments(Sets, Switch, s_rawresults::CSVResult)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalCapacityAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalCapacityAnnual = create_daa(in_data, "", Sets.Year, Sets.Technology, Sets.Region_full)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalTradeCapacity_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalTradeCapacity = create_daa(in_data, "", Sets.Year, Sets.Fuel, Sets.Region_full, Sets.Region_full)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalStorageCapacityAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_TotalStorageCapacityAnnual = create_daa(in_data, "", Sets.Storage, Sets.Year, Sets.Region_full)
    return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual
end

function read_investments(Sets, Switch, region_full, s_rawresults::TXTResult)
    tmp_TotalCapacityAnnual = read_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalCapacityAnnual[", year=Sets.Year, technology=Sets.Technology, region=region_full)
    tmp_TotalTradeCapacity = read_trade_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalTradeCapacity[", year=Sets.Year, technology=Sets.Fuel, region=region_full)
    tmp_TotalStorageCapacityAnnual = read_storage_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalStorageCapacityAnnual[", year=Sets.Year, technology=Sets.Storage, region=region_full)
    return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual
end

function read_investments(Sets, Switch, s_rawresults::TXTResult)
    tmp_TotalCapacityAnnual = read_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalCapacityAnnual[", year=Sets.Year, technology=Sets.Technology, region=Sets.Region_full)
    tmp_TotalTradeCapacity = read_trade_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalTradeCapacity[", year=Sets.Year, technology=Sets.Fuel, region=Sets.Region_full)
    tmp_TotalStorageCapacityAnnual = read_storage_capacities(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="TotalStorageCapacityAnnual[", year=Sets.Year, technology=Sets.Storage, region=Sets.Region_full)
    return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual
end

function read_investments(Sets, Switch, s_rawresults::TXTandCSV)
    try
        tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual = read_investments(Sets, Switch, TXTResult(s_rawresults.filename))
        return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual
    catch
        try
            tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual = read_investments(Sets, Switch, CSVResult())
            return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual
        catch
            return println("Error: Missing result investment result files for dispatch.")
        end
    end
end

function read_investments(Sets, Switch, region_full, s_rawresults::TXTandCSV)
    try
        tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual = read_investments(Sets, Switch, region_full, TXTResult(s_rawresults.filename))
        return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual
    catch
        try
            tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual = read_investments(Sets, Switch, region_full, CSVResult())
            return tmp_TotalCapacityAnnual,tmp_TotalTradeCapacity,tmp_TotalStorageCapacityAnnual
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

function read_emissions(Sets, Switch, region_full, s_rawresults::CSVResult)
    in_data=CSV.read(joinpath(Switch.resultdir[], "AnnualEmissions_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_AnnualEmissions = create_daa(in_data, "", Sets.Year, Sets.Emission, region_full)
    return tmp_AnnualEmissions
end

function read_emissions(Sets, Switch, s_rawresults::CSVResult)
    in_data=CSV.read(joinpath(Switch.resultdir[], "TotalStorageCapacityAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_AnnualEmissions = create_daa(in_data, "", Sets.Year, Sets.Emission, Sets.Region_full)
    return tmp_AnnualEmissions
end

function read_emissions(Sets, Switch, region_full, s_rawresults::TXTResult)
    tmp_AnnualEmissions = read_emissions_txt(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="AnnualEmissions[", year=Sets.Year, emission=Sets.Emission, region=region_full)
    return tmp_AnnualEmissions
end

function read_emissions(Sets, Switch, s_rawresults::TXTResult)
    tmp_AnnualEmissions = read_emissions_txt(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="AnnualEmissions[", year=Sets.Year, emission=Sets.Emission, region=Sets.Region_full)
    return tmp_AnnualEmissions
end

function read_emissions(Sets, Switch, s_rawresults::TXTandCSV)
    try
        tmp_AnnualEmissions = read_emission(Sets, Switch, TXTResult(s_rawresults.filename))
        return tmp_AnnualEmissions
    catch
        try
            tmp_AnnualEmissions = read_emissions(Sets, Switch, CSVResult())
            return tmp_AnnualEmissions
        catch
            return println("Error: Missing result investment result files for dispatch.")
        end
    end
end

function read_emissions(Sets, Switch, region_full, s_rawresults::TXTandCSV)
    try
        tmp_AnnualEmissions = read_investments(Sets, Switch, region_full, TXTResult(s_rawresults.filename))
        return tmp_AnnualEmissions
    catch
        try
            tmp_AnnualEmissions = read_investments(Sets, Switch, region_full, CSVResult())
            return tmp_AnnualEmissions
        catch
            return println("Error: Missing result investment result files for dispatch.")
        end
    end
end

function read_emissions(Sets, Switch, s_rawresults)
    return println("Raw Result types not specified or set to NoRawResult, please specify the types
     of the raw results from the investment run between CSVResult and TXTResult.")
end

function read_emissions(Sets, Switch, region_full, s_rawresults)
    return println("Raw Result types not specified or set to NoRawResult, please specify the types
     of the raw results from the investment run between CSVResult and TXTResult.")
end

function read_nettrade(Sets, Switch, region_full, s_rawresults::CSVResult)
    in_data=CSV.read(joinpath(Switch.resultdir[], "NetTradeAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * "_" *Switch.extr_str_results * ".csv"), DataFrame)
    tmp_NetTradeAnnual = create_daa(in_data, "", Sets.Year, Sets.Fuel, region_full)
    return tmp_NetTradeAnnual
end

function read_nettrade(Sets, Switch, region_full, s_rawresults::TXTResult)
    tmp_NetTradeAnnual = read_nettrade_txt(file=joinpath(Switch.resultdir[],s_rawresults.filename* "_" *Switch.extr_str_results * ".txt"), nam="NetTradeAnnual[", year=Sets.Year, fuel=Sets.Fuel, region=region_full)
    return tmp_NetTradeAnnual
end

function read_nettrade(Sets, Switch, region_full, s_rawresults::TXTandCSV)
    try
        tmp_NetTradeAnnual = read_nettrade(Sets, Switch, region_full, TXTResult(s_rawresults.filename))
        return tmp_NetTradeAnnual
    catch
        try
            tmp_NetTradeAnnual = read_nettrade(Sets, Switch, region_full, CSVResult())
            return tmp_NetTradeAnnual
        catch
            return println("Error: Missing result investment result files for dispatch.")
        end
    end
end

function read_nettrade(Sets, Switch, region_full, s_rawresults)
    return println("Raw Result types not specified or set to NoRawResult, please specify the types
     of the raw results from the investment run between CSVResult and TXTResult.")
end
