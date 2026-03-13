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
Build the model without running it. For information about the switches, refer to the datastructure documentation.
"""
function genesysmod_build_model(;elmod_daystep, elmod_hourstep, solver=nothing, DNLPsolver, year=2018,
    model_region="minimal", data_base_region="DE",
    data_file="Data_Europe_openENTRANCE_technoFriendly_combined_v00_kl_21_03_2022_new",
    hourly_data_file = "Hourly_Data_Europe_v09_kl_23_02_2022",
    threads=4, emissionPathway="MinimalExample", emissionScenario="globalLimit",
    socialdiscountrate=0.05,  inputdir="Inputdata\\", resultdir="Results\\",
    switch_infeasibility_tech = NoInfeasibilityTechs(), switch_investLimit=1, switch_ccs=1,
    switch_ramping=0,switch_weighted_emissions=1,set_symmetric_transmission=0.9, switch_hydrogen_blending_share = 1,
    set_storagelevelstart_up = 0.75, set_storagelevelstart_down = 0.25, E2P_ratio_deviation_factor = 2,
    switch_intertemporal=0, switch_base_year_bounds = 1,switch_peaking_capacity = 1, set_peaking_slack =1.0,
    set_peaking_minrun_share =0.15, set_peaking_res_cf=0.5, set_peaking_min_thermal=0.25, set_peaking_startyear = 2030,
    switch_peaking_with_storages = 1, switch_peaking_with_trade = 1,switch_peaking_minrun = 0,
    switch_employment_calculation = 0, switch_endogenous_employment = 0,
    employment_data_file = "", elmod_nthhour = 0, elmod_starthour = 8,
    elmod_dunkelflaute = 0, switch_raw_results = NoRawResult(), switch_processed_results = 0, write_reduced_timeserie = 1, switch_LCOE_calc=0,
    switch_reserve=0,switch_base_year_bounds_debugging=0,
    extr_str_results = "inv_run", extr_str_dispatch="dispatch_run",switch_iis=1)

    if elmod_nthhour != 0 && (elmod_daystep !=0 || elmod_hourstep !=0)
        @warn "Both elmod_nthhour and elmod_daystep/elmod_hourstep are defined.
         elmod_nthhour will be ignored. To use it, change elmod_daystep/elmod_hourstep to 0"
    elseif elmod_nthhour == 0 && elmod_daystep ==0 && elmod_hourstep ==0
        @warn "Both elmod_nthhour and elmod_daystep/elmod_hourstep are 0.
         Set a value to at least one of them."
    elseif elmod_nthhour != 0 && elmod_daystep ==0 && elmod_hourstep ==0
        elmod_daystep = elmod_nthhour ÷ 24
        elmod_hourstep = elmod_nthhour % 24
    elseif elmod_nthhour == 0
        elmod_nthhour = elmod_daystep*24 + elmod_hourstep
    end

    if !isdir(resultdir)
        mkdir(resultdir)
    end

    elmod_nthhour = Int64(elmod_daystep * 24 + elmod_hourstep)
    switch_dispatch = NoDispatch()

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

    model= JuMP.Model()

    #
    # ####### Load data from provided excel files and declarations #############
    #

    Sets, Params, Emp_Sets = genesysmod_dataload(switch);
    Maps = make_mapping(Sets,Params)
    Vars=genesysmod_dec(model,Sets,Params,switch,Maps)
    #
    # ####### Settings for model run (Years, Regions, etc) #############
    #

    Settings=genesysmod_settings(Sets, Params, switch.socialdiscountrate)

    #end
    #
    # ####### apply general model bounds #############
    #

    genesysmod_bounds(model,Sets,Params,Vars,Settings,switch,Maps)

    #
    # ####### load additional bounds and data for certain scenarios #############
    #

    scn_file = "genesysmod_scenariodata_$(switch.model_region).jl"
    scn_path = joinpath(pkgdir(GENeSYS_MOD),"src", scn_file)
    if isfile(scn_path)
        modname = Symbol("ScenarioData", uppercasefirst(switch.model_region))
        scenario_module = getfield(GENeSYS_MOD, modname)
        scenario_module.genesysmod_scenariodata(model,Sets,Params,Maps,Vars,switch)
    else
        @warn "No scenario data for region $(switch.model_region) found at $(scn_path)!"
    end

    #
    # ####### Including Equations #############
    #

    considered_duals = genesysmod_equ(model,Sets,Params,Vars,Emp_Sets,Settings,switch,Maps)

    return model, Dict("Sets" => Sets, "Params" => Params,
     "Switch" => switch, "Vars" => Vars, "Maps" => Maps, "Settings" => Settings, "ConsideredDuals" => considered_duals)
end

"""
Run the whole model. It runs the whole process from input data reading to
result processing. For information about the switches, refer to the datastructure documentation.
"""
function genesysmod(;elmod_daystep, elmod_hourstep, solver, DNLPsolver, year=2018,
    model_region="minimal", data_base_region="DE",
    data_file="Data_Europe_openENTRANCE_technoFriendly_combined_v00_kl_21_03_2022_new",
    hourly_data_file = "Hourly_Data_Europe_v09_kl_23_02_2022",
    threads=4, emissionPathway="MinimalExample", emissionScenario="globalLimit",
    socialdiscountrate=0.05,  inputdir="Inputdata\\", resultdir="Results\\",
    switch_infeasibility_tech = NoInfeasibilityTechs(), switch_investLimit=1, switch_ccs=1,
    switch_ramping=0,switch_weighted_emissions=1,set_symmetric_transmission=0.9, switch_hydrogen_blending_share = 1,
    set_storagelevelstart_up = 0.75, set_storagelevelstart_down = 0.25, E2P_ratio_deviation_factor = 2,
    switch_intertemporal=0, switch_base_year_bounds = 1,switch_peaking_capacity = 1, set_peaking_slack =1.0,
    set_peaking_minrun_share =0.15, set_peaking_res_cf=0.5, set_peaking_min_thermal=0.25, set_peaking_startyear = 2030,
    switch_peaking_with_storages = 1, switch_peaking_with_trade = 1,switch_peaking_minrun = 0,
    switch_employment_calculation = 0, switch_endogenous_employment = 0,
    employment_data_file = "", elmod_nthhour = 0, elmod_starthour = 8,
    elmod_dunkelflaute = 0, switch_raw_results = NoRawResult(), switch_processed_results = 0, write_reduced_timeserie = 1, switch_LCOE_calc=0,
    switch_reserve=0,switch_base_year_bounds_debugging=0,
    extr_str_results = "inv_run", extr_str_dispatch="dispatch_run",switch_iis=1)

    starttime = Dates.now()

    model, case = genesysmod_build_model(;elmod_daystep=elmod_daystep, elmod_hourstep=elmod_hourstep, solver=solver, DNLPsolver=DNLPsolver,
    year=year, model_region=model_region, data_base_region=data_base_region,
    data_file=data_file, hourly_data_file = hourly_data_file,
    threads=threads, emissionPathway=emissionPathway, emissionScenario=emissionScenario,
    socialdiscountrate=socialdiscountrate,  inputdir=inputdir, resultdir=resultdir,
    switch_infeasibility_tech = switch_infeasibility_tech,
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
    employment_data_file = employment_data_file, elmod_nthhour = elmod_nthhour, elmod_starthour = elmod_starthour,
    elmod_dunkelflaute = elmod_dunkelflaute, switch_raw_results = switch_raw_results,
    switch_processed_results = switch_processed_results, write_reduced_timeserie = write_reduced_timeserie,
    switch_LCOE_calc=switch_LCOE_calc,
    switch_reserve=switch_reserve,
    extr_str_results = extr_str_results, extr_str_dispatch=extr_str_dispatch,
    switch_iis=switch_iis);
    Sets = case["Sets"]
    Params = case["Params"]
    Vars = case["Vars"]
    Maps = case["Maps"]
    Settings = case["Settings"]
    considered_duals = case["ConsideredDuals"]
    switch = case["Switch"]
    #
    # ####### CPLEX Options #############
    #

    set_optimizer(model, solver)

    if solver_name(model) == "Gurobi"
        set_optimizer_attribute(model, "Threads", threads)
        #set_optimizer_attribute(model, "Names", "no")
        set_optimizer_attribute(model, "Method", 2)
        set_optimizer_attribute(model, "BarHomogeneous", 1)
        set_optimizer_attribute(model, "LogFile", joinpath(resultdir,"Run_$(elmod_nthhour)_$(today()).log"))
    elseif solver_name(model) == "CPLEX"
        set_optimizer_attribute(model, "CPX_PARAM_THREADS", threads)
        set_optimizer_attribute(model, "CPX_PARAM_PARALLELMODE", -1)
        set_optimizer_attribute(model, "CPX_PARAM_LPMETHOD", 4)
        set_optimizer_attribute(model, "CPX_PARAM_SOLUTIONTYPE", 2)
        #env = model.moi_backend.optimizer.model.env
        #CPLEX.CPXsetlogfilename(env, joinpath(resultdir,"Run_$(elmod_nthhour)_$(today()).log"), "w+")
        #set_optimizer_attribute(model, "CPX_PARAM_BAROBJRNG", 1e+075)
    elseif solver_name(model) == "HiGHS"
        set_optimizer_attribute(model, "solver", "ipm")
        #set_optimizer_attribute(model, "solver", "pdlp")
        set_optimizer_attribute(model, "run_crossover", "off")
        set_optimizer_attribute(model, "log_file", joinpath(resultdir,"Run_$(elmod_nthhour)_$(today()).log"))
    end

    println("model_region = $model_region")
    println("data_base_region = $data_base_region")
    println("data_file = $data_file")
    println("solver = $solver")

    optimize!(model)

    elapsed = (Dates.now() - starttime)#24#3600;

    #
    # ####### Creating Result Files #############
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
                open(joinpath(resultdir,"IIS_$(elmod_nthhour)_$(today()).txt"), "w") do f
                    for line in res
                        println(f, line)
                    end
                end
            end
        else
            error("Model infeasible. Turn on 'switch_iis' to compute and write the iis file")
        end

    elseif termination_status(model) == MOI.OPTIMAL
        VarPar = genesysmod_variable_parameter(model, Sets, Params, Vars,Maps)
        if switch_processed_results == 1
            genesysmod_results(model, Sets, Params, VarPar, Vars, switch,
             Settings, Maps, elapsed, switch.extr_str_results)
        end
        genesysmod_results_raw(model, VarPar, Params, switch,switch.extr_str_results, switch.switch_raw_results)
        genesysmod_getspecifiedduals(model,switch,switch.extr_str_results, considered_duals)
    else
        println("Termination status:", termination_status(model), ".")
    end

    return model, Dict("Sets" => Sets, "Params" => Params,
     "Switch" => switch)
end
