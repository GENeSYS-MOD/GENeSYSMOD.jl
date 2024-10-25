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
# Unless required by applicable law || agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express || implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# #############################################################
"""
Internal function used in the run process to define the model constraints.
"""
function genesysmod_equ(model,Sets,Params, Vars,Emp_Sets,Settings,Switch, Maps)

  dbr = Switch.data_base_region
  𝓡 = Sets.Region_full
  𝓕 = Sets.Fuel
  𝓨 = Sets.Year
  𝓣 = Sets.Technology
  𝓔 = Sets.Emission
  𝓜 = Sets.Mode_of_operation
  𝓛 = Sets.Timeslice
  𝓢 = Sets.Storage
  𝓜𝓽 = Sets.ModalType
  𝓢𝓮 = Sets.Sector

  ######################
  # Objective Function #
  ######################

  start=Dates.now()

  @objective(model, MOI.MIN_SENSE, sum(Vars.TotalDiscountedCost[y,r] for y ∈ 𝓨 for r ∈ 𝓡)
  + sum(Vars.DiscountedAnnualTotalTradeCosts[y,r] for y ∈ 𝓨 for r ∈ 𝓡)
  + sum(Vars.DiscountedNewTradeCapacityCosts[y,f,r,rr] for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡 for rr ∈ 𝓡)
  + sum(Vars.DiscountedAnnualCurtailmentCost[y,f,r] for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡)
  + sum(Vars.BaseYearBounds_TooHigh[y,r,t,f]*9999 for y ∈ 𝓨 for r ∈ 𝓡 for t ∈ 𝓣 for f ∈ 𝓕)
  + sum(Vars.BaseYearBounds_TooLow[r,t,f,y]*9999 for y ∈ 𝓨 for r ∈ 𝓡 for t ∈ 𝓣 for f ∈ 𝓕)
  - sum(Vars.DiscountedSalvageValueTransmission[y,r] for y ∈ 𝓨 for r ∈ 𝓡))
  print("Cstr: Cost : ",Dates.now()-start,"\n")
  

  #########################
  # Parameter assignments #
  #########################

  start=Dates.now()

  LoopSetOutput = Dict()
  LoopSetInput = Dict()
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    LoopSetOutput[(r,f,y)] = [(x[1],x[2]) for x in keys(Params.OutputActivityRatio[r,:,f,:,y]) if Params.OutputActivityRatio[r,x[1],f,x[2],y] > 0]
    LoopSetInput[(r,f,y)] = [(x[1],x[2]) for x in keys(Params.InputActivityRatio[r,:,f,:,y]) if Params.InputActivityRatio[r,x[1],f,x[2],y] > 0]
  end end end

  function CanFuelBeUsedByModeByTech(y, f, r,t,m)
    temp = Params.InputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛) *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y]
    if (!ismissing(temp)) && (temp > 0)
      return 1
    else
      return 0
    end
  end

  function CanFuelBeUsedByTech(y, f, r,t)
    temp = sum(Params.InputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛) *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] for m ∈ 𝓜 )
    if (!ismissing(temp)) && (temp > 0)
      return 1
    else
      return 0
    end
  end

  function CanFuelBeUsed(y, f, r)
    temp = sum(Params.InputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛) *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] for m ∈ 𝓜 for t ∈ 𝓣)
    if (!ismissing(temp)) && (temp > 0)
      return 1
    else
      return 0
    end
  end

  function CanFuelBeUsedInTimeslice(y, l, f, r)
    temp = sum(Params.InputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    Params.CapacityFactor[r,t,l,y] *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] for m ∈ 𝓜 for t ∈ 𝓣)
    if (!ismissing(temp)) && (temp > 0)
      return 1
    else
      return 0
    end
  end

  CanFuelBeUsedOrDemanded = JuMP.Containers.DenseAxisArray(zeros(length(𝓨), length(𝓕), length(𝓡)), 𝓨, 𝓕, 𝓡)
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    temp = (isempty(LoopSetInput[(r,f,y)]) ? 0 : sum(Params.InputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛) *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] for (t,m) ∈ LoopSetInput[(r,f,y)]))
    if (!ismissing(temp)) && (temp > 0) || Params.SpecifiedAnnualDemand[r,f,y] > 0
      CanFuelBeUsedOrDemanded[y,f,r] = 1
    end
  end end end 

  function CanFuelBeProducedByTech(y, f, r,t)
    temp = sum(Params.OutputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛) *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] for m ∈ 𝓜)
    if (!ismissing(temp)) && (temp > 0)
      return 1
    else
      return 0
    end
  end

  function CanFuelBeProducedByModeByTech(y, f, r,t,m)
    temp = Params.OutputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛) *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y]
    if (!ismissing(temp)) && (temp > 0)
      return 1
    else
      return 0
    end
  end


  CanFuelBeProduced = JuMP.Containers.DenseAxisArray(zeros(length(𝓨), length(𝓕), length(𝓡)), 𝓨, 𝓕, 𝓡)
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    temp = (isempty(LoopSetOutput[(r,f,y)]) ? 0 : sum(Params.OutputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛) *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] for (t,m) ∈ LoopSetOutput[(r,f,y)]))
    if (temp > 0)
      CanFuelBeProduced[y,f,r] = 1
    end
  end end end

  function CanFuelBeProducedInTimeslice(y, l, f, r)
    temp = sum(Params.OutputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] * 
    Params.CapacityFactor[r,t,l,y] *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] for m ∈ 𝓜 for t ∈ 𝓣)
    if (!ismissing(temp)) && (temp > 0)
      return 1
    else
      return 0
    end
  end

  #TagTimeIndependentFuel = JuMP.Containers.DenseAxisArray(zeros(length(𝓨), length(𝓕), length(𝓡)), 𝓨, 𝓕, 𝓡)
  TagTimeIndependentFuel = CanFuelBeUsedOrDemanded.*(1 .- CanFuelBeProduced)
  Info = "reduced"
  if Info == "reduced"
    TagTimeIndependentFuel[:,"Lignite",:] .= 1
    TagTimeIndependentFuel[:,"Biomass",:] .= 1
    TagTimeIndependentFuel[:,"Area_Rooftop_Residential",:] .= 1
    TagTimeIndependentFuel[:,"Area_Rooftop_Commercial",:] .= 1
    TagTimeIndependentFuel[:,"Hardcoal",:] .= 1
    TagTimeIndependentFuel[:,"Nuclear",:] .= 1
    TagTimeIndependentFuel[:,"Oil",:] .= 1
    TagTimeIndependentFuel[:,"Air",:] .= 1
    TagTimeIndependentFuel[:,"DAC_Dummy",:] .= 1
    TagTimeIndependentFuel[:,"ETS",:] .= 1
    TagTimeIndependentFuel[:,"ETS_Source",:] .= 1
  elseif Info == "reduced2"
    TagTimeIndependentFuel[:,"Lignite",:] .= 1
    TagTimeIndependentFuel[:,"Biomass",:] .= 1
    TagTimeIndependentFuel[:,"Area_Rooftop_Residential",:] .= 1
    TagTimeIndependentFuel[:,"Area_Rooftop_Commercial",:] .= 1
    TagTimeIndependentFuel[:,"Hardcoal",:] .= 1
    TagTimeIndependentFuel[:,"Nuclear",:] .= 1
    TagTimeIndependentFuel[:,"Oil",:] .= 1
    TagTimeIndependentFuel[:,"Air",:] .= 1
    TagTimeIndependentFuel[:,"DAC_Dummy",:] .= 1
    TagTimeIndependentFuel[:,"ETS",:] .= 1
    TagTimeIndependentFuel[:,"ETS_Source",:] .= 1
    TagTimeIndependentFuel[:,"LNG",:] .= 1
    TagTimeIndependentFuel[:,"LBG",:] .= 1
  end

  IgnoreFuel = JuMP.Containers.DenseAxisArray(zeros(length(𝓨), length(𝓕), length(𝓡)), 𝓨, 𝓕, 𝓡)
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    if CanFuelBeUsedOrDemanded[y,f,r] == 1 && CanFuelBeProduced[y,f,r] == 0
      IgnoreFuel[y,f,r] = 1
    end
  end end end

  function PureDemandFuel(y, f, r);
    if CanFuelBeUsed(y,f,r) == 0 && Params.SpecifiedAnnualDemand[r,f,y] > 0
      return 1
    else
      return 0
    end
  end
  print("IgnoreFuel : ",Dates.now()-start,"\n")

  ###############
  # Constraints #
  ###############

  
  ############### Capacity Adequacy A #############
  
  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for  r ∈ 𝓡
    cond= (any(x->x>0,[Params.TotalAnnualMaxCapacity[r,t,yy] for yy ∈ 𝓨 if (y - yy < Params.OperationalLife[t]) && (y-yy>= 0)])) && (Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0)
    if cond
      @constraint(model, Vars.AccumulatedNewCapacity[y,t,r] == sum(Vars.NewCapacity[yy,t,r] for yy ∈ 𝓨 if (y - yy < Params.OperationalLife[t]) && (y-yy>= 0)), base_name="CA1_TotalNewCapacity|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.AccumulatedNewCapacity[y,t,r], 0; force=true)
    end
    if cond || (Params.ResidualCapacity[r,t,y]) > 0
      @constraint(model, Vars.AccumulatedNewCapacity[y,t,r] + Params.ResidualCapacity[r,t,y] == Vars.TotalCapacityAnnual[y,t,r], base_name="CA2_TotalAnnualCapacity|$(y)|$(t)|$(r)")
    elseif !cond && (Params.ResidualCapacity[r,t,y]) == 0
      JuMP.fix(Vars.TotalCapacityAnnual[y,t,r],0; force=true)
    end
  end end end

  print("Cstr: Cap Adequacy A1 : ",Dates.now()-start,"\n")

  CanBuildTechnology = JuMP.Containers.DenseAxisArray(zeros(length(𝓨), length(𝓣), length(𝓡)), 𝓨, 𝓣, 𝓡)
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    temp=  (Params.TotalAnnualMaxCapacity[r,t,y] *
    sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛) *
    Params.AvailabilityFactor[r,t,y] * 
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] * 
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y])
    if (temp > 0) && ((!JuMP.is_fixed(Vars.TotalCapacityAnnual[y,t,r]) && !JuMP.has_upper_bound(Vars.TotalCapacityAnnual[y,t,r])) || (JuMP.is_fixed(Vars.TotalCapacityAnnual[y,t,r]) && (JuMP.fix_value(Vars.TotalCapacityAnnual[y,t,r]) > 0)) || (JuMP.has_upper_bound(Vars.TotalCapacityAnnual[y,t,r]) && (JuMP.upper_bound(Vars.TotalCapacityAnnual[y,t,r]) > 0)))
      CanBuildTechnology[y,t,r] = 1
    end
  end end end

  start=Dates.now()
  for y ∈ 𝓨, t ∈ 𝓣, r ∈ 𝓡, m ∈ Maps.Tech_MO[t]
    if (Params.AvailabilityFactor[r,t,y] == 0) ||
      (Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] == 0) ||
      (Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] == 0) ||
      (Params.TotalAnnualMaxCapacity[r,t,y] == 0) ||
      ((JuMP.has_upper_bound(Vars.TotalCapacityAnnual[y,t,r])) && (JuMP.upper_bound(Vars.TotalCapacityAnnual[y,t,r]) == 0)) ||
      ((JuMP.is_fixed(Vars.TotalCapacityAnnual[y,t,r])) && (JuMP.fix_value(Vars.TotalCapacityAnnual[y,t,r]) == 0)) ||
      (sum(Params.OutputActivityRatio[r,t,f,m,y] for f ∈ 𝓕) == 0 && sum(Params.InputActivityRatio[r,t,f,m,y] for f ∈ 𝓕) == 0)
        JuMP.fix.(Vars.RateOfActivity[y,:,t,m,r], 0; force=true)
    else
      for l ∈ 𝓛
        if Params.CapacityFactor[r,t,l,y] == 0
          JuMP.fix(Vars.RateOfActivity[y,l,t,m,r], 0; force=true)
        end
      end
    end
  end
  print("Cstr: Cap Adequacy A2 : ",Dates.now()-start,"\n")

  start=Dates.now()
  if Switch.switch_intertemporal == 1
    for r ∈ 𝓡 for l ∈ 𝓛 for t ∈ 𝓣 for y ∈ 𝓨
      if Params.CapacityFactor[r,t,l,y] > 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
        @constraint(model,
        sum(Vars.RateOfActivity[y,l,t,m,r] for m ∈ Maps.Tech_MO[t]) == Vars.TotalActivityPerYear[r,l,t,y]*Params.AvailabilityFactor[r,t,y] - Vars.DispatchDummy[r,l,t,y]*Params.TagDispatchableTechnology[t]- Vars.CurtailedCapacity[r,l,t,y]*Params.CapacityToActivityUnit[t],
        base_name="CA3a_RateOfTotalActivity_Intertemporal|$(r)|$(l)|$(t)|$(y)")
      end
      if (sum(Params.CapacityFactor[r,t,l,yy] for yy ∈ 𝓨 if y-yy < Params.OperationalLife[t] && y-yy >= 0) > 0 || Params.CapacityFactor[r,t,l,Switch.StartYear] > 0) && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0
        @constraint(model,
        Vars.TotalActivityPerYear[r,l,t,y] == sum(Vars.NewCapacity[yy,t,r] * Params.CapacityFactor[r,t,l,yy] * Params.CapacityToActivityUnit[t] for yy ∈ 𝓨 if y-yy < Params.OperationalLife[t] && y-yy >= 0)+(Params.ResidualCapacity[r,t,y]*Params.CapacityFactor[r,t,l,Switch.StartYear] * Params.CapacityToActivityUnit[t]),
        base_name="CA4_TotalActivityPerYear_Intertemporal|$(r)|$(l)|$(t)|$(y)")
      end
    end end end end

  else
    for y ∈ 𝓨, t ∈ 𝓣, r ∈ 𝓡, l ∈ 𝓛
      if (Params.CapacityFactor[r,t,l,y] > 0) &&
        (Params.AvailabilityFactor[r,t,y] > 0) &&
        (Params.TotalAnnualMaxCapacity[r,t,y] > 0) &&
        (Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0)
        @constraint(model, 
        sum(Vars.RateOfActivity[y,l,t,m,r] for m ∈ Maps.Tech_MO[t]) == Vars.TotalCapacityAnnual[y,t,r] * Params.CapacityFactor[r,t,l,y] * Params.CapacityToActivityUnit[t] * Params.AvailabilityFactor[r,t,y] - Vars.DispatchDummy[r,l,t,y] * Params.TagDispatchableTechnology[t] - Vars.CurtailedCapacity[r,l,t,y] * Params.CapacityToActivityUnit[t],
        base_name="CA3b_RateOfTotalActivity|$(r)|$(l)|$(t)|$(y)")
      end
    end
  end

  for y ∈ 𝓨 for t ∈ 𝓣 for  r ∈ 𝓡 for l ∈ 𝓛
    @constraint(model, model[:TotalCapacityAnnual][y,t,r] >= model[:CurtailedCapacity][r,l,t,y], base_name="CA3c_CurtailedCapacity|$(r)|$(l)|$(t)|$(y)")
  end end end end
  print("Cstr: Cap Adequacy A3 : ",Dates.now()-start,"\n")

   
  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for  r ∈ 𝓡
    if (Params.AvailabilityFactor[r,t,y] < 1) &&
      (Params.TotalAnnualMaxCapacity[r,t,y] > 0) &&
      (Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0) &&
      (((JuMP.has_upper_bound(Vars.TotalCapacityAnnual[y,t,r])) && (JuMP.upper_bound(Vars.TotalCapacityAnnual[y,t,r]) > 0)) ||
      ((!JuMP.has_upper_bound(Vars.TotalCapacityAnnual[y,t,r])) && (!JuMP.is_fixed(Vars.TotalCapacityAnnual[y,t,r]))) ||
      ((JuMP.is_fixed(Vars.TotalCapacityAnnual[y,t,r])) && (JuMP.fix_value(Vars.TotalCapacityAnnual[y,t,r]) > 0)))
      @constraint(model, sum(sum(Vars.RateOfActivity[y,l,t,m,r]  for m ∈ Maps.Tech_MO[t]) * Params.YearSplit[l,y] for l ∈ 𝓛) <= sum(Vars.TotalCapacityAnnual[y,t,r]*Params.CapacityFactor[r,t,l,y]*Params.YearSplit[l,y]*Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t] for l ∈ 𝓛), base_name="CA5_CapacityAdequacy|$(y)|$(t)|$(r)")
    end
  end end end
  print("Cstr: Cap Adequacy B : ",Dates.now()-start,"\n")
  
  ############### Energy Balance A #############
  
  start=Dates.now()
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    for rr ∈ 𝓡
      if Params.TradeRoute[r,rr,f,y] > 0
        for l ∈ 𝓛
          @constraint(model, Vars.Import[y,l,f,r,rr] == Vars.Export[y,l,f,rr,r], base_name="EB1_TradeBalanceEachTS|$(y)|$(l)|$(f)|$(r)|$(rr)")
        end
      else
        for l ∈ 𝓛
          JuMP.fix(Vars.Import[y,l,f,r,rr], 0; force=true)
          JuMP.fix(Vars.Export[y,l,f,rr,r], 0; force=true)
        end
      end
    end

    if sum(Params.TradeRoute[r,rr,f,y] for rr ∈ 𝓡) == 0
      JuMP.fix.(Vars.NetTrade[y,:,f,r], 0; force=true)
    else
      for l ∈ 𝓛
        @constraint(model, sum(Vars.Export[y,l,f,r,rr]*(1+Params.TradeLossBetweenRegions[r,rr,f,y]) - Vars.Import[y,l,f,r,rr] for rr ∈ 𝓡 if Params.TradeRoute[r,rr,f,y] > 0) == Vars.NetTrade[y,l,f,r], 
        base_name="EB4_NetTradeBalance|$(y)|$(l)|$(f)|$(r)")
      end
    end

    if TagTimeIndependentFuel[y,f,r] == 0
      for l ∈ 𝓛
        @constraint(model,sum(Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] for (t,m) ∈ LoopSetOutput[(r,f,y)])* Params.YearSplit[l,y] ==
       (Params.Demand[y,l,f,r] + sum(Vars.RateOfActivity[y,l,t,m,r]*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y] for (t,m) ∈ LoopSetInput[(r,f,y)])*Params.YearSplit[l,y] + Vars.NetTrade[y,l,f,r]),
        base_name="EB2_EnergyBalanceEachTS|$(y)|$(l)|$(f)|$(r)")
      end
    end
  end end end

  print("Cstr: Energy Balance A1 : ",Dates.now()-start,"\n")
  start=Dates.now()
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    @constraint(model, Vars.CurtailedEnergyAnnual[y,f,r] == sum(Vars.CurtailedCapacity[r,l,t,y] * Params.OutputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y] * Params.CapacityToActivityUnit[t] for l ∈ 𝓛 for (t,m) ∈ LoopSetOutput[(r,f,y)]), 
    base_name="EB6_AnnualEnergyCurtailment|$(y)|$(f)|$(r)")

    if Params.SelfSufficiency[y,f,r] != 0
      @constraint(model, sum(Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y]*Params.YearSplit[l,y] for l ∈ 𝓛 for (t,m) ∈ LoopSetOutput[(r,f,y)]) == (Params.SpecifiedAnnualDemand[r,f,y] + sum(Vars.RateOfActivity[y,l,t,m,r]*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y]*Params.YearSplit[l,y] for l ∈ 𝓛 for (t,m) ∈ LoopSetInput[(r,f,y)]))*Params.SelfSufficiency[y,f,r], base_name="EB7_AnnualSelfSufficiency|$(y)|$(f)|$(r)")
    end
  end end end 
  print("Cstr: Energy Balance A2 : ",Dates.now()-start,"\n")

  ############### Energy Balance B #############
  
  start=Dates.now()
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    if sum(Params.TradeRoute[r,rr,f,y] for rr ∈ 𝓡) > 0
      @constraint(model, sum(Vars.NetTrade[y,l,f,r] for l ∈ 𝓛) == Vars.NetTradeAnnual[y,f,r], base_name="EB5_AnnualNetTradeBalance|$(y)|$(f)|$(r)")
    else
      JuMP.fix(Vars.NetTradeAnnual[y,f,r],0; force=true)
    end
    
    if TagTimeIndependentFuel[y,f,r] != 0
      @constraint(model, sum(Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y]*Params.YearSplit[l,y] for l ∈ 𝓛 for (t,m) ∈ LoopSetOutput[(r,f,y)]) >= 
      sum( Vars.RateOfActivity[y,l,t,m,r]*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y]*Params.YearSplit[l,y] for l ∈ 𝓛 for (t,m) ∈ LoopSetInput[(r,f,y)]) + Vars.NetTradeAnnual[y,f,r], 
      base_name="EB3_EnergyBalanceEachYear|$(y)|$(f)|$(r)")
    end
  end end end
  print("Cstr: Energy Balance B : ",Dates.now()-start,"\n")

  
 
  ############### Trade Capacities & Investments #############
  
  for i ∈ eachindex(𝓨) for r ∈ 𝓡 for rr ∈ 𝓡
    if Params.TradeRoute[r,rr,"Power",𝓨[i]] > 0
      for l ∈ 𝓛
        @constraint(model, (model[:Import][𝓨[i],l,"Power",r,rr]) <= model[:TotalTradeCapacity][𝓨[i],"Power",rr,r]*Params.YearSplit[l,𝓨[i]]*31.536 , base_name="TrC1_TradeCapacityPowerLinesImport|$(𝓨[i])|$(l)_Power|$(r)|$(rr)")
      end
      for f ∈ 𝓕
        if Params.TradeCapacityGrowthCosts[r,rr,f] != 0
          @constraint(model, Vars.NewTradeCapacity[𝓨[i],f,r,rr]*Params.TradeCapacityGrowthCosts[r,rr,f]*Params.TradeRoute[r,rr,f,𝓨[i]] == Vars.NewTradeCapacityCosts[𝓨[i],f,r,rr], base_name="TrC4_NewTradeCapacityCosts|$(𝓨[i])|$(f)|$(r)|$(rr)")
          @constraint(model, Vars.NewTradeCapacityCosts[𝓨[i],f,r,rr]/((1+Settings.GeneralDiscountRate[r])^(𝓨[i]-Switch.StartYear+0.5)) == Vars.DiscountedNewTradeCapacityCosts[𝓨[i],f,r,rr], base_name="TrC5_DiscountedNewTradeCapacityCosts|$(𝓨[i])|$(f)|$(r)|$(rr)")
        end
      end
    end
    for f ∈ 𝓕
      if Params.TradeRoute[r,rr,f,𝓨[i]] == 0 || Params.TradeCapacityGrowthCosts[r,rr,f] == 0
        JuMP.fix(Vars.DiscountedNewTradeCapacityCosts[𝓨[i],f,r,rr],0; force=true)
      end
    end

    if Switch.switch_dispatch == 0
      for f ∈ 𝓕
        if Params.TradeRoute[r,rr,f,𝓨[i]] > 0
          if 𝓨[i] == Switch.StartYear
            @constraint(model, Vars.TotalTradeCapacity[𝓨[i],f,r,rr] == Params.TradeCapacity[r,rr,f,𝓨[i]], base_name="TrC2a_TotalTradeCapacityStartYear|$(𝓨[i])|$(f)|$(r)|$(rr)")
          elseif 𝓨[i] > Switch.StartYear
            @constraint(model, Vars.TotalTradeCapacity[𝓨[i],f,r,rr] == Vars.TotalTradeCapacity[𝓨[i-1],f,r,rr] + Vars.NewTradeCapacity[𝓨[i],f,r,rr] + Params.CommissionedTradeCapacity[r,rr,f,𝓨[i]], 
            base_name="TrC2b_TotalTradeCapacity|$(𝓨[i])|$(f)|$(r)|$(rr)")
          end

          if f == "Power" && i > 1 && Params.GrowthRateTradeCapacity[r,rr,f,𝓨[i]] > 0 
            @constraint(model, (Params.GrowthRateTradeCapacity[r,rr,f,𝓨[i]]*YearlyDifferenceMultiplier(𝓨[i],Sets))*Vars.TotalTradeCapacity[𝓨[i-1],f,r,rr] >= Vars.NewTradeCapacity[𝓨[i],f,r,rr], 
            base_name="TrC3_NewTradeCapacityLimitPowerLines|$(𝓨[i])|Power|$(r)|$(rr)")
          end
        end
      end
    end

    ### Trade Capacities for H2 and Natural Gas, when initially no capacities existed, so that the model has the ability to build additional capacities

    if Params.TradeRoute[r,rr,"Gas_Natural",𝓨[i]] > 0 && Params.GrowthRateTradeCapacity[r,rr,"Gas_Natural",𝓨[i]] > 0
      @constraint(model, (Params.TradeCapacity[r,"Gas_Natural",𝓨[i],rr] == 0 ? 100 : 0)+(Params.GrowthRateTradeCapacity[r,rr,"Gas_Natural",𝓨[i]]*YearlyDifferenceMultiplier(𝓨[i],Sets))*Vars.TotalTradeCapacity[𝓨[i-1],"Gas_Natural",r,rr] >= Vars.NewTradeCapacity[𝓨[i],"Gas_Natural",r,rr],
      base_name="TrC4a_NewTradeCapacityLimitNatGas|$(𝓨[i])|Gas_Natural|$(r)|$(rr)")
    end
    if Params.TradeRoute[r,rr,"H2",𝓨[i]] > 0 && Params.GrowthRateTradeCapacity[r,rr,"H2",𝓨[i]] > 0
      @constraint(model, (Params.TradeCapacity[r,"H2",𝓨[i],rr] == 0 ? 50 : 0)+(Params.GrowthRateTradeCapacity[r,rr,"H2",𝓨[i]]*YearlyDifferenceMultiplier(𝓨[i],Sets))*Vars.TotalTradeCapacity[𝓨[i-1],"H2",r,rr] >= Vars.NewTradeCapacity[𝓨[i],"H2",r,rr],
      base_name="TrC5a_NewTradeCapacityLimitH2|$(𝓨[i])|H2|$(r)|$(rr)")
    end
    for f ∈ 𝓕
      if Params.TradeRoute[r,rr,f,𝓨[i]] == 0
        JuMP.fix(Vars.NewTradeCapacity[𝓨[i],f,r,rr],0; force=true)
      end
      if Params.TradeCapacityGrowthCosts[r,rr,f] > 0 && f != "Power"
        @constraint(model, sum(Vars.Import[𝓨[i],l,f,rr,r] for l ∈ 𝓛) <= Vars.TotalTradeCapacity[𝓨[i],f,r,rr],
        base_name="TrC7_TradeCapacityLimitNonPower$(𝓨[i])|$(f)|$(r)|$(rr)")
      end
    end

    if Params.TradeRoute[r,rr,"Power",𝓨[i]] > 0
      @constraint(model, Vars.NewTradeCapacity[𝓨[i],"Power",r,rr] >= Vars.NewTradeCapacity[𝓨[i],"Power",rr,r] * Switch.set_symmetric_transmission,
      base_name="TrC6_SymmetricalTransmissionExpansion|$(𝓨[i])|$(r)|$(rr)")
    end

    if Params.TradeRoute[r,rr,"Power",𝓨[i]] == 0 || Params.GrowthRateTradeCapacity[r,rr,"Power",𝓨[i]] == 0
      JuMP.fix(Vars.NewTradeCapacity[𝓨[i],"Power",r,rr],0; force=true)
    end

#=     for f ∈ 𝓕
      if f != "Power" 
        JuMP.fix(Vars.NewTradeCapacity[𝓨[i],f,r,rr],0; force=true)
      end
      if Params.TradeRoute[r,rr,f,𝓨[i]] == 0 || f != "Power"
        JuMP.fix(Vars.DiscountedNewTradeCapacityCosts[𝓨[i],f,r,rr],0; force=true)
      end
    end =#
  end end end 


  ##############* Pipeline-specific Capacity Accounting #############

  #$ifthen.equ_hydrogen_tradecapacity %switch_hydrogen_blending_share% == 0
  for y ∈ 𝓨 for l ∈ 𝓛 for r ∈ 𝓡 for rr ∈ 𝓡
    @constraint(model, sum(Vars.Import[y,l,f,rr,r] for f ∈ setdiff(intersect(𝓕,Params.TagFuelToSubsets["GasFuels"]),["H2"])) <= Vars.TotalTradeCapacity[y,"Gas_Natural",r,rr]*Params.YearSplit[l,y],
    base_name="TrPA1a_TradeCapacityPipelineAccounting|$(y)|$(l)|$(r)|$(rr)")
  end end end end
  #$else.equ_hydrogen_tradecapacity
  #scalar dedicated_h2;
  #dedicated_h2 = %switch_hydrogen_blending_share%;
  #
  #
  #equation TrPA1b_TradeCapacityPipelineAccountingGasFuels(YEAR_FULL,TIMESLICE_FULL,REGION_FULL,rr_full);
  #TrPA1b_TradeCapacityPipelineAccountingGasFuels(y,l,r,rr)$(%switch_hydrogen_blending_share%>0 and %switch_hydrogen_blending_share%<1).. sum(GasFuels$(not sameas(GasFuels,'H2_blend')), Import(y,l,GasFuels,rr,r)) + Import(y,l,'H2_blend',rr,r)*(11.4/3.0) =l= TotalTradeCapacity(y,'gas_natural',r,rr)*YearSplit(l,y);
  #equation TrPA1c_TradeCapacityPipelineAccountingH2Blend(YEAR_FULL,TIMESLICE_FULL,REGION_FULL,rr_full);
  #TrPl1c_TradeCapacityPipelinesLines(y,l,r,rr)$(%switch_hydrogen_blending_share%>0 and %switch_hydrogen_blending_share%<1).. Import(y,l,'H2_blend',rr,r) =l= (%switch_hydrogen_blending_share%/((1-%switch_hydrogen_blending_share%)*(11.4/3.0))) * sum(GasFuels$(not sameas(GasFuels,'H2_blend')), Import(y,l,GasFuels,rr,r));
  #
  #equation TrPA1d_TradeCapacityPipelineAccountingCombined(YEAR_FULL,TIMESLICE_FULL,REGION_FULL,rr_full);
  #TrPA1d_TradeCapacityPipelineAccountingCombined(y,l,r,rr)$(%switch_hydrogen_blending_share% = 1).. sum(GasFuels$(not sameas(GasFuels,'H2_blend')), Import(y,l,GasFuels,rr,r)) + Import(y,l,'H2_blend',rr,r)*(11.4/3.0) =l= TotalTradeCapacity(y,'gas_natural',r,rr)*YearSplit(l,y);
  #
  #$endif.equ_hydrogen_tradecapacity

  ############### Trading Costs #############

  for y ∈ 𝓨 for r ∈ 𝓡
    if sum(Params.TradeRoute[r,rr,f,y] for f ∈ 𝓕 for rr ∈ 𝓡) > 0
      @constraint(model, sum(Vars.Import[y,l,f,r,rr] * Params.TradeCosts[f,r,rr] for f ∈ 𝓕 for rr ∈ 𝓡 for l ∈ 𝓛 if Params.TradeRoute[r,rr,f,y] > 0) == Vars.AnnualTotalTradeCosts[y,r], base_name="TC1_AnnualTradeCosts|$(y)|$(r)")
    else
      JuMP.fix(Vars.AnnualTotalTradeCosts[y,r], 0; force=true)
    end
    @constraint(model, Vars.AnnualTotalTradeCosts[y,r]/((1+Settings.GeneralDiscountRate[r])^(y-Switch.StartYear+0.5)) == Vars.DiscountedAnnualTotalTradeCosts[y,r], base_name="TC2_DiscountedAnnualTradeCosts|$(y)|$(r)")
  end end 
  
  ############### Accounting Technology Production/Use #############
  
  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for  r ∈ 𝓡 for m ∈ Maps.Tech_MO[t]
    if CanBuildTechnology[y,t,r] > 0
      @constraint(model, sum(Vars.RateOfActivity[y,l,t,m,r]*Params.YearSplit[l,y] for l ∈ 𝓛) == Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r], base_name="ACC1_ComputeTotalAnnualRateOfActivity|$(y)|$(t)|$(m)|$(r)")
    else
      JuMP.fix(Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r],0; force=true)
    end
  end end end end 

  for i ∈ eachindex(𝓨) for f ∈ 𝓕 for r ∈ 𝓡
    for t ∈ Maps.Fuel_Tech[f] 
      if sum(Params.OutputActivityRatio[r,t,f,m,𝓨[i]] for m ∈ 𝓜) > 0 &&
        Params.AvailabilityFactor[r,t,𝓨[i]] > 0 &&
        Params.TotalAnnualMaxCapacity[r,t,𝓨[i]] > 0 &&
        Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0 &&
        (((JuMP.has_upper_bound(Vars.TotalCapacityAnnual[𝓨[i],t,r])) && (JuMP.upper_bound(Vars.TotalCapacityAnnual[𝓨[i],t,r]) > 0)) ||
        ((!JuMP.has_upper_bound(Vars.TotalCapacityAnnual[𝓨[i],t,r])) && (!JuMP.is_fixed(Vars.TotalCapacityAnnual[𝓨[i],t,r]))) ||
        ((JuMP.is_fixed(Vars.TotalCapacityAnnual[𝓨[i],t,r])) && (JuMP.fix_value(Vars.TotalCapacityAnnual[𝓨[i],t,r]) > 0)))
        @constraint(model, sum(sum(Vars.RateOfActivity[𝓨[i],l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,𝓨[i]] for m ∈ Maps.Tech_MO[t] if Params.OutputActivityRatio[r,t,f,m,𝓨[i]] != 0)* Params.YearSplit[l,𝓨[i]] for l ∈ 𝓛) == Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r], base_name= "ACC2_FuelProductionByTechnologyAnnual|$(𝓨[i])|$(t)|$(f)|$(r)")
      else
        JuMP.fix(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r],0;force=true)
      end

      if sum(Params.InputActivityRatio[r,t,f,m,𝓨[i]] for m ∈ 𝓜) > 0 &&
        Params.AvailabilityFactor[r,t,𝓨[i]] > 0 &&
        Params.TotalAnnualMaxCapacity[r,t,𝓨[i]] > 0 &&
        Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0 &&
        (((JuMP.has_upper_bound(Vars.TotalCapacityAnnual[𝓨[i],t,r])) && (JuMP.upper_bound(Vars.TotalCapacityAnnual[𝓨[i],t,r]) > 0)) ||
        ((!JuMP.has_upper_bound(Vars.TotalCapacityAnnual[𝓨[i],t,r])) && (!JuMP.is_fixed(Vars.TotalCapacityAnnual[𝓨[i],t,r]))) ||
        ((JuMP.is_fixed(Vars.TotalCapacityAnnual[𝓨[i],t,r])) && (JuMP.fix_value(Vars.TotalCapacityAnnual[𝓨[i],t,r]) > 0)))
        @constraint(model, sum(sum(Vars.RateOfActivity[𝓨[i],l,t,m,r]*Params.InputActivityRatio[r,t,f,m,𝓨[i]] for m ∈ Maps.Tech_MO[t] if Params.InputActivityRatio[r,t,f,m,𝓨[i]] != 0)* Params.YearSplit[l,𝓨[i]] for l ∈ 𝓛) == Vars.UseByTechnologyAnnual[𝓨[i],t,f,r], base_name= "ACC3_FuelUseByTechnologyAnnual|$(𝓨[i])|$(t)|$(f)|$(r)")
      else
        JuMP.fix(Vars.UseByTechnologyAnnual[𝓨[i],t,f,r],0;force=true)
      end
    end
  end end end

  print("Cstr: Acc. Tech. 1 : ",Dates.now()-start,"\n")
  
  ############### Capital Costs #############
  
  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    @constraint(model, Params.CapitalCost[r,t,y] * Vars.NewCapacity[y,t,r] == Vars.CapitalInvestment[y,t,r], base_name="CC1_UndiscountedCapitalInvestments|$(y)|$(t)|$(r)")
    @constraint(model, Vars.CapitalInvestment[y,t,r]/((1+Settings.TechnologyDiscountRate[r,t])^(y-Switch.StartYear)) == Vars.DiscountedCapitalInvestment[y,t,r], base_name="CC2_DiscountedCapitalInvestments|$(y)|$(t)|$(r)")
  end end end
  print("Cstr: Cap. Cost. : ",Dates.now()-start,"\n")
  
  ############### Investment & Capacity Limits / Smoothing Constraints #############
  
  if Switch.switch_dispatch == 0
    if Switch.switch_investLimit == 1
      for i ∈ eachindex(𝓨)
        if 𝓨[i] > Switch.StartYear
          @constraint(model, 
          sum(Vars.CapitalInvestment[𝓨[i],t,r] for t ∈ 𝓣 for r ∈ 𝓡) <= 1/(max(𝓨...)-Switch.StartYear)*YearlyDifferenceMultiplier(𝓨[i-1],Sets)*Settings.InvestmentLimit*sum(Vars.CapitalInvestment[yy,t,r] for yy ∈𝓨 for t ∈ 𝓣 for r ∈ 𝓡), 
          base_name="SC1_SpreadCapitalInvestmentsAcrossTime|$(𝓨[i])")
          for r ∈ 𝓡 
            for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["Renewables"])
              @constraint(model,
              Vars.NewCapacity[𝓨[i],t,r] <= YearlyDifferenceMultiplier(𝓨[i-1],Sets)*Settings.NewRESCapacity*Params.TotalAnnualMaxCapacity[r,t,𝓨[i]], 
              base_name="SC2_LimitAnnualCapacityAdditions|$(𝓨[i])|$(r)|$(t)")
            end
            for f ∈ 𝓕
              for t ∈ intersect(Maps.Fuel_Tech[f],Params.TagTechnologyToSubsets["PhaseInSet"])
                @constraint(model,
                Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r] >= Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r]*Settings.PhaseIn[𝓨[i]]*(Params.SpecifiedAnnualDemand[r,f,𝓨[i]] > 0 ? Params.SpecifiedAnnualDemand[r,f,𝓨[i]]/Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]] : 1), 
                base_name="SC3_SmoothingRenewableIntegration|$(𝓨[i])|$(r)|$(t)|$(f)")
              end
              for t ∈ intersect(Maps.Fuel_Tech[f],Params.TagTechnologyToSubsets["PhaseOutSet"])
                @constraint(model, 
                Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r] <= Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r]*Settings.PhaseOut[𝓨[i]]*(Params.SpecifiedAnnualDemand[r,f,𝓨[i]] > 0 ? Params.SpecifiedAnnualDemand[r,f,𝓨[i]]/Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]] : 1), 
                base_name="SC3_SmoothingFossilPhaseOuts|$(𝓨[i])|$(r)|$(t)|$(f)")
              end
            end
          end
          for f ∈ 𝓕
            if Settings.ProductionGrowthLimit[𝓨[i],f]>0
              @constraint(model,
              sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r]-Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ Maps.Fuel_Tech[f] for r ∈ 𝓡 if Params.RETagTechnology[r,t,𝓨[i]]==1) <= 
              YearlyDifferenceMultiplier(𝓨[i-1],Sets)*Settings.ProductionGrowthLimit[𝓨[i],f]*sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ Maps.Fuel_Tech[f] for r ∈ 𝓡)-sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ intersect(Maps.Fuel_Tech[f],Params.TagTechnologyToSubsets["StorageDummies"]) for r ∈ 𝓡),
              base_name="SC4_RelativeTechnologyPhaseInLimit|$(𝓨[i])|$(f)")
              for r ∈ 𝓡 
                @constraint(model,
                sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r]-Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ intersect(Maps.Fuel_Tech[f],Params.TagTechnologyToSubsets["StorageDummies"])) <= YearlyDifferenceMultiplier(𝓨[i-1],Sets)*(Settings.ProductionGrowthLimit[𝓨[i],f]+Settings.StorageLimitOffset)*sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ Maps.Fuel_Tech[f]),
                base_name="SC5_AnnualStorageChangeLimit|$(𝓨[i])|$(r)|$(f)")
              end
            end
          end
        end
      end
    end

    ############## CCS-specific constraints #############
    if Switch.switch_ccs == 1
      for r ∈ 𝓡
        for i ∈ 2:length(𝓨) for f ∈ setdiff(𝓕,["DAC_Dummy"]) 
          @constraint(model,
          sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r]-Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ intersect(Maps.Fuel_Tech[f],Params.TagTechnologyToSubsets["CCS"])) <= YearlyDifferenceMultiplier(𝓨[i-1],Sets)*(Settings.ProductionGrowthLimit[𝓨[i],"Air"])*sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ Maps.Fuel_Tech[f]),
          base_name="CCS1_CCSAdditionLimit|$(𝓨[i])|$(r)|$(f)")
        end end

        if sum(Params.RegionalCCSLimit[r] for r ∈ 𝓡)>0
          @constraint(model,
          sum(sum( Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r]*Params.EmissionContentPerFuel[f,e]*Params.InputActivityRatio[r,t,f,m,y]*YearlyDifferenceMultiplier(y,Sets)*((Params.EmissionActivityRatio[r,t,m,e,y]>0 ? (1-Params.EmissionActivityRatio[r,t,m,e,y]) : 0)+
          (Params.EmissionActivityRatio[r,t,m,e,y] < 0 ? (-1)*Params.EmissionActivityRatio[r,t,m,e,y] : 0)) for f ∈ Maps.Tech_Fuel[t] for m ∈ Maps.Tech_MO[t] for e ∈ 𝓔) for y ∈ 𝓨 for t ∈ intersect(𝓣,Params.TagTechnologyToSubsets["CCS"])) <= Params.RegionalCCSLimit[r],
          base_name="CCS2_MaximumCCStorageLimit|$(r)")
        end
      end
    end
    
  end
  
  ############### Salvage Value #############
  
  for y ∈ 𝓨 for r ∈ 𝓡
    for t ∈ 𝓣
      if Settings.DepreciationMethod[r]==1 && ((y + Params.OperationalLife[t] - 1 > max(𝓨...)) && (Settings.TechnologyDiscountRate[r,t] > 0))
        @constraint(model, 
        Vars.SalvageValue[y,t,r] == Params.CapitalCost[r,t,y]*Vars.NewCapacity[y,t,r]*(1-(((1+Settings.TechnologyDiscountRate[r,t])^(max(𝓨...) - y + 1 ) -1)/((1+Settings.TechnologyDiscountRate[r,t])^Params.OperationalLife[t]-1))),
        base_name="SV1_SalvageValueAtEndOfPeriod1|$(y)|$(t)|$(r)")
      end

      if (((y + Params.OperationalLife[t]-1 > max(𝓨...)) && (Settings.TechnologyDiscountRate[r,t] == 0)) || (Settings.DepreciationMethod[r]==2 && (y + Params.OperationalLife[t]-1 > max(𝓨...))))
        @constraint(model,
        Vars.SalvageValue[y,t,r] == Params.CapitalCost[r,t,y]*Vars.NewCapacity[y,t,r]*(1-(max(𝓨...)- y+1)/Params.OperationalLife[t]),
        base_name="SV2_SalvageValueAtEndOfPeriod2|$(y)|$(t)|$(r)")
      end
      if y + Params.OperationalLife[t]-1 <= max(𝓨...)
        @constraint(model,
        Vars.SalvageValue[y,t,r] == 0,
        base_name="SV3_SalvageValueAtEndOfPeriod3|$(y)|$(t)|$(r)")
      end

      @constraint(model,
      Vars.DiscountedSalvageValue[y,t,r] == Vars.SalvageValue[y,t,r]/((1+Settings.TechnologyDiscountRate[r,t])^(1+max(𝓨...) - Switch.StartYear)),
      base_name="SV4_SalvageValueDiscToStartYr|$(y)|$(t)|$(r)")
    end
    if ((Settings.DepreciationMethod[r]==1) && ((y + 40) > max(𝓨...)))
      @constraint(model,
      Vars.DiscountedSalvageValueTransmission[y,r] == sum(Params.TradeCapacityGrowthCosts[r,rr,f]*Params.TradeRoute[r,rr,f,y]*Vars.NewTradeCapacity[y,f,r,rr]*(1-(((1+Settings.GeneralDiscountRate[r])^(max(𝓨...) - y+1)-1)/((1+Settings.GeneralDiscountRate[r])^40))) for f ∈ 𝓕 for rr ∈ 𝓡)/((1+Settings.GeneralDiscountRate[r])^(1+max(𝓨...) - min(𝓨...))),
      base_name="SV1b_SalvageValueAtEndOfPeriod1|$(y)|$(r)")
    end
  end end
  
  ############### Operating Costs #############
  
  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    if (sum(Params.VariableCost[r,t,m,y] for m ∈ Maps.Tech_MO[t]) > 0) & (CanBuildTechnology[y,t,r] > 0)
      @constraint(model, sum((Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r]*Params.VariableCost[r,t,m,y]) for m ∈ Maps.Tech_MO[t]) == Vars.AnnualVariableOperatingCost[y,t,r], base_name="OC1_OperatingCostsVariable|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.AnnualVariableOperatingCost[y,t,r],0; force=true)
    end

    if (Params.FixedCost[r,t,y] > 0) & (CanBuildTechnology[y,t,r] > 0)
      @constraint(model, sum(Vars.NewCapacity[yy,t,r]*Params.FixedCost[r,t,yy] for yy ∈ 𝓨 if (y-yy < Params.OperationalLife[t]) && (y-yy >= 0)) + Params.ResidualCapacity[r,t,y]*Params.FixedCost[r,t,y] == Vars.AnnualFixedOperatingCost[y,t,r], base_name="OC2_OperatingCostsFixedAnnual|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.AnnualFixedOperatingCost[y,t,r],0; force=true)
    end

    if ((JuMP.has_upper_bound(Vars.AnnualVariableOperatingCost[y,t,r]) && JuMP.upper_bound(Vars.AnnualVariableOperatingCost[y,t,r]) >0) || 
      (!JuMP.is_fixed(Vars.AnnualVariableOperatingCost[y,t,r]) >0) && !JuMP.has_upper_bound(Vars.AnnualVariableOperatingCost[y,t,r]) ||
      (JuMP.is_fixed(Vars.AnnualVariableOperatingCost[y,t,r]) && JuMP.fix_value(Vars.AnnualVariableOperatingCost[y,t,r]) >0)) ||
      ((JuMP.has_upper_bound(Vars.AnnualFixedOperatingCost[y,t,r]) && JuMP.upper_bound(Vars.AnnualFixedOperatingCost[y,t,r]) >0) || 
      (!JuMP.is_fixed(Vars.AnnualFixedOperatingCost[y,t,r]) >0) && !JuMP.has_upper_bound(Vars.AnnualFixedOperatingCost[y,t,r]) ||
      (JuMP.is_fixed(Vars.AnnualFixedOperatingCost[y,t,r]) && JuMP.fix_value(Vars.AnnualFixedOperatingCost[y,t,r]) >0)) #OC3_OperatingCostsTotalAnnual
      @constraint(model, (Vars.AnnualFixedOperatingCost[y,t,r] + Vars.AnnualVariableOperatingCost[y,t,r])*YearlyDifferenceMultiplier(y,Sets) == Vars.OperatingCost[y,t,r], base_name="OC3_OperatingCostsTotalAnnual|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.OperatingCost[y,t,r],0; force=true)
    end

    if ((JuMP.has_upper_bound(Vars.OperatingCost[y,t,r]) && JuMP.upper_bound(Vars.OperatingCost[y,t,r]) >0) || 
      (!JuMP.is_fixed(Vars.OperatingCost[y,t,r]) >0) && !JuMP.has_upper_bound(Vars.OperatingCost[y,t,r]) ||
      (JuMP.is_fixed(Vars.OperatingCost[y,t,r]) && JuMP.fix_value(Vars.OperatingCost[y,t,r]) >0)) # OC4_DiscountedOperatingCostsTotalAnnual
      @constraint(model, Vars.OperatingCost[y,t,r]/((1+Settings.TechnologyDiscountRate[r,t])^(y-Switch.StartYear+0.5)) == Vars.DiscountedOperatingCost[y,t,r], base_name="OC4_DiscountedOperatingCostsTotalAnnual|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.DiscountedOperatingCost[y,t,r],0; force=true)
    end
  end end end
  print("Cstr: Op. Cost. : ",Dates.now()-start,"\n")
  
 ############### Total Discounted Costs #############
  
  start=Dates.now()
  for y ∈ 𝓨 for r ∈ 𝓡
    for t ∈ 𝓣 
      @constraint(model,
      Vars.DiscountedOperatingCost[y,t,r]+Vars.DiscountedCapitalInvestment[y,t,r]+Vars.DiscountedTechnologyEmissionsPenalty[y,t,r]-Vars.DiscountedSalvageValue[y,t,r]
      + (Switch.switch_ramping ==1 ? Vars.DiscountedAnnualProductionChangeCost[y,t,r] : 0)
      == Vars.TotalDiscountedCostByTechnology[y,t,r],
      base_name="TDC1_TotalDiscountedCostByTechnology|$(y)|$(t)|$(r)")
    end
    @constraint(model, sum(Vars.TotalDiscountedCostByTechnology[y,t,r] for t ∈ 𝓣)+sum(Vars.TotalDiscountedStorageCost[s,y,r] for s ∈ 𝓢) == Vars.TotalDiscountedCost[y,r]
    ,base_name="TDC2_TotalDiscountedCost|$(y)|$(r)")
  end end
    print("Cstr: Tot. Disc. Cost 2 : ",Dates.now()-start,"\n")
  
  ############### Total Capacity Constraints ##############
  
  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    if (Params.TotalAnnualMaxCapacity[r,t,y] < 999999) && (Params.TotalAnnualMaxCapacity[r,t,y] > 0)
      @constraint(model, Vars.TotalCapacityAnnual[y,t,r] <= Params.TotalAnnualMaxCapacity[r,t,y], base_name="TCC1_TotalAnnualMaxCapacityConstraint|$(y)|$(t)|$(r)")
    elseif Params.TotalAnnualMaxCapacity[r,t,y] == 0
      JuMP.fix(Vars.TotalCapacityAnnual[y,t,r],0; force=true)
    end

    if Params.TotalAnnualMinCapacity[r,t,y]>0
      @constraint(model, Vars.TotalCapacityAnnual[y,t,r] >= Params.TotalAnnualMinCapacity[r,t,y], base_name="TCC2_TotalAnnualMinCapacityConstraint|$(y)|$(t)|$(r)")
    end
  end end end
  print("Cstr: Tot. Cap. : ",Dates.now()-start,"\n")
  
  ############### New Capacity Constraints ##############
  
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    if Params.TotalAnnualMaxCapacityInvestment[r,t,y] < 999999
      @constraint(model,
      Vars.NewCapacity[y,t,r] <= Params.TotalAnnualMaxCapacityInvestment[r,t,y], base_name="NCC1_TotalAnnualMaxNewCapacityConstraint|$(y)|$(t)|$(r)")
    end
    if Params.TotalAnnualMinCapacityInvestment[r,t,y] > 0
      @constraint(model,
      Vars.NewCapacity[y,t,r] >= Params.TotalAnnualMinCapacityInvestment[r,t,y], base_name="NCC2_TotalAnnualMinNewCapacityConstraint|$(y)|$(t)|$(r)")
    end
  end end end
  
  ################ Annual Activity Constraints ##############
  
  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    if (CanBuildTechnology[y,t,r] > 0) && 
      (any(x->x>0, [JuMP.has_upper_bound(Vars.ProductionByTechnologyAnnual[y,t,f,r]) ? JuMP.upper_bound(Vars.ProductionByTechnologyAnnual[y,t,f,r]) : ((JuMP.is_fixed(Vars.ProductionByTechnologyAnnual[y,t,f,r])) && (JuMP.fix_value(Vars.ProductionByTechnologyAnnual[y,t,f,r]) == 0)) ? 0 : 999999 for f ∈ Maps.Tech_Fuel[t]]))
      @constraint(model, sum(Vars.ProductionByTechnologyAnnual[y,t,f,r] for f ∈ Maps.Tech_Fuel[t]) == Vars.TotalTechnologyAnnualActivity[y,t,r], base_name= "AAC1_TotalAnnualTechnologyActivity|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.TotalTechnologyAnnualActivity[y,t,r],0; force=true)
    end

    if Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] < 999999
      @constraint(model, Vars.TotalTechnologyAnnualActivity[y,t,r] <= Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y], base_name= "AAC2_TotalAnnualTechnologyActivityUpperLimit|$(y)|$(t)|$(r)")
    end

    if Params.TotalTechnologyAnnualActivityLowerLimit[r,t,y] > 0 # AAC3_TotalAnnualTechnologyActivityLowerLimit
      @constraint(model, Vars.TotalTechnologyAnnualActivity[y,t,r] >= Params.TotalTechnologyAnnualActivityLowerLimit[r,t,y], base_name= "AAC3_TotalAnnualTechnologyActivityLowerLimit|$(y)|$(t)|$(r)")
    end
  end end end 
  print("Cstr: Annual. Activity : ",Dates.now()-start,"\n")
  
  ################ Total Activity Constraints ##############
  
  start=Dates.now()
  for t ∈ 𝓣 for r ∈ 𝓡
    @constraint(model, sum(Vars.TotalTechnologyAnnualActivity[y,t,r]*YearlyDifferenceMultiplier(y,Sets) for y ∈ 𝓨) == Vars.TotalTechnologyModelPeriodActivity[t,r], base_name="TAC1_TotalModelHorizonTechnologyActivity|$(t)|$(r)")
    if Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] < 999999
      @constraint(model, Vars.TotalTechnologyModelPeriodActivity[t,r] <= Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t], base_name= "TAC2_TotalModelHorizonTechnologyActivityUpperLimit|$(t)|$(r)")
    end
    if Params.TotalTechnologyModelPeriodActivityLowerLimit[r,t] > 0
      @constraint(model, Vars.TotalTechnologyModelPeriodActivity[t,r] >= Params.TotalTechnologyModelPeriodActivityLowerLimit[r,t], base_name= "TAC3_TotalModelHorizonTechnologyActivityLowerLimit|$(t)|$(r)")
    end
  end end
  print("Cstr: Tot. Activity : ",Dates.now()-start,"\n")
  
  ############### Reserve Margin Constraint ############## NTS: Should change demand for production
  
  if Switch.switch_dispatch == 0 || Switch.switch_reserve == 1
    for r ∈ 𝓡, y ∈ 𝓨, l ∈ 𝓛
      @constraint(model,
      sum((Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y] *Params.ReserveMarginTagTechnology[r,t,y] * Params.ReserveMarginTagFuel[r,f,y]) for f ∈ 𝓕 for (t,m) ∈ LoopSetOutput[(r,f,y)]) == Vars.TotalActivityInReserveMargin[r,y,l],
      base_name="RM1_ReserveMargin_TechologiesIncluded_In_Activity_Units|$(y)|$(l)|$(r)")
      
      @constraint(model,
      sum((sum(Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] for (t,m) ∈ LoopSetOutput[(r,f,y)] if t ∈ Maps.Fuel_Tech[f]) * Params.YearSplit[l,y] *Params.ReserveMarginTagFuel[r,f,y]) for f ∈ 𝓕) == Vars.DemandNeedingReserveMargin[y,l,r],
      base_name="RM2_ReserveMargin_FuelsIncluded|$(y)|$(l)|$(r)")

      if Params.ReserveMargin[r,y] > 0
        @constraint(model,
        Vars.DemandNeedingReserveMargin[y,l,r] * Params.ReserveMargin[r,y] <= Vars.TotalActivityInReserveMargin[r,y,l],
        base_name="RM3_ReserveMargin_Constraint|$(y)|$(l)|$(r)")
      end
    end
  end
  
  ############### RE Production Target ############## NTS: Should change demand for production
  
  start=Dates.now()
  for i ∈ eachindex(𝓨) for f ∈ 𝓕 for r ∈ 𝓡
    @constraint(model,
    sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r] for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["Renewables"])) == Vars.TotalREProductionAnnual[𝓨[i],r,f],base_name="RE1_ComputeTotalAnnualREProduction|$(𝓨[i])|$(r)|$(f)")

    @constraint(model,
    Params.REMinProductionTarget[r,f,𝓨[i]]*sum(Vars.RateOfActivity[𝓨[i],l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,𝓨[i]]*Params.YearSplit[l,𝓨[i]] for l ∈ 𝓛 for t ∈ 𝓣 for m ∈ Maps.Tech_MO[t] if Params.OutputActivityRatio[r,t,f,m,𝓨[i]] != 0 )*Params.RETagFuel[r,f,𝓨[i]] <= Vars.TotalREProductionAnnual[𝓨[i],r,f],
    base_name="RE2_AnnualREProductionLowerLimit|$(𝓨[i])|$(r)|$(f)")

    if Switch.switch_dispatch == 0
      if 𝓨[i]> Switch.StartYear && Params.SpecifiedAnnualDemand[r,f,𝓨[i]]>0
        @constraint(model,
        Vars.TotalREProductionAnnual[𝓨[i],r,f] >= Vars.TotalREProductionAnnual[𝓨[i-1],r,f]*((Params.SpecifiedAnnualDemand[r,f,𝓨[i]]/Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]])),
        base_name="RE3_RETargetPath|$(𝓨[i])|$(r)|$(f)")
      end
    end

  end end end
  print("Cstr: RE target : ",Dates.now()-start,"\n")
  
  ################ Emissions Accounting ##############
  
  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    if CanBuildTechnology[y,t,r] > 0
      for e ∈ 𝓔 for m ∈ Maps.Tech_MO[t]
        @constraint(model, Params.EmissionActivityRatio[r,t,m,e,y]*sum((Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r]*Params.EmissionContentPerFuel[f,e]*Params.InputActivityRatio[r,t,f,m,y]) for f ∈ Maps.Tech_Fuel[t]) == Vars.AnnualTechnologyEmissionByMode[y,t,e,m,r] , base_name="E1_AnnualEmissionProductionByMode|$(y)|$(t)|$(e)|$(m)|$(r)" )
      end end
    else
      for m ∈ Maps.Tech_MO[t] for e ∈ 𝓔
        JuMP.fix(Vars.AnnualTechnologyEmissionByMode[y,t,e,m,r],0; force=true)
      end end
    end
  end end end
  print("Cstr: Em. Acc. 1 : ",Dates.now()-start,"\n")
  start=Dates.now()
  for y ∈ 𝓨 for r ∈ 𝓡
    for t ∈ 𝓣
      for e ∈ 𝓔
        @constraint(model, sum(Vars.AnnualTechnologyEmissionByMode[y,t,e,m,r] for m ∈ Maps.Tech_MO[t]) == Vars.AnnualTechnologyEmission[y,t,e,r],
        base_name="E2_AnnualEmissionProduction|$(y)|$(t)|$(e)|$(r)")

        @constraint(model, (Vars.AnnualTechnologyEmission[y,t,e,r]*Params.EmissionsPenalty[r,e,y]*Params.EmissionsPenaltyTagTechnology[r,t,e,y])*YearlyDifferenceMultiplier(y,Sets) == Vars.AnnualTechnologyEmissionPenaltyByEmission[y,t,e,r],
        base_name="E3_EmissionsPenaltyByTechAndEmission|$(y)|$(t)|$(e)|$(r)")
      end

      @constraint(model, sum(Vars.AnnualTechnologyEmissionPenaltyByEmission[y,t,e,r] for e ∈ 𝓔) == Vars.AnnualTechnologyEmissionsPenalty[y,t,r],
      base_name="E4_EmissionsPenaltyByTechnology|$(y)|$(t)|$(r)")

      @constraint(model, Vars.AnnualTechnologyEmissionsPenalty[y,t,r]/((1+Settings.SocialDiscountRate[r])^(y-Switch.StartYear+0.5)) == Vars.DiscountedTechnologyEmissionsPenalty[y,t,r],
      base_name="E5_DiscountedEmissionsPenaltyByTechnology|$(y)|$(t)|$(r)")
    end
  end end 

  for e ∈ 𝓔
    for y ∈ 𝓨
      for r ∈ 𝓡
        @constraint(model, sum(Vars.AnnualTechnologyEmission[y,t,e,r] for t ∈ 𝓣) == Vars.AnnualEmissions[y,e,r], 
        base_name="E6_AnnualEmissionsAccounting|$(y)|$(e)|$(r)")

        @constraint(model, Vars.AnnualEmissions[y,e,r]+Params.AnnualExogenousEmission[r,e,y] <= Params.RegionalAnnualEmissionLimit[r,e,y], 
        base_name="E8_RegionalAnnualEmissionsLimit|$(y)|$(e)|$(r)")
      end
      @constraint(model, sum(Vars.AnnualEmissions[y,e,r]+Params.AnnualExogenousEmission[r,e,y] for r ∈ 𝓡) <= Params.AnnualEmissionLimit[e,y],
      base_name="E9_AnnualEmissionsLimit|$(y)|$(e)")
    end
    @constraint(model, sum(Vars.ModelPeriodEmissions[e,r] for r ∈ 𝓡) <= Params.ModelPeriodEmissionLimit[e],
    base_name="E10_ModelPeriodEmissionsLimit|$(e)")
  end

  print("Cstr: Em. Acc. 2 : ",Dates.now()-start,"\n")
  start=Dates.now()
  for e ∈ 𝓔 for r ∈ 𝓡
    if Params.RegionalModelPeriodEmissionLimit[e,r] < 999999
      @constraint(model, Vars.ModelPeriodEmissions[e,r] <= Params.RegionalModelPeriodEmissionLimit[e,r] ,base_name="E11_RegionalModelPeriodEmissionsLimit|$(e)|$(r)" )
    end
  end end
  print("Cstr: Em. Acc. 3 : ",Dates.now()-start,"\n")
  start=Dates.now()

  if Switch.switch_weighted_emissions == 1
    for e ∈ 𝓔 for r ∈ 𝓡
      @constraint(model,
      sum(Vars.WeightedAnnualEmissions[𝓨[i],e,r]*(𝓨[i+1]-𝓨[i]) for i ∈ eachindex(𝓨)[1:end-1] if 𝓨[i+1]-𝓨[i] > 0) +  Vars.WeightedAnnualEmissions[𝓨[end],e,r] == Vars.ModelPeriodEmissions[e,r]- Params.ModelPeriodExogenousEmission[r,e],
      base_name="E7_ModelPeriodEmissionsAccounting|$(e)|$(r)")

      @constraint(model,
      Vars.AnnualEmissions[𝓨[end],e,r] == Vars.WeightedAnnualEmissions[𝓨[end],e,r],
      base_name="E7b_WeightedLastYearEmissions|$(𝓨[end])|$(e)|$(r)")
      for i ∈ eachindex(𝓨)[1:end-1]
        @constraint(model,
        (Vars.AnnualEmissions[𝓨[i],e,r]+Vars.AnnualEmissions[𝓨[i+1],e,r])/2 == Vars.WeightedAnnualEmissions[𝓨[i],e,r],
        base_name="E7a_WeightedEmissions|$(𝓨[i])|$(e)|$(r)")
      end
    end end
  else
    for e ∈ 𝓔 for r ∈ 𝓡
      @constraint(model, sum( Vars.AnnualEmissions[𝓨[ind],e,r]*(𝓨[ind+1]-𝓨[ind]) for ind ∈ 1:(length(𝓨)-1) if 𝓨[ind+1]-𝓨[ind]>0)
      +  Vars.AnnualEmissions[𝓨[end],e,r] == Vars.ModelPeriodEmissions[e,r]- Params.ModelPeriodExogenousEmission[r,e],
      base_name="E7_ModelPeriodEmissionsAccounting|$(e)|$(r)")
    end end
  end
  print("Cstr: Em. Acc. 4 : ",Dates.now()-start,"\n")
  
  ################ Sectoral Emissions Accounting ##############
  start=Dates.now()
  for y ∈ 𝓨, e ∈ 𝓔, se ∈ 𝓢𝓮
    if Params.AnnualSectoralEmissionLimit[e,se,y] < 999999
      for r ∈ 𝓡
        @constraint(model,
        sum(Vars.AnnualTechnologyEmission[y,t,e,r] for t ∈ 𝓣 if Params.TagTechnologyToSector[t,se] != 0) == Vars.AnnualSectoralEmissions[y,e,se,r],
        base_name="E12_AnnualSectorEmissions|$(y)|$(e)|$(se)|$(r)")
      end

      @constraint(model,
      sum(Vars.AnnualSectoralEmissions[y,e,se,r] for r ∈ 𝓡 ) <= Params.AnnualSectoralEmissionLimit[e,se,y],
      base_name="E13_AnnualSectorEmissionsLimit|$(y)|$(e)|$(se)")
  end end end

  print("Cstr: ES: ",Dates.now()-start,"\n")
  ######### Short-Term Storage Constraints #############
  start=Dates.now()

  for r ∈ 𝓡 for s ∈ 𝓢 for y ∈ 𝓨
    @constraint(model,
    Vars.StorageLevelYearStart[s,y,r] <= Settings.StorageLevelYearStartUpperLimit * sum(Vars.NewStorageCapacity[s,yy,r] for yy ∈ 𝓨 if Params.OperationalLifeStorage[s] >= (y - yy) && (y - yy) >= 0) + Params.ResidualStorageCapacity[r,s,y], base_name="S1a_StorageLevelYearStartUpperLimit|$(r)|$(s)|$(y)")

    @constraint(model,
    Vars.StorageLevelYearStart[s,y,r] >= Settings.StorageLevelYearStartLowerLimit * sum(Vars.NewStorageCapacity[s,yy,r] for yy ∈ 𝓨 if Params.OperationalLifeStorage[s] >= (y - yy) && (y - yy) >= 0) + Params.ResidualStorageCapacity[r,s,y], base_name="S1b_StorageLevelYearStartLowerLimit|$(r)|$(s)|$(y)")
  end end end

  for r ∈ 𝓡 for s ∈ 𝓢 for i ∈ eachindex(𝓨)
    @constraint(model,
    sum((sum(Vars.RateOfActivity[𝓨[i],l,t,m,r] * Params.TechnologyToStorage[t,s,m,𝓨[i]] for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["StorageDummies"])  for m ∈ Maps.Tech_MO[t] if Params.TechnologyToStorage[t,s,m,𝓨[i]]>0)
              - sum(Vars.RateOfActivity[𝓨[i],l,t,m,r] / Params.TechnologyFromStorage[t,s,m,𝓨[i]] for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["StorageDummies"]) for m ∈ Maps.Tech_MO[t] if Params.TechnologyFromStorage[t,s,m,𝓨[i]]>0)) for l ∈ 𝓛) == 0,
              base_name="S3_StorageRefilling|$(r)|$(s)|$(𝓨[i])")

    @constraint(model, Vars.StorageLevelYearStart[s,𝓨[i],r] ==  Vars.StorageLevelYearFinish[s,𝓨[i],r],
    base_name="S4_StorageLevelYearFinish|$(s)|$(𝓨[i])|$(r)")

    for j ∈ eachindex(𝓛)
      @constraint(model,
      (j>1 ? Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j-1],r] + 
      (sum((Params.TechnologyToStorage[t,s,m,𝓨[i]]>0 ? Vars.RateOfActivity[𝓨[i],𝓛[j-1],t,m,r] * Params.TechnologyToStorage[t,s,m,𝓨[i]] : 0) for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["StorageDummies"]) for m ∈ Maps.Tech_MO[t])
        - sum((Params.TechnologyFromStorage[t,s,m,𝓨[i]]>0 ? Vars.RateOfActivity[𝓨[i],𝓛[j-1],t,m,r] / Params.TechnologyFromStorage[t,s,m,𝓨[i]] : 0 ) for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["StorageDummies"]) for m ∈ Maps.Tech_MO[t])) * Params.YearSplit[𝓛[j-1],𝓨[i]] : 0)
        + (j == 1 ? Vars.StorageLevelYearStart[s,𝓨[i],r] : 0)   == Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j],r],
        base_name="S2_StorageLevelTSStart|$(r)|$(s)|$(𝓨[i])|$(𝓛[j])")
      @constraint(model,
      sum(Vars.NewStorageCapacity[s,𝓨[i],r] + Params.ResidualStorageCapacity[r,s,𝓨[i]] for yy ∈ 𝓨 if (𝓨[i]-yy < Params.OperationalLifeStorage[s] && 𝓨[i]-yy >= 0))
      >= Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j],r],
      base_name="S5b_StorageChargeUpperLimit|$(s)|$(𝓨[i])|$(𝓛[j])|$(r)")
    end
    @constraint(model,
    Params.CapitalCostStorage[r,s,𝓨[i]] * Vars.NewStorageCapacity[s,𝓨[i],r] == Vars.CapitalInvestmentStorage[s,𝓨[i],r],
    base_name="SI1_UndiscountedCapitalInvestmentStorage|$(s)|$(𝓨[i])|$(r)")
    @constraint(model,
    Vars.CapitalInvestmentStorage[s,𝓨[i],r]/((1+Settings.GeneralDiscountRate[r])^(𝓨[i]-Switch.StartYear+0.5)) == Vars.DiscountedCapitalInvestmentStorage[s,𝓨[i],r],
    base_name="SI2_DiscountingCapitalInvestmentStorage|$(s)|$(𝓨[i])|$(r)")
    if ((𝓨[i]+Params.OperationalLifeStorage[s]-1) <= 𝓨[end] )
      @constraint(model,
      Vars.SalvageValueStorage[s,𝓨[i],r] == 0,
      base_name="SI3a_SalvageValueStorageAtEndOfPeriod1|$(s)|$(𝓨[i])|$(r)")
    end
    if ((Settings.DepreciationMethod[r]==1 && (𝓨[i]+Params.OperationalLifeStorage[s]-1) > 𝓨[end] && Settings.GeneralDiscountRate[r]==0) || (Settings.DepreciationMethod[r]==2 && (𝓨[i]+Params.OperationalLifeStorage[s]-1) > 𝓨[end] && Settings.GeneralDiscountRate[r]==0))
      @constraint(model,
      Vars.CapitalInvestmentStorage[s,𝓨[i],r]*(1- 𝓨[end] - 𝓨[i]+1)/Params.OperationalLifeStorage[s] == Vars.SalvageValueStorage[s,𝓨[i],r],
      base_name="SI3b_SalvageValueStorageAtEndOfPeriod2|$(s)|$(𝓨[i])|$(r)")
    end
    if (Settings.DepreciationMethod[r]==1 && ((𝓨[i]+Params.OperationalLifeStorage[s]-1) > 𝓨[end] && Settings.GeneralDiscountRate[r]>0))
      @constraint(model,
      Vars.CapitalInvestmentStorage[s,𝓨[i],r]*(1-(((1+Settings.GeneralDiscountRate[r])^(𝓨[end] - 𝓨[i]+1)-1)/((1+Settings.GeneralDiscountRate[r])^Params.OperationalLifeStorage[s]-1))) == Vars.SalvageValueStorage[s,𝓨[i],r],
      base_name="SI3c_SalvageValueStorageAtEndOfPeriod3|$(s)|$(𝓨[i])|$(r)")
    end
    @constraint(model,
    Vars.SalvageValueStorage[s,𝓨[i],r]/((1+Settings.GeneralDiscountRate[r])^(1+max(𝓨...) - Switch.StartYear)) == Vars.DiscountedSalvageValueStorage[s,𝓨[i],r],
    base_name="SI4_SalvageValueStorageDiscountedToStartYear|$(s)|$(𝓨[i])|$(r)")
    @constraint(model,
    Vars.DiscountedCapitalInvestmentStorage[s,𝓨[i],r]-Vars.DiscountedSalvageValueStorage[s,𝓨[i],r] == Vars.TotalDiscountedStorageCost[s,𝓨[i],r],
    base_name="SI5_TotalDiscountedCostByStorage|$(s)|$(𝓨[i])|$(r)")
  end end end
  for s ∈ 𝓢 for i ∈ eachindex(𝓨)
    for r ∈ 𝓡 
      if Params.MinStorageCharge[r,s,𝓨[i]] > 0
        for j ∈ eachindex(𝓛)
          @constraint(model, 
          Params.MinStorageCharge[r,s,𝓨[i]]*sum(Vars.NewStorageCapacity[s,𝓨[i],r] + Params.ResidualStorageCapacity[r,s,𝓨[i]] for yy ∈ 𝓨 if (𝓨[i]-yy < Params.OperationalLifeStorage[s] && 𝓨[i]-yy >= 0))
          <= Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j],r],
          base_name="S5a_StorageChargeLowerLimit|$(s)|$(𝓨[i])|$(𝓛[j])|$(r)")
        end
      end
    end
    for t ∈ intersect(Sets.Technology, Params.TagTechnologyToSubsets["StorageDummies"]) for m ∈ Maps.Tech_MO[t]
      if Params.TechnologyFromStorage[t,s,m,𝓨[i]]>0
        for r ∈ 𝓡 for j ∈ eachindex(𝓛)
          @constraint(model,
          Vars.RateOfActivity[𝓨[i],𝓛[j],t,m,r]/Params.TechnologyFromStorage[t,s,m,𝓨[i]]*Params.YearSplit[𝓛[j],𝓨[i]] <= Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j],r],
          base_name="S6_StorageActivityLimit|$(s)|$(t)|$(𝓨[i])|$(𝓛[j])|$(r)|$(m)")
        end end
      end
    end end
  end end
  print("Cstr: Storage 1 : ",Dates.now()-start,"\n")
  
  ######### Transportation Equations #############
  start=Dates.now()
  for r ∈ 𝓡 for y ∈ 𝓨
    for f ∈ intersect(Sets.Fuel, Params.TagFuelToSubsets["TransportFuels"])
      if Params.SpecifiedAnnualDemand[r,f,y] != 0
        for l ∈ 𝓛 for mt ∈ 𝓜𝓽  
          @constraint(model,
          Params.SpecifiedAnnualDemand[r,f,y]*Params.ModalSplitByFuelAndModalType[r,f,y,mt]*Params.SpecifiedDemandProfile[r,f,l,y] == Vars.DemandSplitByModalType[mt,l,r,f,y],
          base_name="T1_SpecifiedAnnualDemandByModalSplit|$(mt)|$(l)|$(r)|$(f)|$(y)")
        end end
      end
    
      for mt ∈ 𝓜𝓽
        if sum(Params.TagTechnologyToModalType[:,:,mt]) != 0 && sum(Params.OutputActivityRatio[r,:,f,:,y]) != 0
          for l ∈ 𝓛
            @constraint(model,
            sum(Params.TagTechnologyToModalType[t,m,mt]*Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y]*Params.YearSplit[l,y] for (t,m) ∈ LoopSetOutput[(r,f,y)]) == Vars.ProductionSplitByModalType[mt,l,r,f,y],
            base_name="T2_ProductionOfTechnologyByModalSplit|$(mt)|$(l)|$(r)|$(f)|$(y)")
            @constraint(model,
            Vars.ProductionSplitByModalType[mt,l,r,f,y] >= Vars.DemandSplitByModalType[mt,l,r,f,y],
            base_name="T3_ModalSplitBalance|$(mt)|$(l)|$(r)|$(f)|$(y)")
          end
        end
      end
    end

    for l ∈ 𝓛 
      JuMP.fix(Vars.ProductionSplitByModalType["MT_FRT_SHIP_RE",l,r,"Mobility_Passenger",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_FRT_ROAD_RE",l,r,"Mobility_Passenger",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_FRT_RAIL_RE",l,r,"Mobility_Passenger",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_FRT_SHIP_CONV",l,r,"Mobility_Passenger",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_FRT_ROAD_CONV",l,r,"Mobility_Passenger",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_FRT_RAIL_CONV",l,r,"Mobility_Passenger",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_PSNG_AIR_RE",l,r,"Mobility_Freight",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_PSNG_ROAD_RE",l,r,"Mobility_Freight",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_PSNG_RAIL_RE",l,r,"Mobility_Freight",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_PSNG_AIR_CONV",l,r,"Mobility_Freight",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_PSNG_ROAD_CONV",l,r,"Mobility_Freight",y], 0; force=true)
      JuMP.fix(Vars.ProductionSplitByModalType["MT_PSNG_RAIL_CONV",l,r,"Mobility_Freight",y], 0; force=true)
    end
  end end

  print("Cstr: transport: ",Dates.now()-start,"\n")
  if Switch.switch_ramping == 1
  
    ############### Ramping #############
    start=Dates.now()
    for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
      for f ∈ Maps.Tech_Fuel[t]
        for i ∈ eachindex(𝓛)
          if i>1
            if Params.TagDispatchableTechnology[t]==1 && (Params.RampingUpFactor[t,y] != 0 || Params.RampingDownFactor[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0)
              @constraint(model,
              ((sum(Vars.RateOfActivity[y,𝓛[i],t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] for m ∈ Maps.Tech_MO[t] if Params.OutputActivityRatio[r,t,f,m,y] != 0)*Params.YearSplit[𝓛[i],y]) - (sum(Vars.RateOfActivity[y,𝓛[i-1],t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] for m ∈ Maps.Tech_MO[t] if Params.OutputActivityRatio[r,t,f,m,y] != 0)*Params.YearSplit[𝓛[i-1],y]))
              == Vars.ProductionUpChangeInTimeslice[y,𝓛[i],f,t,r] - Vars.ProductionDownChangeInTimeslice[y,𝓛[i],f,t,r],
              base_name="R1_ProductionChange|$(y)|$(𝓛[i])|$(f)|$(t)|$(r)")
            end
            if Params.TagDispatchableTechnology[t]==1 && Params.RampingUpFactor[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
              @constraint(model,
              Vars.ProductionUpChangeInTimeslice[y,𝓛[i],f,t,r] <= Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t]*Params.RampingUpFactor[t,y]*Params.YearSplit[𝓛[i],y],
              base_name="R2_RampingUpLimit|$(y)|$(𝓛[i])|$(f)|$(t)|$(r)")
            end
            if Params.TagDispatchableTechnology[t]==1 && Params.RampingDownFactor[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
              @constraint(model,
              Vars.ProductionDownChangeInTimeslice[y,𝓛[i],f,t,r] <= Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t]*Params.RampingDownFactor[t,y]*Params.YearSplit[𝓛[i],y],
              base_name="R3_RampingDownLimit|$(y)|$(𝓛[i])|$(f)|$(t)|$(r)")
            end
          end
          ############### Min Runing Constraint #############
          if Params.MinActiveProductionPerTimeslice[y,𝓛[i],f,t,r] > 0
            @constraint(model,
            sum(Vars.RateOfActivity[y,𝓛[i],t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] for m ∈ Maps.Tech_MO[t] if Params.OutputActivityRatio[r,t,f,m,y] != 0) >= 
            Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t]*Params.MinActiveProductionPerTimeslice[y,𝓛[i],f,t,r],
            base_name="MRC1_MinRunningConstraint|$(y)|$(𝓛[i])|$(f)|$(t)|$(r)")
          end
        end

        ############### Ramping Costs #############
        if Params.TagDispatchableTechnology[t]==1 && Params.ProductionChangeCost[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
          @constraint(model,
          sum((Vars.ProductionUpChangeInTimeslice[y,l,f,t,r] + Vars.ProductionDownChangeInTimeslice[y,l,f,t,r])*Params.ProductionChangeCost[t,y] for l ∈ 𝓛) == Vars.AnnualProductionChangeCost[y,t,r],
          base_name="RC1_AnnualProductionChangeCosts|$(y)|$(f)|$(t)|$(r)")
        end
        if Params.TagDispatchableTechnology[t]==1 && Params.ProductionChangeCost[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
          @constraint(model,
          Vars.AnnualProductionChangeCost[y,t,r]/((1+Settings.TechnologyDiscountRate[r,t])^(y-Switch.StartYear+0.5)) == Vars.DiscountedAnnualProductionChangeCost[y,t,r],
          base_name="RC2_DiscountedAnnualProductionChangeCost|$(y)|$(f)|$(t)|$(r)")
        end
      end
      if (Params.TagDispatchableTechnology[t] == 0 || sum(Params.OutputActivityRatio[r,t,f,m,y] for f ∈ Maps.Tech_Fuel[t] for m ∈ Maps.Tech_MO[t]) == 0 || Params.ProductionChangeCost[t,y] == 0 || Params.AvailabilityFactor[r,t,y] == 0 || Params.TotalAnnualMaxCapacity[r,t,y] == 0 || Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] == 0)
        JuMP.fix(Vars.DiscountedAnnualProductionChangeCost[y,t,r], 0; force=true)
        JuMP.fix(Vars.AnnualProductionChangeCost[y,t,r], 0; force=true)
      end
    end end end
   
  print("Cstr: Ramping : ",Dates.now()-start,"\n")
  end

  ############### Curtailment && Curtailment Costs #############
  start=Dates.now()
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    @constraint(model,
    Vars.CurtailedEnergyAnnual[y,f,r]*Params.CurtailmentCostFactor[r,f,y] == Vars.AnnualCurtailmentCost[y,f,r],
    base_name="CC1_AnnualCurtailmentCosts|$(y)|$(f)|$(r)")
    @constraint(model,
    Vars.AnnualCurtailmentCost[y,f,r]/((1+Settings.GeneralDiscountRate[r])^(y-Switch.StartYear+0.5)) == Vars.DiscountedAnnualCurtailmentCost[y,f,r],
    base_name="CC2_DiscountedAnnualCurtailmentCosts|$(y)|$(f)|$(r)")
  end end end

  print("Cstr: Curtailment : ",Dates.now()-start,"\n")

  if Switch.switch_base_year_bounds == 1
  
   ############### General BaseYear Limits && trajectories #############
   start=Dates.now()
    for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
      for f ∈ Maps.Tech_Fuel[t]
        if Switch.switch_base_year_bounds_debugging == 0
          JuMP.fix(Vars.BaseYearBounds_TooHigh[y,r,t,f], 0; force=true)
          JuMP.fix(Vars.BaseYearBounds_TooLow[y,r,t,f], 0; force=true)
        end
        if Params.RegionalBaseYearProduction[r,t,f,y] != 0
          @constraint(model,
          Vars.ProductionByTechnologyAnnual[y,t,f,r] >= Params.RegionalBaseYearProduction[r,t,f,y]*(1-Settings.BaseYearSlack[f]) - Vars.BaseYearBounds_TooHigh[y,r,t,f],
          base_name="BYB1_RegionalBaseYearProductionLowerBound|$(y)|$(r)|$(t)|$(f)")
        end
      
        if Params.RegionalBaseYearProduction[r,t,f,y] != 0
          @constraint(model,
          Vars.ProductionByTechnologyAnnual[y,t,f,r] <= Params.RegionalBaseYearProduction[r,t,f,y] + Vars.BaseYearBounds_TooLow[r,t,f,y],
          base_name="BYB2_RegionalBaseYearProductionUpperBound|$(y)|$(r)|$(t)|$(f)")
        end
      end
    end end end
    print("Cstr: Baseyear : ",Dates.now()-start,"\n")
  end
  
  ######### Peaking Equations #############
  start=Dates.now()
  if Switch.switch_peaking_capacity == 1
    GWh_to_PJ = 0.0036
    PeakingSlack = Switch.set_peaking_slack
    MinRunShare = Switch.set_peaking_minrun_share
    RenewableCapacityFactorReduction = Switch.set_peaking_res_cf
    MinThermalShare = Switch.set_peaking_min_thermal
    for y ∈ 𝓨 for r ∈ 𝓡
      @constraint(model,
      Vars.PeakingDemand[y,r] ==
        sum(Vars.UseByTechnologyAnnual[y,t,"Power",r]/GWh_to_PJ*Params.x_peakingDemand[r,se]/8760
          #Demand per Year in PJ             to Gwh     Highest peak hour value   /number hours per year
        for se ∈ 𝓢𝓮 for t ∈ setdiff(Maps.Fuel_Tech["Power"],Params.TagTechnologyToSubsets["StorageDummies"]) if Params.x_peakingDemand[r,se] != 0 && Params.TagTechnologyToSector[t,se] != 0)
      + Params.SpecifiedAnnualDemand[r,"Power",y]/GWh_to_PJ*Params.x_peakingDemand[r,"Power"]/8760,
      base_name="PC1_PowerPeakingDemand|$(y)|$(r)")

      @constraint(model,
      Vars.PeakingCapacity[y,r] ==
        sum((sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛 ) < length(𝓛) ? Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y]*RenewableCapacityFactorReduction*(sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛)/length(𝓛)) : 0)
        + (sum(Params.CapacityFactor[r,t,l,y] for l ∈ 𝓛 ) >= length(𝓛) ? Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y] : 0)
        for t ∈ setdiff(𝓣,Params.TagTechnologyToSubsets["StorageDummies"]) if (sum(Params.OutputActivityRatio[r,t,"Power",m,y] for m ∈ Maps.Tech_MO[t]) != 0)),
        base_name="PC2_PowerPeakingCapacity|$(y)|$(r)")

      if y >Switch.set_peaking_startyear
        @constraint(model,
        Vars.PeakingCapacity[y,r] + (Switch.switch_peaking_with_trade == 1 ? sum(Vars.TotalTradeCapacity[y,"Power",rr,r] for rr ∈ 𝓡) : 0)
        + (Switch.switch_peaking_with_storages == 1 ? sum(Vars.TotalCapacityAnnual[y,t,r] for t ∈ setdiff(𝓣,Params.TagTechnologyToSubsets["StorageDummies"]) if (sum(Params.OutputActivityRatio[r,t,"Power",m,y] for m ∈ Maps.Tech_MO[t]) != 0)) : 0)
        >= Vars.PeakingDemand[y,r]*PeakingSlack,
        base_name="PC3_PeakingConstraint|$(y)|$(r)")
      end

      if Switch.switch_peaking_with_storages == 1
        @constraint(model, Vars.PeakingCapacity[y,r] >= MinThermalShare*Vars.PeakingDemand[y,r]*PeakingSlack,
        base_name="PC3b_PeakingConstraint_Thermal|$(y)|$(r)"
        )
      end
      
      if Switch.switch_peaking_minrun == 1
        for t ∈ 𝓣
          if (Params.TagTechnologyToSector[t,"Power"]==1 && Params.AvailabilityFactor[r,t,y]<=1 && 
            Params.TagDispatchableTechnology[t]==1 && Params.AvailabilityFactor[r,t,y] > 0 && 
            Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0 && 
            ((((JuMP.has_upper_bound(Vars.TotalCapacityAnnual[y,t,r])) && (JuMP.upper_bound(Vars.TotalCapacityAnnual[y,t,r]) > 0)) ||
            ((!JuMP.has_upper_bound(Vars.TotalCapacityAnnual[y,t,r])) && (!JuMP.is_fixed(Vars.TotalCapacityAnnual[y,t,r]))) ||
            ((JuMP.is_fixed(Vars.TotalCapacityAnnual[y,t,r])) && (JuMP.fix_value(Vars.TotalCapacityAnnual[y,t,r]) > 0)))) && 
            y > Switch.set_peaking_startyear)
            @constraint(model,
            sum(sum(Vars.RateOfActivity[y,l,t,m,r] for m ∈ Maps.Tech_MO[t])*Params.YearSplit[l,y] for l ∈ 𝓛 ) >= 
            sum(Vars.TotalCapacityAnnual[y,t,r]*Params.CapacityFactor[r,t,l,y]*Params.YearSplit[l,y]*Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t] for l ∈ 𝓛 )*MinRunShare,
            base_name="PC4_MinRunConstraint|$(y)|$(t)|$(r)")
          end
        end
      end
    end end
  end
  print("Cstr: Peaking : ",Dates.now()-start,"\n")


  if Switch.switch_endogenous_employment == 1

   ############### Employment effects #############
  
    @variable(model, TotalJobs[𝓡, 𝓨])

    genesysmod_employment(model,Params,Emp_Sets)
    for r ∈ 𝓡 for y ∈ 𝓨
      @constraint(model,
      sum(((Vars.NewCapacity[y,t,r]*Emp_Params.EFactorManufacturing[t,y]*Emp_Params.RegionalAdjustmentFactor[Switch.model_region,y]*Emp_Params.LocalManufacturingFactor[Switch.model_region,y])
      +(Vars.NewCapacity[y,t,r]*Emp_Params.EFactorConstruction[t,y]*Emp_Params.RegionalAdjustmentFactor[Switch.model_region,y])
      +(Vars.TotalCapacityAnnual[y,t,r]*Emp_Params.EFactorOM[t,y]*Emp_Params.RegionalAdjustmentFactor[Switch.model_region,y])
      +(Vars.UseByTechnologyAnnual[y,t,f,r]*Emp_Params.EFactorFuelSupply[t,y]))*(1-Emp_Params.DeclineRate[t,y])^YearlyDifferenceMultiplier(y,Sets)
      +((Vars.UseByTechnologyAnnual[y,"HLI_Hardcoal","Hardcoal",r]+Vars.UseByTechnologyAnnual[y,"HMI_HardCoal","Hardcoal",r]
      +(Vars.UseByTechnologyAnnual[y,"HHI_BF_BOF","Hardcoal",r])*Emp_Params.EFactorCoalJobs["Coal_Heat",y]*Emp_Params.CoalSupply[r,y]))
      +(Emp_Params.CoalSupply[r,y]*Emp_Params.CoalDigging[Switch.model_region,"Coal_Export","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]*Emp_Params.EFactorCoalJobs["Coal_Export",y]) for f ∈ 𝓕 for t ∈ Maps.Fuel_Tech[f])
      == Vars.TotalJobs[r,y],
      base_name="Jobs1_TotalJobs|$(r)|$(y)")
    end end
  end
end