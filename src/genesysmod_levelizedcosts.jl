"""
Internal function used in the run process to compute results related to levelized costs.
"""
function genesysmod_levelizedcosts(model,Sets, Params, VarPar, Vars, Switch, Settings, z_fuelcosts, LoopSetOutput, LoopSetInput, extr_str)
    TierTwo = [
    "X_Methanation",
    "X_SMR"]

    TierThree = [
    "Gas_Bio",
    "Biofuel",
    "Gas_Synth"]

    TierFive = [
    "Mobility_Passenger",
    "Mobility_Freight",
    "Heat_Buildings",
    "Heat_Low_Industrial",
    "Heat_MediumHigh_Industrial",
    "Heat_MediumLow_Industrial",
    "Heat_High_Industrial"]

    Resources = [
    "Hardcoal",
    "Lignite",
    "Gas_Natural",
    "Oil",
    "Nuclear",
    "Biomass",
    "H2"]

    ResourceTechnologies = [
    "R_Grass",
    "R_Wood",
    "R_Residues",
    "R_Paper_Cardboard",
    "R_Roundwood",
    "R_Biogas",
    "Z_Import_Hardcoal",
    "R_Coal_Hardcoal",
    "R_Coal_Lignite",
    "Z_Import_Oil",
    "Z_Import_Gas",
    "R_Nuclear",
    "R_Gas",
    "R_Oil"]


    Time=range(0,110)

    #parameters
    levelizedcostsPJ = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Fuel),length(Sets.Mode_of_operation),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Fuel, Sets.Mode_of_operation, Sets.Year)
    levelizedcostskWh = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Fuel),length(Sets.Mode_of_operation),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Fuel, Sets.Mode_of_operation, Sets.Year)
    maxgeneration = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Year),length(Sets.Mode_of_operation),length(Sets.Fuel)), Sets.Region_full, Sets.Technology, Sets.Year, Sets.Mode_of_operation, Sets.Fuel)
    fuelcosts = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Fuel),length(Sets.Mode_of_operation),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Fuel, Sets.Mode_of_operation, Sets.Year)
    resourcecosts = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Fuel),length(Sets.Year)), Sets.Region_full, Sets.Fuel, Sets.Year)
    #AnnualProduction
    #AnnualTechnologyProduction
    emissioncosts = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Fuel),length(Sets.Mode_of_operation),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Fuel, Sets.Mode_of_operation, Sets.Year)
    capitalcosts = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Fuel),length(Sets.Mode_of_operation),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Fuel, Sets.Mode_of_operation, Sets.Year)
    omcosts = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Fuel),length(Sets.Mode_of_operation),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Fuel, Sets.Mode_of_operation, Sets.Year)
    discountedfuelcosts = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Fuel),length(Sets.Mode_of_operation),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Fuel, Sets.Mode_of_operation, Sets.Year)
    testlevelizedcostsPJ = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Fuel),length(Sets.Mode_of_operation),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Fuel, Sets.Mode_of_operation, Sets.Year)
    AnnualTechnologyProductionByMode = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Technology),length(Sets.Mode_of_operation),length(Sets.Fuel),length(Sets.Year)), Sets.Region_full, Sets.Technology, Sets.Mode_of_operation, Sets.Fuel, Sets.Year)
    #output_costs
    tmp_set= vcat(Sets.Fuel,["Power2","Power3","H22","Gas_Synth2","Gas_Bio2","Biofuel2"])
    testcosts = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(tmp_set),length(Sets.Year)), Sets.Region_full, tmp_set, Sets.Year)
    #output_fuelcosts
    #TechnologyEmissions
    RegionalEmissionContentPerFuel = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year),length(Sets.Region_full),length(Sets.Fuel),length(Sets.Emission)), Sets.Year, Sets.Region_full, Sets.Fuel, Sets.Emission)
    #AnnualSectorEmissions
    #TechnologyEmissionsByMode

    AnnualProduction = VarPar.ProductionAnnual
    AnnualTechnologyProduction = value.(model[:ProductionByTechnologyAnnual])
    for r ∈ Sets.Region_full for t ∈ Sets.Technology for m ∈ Sets.Mode_of_operation for f ∈ Sets.Fuel for y ∈ Sets.Year
        AnnualTechnologyProductionByMode[r,t,m,f,y] = sum(VarPar.RateOfProductionByTechnologyByMode[y,l,t,m,f,r]*Params.YearSplit[l,y] for l ∈ Sets.Timeslice)
    end end end end end
    TechnologyEmissions = value.(model[:AnnualTechnologyEmission])
    AnnualSectorEmissions = value.(model[:AnnualSectoralEmissions])
    # TechnologyEmissionsByMode = value.(Vars.AnnualTechnologyEmissionByMode)

    CarbonPrice = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Region_full),length(Sets.Emission),length(Sets.Year)), Sets.Region_full, Sets.Emission, Sets.Year)
    for r ∈ Sets.Region_full for y ∈ Sets.Year for e ∈ Sets.Emission
        CarbonPrice[r,e,y] = (-1)*dual(constraint_by_name(model,"E8_RegionalAnnualEmissionsLimit_$(y)_CO2_$(r)"))
        if CarbonPrice[r,e,y] == 0
            CarbonPrice[r,e,y] = (-1)*dual(constraint_by_name(model,"E9_AnnualEmissionsLimit_$(y)_CO2"))
        end
        if CarbonPrice[r,e,y] == 0
            CarbonPrice[r,e,y] = Params.EmissionsPenalty[r,e,y]
        end
        if CarbonPrice[r,e,y] == 0
            CarbonPrice[r,e,y] = 15
        end
    end end end

    SectorEmissions, EmissionIntensity = genesysmod_emissionintensity(model, Sets, Params, VarPar, Vars, TierFive, LoopSetOutput, LoopSetInput)

    for y ∈ Sets.Year for r ∈ Sets.Region_full for e ∈ Sets.Emission
        for f ∈ Sets.Fuel
            RegionalEmissionContentPerFuel[y,r,f,e] = Params.EmissionContentPerFuel[f,e]
        end
        RegionalEmissionContentPerFuel[y,r,"Power",e] = EmissionIntensity[y,r,"Power",e]
    end end end

    ####
    #### Tier 0: Preliminary Calculations (Generation Factors, O&M Costs, Capital Costs, Resource Commodity Prices)
    ####
    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                maxgeneration[r,t,y,m,f] =  sum(Params.CapacityFactor[r,t,l,y]*Params.YearSplit[l,y] for l ∈ Sets.Timeslice)* maximum(Params.AvailabilityFactor[r,t,:])*Params.CapacityToActivityUnit[t]*Params.OutputActivityRatio[r,t,f,m,y]
            end
        end
        for f ∈ Resources
            if value(AnnualProduction[y,f,r]) > 0
                resourcecosts[r,f,y] = sum((Params.VariableCost[r,t,1,y] * AnnualTechnologyProduction[y,t,f,r]/AnnualProduction[y,f,r]) for t ∈ ResourceTechnologies)
            end
            if resourcecosts[r,f,y] == 0
                resourcecosts[r,f,y] = z_fuelcosts[f,y,r]
            end
        end
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                maxgeneration[r,t,y,m,f] =  sum(Params.CapacityFactor[r,t,l,y]*Params.YearSplit[l,y] for l ∈ Sets.Timeslice)* maximum(Params.AvailabilityFactor[r,t,:])*Params.CapacityToActivityUnit[t]*Params.OutputActivityRatio[r,t,f,m,y]

                if Params.OutputActivityRatio[r,t,f,m,y] > 0
                    fuelcosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
                    emissioncosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*sum(Params.EmissionActivityRatio[r,t,m,e,y]*RegionalEmissionContentPerFuel[y,r,fff,e]*CarbonPrice[r,e,y] for e ∈ Sets.Emission) for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
                    if maxgeneration[r,t,y,m,f] > 0
                        capitalcosts[r,t,f,m,y]  = (Params.CapitalCost[r,t,y]) / sum((maxgeneration[r,t,y,m,f]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                        omcosts[r,t,f,m,y] = (sum(((Params.FixedCost[r,t,y]+(Params.VariableCost[r,t,m,y])*maxgeneration[r,t,y,m,f])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) / sum((maxgeneration[r,t,y,m,f]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                    end
                end
            end
        end
    end end


    ####
    #### Tier 1: Power Prices WITHOUT Re-Electrification
    ####

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for (t,m) ∈ LoopSetOutput[(r,"Power",y)]
            if Params.OutputActivityRatio[r,t,"Power",m,y] > 0 && maxgeneration[r,t,y,m,"Power"] > 0
                discountedfuelcosts[r,t,"Power",m,y] = (sum((((fuelcosts[r,t,"Power",m,y])*maxgeneration[r,t,y,m,"Power"])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                sum((maxgeneration[r,t,y,m,"Power"]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])

                testlevelizedcostsPJ[r,t,"Power",m,y] = (Params.CapitalCost[r,t,y]+sum(((Params.FixedCost[r,t,y]+(Params.VariableCost[r,t,m,y]+fuelcosts[r,t,"Power",m,y])*maxgeneration[r,t,y,m,"Power"])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                sum((maxgeneration[r,t,y,m,"Power"]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
            end

            levelizedcostsPJ[r,t,"Power",m,y] = capitalcosts[r,t,"Power",m,y]+omcosts[r,t,"Power",m,y]+discountedfuelcosts[r,t,"Power",m,y]+emissioncosts[r,t,"Power",m,y]
        end

        if AnnualProduction[y,"Power",r] > 0
            resourcecosts[r,"Power",y] = sum((levelizedcostsPJ[r,t,"Power",1,y] * AnnualTechnologyProductionByMode[r,t,1,"Power",y]/sum(AnnualTechnologyProductionByMode[r,tt,1,"Power",y] for tt ∈ Sets.Technology)) for t ∈ Sets.Technology)
        end
        testcosts[r,"Power",y] = resourcecosts[r,"Power",y]*3.6

    end end


    ####
    #### Tier 2: Hydrogen
    ####

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                fuelcosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
            end
        end
        for (t,m) ∈ LoopSetOutput[(r,"H2",y)]
            if Params.OutputActivityRatio[r,t,"H2",m,y] > 0 && maxgeneration[r,t,y,m,"H2"] > 0
                discountedfuelcosts[r,t,"H2",m,y] = (sum((((fuelcosts[r,t,"H2",m,y])*maxgeneration[r,t,y,m,"H2"])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                sum((maxgeneration[r,t,y,m,"H2"]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                levelizedcostsPJ[r,t,"H2",m,y] = capitalcosts[r,t,"H2",m,y]+omcosts[r,t,"H2",m,y]+discountedfuelcosts[r,t,"H2",m,y]+emissioncosts[r,t,"H2",m,y]
            end
        end
        if sum(AnnualTechnologyProductionByMode[r,tt,1,"H2",y] for tt ∈ Sets.Technology) > 0
            resourcecosts[r,"H2",y] = sum((levelizedcostsPJ[r,t,"H2",1,y] * AnnualTechnologyProductionByMode[r,t,1,"H2",y]/sum(AnnualTechnologyProductionByMode[r,tt,1,"H2",y] for tt ∈ Sets.Technology)) for t ∈ Sets.Technology)
        end
        testcosts[r,"H2",y] = resourcecosts[r,"H2",y]*3.6
    end end

    ####
    #### Tier 3: Synth Nat Gas, Biogas, Biofuels
    ####

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                fuelcosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
            end
        end
        for f ∈ TierThree
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                if maxgeneration[r,t,y,m,f] > 0
                    discountedfuelcosts[r,t,f,m,y] = (sum((((fuelcosts[r,t,f,m,y])*maxgeneration[r,t,y,m,f])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                    sum((maxgeneration[r,t,y,m,f]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                    levelizedcostsPJ[r,t,f,m,y] = capitalcosts[r,t,f,m,y]+omcosts[r,t,f,m,y]+discountedfuelcosts[r,t,f,m,y]+emissioncosts[r,t,f,m,y]
                end
            end
        end
        for f ∈ TierThree
            if sum(AnnualTechnologyProductionByMode[r,tt,1,f,y] for tt ∈ Sets.Technology) > 0
                resourcecosts[r,f,y] = sum((levelizedcostsPJ[r,t,f,1,y] * AnnualTechnologyProductionByMode[r,t,1,f,y]/sum(AnnualTechnologyProductionByMode[r,tt,1,f,y] for tt ∈ Sets.Technology)) for t ∈ Sets.Technology)
            end
            testcosts[r,f,y] = resourcecosts[r,f,y]*3.6
        end
        if resourcecosts[r,"Gas_Bio",y] == 0
            resourcecosts[r,"Gas_Bio",y] = resourcecosts[r,"Biomass",y]*Params.InputActivityRatio[r,"X_Methanation","Biomass",2,y]
        end
    end end

    ####
    #### Tier 4: Power Prices including Re-Electrification from e.g. Synth Nat Gas
    ####
    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                if Params.OutputActivityRatio[r,t,f,m,y] > 0
                    fuelcosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
                end
            end
            for t ∈ Params.TagTechnologyToSubsets["StorageDummies"]
                if Params.OutputActivityRatio[r,t,f,2,y] > 0
                    fuelcosts[r,t,f,1,y] = sum(Params.InputActivityRatio[r,t,fff,1,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/(Params.OutputActivityRatio[r,t,f,2,y]*sum(Params.TechnologyToStorage[t,s,1,y]^2 for s ∈ Sets.Storage))
                end
            end
        end
        for (t,m) ∈ LoopSetOutput[(r,"Power",y)]
            if Params.OutputActivityRatio[r,t,"Power",m,y] > 0 && maxgeneration[r,t,y,m,"Power"] > 0
                discountedfuelcosts[r,t,"Power",m,y] = (sum((((fuelcosts[r,t,"Power",m,y])*maxgeneration[r,t,y,m,"Power"])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                sum((maxgeneration[r,t,y,m,"Power"]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                levelizedcostsPJ[r,t,"Power",m,y] = capitalcosts[r,t,"Power",m,y]+omcosts[r,t,"Power",m,y]+discountedfuelcosts[r,t,"Power",m,y]+emissioncosts[r,t,"Power",m,y]
            end
        end
        if AnnualProduction[y,"Power",r] > 0
            resourcecosts[r,"Power",y]= sum((levelizedcostsPJ[r,t,"Power",m,y] * AnnualTechnologyProductionByMode[r,t,m,"Power",y]/sum(AnnualTechnologyProductionByMode[r,tt,mm,"Power",y] for tt ∈ Sets.Technology for mm ∈ Sets.Mode_of_operation)) for t ∈ Sets.Technology for m ∈ Sets.Mode_of_operation)
        end
        testcosts[r,"Power2",y] = resourcecosts[r,"Power",y]*3.6
    end end

    ####
    #### Tier 4.5: Resource Costs for the Case of no Production
    ####
    for r ∈ Sets.Region_full for y ∈ Sets.Year
        if resourcecosts[r,"H2",y] == 0
            resourcecosts[r,"H2",y] = levelizedcostsPJ[r,"Z_Import_H2","H2",1,y]
        end
        if resourcecosts[r,"Biofuel",y] == 0
            resourcecosts[r,"Biofuel",y] = levelizedcostsPJ[r,"X_Biofuel","Biofuel",1,y]
        end
        resourcecosts[r,"Gas_Synth",y] = levelizedcostsPJ[r,"X_Methanation","Gas_Synth",1,y]
    end end

    #$ontext
    ####
    #### Tier 2X: Hydrogen
    ####

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                if Params.OutputActivityRatio[r,t,f,m,y] > 0
                    fuelcosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
                end
            end
        end
        for (t,m) ∈ LoopSetOutput[(r,"H2",y)]
            if Params.OutputActivityRatio[r,t,"H2",m,y] > 0 && maxgeneration[r,t,y,m,"H2"] > 0
                discountedfuelcosts[r,t,"H2",m,y] = (sum((((fuelcosts[r,t,"H2",m,y])*maxgeneration[r,t,y,m,"H2"])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                sum((maxgeneration[r,t,y,m,"H2"]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                levelizedcostsPJ[r,t,"H2",m,y] = capitalcosts[r,t,"H2",m,y]+omcosts[r,t,"H2",m,y]+discountedfuelcosts[r,t,"H2",m,y]+emissioncosts[r,t,"H2",m,y]
            end
        end
        if sum(AnnualTechnologyProductionByMode[r,tt,1,"H2",y] for tt ∈ Sets.Technology) != 0
            resourcecosts[r,"H2",y]= sum((levelizedcostsPJ[r,t,"H2",1,y] * AnnualTechnologyProductionByMode[r,t,1,"H2",y]/sum(AnnualTechnologyProductionByMode[r,tt,1,"H2",y] for tt ∈ Sets.Technology)) for t ∈ Sets.Technology)
        end
        testcosts[r,"H22",y] = resourcecosts[r,"H2",y]*3.6
    end end

    ####
    #### Tier 3X: Synth Nat Gas, Biogas, Biofuels
    ####

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                if Params.OutputActivityRatio[r,t,f,m,y] > 0
                    fuelcosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
                end
            end
        end
        for f ∈ TierThree
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                if Params.OutputActivityRatio[r,t,f,m,y] > 0 && maxgeneration[r,t,y,m,f] > 0
                    discountedfuelcosts[r,t,f,m,y] = (sum((((fuelcosts[r,t,f,m,y])*maxgeneration[r,t,y,m,f])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                    sum((maxgeneration[r,t,y,m,f]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                    levelizedcostsPJ[r,t,f,m,y] = capitalcosts[r,t,f,m,y]+omcosts[r,t,f,m,y]+discountedfuelcosts[r,t,f,m,y]+emissioncosts[r,t,f,m,y]
                end
            end
        end
        for f ∈ TierThree
            if sum(AnnualTechnologyProductionByMode[r,tt,mm,f,y] for tt ∈ Sets.Technology for mm ∈ Sets.Mode_of_operation) > 0
                resourcecosts[r,f,y]= sum((levelizedcostsPJ[r,t,f,m,y] * AnnualTechnologyProductionByMode[r,t,m,f,y]/sum(AnnualTechnologyProductionByMode[r,tt,mm,f,y] for tt ∈ Sets.Technology for mm ∈ Sets.Mode_of_operation)) for t ∈ Sets.Technology for m ∈ Sets.Mode_of_operation)
            end
        end
        resourcecosts[r,"Gas_Synth",y] = levelizedcostsPJ[r,"X_Methanation","Gas_Synth",1,y]
        testcosts[r,"Gas_Synth2",y] = resourcecosts[r,"Gas_Synth",y]*3.6
        testcosts[r,"Gas_Bio2",y] = resourcecosts[r,"Gas_Bio",y]*3.6
        testcosts[r,"Biofuel2",y] = resourcecosts[r,"Biofuel",y]*3.6
    end end

    ####
    #### Tier 4X: Power Prices including Re-Electrification from e.g. Synth Nat Gas
    ####

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                if Params.OutputActivityRatio[r,t,f,m,y] > 0
                    fuelcosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
                end
            end
            for t ∈ Params.TagTechnologyToSubsets["StorageDummies"]
                if Params.OutputActivityRatio[r,t,f,2,y] > 0
                    fuelcosts[r,t,f,1,y] = sum(Params.InputActivityRatio[r,t,fff,1,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/(Params.OutputActivityRatio[r,t,f,2,y]*sum(Params.TechnologyToStorage[t,s,1,y]^2 for s ∈ Sets.Storage))
                end
            end
        end
        for (t,m) ∈ LoopSetOutput[(r,"Power",y)]
            if Params.OutputActivityRatio[r,t,"Power",m,y] > 0 && maxgeneration[r,t,y,m,"Power"] > 0
                discountedfuelcosts[r,t,"Power",m,y] = (sum((((fuelcosts[r,t,"Power",m,y])*maxgeneration[r,t,y,m,"Power"])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                sum((maxgeneration[r,t,y,m,"Power"]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                levelizedcostsPJ[r,t,"Power",m,y] = capitalcosts[r,t,"Power",m,y]+omcosts[r,t,"Power",m,y]+discountedfuelcosts[r,t,"Power",m,y]+emissioncosts[r,t,"Power",m,y]
            end
        end
        if AnnualProduction[y,"Power",r] > 0
            resourcecosts[r,"Power",y]= sum((levelizedcostsPJ[r,t,"Power",m,y] * AnnualTechnologyProductionByMode[r,t,m,"Power",y]/sum(AnnualTechnologyProductionByMode[r,tt,mm,"Power",y] for tt ∈ Sets.Technology for mm ∈ Sets.Mode_of_operation)) for t ∈ Sets.Technology for m ∈ Sets.Mode_of_operation)
        end
        testcosts[r,"Power3",y] = resourcecosts[r,"Power",y]*3.6
    end end
    #$offtext
    ####
    #### Tier 5: Heat, Transport, Final Tier
    ####

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        for f ∈ Sets.Fuel
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                if Params.OutputActivityRatio[r,t,f,m,y] > 0
                    fuelcosts[r,t,f,m,y] = sum(Params.InputActivityRatio[r,t,fff,m,y]*resourcecosts[r,fff,y] for fff ∈ Sets.Fuel)/Params.OutputActivityRatio[r,t,f,m,y]
                end
            end
        end
        for f ∈ TierFive
            for (t,m) ∈ LoopSetOutput[(r,f,y)]
                if Params.OutputActivityRatio[r,t,f,m,y] > 0 && maxgeneration[r,t,y,m,f] > 0
                    discountedfuelcosts[r,t,f,m,y] = (sum((((fuelcosts[r,t,f,m,y])*maxgeneration[r,t,y,m,f])/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])) /
                    sum((maxgeneration[r,t,y,m,f]/((1+Settings.GeneralDiscountRate[r])^o)) for o ∈ Time if o <= Params.OperationalLife[t])
                    levelizedcostsPJ[r,t,f,m,y] = capitalcosts[r,t,f,m,y]+omcosts[r,t,f,m,y]+discountedfuelcosts[r,t,f,m,y]+emissioncosts[r,t,f,m,y]
                end
            end
        end
        for f ∈ TierFive
            if AnnualProduction[y,f,r] > 0
            resourcecosts[r,f,y]= sum((levelizedcostsPJ[r,t,f,m,y] * AnnualTechnologyProductionByMode[r,t,m,f,y]/sum(AnnualTechnologyProductionByMode[r,tt,mm,f,y] for tt ∈ Sets.Technology for mm ∈ Sets.Mode_of_operation)) for t ∈ Sets.Technology for m ∈ Sets.Mode_of_operation)
            testcosts[r,f,y] = resourcecosts[r,f,y]*3.6
            end
        end
    end end



    #resourcecosts(r,"Gas_Synth",y) = levelizedcostsPJ(r,"X_Methanation","Gas_Synth",1,y)
    #$offtext

    ####
    #### Tier X: Calculate Costs per MWh instead of PJ and prepare Excel Output
    ####

    subset_fuel = [f for f ∈ Sets.Fuel if sum(Params.TagDemandFuelToSector[f,se] for se ∈ setdiff(Sets.Sector,"Power")) == 0]

    fc1 = convert_jump_container_to_df(resourcecosts[:,subset_fuel,:];dim_names=[:Region, :Fuel, :Year])
    fc1[!,:Variable] .= "Fuel Costs in MEUR/PJ"
    fc2 = convert_jump_container_to_df(resourcecosts[:,subset_fuel,:]*3.6;dim_names=[:Region, :Fuel, :Year])
    fc2[!,:Variable] .= "Fuel Costs in EUR/MWh"
    output_fuelcosts = vcat(fc1,fc2)

    for r ∈ Sets.Region_full for y ∈ Sets.Year
        tmp_h2 = resourcecosts[r,"H2",y]*(1+Setting.GeneralDiscountrate[r])^(y-Sets.Year[0])
        tmp_gsynth = resourcecosts[r,"Gas_Synth",y]*(1+Setting.GeneralDiscountrate[r])^(y-Sets.Year[0])
        output_fuelcosts[r,"H2", y, tmp_h2, "Fuel Costs in MEUR/PJ"]
        output_fuelcosts[r,"Gas_Synth", y, tmp_gsynth, "Fuel Costs in MEUR/PJ"]
        for t ∈ Sets.Technology for m ∈ Sets.Mode_of_operation
            for f ∈ setdiff(Sets.Fuel,Params.TagTechnologyToSubsets["Transport"])
                capitalcosts[r,t,f,m,y] = capitalcosts[r,t,f,m,y]*3.6
                omcosts[r,t,f,m,y] = omcosts[r,t,f,m,y]*3.6
                discountedfuelcosts[r,t,f,m,y] = discountedfuelcosts[r,t,f,m,y]*3.6
                emissioncosts[r,t,f,m,y] = emissioncosts[r,t,f,m,y]*3.6
                levelizedcostsPJ[r,t,f,m,y] = levelizedcostsPJ[r,t,f,m,y]*3.6
            end
        end end
    end end
    for y ∈ Sets.Year
        for f ∈ subset_fuel
            if sum(VarPar.ProductionAnnual[y,f,r] for r ∈ Sets.Region_full) > 0
                tmp = sum(resourcecosts[r,f,y]*VarPar.ProductionAnnual[y,f,r] for r ∈ Sets.Region_full)/sum(VarPar.ProductionAnnual[y,f,r] for r ∈ Sets.Region_full)
                push!(output_fuelcosts, ["Total",f,y,tmp,"Fuel Costs in MEUR/PJ"])
            end
            if sum(VarPar.ProductionAnnual[y,f,r] for r ∈ Sets.Region_full) == 0 && sum(resourcecosts[r,f,y] for r ∈ Sets.Region_full) > 0
                tmp = sum(resourcecosts[r,f,y] for r ∈ Sets.Region_full)/length(Sets.Region_full)
                push!(output_fuelcosts, ["Total",f,y,tmp,"Fuel Costs in MEUR/PJ"])
            end
            if sum(VarPar.ProductionAnnual[y,f,r] for r ∈ Sets.Region_full) > 0 || sum(VarPar.ProductionAnnual[y,f,r] for r ∈ Sets.Region_full) == 0 && sum(resourcecosts[r,f,y] for r ∈ Sets.Region_full) > 0
                tmp=output_fuelcosts[(output_fuelcosts.Region .== "Total") .&& (output_fuelcosts.Fuel .== f) .&& (output_fuelcosts.Year .== y) .&& (output_fuelcosts.Variable .== "Fuel Costs in MEUR/PJ"),:Value][1]*3.6
                push!(output_fuelcosts, ["Total",f,y,tmp,"Fuel Costs in EUR/MWh"])
            end
        end
    end

    capex = convert_jump_container_to_df(capitalcosts;dim_names=[:Region, :Technology, :Fuel, :Mode_of_operation, :Year])
    capex[!,:Variable] .= "Capex"
    OEM = convert_jump_container_to_df(omcosts;dim_names=[:Region, :Technology, :Fuel, :Mode_of_operation, :Year])
    OEM[!,:Variable] .= "OandM"
    Fuelcosts = convert_jump_container_to_df(discountedfuelcosts;dim_names=[:Region, :Technology, :Fuel, :Mode_of_operation, :Year])
    Fuelcosts[!,:Variable] .= "Fuelcosts"
    Emissions = convert_jump_container_to_df(emissioncosts;dim_names=[:Region, :Technology, :Fuel, :Mode_of_operation, :Year])
    Emissions[!,:Variable] .= "Emissions"
    TotalLevelized = convert_jump_container_to_df(levelizedcostsPJ;dim_names=[:Region, :Technology, :Fuel, :Mode_of_operation, :Year])
    TotalLevelized[!,:Variable] .= "TotalLevelized"

    output_costs = vcat(capex,OEM,Fuelcosts,Emissions,TotalLevelized)

    output_emissionintensity = convert_jump_container_to_df(EmissionIntensity[:,:,"Power",:];dim_names=[:Year, :Region, :Emission])
    output_emissionintensity[!,:Fuel] .= "Power"
    TotalLevelized[!,:Fuel] .= "Power"


    ####
    #### Excel Output Sheet Definition and Export of GDX
    ####

    CSV.write(joinpath(Switch.resultdir[],"output_costs_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_costs[output_costs.Value .!= 0,:])
    CSV.write(joinpath(Switch.resultdir[],"output_fuelcosts_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_fuelcosts[output_fuelcosts.Value .!= 0,:])
    CSV.write(joinpath(Switch.resultdir[],"output_emissions_$(Switch.model_region)_$(Switch.emissionPathway)_$(Switch.emissionScenario)_$(extr_str).csv"), output_emissionintensity[output_emissionintensity.Value .!= 0,:])

    return resourcecosts, output_emissionintensity
end
