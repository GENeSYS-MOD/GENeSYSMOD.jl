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
function genesysmod_variable_parameter(model, Sets, Params, Vars, Maps)
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
        LoopSetOutput[(r,f,y)] = [(out_i_labels[i[1]], out_j_labels[i[2]]) for i in findall(x -> x > 0, Array(slice_out))]
        LoopSetInput[(r,f,y)]  = [(in_i_labels[i[1]],  in_j_labels[i[2]])  for i in findall(x -> x > 0, Array(slice_in))]
    end

    for y ∈ Sets.Year for r ∈ Sets.Region_full
        for l ∈ Sets.Timeslice
            for t ∈ Sets.Technology
                RateOfTotalActivity[y,l,t,r] = sum(JuMP.value.(Vars.RateOfActivity[y,l,t,:,r]))
            end
            for f ∈ Sets.Fuel
                for (t,m) ∈ LoopSetOutput[(r,f,y)]
                    RateOfProductionByTechnologyByMode[y,l,t,m,f,r] = JuMP.value(Vars.RateOfActivity[y,l,t,m,r])*Params.OutputActivityRatio[r,t,f,m,y]
                    RateOfProductionByTechnology[y,l,t,f,r] += JuMP.value(Vars.RateOfActivity[y,l,t,m,r])*Params.OutputActivityRatio[r,t,f,m,y]
                    ProductionByTechnology[y,l,t,f,r] += JuMP.value(Vars.RateOfActivity[y,l,t,m,r])*Params.OutputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y]
                    CurtailedEnergy[y,f,r,l] += JuMP.value(Vars.CurtailedCapacity[r,l,t,y]) * Params.OutputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y] * Params.CapacityToActivityUnit[t]
                end
                for (t,m) ∈ LoopSetInput[(r,f,y)]
                    RateOfUseByTechnologyByMode[y,l,t,m,f,r] = JuMP.value(Vars.RateOfActivity[y,l,t,m,r])*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y]
                    RateOfUseByTechnology[y,l,t,f,r] += JuMP.value(Vars.RateOfActivity[y,l,t,m,r])*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y]
                    UseByTechnology[y,l,t,f,r] += JuMP.value(Vars.RateOfActivity[y,l,t,m,r])*Params.InputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y]*Params.TimeDepEfficiency[r,t,l,y]
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
        ModelPeriodCostByRegion[r] = sum(JuMP.value.(Vars.TotalDiscountedCost[:,r]))
    end

    for r ∈ Sets.Region_full, t ∈ Sets.Technology, y ∈ Sets.Year
        CCSByTechnologyAnnual[r, t, y] = sum(
            JuMP.value(Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r])*Params.EmissionContentPerFuel[f,e]*Params.InputActivityRatio[r,t,f,m,y]*YearlyDifferenceMultiplier(y,Sets)* (Params.EmissionActivityRatio[r,t,m,e,y] >= 0 ? 1-Params.EmissionActivityRatio[r,t,m,e,y] : -1 * Params.EmissionActivityRatio[r,t,m,e,y]) for e ∈ Sets.Emission for f ∈ Maps.Tech_Fuel[t] for m ∈ Maps.Tech_MO[t]; init=0)
    end

    VarPar = Variable_Parameters(RateOfTotalActivity, RateOfProductionByTechnologyByMode, RateOfUseByTechnologyByMode, RateOfProductionByTechnology, RateOfUseByTechnology,
    ProductionByTechnology, UseByTechnology, RateOfProduction, RateOfUse, Production, Use, ProductionAnnual, UseAnnual, CurtailedEnergy, ModelPeriodCostByRegion)
    return VarPar
end
