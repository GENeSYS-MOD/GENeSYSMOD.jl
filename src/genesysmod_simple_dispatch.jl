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
Run the simple dispatch model. A previous run is necessary to allow to read in investment 
decisions. For information about the switches, refer to the datastructure documentation
"""
function genesysmod_simple_dispatch(; solver, DNLPsolver, year=2018,
        model_region="minimal", data_base_region="DE", data_file="Data_Europe_openENTRANCE_technoFriendly_combined_v00_kl_21_03_2022_new",
        hourly_data_file = "Hourly_Data_Europe_v09_kl_23_02_2022", threads=20, emissionPathway="MinimalExample",
        emissionScenario="globalLimit", socialdiscountrate=0.05,  inputdir="Inputdata\\",resultdir="Results\\",
        switch_investLimit=1, switch_ccs=1, switch_ramping=0,switch_weighted_emissions=1,switch_intertemporal=0,
        switch_base_year_bounds = 1,switch_peaking_capacity = 1, set_peaking_slack =1.0, set_peaking_minrun_share =0.15, 
        set_peaking_res_cf=0.5, set_peaking_startyear = 2025, switch_peaking_with_storages = 0, switch_peaking_with_trade = 0,switch_peaking_minrun = 1,
        switch_employment_calculation = 0, switch_endogenous_employment = 0, employment_data_file = "",  
        elmod_dunkelflaute = 0, switch_raw_results = 0, switch_processed_results = 1, write_reduced_timeserie = 1, switch_LCOE_calc=0, clusters=0,
        warping_window, hoffmann, switch_reserve=0, pca_path="")

    elmod_daystep = 0
    elmod_hourstep = 1
    elmod_nthhour = 1
    elmod_starthour = 1
    switch_dispatch = 1
    switch_infeasibility_tech = 1
    set_symmetric_transmission = 0
    switch_base_year_bounds_debugging = 0
    set_peaking_min_thermal = 0
    switch_emission_penalty = 1

    Switch = GENeSYS_MOD.Switch(year,
    solver,
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
    clusters,
    warping_window,
    hoffmann,
    switch_reserve,
    switch_emission_penalty,
    pca_path)

    starttime= Dates.now()
    model= JuMP.Model(add_bridges=false)
    Sets, Params, Emp_Sets = genesysmod_dataload(Switch);
    println(length(Sets.Timeslice))
    Maps = make_mapping(Sets,Params)
    Vars=genesysmod_dec(model,Sets,Params,Switch,Maps)
    Settings=genesysmod_settings(Sets, Params, Switch.socialdiscountrate)
    genesysmod_bounds(model,Sets,Params,Vars,Settings,Switch,Maps)
    genesysmod_equ(model,Sets,Params,Vars,Emp_Sets,Settings,Switch,Maps)
    #
    # ####### Fix Investment Variables #############
    #
    # read investment results for relevant variables
    if endswith(Switch.resultdir, ".txt")  || endswith(Switch.resultdir, ".TXT")
        tmp_TotalCapacityAnnual = GENeSYS_MOD.read_capacities(file=Switch.resultdir, nam="TotalCapacityAnnual[", year=Sets.Year, technology=Sets.Technology, region=Sets.Region_full)
        tmp_TotalTradeCapacity = GENeSYS_MOD.read_trade_capacities(file=Switch.resultdir, nam="TotalTradeCapacity[", year=Sets.Year, technology=Sets.Fuel, region=Sets.Region_full)
        tmp_NewStorageCapacity = GENeSYS_MOD.read_storage_capacities(file=Switch.resultdir, nam="TotalStorageCapacity[", year=Sets.Year, technology=Sets.Storage, region=Sets.Region_full)
        tmp_AnnualActivityMode = GENeSYS_MOD.read_activity_by_mode(file=Switch.resultdir, nam="TotalAnnualTechnologyActivityByMode[", year=Sets.Year, technology=Sets.Technology, mode=Sets.Mode_of_operation, region=Sets.Region_full)
    else
        in_data=CSV.read(joinpath(Switch.resultdir, "TotalCapacityAnnual_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * ".csv"), DataFrame)
        tmp_TotalCapacityAnnual = GENeSYS_MOD.create_daa(in_data, "Par_TotalCapacityAnnual", data_base_region, Sets.Year, Sets.Technology, Sets.Region_full)
        in_data=CSV.read(joinpath(Switch.resultdir, "TotalTradeCapacity_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * ".csv"), DataFrame)
        tmp_TotalTradeCapacity = GENeSYS_MOD.create_daa(in_data, "Par_TotalTradeCapacity", data_base_region, Sets.Year, Sets.Fuel, Sets.Region_full, Sets.Region_full)
        in_data=CSV.read(joinpath(Switch.resultdir, "NewStorageCapacity_" * Switch.model_region * "_" * Switch.emissionPathway * "_" * Switch.emissionScenario * ".csv"), DataFrame)
        tmp_NewStorageCapacity = GENeSYS_MOD.create_daa(in_data, "Par_NewStorageCapacity", data_base_region, Sets.Storage, Sets.Year, Sets.Region_full)
    end


    # fix rate of activity if zero mode
    #for y ∈ Sets.Year, r ∈ Sets.Region_full, t ∈ Sets.Technology, m ∈ Sets.Mode_of_operation
    #    if tmp_AnnualActivityMode[y,t,m,r] == 0
  #          println(y,r,t,m)
            #@constraint(model, model[:RateOfActivity][y,:,t,m,r] .== 0,
            #    base_name="Fix_RateofActivitybyMode_$(y)_$(t)_$(r)_$(m)")
   #     end
    #end

    for y ∈ Sets.Year, r ∈ Sets.Region_full, m ∈ 1:2, t ∈ ["HMI_Gas", "P_Gas_OCGT", "HLI_Gas_Boiler", "HLR_Gas_Boiler", "CHP_Gas_CCGT_Natural"]
        if tmp_AnnualActivityMode[y,t,m,r] == 0
            @constraint(model, model[:RateOfActivity][y,:,t,m,r] .== 0,
                    base_name="Fix_RateofActivitybyMode_$(y)_$(r)_$(m)")
        end
    end


    # make constraints fixing investments
    for y ∈ Sets.Year for r ∈ Sets.Region_full
        for t ∈ setdiff(Sets.Technology, Params.TagTechnologyToSubsets["DummyTechnology"])
            @constraint(model, model[:TotalCapacityAnnual][y,t,r] == tmp_TotalCapacityAnnual[y,t,r],
            base_name="Fix_Investments_$(y)_$(t)_$(r)")

            @constraint(model, model[:AccumulatedNewCapacity][y,t,r] == tmp_TotalCapacityAnnual[y,t,r],
            base_name="Fix_Investments2_$(y)_$(t)_$(r)")

            @constraint(model, model[:NewCapacity][y,t,r] == 0,
            base_name="Fix_Investments3_$(y)_$(t)_$(r)")

            if tmp_TotalCapacityAnnual[y,t,r] == 0
                @constraint(model, model[:RateOfActivity][y,:,t,:,r] .== 0,
                base_name="Fix_RateofActivity_$(y)_$(t)_$(r)")
            end


            #@constraint(model, model[:NewCapacity][y,t,r] == 0,
            #base_name="Fix_Investments_new_$(y)_$(t)_$(r)")
        end
        if Switch.switch_infeasibility_tech == 1
            for t ∈ Params.TagTechnologyToSubsets["DummyTechnology"]
                println(t)
                @constraint(model, model[:TotalCapacityAnnual][y,t,r] == 99999,
                base_name="Fix_Investments_$(y)_$(t)_$(r)")
            end
        end
        for s ∈ Sets.Storage
            @constraint(model, model[:NewStorageCapacity][s,y,r] == tmp_NewStorageCapacity[s,y,r],
            base_name="Fix_NewStorageCapacity_$(s)_$(y)_$(r)")
        end
    end end
    for y ∈ Sets.Year, f ∈ Params.TagFuelToSubsets["TradeInv"], r ∈ Sets.Region_full, rr ∈ Sets.Region_full
        @constraint(model, model[:TotalTradeCapacity][y,f,r,rr] == tmp_TotalTradeCapacity[y,f,r,rr],
        base_name="Fix_TradeConnection_$(y)_$(f)_$(r)_$(rr)")
    end
    #
    # ####### CPLEX Options #############
    #

    set_optimizer(model, solver)

    if string(solver) == "Gurobi.Optimizer"
        set_optimizer_attribute(model, "Threads", threads)
        #set_optimizer_attribute(model, "Names", "no")
        set_optimizer_attribute(model, "Method", 2)
        set_optimizer_attribute(model, "BarHomogeneous", 1)
        #set_optimizer_attribute(model, "ResultFile", "Solution_julia.sol")
    elseif string(solver) == "CPLEX.Optimizer"
        set_optimizer_attribute(model, "Threads", threads)          # Match number of threads
        set_optimizer_attribute(model, "Method", 2)                 # Use barrier method (CPLEX LPMETHOD = 4)
        set_optimizer_attribute(model, "BarHomogeneous", 1)         # Use homogeneous barrier method
        #set_optimizer_attribute(model, "Crossover", 1)              # Enable crossover to get basic solution
        #set_optimizer_attribute(model, "Seed", 42)                  # Set seed for deterministic behavior        
        file = open("cplex.opt","w")
        write(file,"threads $threads ")
        write(file,"parallelmode 1")
        write(file,"lpmethod 4 ")
        close(file)
    elseif string(solver) == "HiGHS.Optimizer"
        set_optimizer_attribute(model, "solver", "pdlp")
    end


    println("model_region = $model_region")
    println("data_base_region = $data_base_region")
    println("data_file = $data_file")
    println("solver = $solver")
    optimize!(model)
    println(string(termination_status(model)))

    if occursin("INFEASIBLE",string(termination_status(model))) || termination_status(model) == OBJECTIVE_LIMIT
        println("Model Infeasible! Computing IIS")
        compute_conflict!(model)
        GENeSYS_MOD.print_iis(model)
        println("Saving IIS to file")

        
        #
        # ####### Creating Result Files #############
        #
    
    elseif termination_status(model) == MOI.OPTIMAL 
        #VarPar = GENeSYS_MOD.genesysmod_variable_parameter(model, Sets, Params)
        
        elapsed = (Dates.now() - starttime)#24#3600;
        println(elapsed)


        if endswith(Switch.resultdir, ".txt")
            resultdir = dirname(Switch.resultdir)
        else
            resultdir = Switch.resultdir
        end

        open(joinpath(resultdir, "dispatch_$(basename(Switch.resultdir))_l.txt"), "w") do file
            objective = objective_value(model)
            println(file, "Objective = $objective")
            for v in all_variables(model)
                if value.(v) > 0
                    val = value.(v)
                    str = string(v)
                    println(file, "$str = $val")
                end
            end
        end

        # for y ∈ axes(VarPar.ProductionByTechnology)[1], l ∈ axes(VarPar.ProductionByTechnology)[2], t ∈ axes(VarPar.ProductionByTechnology)[3], f ∈ axes(VarPar.ProductionByTechnology)[4], r ∈ axes(VarPar.ProductionByTechnology)[5]
        #     value = VarPar.ProductionByTechnology[y,l,t,f,r]
        #     if value > 0
        #         println(file, "ProductionByTechnology[$y,$l,$t,$f,$r] = $value")
        #     end
        # end
        #     for y ∈ axes(Params.RateOfDemand)[1], l ∈ axes(Params.RateOfDemand)[2], f ∈ axes(Params.RateOfDemand)[3], r ∈ axes(Params.RateOfDemand)[4]
        #         value = Params.Demand[y,l,f,r] *  Params.YearSplit[l,y]
        #         if value > 0
        #             println(file, "RateOfDemand[$y,$l,$f,$r] = $value")
        #             println(file, "Demand[$y,$l,$f,$r] = $(Params.Demand[y,l,f,r])")
        #         end
        #     end
        # end

        if switch_processed_results == 1
            GENeSYS_MOD.genesysmod_results(model,Sets, Params, VarPar, Vars, Switch, Settings, elapsed,"dispatch")
        end
        if switch_raw_results == 1
            GENeSYS_MOD.genesysmod_results_raw(model, Switch,"dispatch")
        end
    else
        println(termination_status(model))
    end

    return model, Dict("Sets" => Sets, "Params" => Params, "Switch" => Switch)
end