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
Internal function used in the run process after solving to compute aggregated versions of the rate of activity,
    rate of use and demand, on mode of operation, timeslice and technology.
"""
function genesysmod_variable_parameter(model, Sets, Params)
    RateOfTotalActivity = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Technology), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Region_full)
    RateOfProductionByTechnologyByMode = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Technology), length(Sets.Mode_of_operation), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Mode_of_operation, Sets.Fuel, Sets.Region_full)
    RateOfUseByTechnologyByMode = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Year), length(Sets.Timeslice), length(Sets.Technology), length(Sets.Mode_of_operation), length(Sets.Fuel), length(Sets.Region_full)), Sets.Year, Sets.Timeslice, Sets.Technology, Sets.Mode_of_operation, Sets.Fuel, Sets.Region_full)
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
    TotalStorageCapacity = JuMP.Containers.DenseAxisArray(zeros(length(Sets.Storage), length(Sets.Year), length(Sets.Region_full)), Sets.Storage, Sets.Year, Sets.Region_full)

    LoopSetOutput = Dict()
    LoopSetInput = Dict()
    for y ∈ Sets.Year for f ∈ Sets.Fuel for r ∈ Sets.Region_full
        LoopSetOutput[(r,f,y)] = [(x[1],x[2]) for x in keys(Params.OutputActivityRatio[r,:,f,:,y]) if Params.OutputActivityRatio[r,x[1],f,x[2],y] > 0]
        LoopSetInput[(r,f,y)] = [(x[1],x[2]) for x in keys(Params.InputActivityRatio[r,:,f,:,y]) if Params.InputActivityRatio[r,x[1],f,x[2],y] > 0]
    end end end

    for (i,y) ∈ enumerate(Sets.Year), r ∈ Sets.Region_full
        for s ∈ Sets.Storage
            if i == 1
                TotalStorageCapacity[s,Sets.Year[i],r] = Params.ResidualStorageCapacity[r,s,Sets.Year[i]] + JuMP.value.(model[:NewStorageCapacity][s,Sets.Year[i],r]) 
            else
                TotalStorageCapacity[s,Sets.Year[i],r] = Params.ResidualStorageCapacity[r,s,Sets.Year[i]] 
                TotalStorageCapacity[s,Sets.Year[i],r] += sum(JuMP.value(model[:NewStorageCapacity][s,yy,r]) for yy ∈ Sets.Year if Params.OperationalLifeStorage[s] >= (y - yy) && (y - yy) >= 0) 
            end
        end
        
        for l ∈ Sets.Timeslice
            #for t ∈ Sets.Technology
            #    RateOfTotalActivity[y,l,t,r] = sum(JuMP.value.(model[:RateOfActivity][y,l,t,:,r]))
            #end
            for f ∈ Sets.Fuel
                for (t,m) ∈ LoopSetOutput[(r,f,y)]
                    #RateOfProductionByTechnologyByMode[y,l,t,m,f,r] = JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.OutputActivityRatio[r,t,f,m,y]
                    #RateOfProductionByTechnology[y,l,t,f,r] += JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.OutputActivityRatio[r,t,f,m,y]
                    ProductionByTechnology[y,l,t,f,r] += JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.OutputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y]
                    #CurtailedEnergy[y,f,r,l] += JuMP.value(model[:CurtailedCapacity][r,l,t,y]) * Params.OutputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y] * Params.CapacityToActivityUnit[t]
                end
                #for (t,m) ∈ LoopSetInput[(r,f,y)]
                #    RateOfUseByTechnologyByMode[y,l,t,m,f,r] = JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y]
                #    RateOfUseByTechnology[y,l,t,f,r] += JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y]
                #    UseByTechnology[y,l,t,f,r] += JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.InputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y]*Params.TimeDepEfficiency[r,t,l,y]
                #end
        
                #RateOfProduction[y,l,f,r] = sum(JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.OutputActivityRatio[r,t,f,m,y] for (t,m) ∈ LoopSetOutput[(r,f,y)] )
                RateOfProduction[y,l,f,r] = sum(RateOfProductionByTechnology[y,l,:,f,r])
                #RateOfUse[y,l,f,r] = sum(JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.InputActivityRatio[r,t,f,m,y] for (t,m) ∈ LoopSetInput[(r,f,y)] )
                RateOfUse[y,l,f,r] = sum(RateOfUseByTechnology[y,l,:,f,r])
                #Production[y,l,f,r] = sum(JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.OutputActivityRatio[r,t,f,m,y] for (t,m) ∈ LoopSetOutput[(r,f,y)] )*Params.YearSplit[l,y]
                Production[y,l,f,r] = sum(ProductionByTechnology[y,l,:,f,r])
                #Use[y,l,f,r] = sum(JuMP.value(model[:RateOfActivity][y,l,t,m,r])*Params.InputActivityRatio[r,t,f,m,y] for (t,m) ∈ LoopSetInput[(r,f,y)] )*Params.YearSplit[l,y]
                Use[y,l,f,r] = sum(UseByTechnology[y,l,:,f,r])
            end
        end
        #for f ∈ Sets.Fuel
        #ProductionAnnual[y,f,r] = sum(Production[y,:,f,r])
        #UseAnnual[y,f,r] = sum(Use[y,:,f,r])
        #end
    end 

    #for r ∈ Sets.Region_full
    #    ModelPeriodCostByRegion[r] = sum(JuMP.value.(model[:TotalDiscountedCost][:,r]))
    #end

    VarPar = Variable_Parameters(RateOfTotalActivity, RateOfProductionByTechnologyByMode, RateOfUseByTechnologyByMode, RateOfProductionByTechnology, RateOfUseByTechnology,
    ProductionByTechnology, UseByTechnology, RateOfProduction, RateOfUse, Production, Use, ProductionAnnual, UseAnnual, CurtailedEnergy, ModelPeriodCostByRegion, TotalStorageCapacity)
    return VarPar
end