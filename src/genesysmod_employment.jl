function genesysmod_employment(model,Params,Emp_Sets)

    if Switch.switch_endogenous_employment == 0
        output_energyjobs = JuMP.Containers.DenseAxisArray(zeros(length(Emp_Sets.Technology),length(Emp_Sets.Year)), Emp_Sets.Technology, Emp_Sets.Year)

        for i ∈ 2:length(Emp_Sets.Year)-1
            for t ∈ Emp_Sets.Technology
                if Params.EFactorConstruction[t,Emp_Sets.Year[i]] == 0
                    Params.EFactorConstruction[t,Emp_Sets.Year[i]] = (Params.EFactorConstruction[t,Emp_Sets.Year[i-1]]+Params.EFactorConstruction[t,Emp_Sets.Year[i+1]])/2
                end
                if Params.EFactorOM[t,Emp_Sets.Year[i]] == 0
                    Params.EFactorOM[t,Emp_Sets.Year[i]] = (Params.EFactorOM[t,Emp_Sets.Year[i-1]]+Params.EFactorOM[t,Emp_Sets.Year[i+1]])/2
                end
                if Params.EFactorManufacturing[t,Emp_Sets.Year[i]] == 0
                    Params.EFactorManufacturing[t,Emp_Sets.Year[i]] = (Params.EFactorManufacturing[t,Emp_Sets.Year[i-1]]+Params.EFactorManufacturing[t,Emp_Sets.Year[i+1]])/2
                end
                if Params.EFactorFuelSupply[t,Emp_Sets.Year[i]] == 0
                    Params.EFactorFuelSupply[t,Emp_Sets.Year[i]] = (Params.EFactorFuelSupply[t,Emp_Sets.Year[i-1]]+Params.EFactorFuelSupply[t,Emp_Sets.Year[i+1]])/2
                end
                if Params.EFactorCoalJobs[t,Emp_Sets.Year[i]] == 0
                    Params.EFactorCoalJobs[t,Emp_Sets.Year[i]] = (Params.EFactorCoalJobs[t,Emp_Sets.Year[i-1]]+Params.EFactorCoalJobs[t,Emp_Sets.Year[i+1]])/2
                end
                if Params.DeclineRate[t,Emp_Sets.Year[i]] == 0
                    Params.DeclineRate[t,Emp_Sets.Year[i]] = (Params.DeclineRate[t,Emp_Sets.Year[i-1]]+Params.DeclineRate[t,Emp_Sets.Year[i+1]])/2
                end

            end
            for r ∈ Sets.Region_full
                if Params.CoalSupply[r,Emp_Sets.Year[i]] == 0
                    Params.CoalSupply[r,Emp_Sets.Year[i]] = (Params.CoalSupply[r,Emp_Sets.Year[i-1]]+Params.CoalSupply[r,Emp_Sets.Year[i+1]])/2
                end
            end
            if Params.CoalDigging[Switch.model_region,"Coal_Export","$(Switch.emissionPathway)_$(Switch.emissionScenario)",Emp_Sets.Year[i]] == 0
                Params.CoalDigging[Switch.model_region,"Coal_Export","$(Switch.emissionPathway)_$(Switch.emissionScenario)",Emp_Sets.Year[i]] = (Params.CoalDigging[Switch.model_region,"Coal_Export","$(Switch.emissionPathway)_$(Switch.emissionScenario)",Emp_Sets.Year[i-1]]+Params.CoalDigging[Switch.model_region,"Coal_Export","$(Switch.emissionPathway)_$(Switch.emissionScenario)",Emp_Sets.Year[i+1]])/2
            end
            if Params.RegionalAdjustmentFactor[Switch.model_region,Emp_Sets.Year[i]] == 0
                Params.RegionalAdjustmentFactor[Switch.model_region,Emp_Sets.Year[i]] = (Params.RegionalAdjustmentFactor[Switch.model_region,Emp_Sets.Year[i-1]] + Params.RegionalAdjustmentFactor[Switch.model_region,Emp_Sets.Year[i+1]])/2
            end
            if Params.LocalManufacturingFactor[Switch.model_region,Emp_Sets.Year[i]] ==0
                Params.LocalManufacturingFactor[Switch.model_region,Emp_Sets.Year[i]] = (Params.LocalManufacturingFactor[Switch.model_region,Emp_Sets.Year[i-1]] + Params.LocalManufacturingFactor[Switch.model_region,Emp_Sets.Year[i+1]])/2
            end
        end

        for t ∈ Emp_Sets.Technology for y ∈ Emp_Sets.Year
            output_energyjobs[Switch.model_region,t,"ManufacturingJobs","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y] = sum(output_capacity[Switch.model_region,se,t,"NewCapacity","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]*Params.Params.EFactorManufacturing[t,y]*Params.RegionalAdjustmentFactor[Switch.model_region,y]*Params.LocalManufacturingFactor[Switch.model_region,y]*(1-Params.DeclineRate[t,y])^YearlyDifferenceMultiplier(y,Emp_Sets) for se ∈ Sets.Sector)
            output_energyjobs[Switch.model_region,t,"ConstructionJobs","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y] =  sum(output_capacity[Switch.model_region,se,t,"NewCapacity","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]*Params.EFactorConstruction[t,y]*Params.RegionalAdjustmentFactor[Switch.model_region,y]*(1-Params.DeclineRate[t,y])^YearlyDifferenceMultiplier(y,Emp_Sets) for se ∈ Sets.Sector)
            output_energyjobs[Switch.model_region,t,"OMJobs","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y] =  sum(output_capacity[Switch.model_region,se,t,"TotalCapacity","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]*Params.EFactorOM[t,y]*Params.RegionalAdjustmentFactor[Switch.model_region,y]*(1-DeclineRate[t,y])^YearlyDifferenceMultiplier(y,Emp_Sets) for se ∈ Sets.Sector)
            output_energyjobs[Switch.model_region,t,"SupplyJobs","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y] = (sum(sum(output_energy_balance[Switch.model_region,se,t,m,f,l,"Use","PJ","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y] for f ∈ Sets.Fuel for m ∈ Sets.Mode_of_operation for l ∈ Sets.Timeslice)*Params.EFactorFuelSupply[t,y]*(1-Params.DeclineRate[t,y])^YearlyDifferenceMultiplier(y,Emp_Sets) for se ∈ Sets.Sector))*(-1)
        end end
        for r ∈ Sets.Region_full for y in Emp_Sets.Year
            output_energyjobs[r,"Coal_Heat","SupplyJobs","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y] = (sum(sum((output_energy_balance[rr,se,"HLI_Hardcoal",m,"Hardcoal",l,"Use","PJ","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]+output_energy_balance[rr,se,"HMI_HardCoal",m,"Hardcoal",l,"Use","PJ","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]+output_energy_balance[rr,se,"HHI_BF_BOF",m,"Hardcoal",l,"Use","PJ","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]) for m ∈ Sets.Mode_of_operation for l ∈ Sets.Timeslice for se ∈ Sets.Sector ) for rr ∈ Sets.Region_full)*EFactorCoalJobs["Coal_Heat",y]*CoalSupply[r,y])*(-1)
            output_energyjobs[r,"Coal_Export","SupplyJobs","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y] = CoalSupply[r,y]*CoalDigging[Switch.model_region,"Coal_Export","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]*EFactorCoalJobs["Coal_Export",y]
        end end

    end
end
