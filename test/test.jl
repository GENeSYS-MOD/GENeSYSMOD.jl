import Pkg
cd("/cluster/home/danare/git/GENeSYS-MOD/dev_jl")
Pkg.activate(".")
using Pkg
Pkg.develop(path="/cluster/home/danare/git/GENeSYS-MOD-main/GENeSYS_MOD.jl")
ENV["CPLEX_STUDIO_BINARIES"] = "/cluster/home/danare/opt/ibm/ILOG/CPLEX_Studio2211/cplex/bin/x86-64_linux/"
Pkg.build("CPLEX")

using MultivariateStats 
using GENeSYS_MOD
using JuMP
using Dates
using CPLEX
using Ipopt
using CSV
using Revise
using XLSX
using Pkg
using DataFrames
using HiGHS
using SavitzkyGolay
using Gurobi

for dir in ["test"]
    building_time=[]
    solving_time=[]
    objective_list=[]
    n_var = []
    n_constr = []
    resultdir = joinpath("/cluster/home/danare/git/dana/results","spatial", "3_Submission", dir)

    # iterate through 1,2,3,4 days respectively
    for c in [3]
        year=2018
        solver=Gurobi.Optimizer
        DNLPsolver=Ipopt.Optimizer
        model_region="minimal"
        data_base_region="DE"
        data_file="Eight_Nodes_Gradual_De_20250417"
        hourly_data_file="Timeseries_renewable_ninja"
        threads=30
        emissionPathway="MinimalExample"
        emissionScenario="globalLimit"
        socialdiscountrate=0.05
        inputdir=joinpath("/cluster/home/danare/git/oceangrid_case/Input")
        resultdir = resultdir
        switch_infeasibility_tech=0
        switch_investLimit=0
        switch_ccs=0
        switch_ramping=0
        switch_weighted_emissions=0
        set_symmetric_transmission=0
        switch_intertemporal=0
        switch_base_year_bounds=0
        switch_base_year_bounds_debugging=0
        switch_peaking_capacity=0
        set_peaking_slack=0
        set_peaking_minrun_share=0
        set_peaking_res_cf=0
        set_peaking_min_thermal=0
        set_peaking_startyear=0
        switch_peaking_with_storages=0
        switch_peaking_with_trade=0
        switch_peaking_minrun=0
        switch_employment_calculation=0
        switch_endogenous_employment=0
        employment_data_file="None"
        switch_dispatch=0
        elmod_nthhour=1
        elmod_starthour=0
        elmod_dunkelflaute=0
        elmod_daystep=0
        elmod_hourstep=0
        switch_raw_results=0
        switch_processed_results=0
        write_reduced_timeserie=1
        switch_LCOE_calc=0
        clusters=c
        warping_window=1
        hoffmann = false
        switch_reserve=0
        switch_emission_penalty=1
        pca_path = "/cluster/home/danare/TMP/29_Input_Data_Analysis/pca_components.xlsx"
        println("Hoffmann $hoffmann $dir")
        println(pca_path)

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

        switch_iis = 1

        model= JuMP.Model(add_bridges=false)
        Sets, Params, Emp_Sets = GENeSYS_MOD.genesysmod_dataload(Switch);
        Maps = GENeSYS_MOD.make_mapping(Sets,Params)
        Vars=GENeSYS_MOD.genesysmod_dec(model,Sets,Params,Switch,Maps)
        Settings=GENeSYS_MOD.genesysmod_settings(Sets, Params, Switch.socialdiscountrate)
        GENeSYS_MOD.genesysmod_bounds(model,Sets,Params,Vars,Settings,Switch,Maps)
        GENeSYS_MOD.genesysmod_equ(model,Sets,Params,Vars,Emp_Sets,Settings,Switch,Maps)

        set_optimizer(model, solver)

        # cplex
        if string(solver) == "Gurobi.Optimizer"
            set_optimizer_attribute(model, "Threads", threads)
            #set_optimizer_attribute(model, "Names", "no")
            set_optimizer_attribute(model, "Method", 2)
            set_optimizer_attribute(model, "BarHomogeneous", 1)
            set_optimizer_attribute(model, "ResultFile", "Solution_julia.sol")
            file = open("gurobi.opt","w")
            write(file,"threads $threads ")
            write(file,"method 2 ")
            #write(file,"names no ")
            write(file,"barhomogeneous 1 ")
            #write(file,"timelimit 1000000 ")
            close(file)
        elseif string(solver) == "CPLEX.Optimizer"
            set_optimizer_attribute(model, "CPX_PARAM_THREADS", threads)
            set_optimizer_attribute(model, "CPX_PARAM_PARALLELMODE", -1)
            set_optimizer_attribute(model, "CPX_PARAM_LPMETHOD", 4)
            #set_optimizer_attribute(model, "CPX_PARAM_BAROBJRNG", 1e+075)
    
            file = open("cplex.opt","w")
            write(file,"threads $threads ")
            write(file,"parallelmode -1 ")
            write(file,"lpmethod 4 ")
            #write(file,"quality yes ")
            #write(file,"barobjrng 1e+075 ")
            #write(file,"tilim 1000000 ")
            close(file)
        end
        
        n = Dates.now()
        b = (n - starttime)

        optimize!(model)
        println(objective_value(model))
    end
end