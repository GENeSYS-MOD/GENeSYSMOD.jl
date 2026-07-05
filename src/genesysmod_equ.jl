"""
Internal function used in the run process to define the model constraints.
"""
function genesysmod_equ(model,Sets,Params, Vars,Emp_Sets,Settings,Switch, Maps; storage_ratio=0, Params_full=nothing, Region_Full=nothing)

  considered_duals = String[]

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

  if !(Switch.switch_dispatch isa NoDispatch)
    DummyEmissionInfeasibility = @variable(model, DummyEmissionInfeasibility[𝓨,𝓔,𝓡] >=0, container=DenseArray)
  end

  start=Dates.now()

  @objective(model, MOI.MIN_SENSE, sum(Vars.TotalDiscountedCost[y,r] for y ∈ 𝓨 for r ∈ 𝓡)
  + sum(Vars.DiscountedAnnualTotalTradeCosts[y,r] for y ∈ 𝓨 for r ∈ 𝓡)
  + sum(Vars.DiscountedNewTradeCapacityCosts[y,f,r,rr] for y ∈ 𝓨 for (f,r,rr) ∈ Maps.Set_Fuel_Regions)
  + sum(Vars.DiscountedAnnualCurtailmentCost[y,f,r] for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡)
  + (Switch.switch_base_year_bounds_debugging == 1 ? sum(Vars.BaseYearBounds_TooHigh[r,t,f,y]*1000 for y ∈ 𝓨 for r ∈ 𝓡 for (t,f) ∈ Maps.Set_Tech_FuelOut) : 0)
  + (Switch.switch_base_year_bounds_debugging == 1 ? sum(Vars.BaseYearBounds_TooLow[r,t,f,y]*1000 for y ∈ 𝓨 for r ∈ 𝓡 for (t,f) ∈ Maps.Set_Tech_FuelOut) : 0)
  + (Switch.switch_base_year_bounds_debugging == 1 ? sum(Vars.HeatingSlack[r,y]*1000 for r ∈ 𝓡 for y ∈ 𝓨) : 0)
  - sum(Vars.DiscountedSalvageValueTransmission[y,r] for y ∈ 𝓨 for r ∈ 𝓡)
  + (Switch.switch_dispatch isa NoDispatch ? 0 : sum(DummyEmissionInfeasibility[y,e,r] * 99999 for y ∈ 𝓨 for r ∈ 𝓡 for e ∈ 𝓔)))
  print("Cstr: Cost : ",Dates.now()-start,"\n")


  #########################
  # Parameter assignments #
  #########################

  start=Dates.now()

  LoopSetOutput = Dict()
  LoopSetInput = Dict()
  for y ∈ 𝓨, f ∈ 𝓕, r ∈ 𝓡
      slice_out = Params.OutputActivityRatio[r,:,f,:,y]
      slice_in  = Params.InputActivityRatio[r,:,f,:,y]

      # Get the original labels from the axes
      out_i_labels = axes(slice_out, 1)
      out_j_labels = axes(slice_out, 2)

      in_i_labels = axes(slice_in, 1)
      in_j_labels = axes(slice_in, 2)

      # Find positions where value > 0
      LoopSetOutput[(r,f,y)] = [(out_i_labels[i[1]], out_j_labels[i[2]]) for i in findall(>(0), slice_out.data)]
      LoopSetInput[(r,f,y)]  = [(in_i_labels[i[1]],  in_j_labels[i[2]])  for i in findall(>(0), slice_in.data)]
  end

  print("LoopSets : ",Dates.now()-start,"\n")
  start=Dates.now()

  # Sum CapacityFactor over 𝓛 on .data with axis positions resolved once
  # (was one 4-key axis-hash per element). Plain sequential accumulation in 𝓛
  # order keeps the floats bit-identical to the original generator sum —
  # SumCapacityFactor feeds >0 / <length(𝓛) threshold checks downstream.
  SumCapacityFactor = let pos = ax -> Dict(v => i for (i, v) ∈ enumerate(ax)),
      cfd = Params.CapacityFactor.data, cfax = map(pos, axes(Params.CapacityFactor))
      l_cf = [cfax[3][l] for l ∈ 𝓛]
      scf = Array{Float64}(undef, length(𝓡), length(𝓣), length(𝓨))
      for (yi, y) ∈ enumerate(𝓨), (ti, t) ∈ enumerate(𝓣), (ri, r) ∈ enumerate(𝓡)
          r_cf = cfax[1][r]; t_cf = cfax[2][t]; y_cf = cfax[4][y]
          s = cfd[r_cf, t_cf, l_cf[1], y_cf]
          @inbounds for li ∈ 2:length(l_cf)
              s += cfd[r_cf, t_cf, l_cf[li], y_cf]
          end
          scf[ri, ti, yi] = s
      end
      JuMP.Containers.DenseAxisArray(scf, 𝓡, 𝓣, 𝓨)
  end

  # Precomputed filtered subsets reused across many constraint sections
  StorageDummies_techs = intersect(𝓣, Params.Tags.TagTechnologyToSubsets["StorageDummies"])
  techs_by_sector = Dict(se => [t for t ∈ 𝓣 if Params.Tags.TagTechnologyToSector[t,se] != 0] for se ∈ 𝓢𝓮)
  pairs_by_fuel = Dict{String, Vector{Tuple{String,String}}}()
  fuel_rr_by_r1 = Dict{String, Vector{Tuple{String,String}}}()
  for (f_r,r1,r2) ∈ Maps.Set_Fuel_Regions
      push!(get!(pairs_by_fuel, f_r, Tuple{String,String}[]), (r1,r2))
      push!(get!(fuel_rr_by_r1, r1, Tuple{String,String}[]), (f_r,r2))
  end
  # (tech,mode) pairs that can charge / discharge each storage (region-free, nonzero in some year)
  charge_tm    = Dict(s => [(t,m) for t ∈ StorageDummies_techs for m ∈ Maps.Tech_MO[t]
                            if any(Params.TechnologyToStorage[t,s,m,y]   != 0 for y ∈ 𝓨)] for s ∈ 𝓢)
  discharge_tm = Dict(s => [(t,m) for t ∈ StorageDummies_techs for m ∈ Maps.Tech_MO[t]
                            if any(Params.TechnologyFromStorage[t,s,m,y] != 0 for y ∈ 𝓨)] for s ∈ 𝓢)

  function CanFuelBeUsedByModeByTech(y, f, r,t,m)
    temp = Params.InputActivityRatio[r,t,f,m,y]*
    Params.TotalAnnualMaxCapacity[r,t,y] *
    SumCapacityFactor[r,t,y] *
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
    SumCapacityFactor[r,t,y] *
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
    SumCapacityFactor[r,t,y] *
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
    SumCapacityFactor[r,t,y] *
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
    SumCapacityFactor[r,t,y] *
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
    SumCapacityFactor[r,t,y] *
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
    SumCapacityFactor[r,t,y] *
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

  # A fuel that can be used/demanded but not produced is time-independent (derived
  # base). On top of that, the per-fuel data tag Par_TagTimeIndependentFuel marks
  # additional fuels as time-independent — replacing the old hard-coded
  # `Info == "reduced"` override list with an input-data parameter.
  TagTimeIndependentFuel = CanFuelBeUsedOrDemanded.*(1 .- CanFuelBeProduced)
  for f ∈ 𝓕
    if Params.TagTimeIndependentFuel[f] == 1
      TagTimeIndependentFuel[:,f,:] .= 1
    end
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
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
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

  cap_is_fixed = JuMP.Containers.DenseAxisArray(
      Bool[JuMP.is_fixed(Vars.TotalCapacityAnnual[y,t,r]) for y ∈ 𝓨, t ∈ 𝓣, r ∈ 𝓡], 𝓨, 𝓣, 𝓡)
  cap_fix_val  = JuMP.Containers.DenseAxisArray(
      Float64[cap_is_fixed[y,t,r] ? JuMP.fix_value(Vars.TotalCapacityAnnual[y,t,r]) : 0.0 for y ∈ 𝓨, t ∈ 𝓣, r ∈ 𝓡], 𝓨, 𝓣, 𝓡)
  cap_has_ub   = JuMP.Containers.DenseAxisArray(
      Bool[JuMP.has_upper_bound(Vars.TotalCapacityAnnual[y,t,r]) for y ∈ 𝓨, t ∈ 𝓣, r ∈ 𝓡], 𝓨, 𝓣, 𝓡)
  cap_ub       = JuMP.Containers.DenseAxisArray(
      Float64[cap_has_ub[y,t,r] ? JuMP.upper_bound(Vars.TotalCapacityAnnual[y,t,r]) : 0.0 for y ∈ 𝓨, t ∈ 𝓣, r ∈ 𝓡], 𝓨, 𝓣, 𝓡)

  CanBuildTechnology = JuMP.Containers.DenseAxisArray(zeros(length(𝓨), length(𝓣), length(𝓡)), 𝓨, 𝓣, 𝓡)
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    temp=  (Params.TotalAnnualMaxCapacity[r,t,y] *
    SumCapacityFactor[r,t,y] *
    Params.AvailabilityFactor[r,t,y] *
    Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] *
    Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y])
    if (temp > 0) && ((!cap_is_fixed[y,t,r] && !cap_has_ub[y,t,r]) || (cap_is_fixed[y,t,r] && cap_fix_val[y,t,r] > 0) || (cap_has_ub[y,t,r] && cap_ub[y,t,r] > 0))
      CanBuildTechnology[y,t,r] = 1
    end
  end end end

  start=Dates.now()
  for y ∈ 𝓨, (t,m) ∈ Maps.Set_Tech_MO, r ∈ 𝓡
    if (Params.AvailabilityFactor[r,t,y] == 0) ||
      (Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] == 0) ||
      (Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] == 0) ||
      (Params.TotalAnnualMaxCapacity[r,t,y] == 0) ||
      (cap_has_ub[y,t,r] && cap_ub[y,t,r] == 0) ||
      (cap_is_fixed[y,t,r] && cap_fix_val[y,t,r] == 0) ||
      (sum(Params.OutputActivityRatio[r,t,f,m,y] for f ∈ 𝓕) == 0 && sum(Params.InputActivityRatio[r,t,f,m,y] for f ∈ 𝓕) == 0)
        for l ∈ 𝓛
            JuMP.fix.(Vars.RateOfActivity[y,l,t,m,r], 0; force=true)
        end
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
        sum(Vars.RateOfActivity[y,l,t,m,r] for m ∈ Maps.Tech_MO[t]) == Vars.TotalActivityPerYear[r,l,t,y] - Vars.DispatchDummy[r,l,t,y]*Params.Tags.TagDispatchableTechnology[t]- Vars.CurtailedCapacity[r,l,t,y]*Params.CapacityToActivityUnit[t],
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
          sum(Vars.RateOfActivity[y,l,t,m,r] for m ∈ Maps.Tech_MO[t]) == Vars.TotalCapacityAnnual[y,t,r] * Params.CapacityFactor[r,t,l,y] * Params.CapacityToActivityUnit[t] - Vars.DispatchDummy[r,l,t,y] * Params.Tags.TagDispatchableTechnology[t] - Vars.CurtailedCapacity[r,l,t,y] * Params.CapacityToActivityUnit[t],
          base_name="CA3b_RateOfTotalActivity|$(r)|$(l)|$(t)|$(y)")
      end
    end
  end

  for y ∈ 𝓨 for t ∈ 𝓣 for  r ∈ 𝓡
    if CanBuildTechnology[y,t,r] > 0
      for l ∈ 𝓛
        @constraint(model, Vars.TotalCapacityAnnual[y,t,r] >= Vars.CurtailedCapacity[r,l,t,y], base_name="CA3c_CurtailedCapacity|$(r)|$(l)|$(t)|$(y)")
      end
    else
      for l ∈ 𝓛
        JuMP.fix(Vars.CurtailedCapacity[r,l,t,y], 0; force=true)
      end
    end
  end end end
  print("Cstr: Cap Adequacy A3 : ",Dates.now()-start,"\n")


  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for  r ∈ 𝓡
    if (Params.AvailabilityFactor[r,t,y] < 1) &&
      (Params.TotalAnnualMaxCapacity[r,t,y] > 0) &&
      (Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0) &&
      ((cap_has_ub[y,t,r] && cap_ub[y,t,r] > 0) ||
      (!cap_has_ub[y,t,r] && !cap_is_fixed[y,t,r]) ||
      (cap_is_fixed[y,t,r] && cap_fix_val[y,t,r] > 0))
      @constraint(model, sum(sum(Vars.RateOfActivity[y,l,t,m,r]  for m ∈ Maps.Tech_MO[t]) * Params.YearSplit[l,y] for l ∈ 𝓛) <= sum(Vars.TotalCapacityAnnual[y,t,r]*Params.CapacityFactor[r,t,l,y]*Params.YearSplit[l,y]*Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t] for l ∈ 𝓛), base_name="CA5_CapacityAdequacy|$(y)|$(t)|$(r)")
    end
  end end end
  print("Cstr: Cap Adequacy B : ",Dates.now()-start,"\n")

  ############### Energy Balance A #############

  start=Dates.now()
  region2s_map = Dict{Tuple{String,String}, Vector{String}}()
  for (f_r,r1,r2) ∈ Maps.Set_Fuel_Regions
      push!(get!(region2s_map, (f_r,r1), String[]), r2)
  end
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    region2s = get(region2s_map, (f,r), String[])
    if !isempty(region2s)
        for rr ∈ region2s
            for l ∈ 𝓛
                @constraint(model, Vars.Import[y,l,f,r,rr] == Vars.Export[y,l,f,rr,r], base_name="EB1_TradeBalanceEachTS|$(y)|$(l)|$(f)|$(r)|$(rr)")
            end
        end

        if (sum(Params.TradeRoute[r,rr,f,y] for rr ∈ region2s) == 0) || (Params.Tags.TagCanFuelBeTraded[f] == 0)
            JuMP.fix.(Vars.NetTrade[y,:,f,r], 0; force=true)
        else
            for l ∈ 𝓛
                @constraint(model, sum(Vars.Export[y,l,f,r,rr]*(1+Params.TradeLossBetweenRegions[r,rr,f,y]) - Vars.Import[y,l,f,r,rr] for rr ∈ region2s) == Vars.NetTrade[y,l,f,r],
                base_name="EB4_NetTradeBalance|$(y)|$(l)|$(f)|$(r)")
            end
        end
    else
        JuMP.fix.(Vars.NetTrade[y,:,f,r], 0; force=true)
    end
  end end end

  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    if TagTimeIndependentFuel[y,f,r] == 0
        for l ∈ 𝓛
            @constraint(model,sum(Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] for (t,m) ∈ LoopSetOutput[(r,f,y)])* Params.YearSplit[l,y] ==
        (Params.Demand[y,l,f,r] + sum(Vars.RateOfActivity[y,l,t,m,r]*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y] for (t,m) ∈ LoopSetInput[(r,f,y)])*Params.YearSplit[l,y] + Vars.NetTrade[y,l,f,r]),
            base_name="EB2_EnergyBalanceEachTS|$(y)|$(l)|$(f)|$(r)")
            push!(considered_duals, "EB2_EnergyBalanceEachTS|$(y)|$(l)|$(f)|$(r)")
        end
    end
  end end end

  print("Cstr: Energy Balance A1 : ",Dates.now()-start,"\n")
  start=Dates.now()
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    @constraint(model, Vars.CurtailedEnergyAnnual[y,f,r] == sum(Vars.CurtailedCapacity[r,l,t,y] * Params.OutputActivityRatio[r,t,f,m,y] * Params.YearSplit[l,y] * Params.CapacityToActivityUnit[t] for l ∈ 𝓛 for (t,m) ∈ LoopSetOutput[(r,f,y)]),
    base_name="EB6_AnnualEnergyCurtailment|$(y)|$(f)|$(r)")

    if Params.SelfSufficiency[r,f,y] != 0
      @constraint(model, sum(Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y]*Params.YearSplit[l,y] for l ∈ 𝓛 for (t,m) ∈ LoopSetOutput[(r,f,y)]) ==
      (Params.SpecifiedAnnualDemand[r,f,y] + sum(Vars.RateOfActivity[y,l,t,m,r]*Params.InputActivityRatio[r,t,f,m,y]*Params.TimeDepEfficiency[r,t,l,y]*Params.YearSplit[l,y] for l ∈ 𝓛 for (t,m) ∈ LoopSetInput[(r,f,y)]))*Params.SelfSufficiency[r,f,y],
      base_name="EB7_AnnualSelfSufficiency|$(y)|$(f)|$(r)")
    end
  end end end
  print("Cstr: Energy Balance A2 : ",Dates.now()-start,"\n")

  ############### Energy Balance B #############

  start=Dates.now()
  for y ∈ 𝓨 for f ∈ 𝓕 for r ∈ 𝓡
    if (sum(Params.TradeRoute[r,rr,f,y] for rr ∈ 𝓡) > 0) && (Params.Tags.TagCanFuelBeTraded[f] != 0)
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


  for i ∈ eachindex(𝓨)
    for (f,r,rr) ∈ Maps.Set_Fuel_Regions
      if f == "Power"
        for l ∈ 𝓛
          @constraint(model, (Vars.Import[𝓨[i],l,"Power",r,rr]) <= Vars.TotalTradeCapacity[𝓨[i],"Power",rr,r]*Params.YearSplit[l,𝓨[i]]*31.536 , base_name="TrC1_TradeCapacityPowerLinesImport|$(𝓨[i])|$(l)_Power|$(r)|$(rr)")
        end
      end
      if Params.TradeCapacityGrowthCosts[r,rr,f] != 0
        @constraint(model, Vars.NewTradeCapacity[𝓨[i],f,r,rr]*Params.TradeCapacityGrowthCosts[r,rr,f]*Params.TradeRoute[r,rr,f,𝓨[i]] == Vars.NewTradeCapacityCosts[𝓨[i],f,r,rr], base_name="TrC4_NewTradeCapacityCosts|$(𝓨[i])|$(f)|$(r)|$(rr)")
        @constraint(model, Vars.NewTradeCapacityCosts[𝓨[i],f,r,rr]/((1+Settings.GeneralDiscountRate[r])^(𝓨[i]-Switch.StartYear+0.5)) == Vars.DiscountedNewTradeCapacityCosts[𝓨[i],f,r,rr], base_name="TrC5_DiscountedNewTradeCapacityCosts|$(𝓨[i])|$(f)|$(r)|$(rr)")
      end
    end
    #= for f ∈ 𝓕
      if Params.TradeRoute[r,rr,f,𝓨[i]] != 0 && Params.TradeCapacityGrowthCosts[r,rr,f] == 0
        JuMP.fix(Vars.DiscountedNewTradeCapacityCosts[𝓨[i],f,r,rr],0; force=true)
      end
    end =#

    if Switch.switch_dispatch isa NoDispatch
      for (f,r,rr) ∈ Maps.Set_Fuel_Regions
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

    ### Trade Capacities for H2 and Natural Gas, when initially no capacities existed, so that the model has the ability to build additional capacities
    if i > 1
      for (r,rr) ∈ get(pairs_by_fuel, "Gas_Natural", Tuple{String,String}[])
        @constraint(model, (Params.TradeCapacity[r,rr,"Gas_Natural",𝓨[i]] == 0 ? 100 : 0)+(Params.GrowthRateTradeCapacity[r,rr,"Gas_Natural",𝓨[i]]*YearlyDifferenceMultiplier(𝓨[i],Sets))*Vars.TotalTradeCapacity[𝓨[i-1],"Gas_Natural",r,rr] >= Vars.NewTradeCapacity[𝓨[i],"Gas_Natural",r,rr],
        base_name="TrC4a_NewTradeCapacityLimitNatGas|$(𝓨[i])|Gas_Natural|$(r)|$(rr)")
      end
      for (r,rr) ∈ get(pairs_by_fuel, "H2", Tuple{String,String}[])
        @constraint(model, (Params.TradeCapacity[r,rr,"H2",𝓨[i]] == 0 ? 50 : 0)+(Params.GrowthRateTradeCapacity[r,rr,"H2",𝓨[i]]*YearlyDifferenceMultiplier(𝓨[i],Sets))*Vars.TotalTradeCapacity[𝓨[i-1],"H2",r,rr] >= Vars.NewTradeCapacity[𝓨[i],"H2",r,rr],
        base_name="TrC5a_NewTradeCapacityLimitH2|$(𝓨[i])|H2|$(r)|$(rr)")
      end
    else
      # first modelled year: cap new trade capacity where none existed.
      # only build at i == 1, otherwise these (𝓨[1]) rows duplicate every year.
      for (r,rr) ∈ get(pairs_by_fuel, "Gas_Natural", Tuple{String,String}[])
          @constraint(model, (Params.TradeCapacity[r,rr,"Gas_Natural",𝓨[1]] == 0 ? 100 : 0) >= Vars.NewTradeCapacity[𝓨[1],"Gas_Natural",r,rr],
          base_name="TrC4a_NewTradeCapacityLimitNatGas|$(𝓨[1])|Gas_Natural|$(r)|$(rr)")
      end
      for (r,rr) ∈ get(pairs_by_fuel, "H2", Tuple{String,String}[])
          @constraint(model, (Params.TradeCapacity[r,rr,"H2",𝓨[1]] == 0 ? 50 : 0) >= Vars.NewTradeCapacity[𝓨[1],"H2",r,rr],
          base_name="TrC5a_NewTradeCapacityLimitH2|$(𝓨[1])|H2|$(r)|$(rr)")
      end
    end
    for (f,r,rr) ∈ Maps.Set_Fuel_Regions
      if Params.TradeCapacityGrowthCosts[r,rr,f] > 0 && f != "Power"
        @constraint(model, sum(Vars.Import[𝓨[i],l,f,rr,r] for l ∈ 𝓛) <= Vars.TotalTradeCapacity[𝓨[i],f,r,rr],
        base_name="TrC7_TradeCapacityLimitNonPower$(𝓨[i])|$(f)|$(r)|$(rr)")
      end
      if Params.TradeRoute[r,rr,"Power",𝓨[i]] > 0 && f == "Power"
        @constraint(model, Vars.NewTradeCapacity[𝓨[i],"Power",r,rr] >= Vars.NewTradeCapacity[𝓨[i],"Power",rr,r] * Switch.set_symmetric_transmission,
        base_name="TrC6_SymmetricalTransmissionExpansion|$(𝓨[i])|$(r)|$(rr)")
      end
    end

    for (f,r,rr) ∈ Maps.Set_Fuel_Regions
        if Params.TradeRoute[r,rr,f,𝓨[i]] != 0 && (Params.Tags.TagCanFuelBeTraded[f] != 0) && (Params.GrowthRateTradeCapacity[r,rr,f,𝓨[i]] == 0 || i == 1)
            JuMP.fix(Vars.NewTradeCapacity[𝓨[i],f,r,rr],0; force=true)
        end
    end
  #=     for f ∈ 𝓕
      if f != "Power"
        JuMP.fix(Vars.NewTradeCapacity[𝓨[i],f,r,rr],0; force=true)
      end
      if Params.TradeRoute[r,rr,f,𝓨[i]] == 0 || f != "Power"
        JuMP.fix(Vars.DiscountedNewTradeCapacityCosts[𝓨[i],f,r,rr],0; force=true)
      end
    end =#
  end


  ############## Pipeline-specific Capacity Accounting #############
  # H2 / LH2 dedicated trade-capacity limits (GAMS TrPl1aa, TrPl1aaa)
  for y ∈ 𝓨 for l ∈ 𝓛 for (f,r,rr) ∈ Maps.Set_Fuel_Regions
    if f == "H2"
      @constraint(model, Vars.Import[y,l,"H2",rr,r] <= Vars.TotalTradeCapacity[y,"H2",r,rr]*Params.YearSplit[l,y],
      base_name="TrPl1aa_TradeCapacityPipelinesLines|$(y)|$(l)|$(r)|$(rr)")
    elseif f == "LH2"
      @constraint(model, Vars.Import[y,l,"LH2",rr,r] <= Vars.TotalTradeCapacity[y,"LH2",r,rr]*Params.YearSplit[l,y],
      base_name="TrPl1aaa_TradeCapacityTrucks|$(y)|$(l)|$(r)|$(rr)")
    end
  end end end

  # one (r,rr) per gas-trade pair: Set_Fuel_Regions has a triple per gas fuel,
  # so dropping the fuel repeats each pair -> unique() avoids duplicate TrPA1* rows.
  set_regions = unique([(y,z) for (x,y,z) ∈ Maps.Set_Fuel_Regions if x in intersect(𝓕,Params.Tags.TagFuelToSubsets["GasFuels"])])
  for y ∈ 𝓨 for l ∈ 𝓛 for (r,rr) ∈ set_regions
    fuels= [x for (x,y,z) ∈ Maps.Set_Fuel_Regions if (y == r) && (z == rr) && (x in intersect(𝓕,Params.Tags.TagFuelToSubsets["GasFuels"]))]
    if Switch.switch_hydrogen_blending_share == 0
        @constraint(model, sum(Vars.Import[y,l,f,rr,r] for f ∈ setdiff(fuels,["H2_Blend"])) <= Vars.TotalTradeCapacity[y,"Gas_Natural",r,rr]*Params.YearSplit[l,y],
        base_name="TrPA1a_TradeCapacityPipelineAccounting|$(y)|$(l)|$(r)|$(rr)")

    elseif (Switch.switch_hydrogen_blending_share < 1) && (Switch.switch_hydrogen_blending_share > 0)
        dedicated_h2 = Switch.switch_hydrogen_blending_share
        @constraint(model, sum(Vars.Import[y,l,f,rr,r] for f ∈ fuels if f != "H2_Blend") + Vars.Import[y,l,"H2_Blend",rr,r]*(11.4/3.0) <= Vars.TotalTradeCapacity[y,"Gas_Natural",r,rr]*Params.YearSplit[l,y],
        base_name="TrPA1b_TradeCapacityPipelineAccountingGasFuels|$(y)|$(l)|$(r)|$(rr)")
        @constraint(model, Vars.Import[y,l,"H2_Blend",rr,r] <= (dedicated_h2/((1-dedicated_h2)*(11.4/3.0))) * sum(Vars.Import[y,l,f,rr,r] for f ∈ fuels if f != "H2_Blend"),
        base_name="TrPA1c_TradeCapacityPipelineAccountingH2Blend|$(y)|$(l)|$(r)|$(rr)")
    elseif Switch.switch_hydrogen_blending_share == 1
        @constraint(model, sum(Vars.Import[y,l,f,rr,r] for f ∈ fuels if f != "H2_Blend") + Vars.Import[y,l,"H2_Blend",rr,r]*(11.4/3.0) <= Vars.TotalTradeCapacity[y,"Gas_Natural",r,rr]*Params.YearSplit[l,y],
        base_name="TrPA1d_TradeCapacityPipelineAccountingCombined|$(y)|$(l)|$(r)|$(rr)")
    end
  end end end

  ######## Gas-specific import restrictions over the year

  for y ∈ 𝓨 for l ∈ 𝓛 for r ∈ 𝓡
    @constraint(model, Vars.RateOfActivity[y,l,"Z_Import_H2",1,r] <= sum(Vars.RateOfActivity[y,ll,"Z_Import_H2",1,r] for ll ∈ 𝓛)*Params.YearSplit[l,y]*1.05,
    base_name= "TrPA2a_FlatH2Imports|$(y)|$(l)|$(r)")
    @constraint(model, Vars.RateOfActivity[y,l,"Z_Import_Gas",1,r] <= sum(Vars.RateOfActivity[y,ll,"Z_Import_Gas",1,r] for ll ∈ 𝓛)*Params.YearSplit[l,y]*1.05,
    base_name= "TrPA2b_FlatGasImports|$(y)|$(l)|$(r)")
  end end end
  ############### Trading Costs #############

  for y ∈ 𝓨 for r ∈ 𝓡
    set_fuel_region2 = get(fuel_rr_by_r1, r, Tuple{String,String}[])
    if !isempty(set_fuel_region2) && sum(Params.TradeRoute[r,rr,f,y] for (f,rr) ∈ set_fuel_region2) > 0
      @constraint(model, sum(Vars.Import[y,l,f,r,rr] * Params.TradeCosts[r,f,y,rr] for (f,rr) ∈ set_fuel_region2 for l ∈ 𝓛) == Vars.AnnualTotalTradeCosts[y,r], base_name="TC1_AnnualTradeCosts|$(y)|$(r)")
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

  for i ∈ eachindex(𝓨) for r ∈ 𝓡
    for (t,f) ∈ Maps.Set_Tech_FuelOut
      if sum(Params.OutputActivityRatio[r,t,f,m,𝓨[i]] for m ∈ 𝓜) > 0 &&
        Params.AvailabilityFactor[r,t,𝓨[i]] > 0 &&
        Params.TotalAnnualMaxCapacity[r,t,𝓨[i]] > 0 &&
        Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0 &&
        ((cap_has_ub[𝓨[i],t,r] && cap_ub[𝓨[i],t,r] > 0) ||
        (!cap_has_ub[𝓨[i],t,r] && !cap_is_fixed[𝓨[i],t,r]) ||
        (cap_is_fixed[𝓨[i],t,r] && cap_fix_val[𝓨[i],t,r] > 0))
        @constraint(model, sum(sum(Vars.RateOfActivity[𝓨[i],l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,𝓨[i]] for m ∈ Maps.Tech_MO[t] if Params.OutputActivityRatio[r,t,f,m,𝓨[i]] != 0)* Params.YearSplit[l,𝓨[i]] for l ∈ 𝓛) == Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r], base_name= "ACC2_FuelProductionByTechnologyAnnual|$(𝓨[i])|$(t)|$(f)|$(r)")
      else
        JuMP.fix(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r],0;force=true)
      end
    end
    for (t,f) ∈ Maps.Set_Tech_FuelIn
      if sum(Params.InputActivityRatio[r,t,f,m,𝓨[i]] for m ∈ 𝓜) > 0 &&
        Params.AvailabilityFactor[r,t,𝓨[i]] > 0 &&
        Params.TotalAnnualMaxCapacity[r,t,𝓨[i]] > 0 &&
        Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0 &&
        ((cap_has_ub[𝓨[i],t,r] && cap_ub[𝓨[i],t,r] > 0) ||
        (!cap_has_ub[𝓨[i],t,r] && !cap_is_fixed[𝓨[i],t,r]) ||
        (cap_is_fixed[𝓨[i],t,r] && cap_fix_val[𝓨[i],t,r] > 0))
        @constraint(model, sum(sum(Vars.RateOfActivity[𝓨[i],l,t,m,r]*Params.InputActivityRatio[r,t,f,m,𝓨[i]] for m ∈ Maps.Tech_MO[t] if Params.InputActivityRatio[r,t,f,m,𝓨[i]] != 0)* Params.YearSplit[l,𝓨[i]] for l ∈ 𝓛) == Vars.UseByTechnologyAnnual[𝓨[i],t,f,r], base_name= "ACC3_FuelUseByTechnologyAnnual|$(𝓨[i])|$(t)|$(f)|$(r)")
      else
        JuMP.fix(Vars.UseByTechnologyAnnual[𝓨[i],t,f,r],0;force=true)
      end
    end
  end end

  print("Cstr: Acc. Tech. 1 : ",Dates.now()-start,"\n")

  ############### Capital Costs #############

  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    @constraint(model, Params.CapitalCost[r,t,y] * Vars.NewCapacity[y,t,r] == Vars.CapitalInvestment[y,t,r], base_name="CC1_UndiscountedCapitalInvestments|$(y)|$(t)|$(r)")
    @constraint(model, Vars.CapitalInvestment[y,t,r]/((1+Settings.TechnologyDiscountRate[r,t])^(y-Switch.StartYear)) == Vars.DiscountedCapitalInvestment[y,t,r], base_name="CC2_DiscountedCapitalInvestments|$(y)|$(t)|$(r)")
  end end end
  print("Cstr: Cap. Cost. : ",Dates.now()-start,"\n")

  ############### Investment & Capacity Limits / Smoothing Constraints #############
  if Switch.switch_dispatch isa NoDispatch
    if Switch.switch_investLimit == 1
      for i ∈ eachindex(𝓨)
        if 𝓨[i] > Switch.StartYear
          @constraint(model,
          sum(Vars.CapitalInvestment[𝓨[i],t,r] for t ∈ 𝓣 for r ∈ 𝓡) <= 1/(max(𝓨...)-Switch.StartYear)*YearlyDifferenceMultiplier(𝓨[i-1],Sets)*Settings.InvestmentLimit*sum(Vars.CapitalInvestment[yy,t,r] for yy ∈𝓨 for t ∈ 𝓣 for r ∈ 𝓡),
          base_name="SC1_SpreadCapitalInvestmentsAcrossTime|$(𝓨[i])")
          for r ∈ 𝓡
            for t ∈ intersect(Sets.Technology, Params.Tags.TagTechnologyToSubsets["Renewables"])
                if 𝓨[i] > 2025
                    # SC2 must never cap below the new-build needed to stay on the
                    # TotalAnnualMinCapacity path: a tight TotalAnnualMaxCapacity
                    # (max ~ min) makes f*max alone starve a steep exogenous min ->
                    # infeasible under switch_investLimit. min_inc is a constant
                    # from input params (min, residual); keeps the model linear.
                    rr_y  = max(0.0, Params.TotalAnnualMinCapacity[r,t,𝓨[i]]   - Params.ResidualCapacity[r,t,𝓨[i]])
                    rr_ym = max(0.0, Params.TotalAnnualMinCapacity[r,t,𝓨[i-1]] - Params.ResidualCapacity[r,t,𝓨[i-1]])
                    min_inc = max(0.0, rr_y - rr_ym)
                    @constraint(model,
                    Vars.NewCapacity[𝓨[i],t,r] <= max(YearlyDifferenceMultiplier(𝓨[i-1],Sets)*Settings.NewRESCapacity*Params.TotalAnnualMaxCapacity[r,t,𝓨[i]], min_inc),
                    base_name="SC2_LimitAnnualCapacityAdditions|$(𝓨[i])|$(r)|$(t)")
                end
            end
            for (t,f) ∈ Maps.Set_Tech_FuelOut
              if Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]] != 0
                if t ∈ Params.Tags.TagTechnologyToSubsets["PhaseInSet"] && f != "Heat_District"
                    @constraint(model,
                    Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r] >= Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r]*Settings.PhaseIn[𝓨[i]]*(Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]] > 0 ? Params.SpecifiedAnnualDemand[r,f,𝓨[i]]/Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]] : 1),
                    base_name="SC3_SmoothingRenewableIntegration|$(𝓨[i])|$(r)|$(t)|$(f)")
                end

                if t ∈ Params.Tags.TagTechnologyToSubsets["PhaseOutSet"]
                    @constraint(model,
                    Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r] <= Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r]*Settings.PhaseOut[𝓨[i]]*(Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]] > 0 ? Params.SpecifiedAnnualDemand[r,f,𝓨[i]]/Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]] : 1),
                    base_name="SC3_SmoothingFossilPhaseOuts|$(𝓨[i])|$(r)|$(t)|$(f)")
                end
              end
            end
            for f ∈ unique([y for (x,y) ∈ Maps.Set_Tech_FuelOut])
              techs=[x for (x,y) ∈ Maps.Set_Tech_FuelOut if y == f]
              if Params.ProductionGrowthLimit[f,𝓨[i]]>0
                if f ∉ Params.Tags.TagFuelToSubsets["TransportFuels"]
                    @constraint(model,
                    sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r]-Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ techs if (Params.Tags.RETagTechnology[r,t,𝓨[i]] == 1)) <=
                    YearlyDifferenceMultiplier(𝓨[i-1],Sets)*Params.ProductionGrowthLimit[f,𝓨[i]]*sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ techs)-sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ intersect(techs,Params.Tags.TagTechnologyToSubsets["StorageDummies"])),
                    base_name="SC4a_RelativeTechnologyPhaseInLimit|$(𝓨[i])|$(r)|$(f)")
                elseif 𝓨[i] > 2025
                    # GAMS guards SC4b with TagModalTypeToModalGroups(mt,'TransportModes'):
                    # only the parent transport modaltypes, NOT the RE/CONV subgroups.
                    # Without this, the limit also caps RE-subgroup (e.g. MT_PSNG_ROAD_RE)
                    # growth, throttling BEV/H2 and forcing PHEV.
                    for mt ∈ 𝓜𝓽
                      if Params.Tags.TagModalTypeToModalGroups[mt,"TransportModes"] == 1
                        @constraint(model,
                        sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r]-Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ techs if (Params.Tags.RETagTechnology[r,t,𝓨[i]] == 1) && (Params.Tags.TagTechnologyToModalType[t,1,mt] == 1)) <=
                        YearlyDifferenceMultiplier(𝓨[i-1],Sets)*Params.ProductionGrowthLimit[f,𝓨[i]]*sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ techs if Params.Tags.TagTechnologyToModalType[t,1,mt] == 1),
                        base_name="SC4b_RelativeTechnologyPhaseInLimit_Transport|$(𝓨[i])|$(r)|$(f)|$(mt)")
                      end
                    end
                end
                @constraint(model,
                sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r]-Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ intersect(techs,Params.Tags.TagTechnologyToSubsets["StorageDummies"])) <= YearlyDifferenceMultiplier(𝓨[i-1],Sets)*(Params.ProductionGrowthLimit[f,𝓨[i]]+Settings.StorageLimitOffset)*sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ techs),
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
          techs=[x for (x,y) ∈ Maps.Set_Tech_FuelOut if y == f]
          @constraint(model,
          sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r]-Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ intersect(techs,Params.Tags.TagTechnologyToSubsets["CCS"])) <= YearlyDifferenceMultiplier(𝓨[i-1],Sets)*(Params.ProductionGrowthLimit["Air",𝓨[i]])*sum(Vars.ProductionByTechnologyAnnual[𝓨[i-1],t,f,r] for t ∈ techs),
          base_name="CCS1_CCSAdditionLimit|$(𝓨[i])|$(r)|$(f)")
        end end

        if sum(Params.RegionalCCSLimit[r] for r ∈ 𝓡)>0
          @constraint(model,
          sum(sum( Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r]*Params.EmissionContentPerFuel[f,e]*Params.InputActivityRatio[r,t,f,m,y]*YearlyDifferenceMultiplier(y,Sets)*((Params.EmissionActivityRatio[r,t,m,e,y]>0 ? (1-Params.EmissionActivityRatio[r,t,m,e,y]) : 0)+
          (Params.EmissionActivityRatio[r,t,m,e,y] < 0 ? (-1)*Params.EmissionActivityRatio[r,t,m,e,y] : 0)) for f ∈ Maps.Tech_Fuel[t] for m ∈ Maps.Tech_MO[t] for e ∈ 𝓔) for y ∈ 𝓨 for t ∈ intersect(𝓣,Params.Tags.TagTechnologyToSubsets["CCS"]) ) <= Params.RegionalCCSLimit[r],
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
    set_fuel_region2 = get(fuel_rr_by_r1, r, Tuple{String,String}[])
    if ((Settings.DepreciationMethod[r]==1) && ((y + 40) > max(𝓨...)))
      @constraint(model,
      Vars.DiscountedSalvageValueTransmission[y,r] == sum(Params.TradeCapacityGrowthCosts[r,rr,f]*Params.TradeRoute[r,rr,f,y]*Vars.NewTradeCapacity[y,f,r,rr]*(1-(((1+Settings.GeneralDiscountRate[r])^(max(𝓨...) - y+1)-1)/((1+Settings.GeneralDiscountRate[r])^40))) for (f,rr) ∈ set_fuel_region2)/((1+Settings.GeneralDiscountRate[r])^(1+max(𝓨...) - min(𝓨...))),
      base_name="SV1b_SalvageValueAtEndOfPeriod1|$(y)|$(r)")
    elseif Settings.DepreciationMethod[r]==1
        JuMP.fix(Vars.DiscountedSalvageValueTransmission[y,r],0; force=true)
    end
  end end

  ############### Operating Costs #############

  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    varcost_active = (any(x->x!=0, Params.VariableCost[r,t,:,y])) && (CanBuildTechnology[y,t,r] > 0)
    if varcost_active
      @constraint(model, sum((Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r]*Params.VariableCost[r,t,m,y]) for m ∈ Maps.Tech_MO[t]) == Vars.AnnualVariableOperatingCost[y,t,r], base_name="OC1_OperatingCostsVariable|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.AnnualVariableOperatingCost[y,t,r],0; force=true)
    end

    fixcost_active = (Params.FixedCost[r,t,y] > 0) & (CanBuildTechnology[y,t,r] > 0)
    if fixcost_active
      @constraint(model, sum(Vars.NewCapacity[yy,t,r]*Params.FixedCost[r,t,yy] for yy ∈ 𝓨 if (y-yy < Params.OperationalLife[t]) && (y-yy >= 0)) + Params.ResidualCapacity[r,t,y]*Params.FixedCost[r,t,y] == Vars.AnnualFixedOperatingCost[y,t,r], base_name="OC2_OperatingCostsFixedAnnual|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.AnnualFixedOperatingCost[y,t,r],0; force=true)
    end

    opcost_active = varcost_active || fixcost_active
    if opcost_active
      @constraint(model, (Vars.AnnualFixedOperatingCost[y,t,r] + Vars.AnnualVariableOperatingCost[y,t,r])*YearlyDifferenceMultiplier(y,Sets) == Vars.OperatingCost[y,t,r], base_name="OC3_OperatingCostsTotalAnnual|$(y)|$(t)|$(r)")
      @constraint(model, Vars.OperatingCost[y,t,r]/((1+Settings.TechnologyDiscountRate[r,t])^(y-Switch.StartYear+0.5)) == Vars.DiscountedOperatingCost[y,t,r], base_name="OC4_DiscountedOperatingCostsTotalAnnual|$(y)|$(t)|$(r)")
    else
      JuMP.fix(Vars.OperatingCost[y,t,r],0; force=true)
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

  # TCC3 / TCC4: aggregated upper / lower limit on TotalCapacityAnnual summed
  # over a technology subset (Tags.TagTechnologyToSubsets) intersected with a
  # region subset (Tags.TagRegionToSubsets), per year. Use 999999 sentinel for
  # "no upper limit" (matches TCC1 convention); 0 lower limit is inert.
  # Group limits only bind investment runs; in a region-restricted dispatch they
  # can be spuriously infeasible, so skip them outside the NoDispatch path.
  if Switch.switch_dispatch isa NoDispatch
  for (ts, techs) ∈ Params.Tags.TagTechnologyToSubsets
    techs_in_subset = intersect(techs, 𝓣)
    isempty(techs_in_subset) && continue
    for (rs, regs) ∈ Params.Tags.TagRegionToSubsets
      regs_in_subset = intersect(regs, 𝓡)
      isempty(regs_in_subset) && continue
      for y ∈ 𝓨
        if Params.GroupTotalAnnualMaxCapacity[ts,rs,y] < 999999
          @constraint(model,
            sum(Vars.TotalCapacityAnnual[y,t,r] for t ∈ techs_in_subset for r ∈ regs_in_subset)
              <= Params.GroupTotalAnnualMaxCapacity[ts,rs,y],
            base_name="TCC3_GroupMaxCapacityConstraint|$(y)|$(ts)|$(rs)")
        end
        # TCC5: aggregated upper limit on NewCapacity (annual additions) summed over
        # the same subset x region subset -> smooths a tech group's build path
        # from data, no per-tech/region hardcode. 999999 = no limit.
        if Params.GroupTotalAnnualMaxNewCapacity[ts,rs,y] < 999999
          @constraint(model,
            sum(Vars.NewCapacity[y,t,r] for t ∈ techs_in_subset for r ∈ regs_in_subset)
              <= Params.GroupTotalAnnualMaxNewCapacity[ts,rs,y],
            base_name="TCC5_GroupMaxNewCapacityConstraint|$(y)|$(ts)|$(rs)")
        end
        if Params.GroupTotalAnnualMinCapacity[ts,rs,y] > 0
          @constraint(model,
            sum(Vars.TotalCapacityAnnual[y,t,r] for t ∈ techs_in_subset for r ∈ regs_in_subset)
              >= Params.GroupTotalAnnualMinCapacity[ts,rs,y],
            base_name="TCC4_GroupMinCapacityConstraint|$(y)|$(ts)|$(rs)")
        end
      end
    end
  end
  end
  print("Cstr: Tot. Cap. : ",Dates.now()-start,"\n")

  ############### New Capacity Constraints ##############

  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    if Params.AnnualMaxNewCapacity[r,t,y] < 999999
      @constraint(model,
      Vars.NewCapacity[y,t,r] <= Params.AnnualMaxNewCapacity[r,t,y],
      base_name="NCC1_AnnualMaxNewCapacityConstraint|$(y)|$(t)|$(r)")
    end
    if Params.AnnualMinNewCapacity[r,t,y] > 0
      @constraint(model,
      Vars.NewCapacity[y,t,r] >= Params.AnnualMinNewCapacity[r,t,y],
      base_name="NCC2_AnnualMinNewCapacityConstraint|$(y)|$(t)|$(r)")
    end
    if (y > Params.NewCapacityExpansionStop[r,t]) && (Params.NewCapacityExpansionStop[r,t] != 0) &&
        (Params.TotalAnnualMinCapacity[r,t,y] == 0) && (Params.AnnualMinNewCapacity[r,t,y] == 0)
      JuMP.fix(Vars.NewCapacity[y,t,r],0; force=true)
    end
    if Params.TotalAnnualMaxCapacityInvestment[r,t,y] < 999999
      @constraint(model,
      Vars.CapitalInvestment[y,t,r] <= Params.TotalAnnualMaxCapacityInvestment[r,t,y],
      base_name="NCC3_TotalAnnualMaxInvestmentConstraint|$(y)|$(t)|$(r)")
    end
    if Params.TotalAnnualMinCapacityInvestment[r,t,y] > 0
      @constraint(model,
      Vars.CapitalInvestment[y,t,r] >= Params.TotalAnnualMinCapacityInvestment[r,t,y],
      base_name="NCC4_TotalAnnualMinInvestmentConstraint|$(y)|$(t)|$(r)")
    end
  end end end

  ################ Annual Activity Constraints ##############

  start=Dates.now()
  for y ∈ 𝓨 for t ∈ 𝓣 for r ∈ 𝓡
    fuels = [y for (x,y) ∈ Maps.Set_Tech_FuelOut if x == t]
    if (CanBuildTechnology[y,t,r] > 0) &&
      (any(x->x>0, [JuMP.has_upper_bound(Vars.ProductionByTechnologyAnnual[y,t,f,r]) ? JuMP.upper_bound(Vars.ProductionByTechnologyAnnual[y,t,f,r]) : ((JuMP.is_fixed(Vars.ProductionByTechnologyAnnual[y,t,f,r])) && (JuMP.fix_value(Vars.ProductionByTechnologyAnnual[y,t,f,r]) == 0)) ? 0 : 999999 for f ∈ fuels]))
      @constraint(model, sum(Vars.ProductionByTechnologyAnnual[y,t,f,r] for f ∈ fuels) == Vars.TotalTechnologyAnnualActivity[y,t,r], base_name= "AAC1_TotalAnnualTechnologyActivity|$(y)|$(t)|$(r)")
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

  if Switch.switch_dispatch isa NoDispatch && Switch.switch_reserve == 1 #TODO should this be enabled for dispatch?
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
    if Params.REMinProductionTarget[r,f,𝓨[i]] > 0
        techs = [t for (t,y) ∈ Maps.Set_Tech_FuelOut if y == f]
        @constraint(model,
        sum(Vars.ProductionByTechnologyAnnual[𝓨[i],t,f,r] for t ∈ intersect(techs, Params.Tags.TagTechnologyToSubsets["Renewables"])) == Vars.TotalREProductionAnnual[𝓨[i],r,f],base_name="RE1_ComputeTotalAnnualREProduction|$(𝓨[i])|$(r)|$(f)")

        @constraint(model,
        Params.REMinProductionTarget[r,f,𝓨[i]]*sum(Vars.RateOfActivity[𝓨[i],l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,𝓨[i]]*Params.YearSplit[l,𝓨[i]] for l ∈ 𝓛 for (t,m) ∈ LoopSetOutput[(r,f,𝓨[i])])*Params.Tags.RETagFuel[r,f,𝓨[i]] <= Vars.TotalREProductionAnnual[𝓨[i],r,f],
        base_name="RE2_AnnualREProductionLowerLimit|$(𝓨[i])|$(r)|$(f)")

        if Switch.switch_dispatch isa NoDispatch
            if (𝓨[i]> Switch.StartYear) && (Params.SpecifiedAnnualDemand[r,f,𝓨[i]]>0) && (Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]]>0)
                @constraint(model,
                Vars.TotalREProductionAnnual[𝓨[i],r,f] >= Vars.TotalREProductionAnnual[𝓨[i-1],r,f]*((Params.SpecifiedAnnualDemand[r,f,𝓨[i]]/Params.SpecifiedAnnualDemand[r,f,𝓨[i-1]])),
                base_name="RE3_RETargetPath|$(𝓨[i])|$(r)|$(f)")
            end
        end
    end
  end end end
  print("Cstr: RE target : ",Dates.now()-start,"\n")

  ################ Emissions Accounting ##############

  start=Dates.now()
  for y ∈ 𝓨 for (t,m) ∈ Maps.Set_Tech_MO for r ∈ 𝓡
    if CanBuildTechnology[y,t,r] > 0
      for e ∈ 𝓔
        @constraint(model, Params.EmissionActivityRatio[r,t,m,e,y]*sum((Vars.TotalAnnualTechnologyActivityByMode[y,t,m,r]*Params.EmissionContentPerFuel[f,e]*Params.InputActivityRatio[r,t,f,m,y]) for f ∈ Maps.Tech_Fuel[t]; init=0.0) == Vars.AnnualTechnologyEmissionByMode[y,t,e,m,r] , base_name="E1_AnnualEmissionProductionByMode|$(y)|$(t)|$(e)|$(m)|$(r)" )
      end
    else
      for e ∈ 𝓔
        JuMP.fix(Vars.AnnualTechnologyEmissionByMode[y,t,e,m,r],0; force=true)
      end
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
        @constraint(model, sum(Vars.AnnualTechnologyEmission[y,t,e,r] for t ∈ 𝓣) - (Switch.switch_dispatch isa NoDispatch ? 0 : DummyEmissionInfeasibility[y,e,r]) == Vars.AnnualEmissions[y,e,r],
        base_name="E6_AnnualEmissionsAccounting|$(y)|$(e)|$(r)")

        # Only emit the limit constraint when a real limit is set; the 999999
        # sentinel ("no limit") would otherwise add a toothless <= ~1e6 row that
        # stretches the RHS range.
        if Params.RegionalAnnualEmissionLimit[r,e,y] < 999999
          @constraint(model, Vars.AnnualEmissions[y,e,r]+Params.AnnualExogenousEmission[r,e,y] <= Params.RegionalAnnualEmissionLimit[r,e,y],
          base_name="E8_RegionalAnnualEmissionsLimit|$(y)|$(e)|$(r)")
        end
      end
      if Params.AnnualEmissionLimit[e,y] < 999999
        @constraint(model, sum(Vars.AnnualEmissions[y,e,r]+Params.AnnualExogenousEmission[r,e,y] for r ∈ 𝓡) <= Params.AnnualEmissionLimit[e,y],
        base_name="E9_AnnualEmissionsLimit|$(y)|$(e)")
      end
    end
    if Params.ModelPeriodEmissionLimit[e] < 999999
      @constraint(model, sum(Vars.ModelPeriodEmissions[r,e] for r ∈ 𝓡) <= Params.ModelPeriodEmissionLimit[e],
      base_name="E10_ModelPeriodEmissionsLimit|$(e)")
    end
  end

  print("Cstr: Em. Acc. 2 : ",Dates.now()-start,"\n")
  start=Dates.now()
  for e ∈ 𝓔 for r ∈ 𝓡
    if Params.RegionalModelPeriodEmissionLimit[r,e] < 999999
      @constraint(model, Vars.ModelPeriodEmissions[r,e] <= Params.RegionalModelPeriodEmissionLimit[r,e] ,base_name="E11_RegionalModelPeriodEmissionsLimit|$(r)|$(e)" )
    end
  end end
  print("Cstr: Em. Acc. 3 : ",Dates.now()-start,"\n")
  start=Dates.now()

  if Switch.switch_weighted_emissions == 1
    for e ∈ 𝓔 for r ∈ 𝓡
      @constraint(model,
      sum(Vars.WeightedAnnualEmissions[𝓨[i],e,r]*(𝓨[i+1]-𝓨[i]) for i ∈ eachindex(𝓨)[1:end-1] if 𝓨[i+1]-𝓨[i] > 0) +  Vars.WeightedAnnualEmissions[𝓨[end],e,r] == Vars.ModelPeriodEmissions[r,e]- Params.ModelPeriodExogenousEmission[r,e],
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
      +  Vars.AnnualEmissions[𝓨[end],e,r] == Vars.ModelPeriodEmissions[r,e]- Params.ModelPeriodExogenousEmission[r,e],
      base_name="E7_ModelPeriodEmissionsAccounting|$(e)|$(r)")
    end end
  end
  print("Cstr: Em. Acc. 4 : ",Dates.now()-start,"\n")

  ################ Sectoral Emissions Accounting ##############
  start=Dates.now()
  for y ∈ 𝓨, e ∈ 𝓔, se ∈ 𝓢𝓮
      for r ∈ 𝓡
        @constraint(model,
        sum(Vars.AnnualTechnologyEmission[y,t,e,r] for t ∈ techs_by_sector[se]) == Vars.AnnualSectoralEmissions[y,e,se,r],
        base_name="E12_AnnualSectorEmissions|$(y)|$(e)|$(se)|$(r)")
      end
      if Params.AnnualSectoralEmissionLimit[e,se,y] < 999999
        @constraint(model,
        sum(Vars.AnnualSectoralEmissions[y,e,se,r] for r ∈ 𝓡 ) <= Params.AnnualSectoralEmissionLimit[e,se,y],
        base_name="E13_AnnualSectorEmissionsLimit|$(y)|$(e)|$(se)")
      end
  end

  print("Cstr: ES: ",Dates.now()-start,"\n")
  ######### Short-Term Storage Constraints #############
  start=Dates.now()

  for r ∈ 𝓡 for s ∈ 𝓢 for y ∈ 𝓨
    @constraint(model,
    Vars.StorageLevelYearStart[s,y,r] <= Switch.set_storagelevelstart_up * Vars.TotalStorageCapacityAnnual[s,y,r], base_name="S1a_StorageLevelYearStartUpperLimit|$(r)|$(s)|$(y)")

    @constraint(model,
    Vars.StorageLevelYearStart[s,y,r] >= Switch.set_storagelevelstart_down * Vars.TotalStorageCapacityAnnual[s,y,r], base_name="S1b_StorageLevelYearStartLowerLimit|$(r)|$(s)|$(y)")
  end end end

  for r ∈ 𝓡 for s ∈ 𝓢 for i ∈ eachindex(𝓨)
    @constraint(model,
    sum((sum(Vars.RateOfActivity[𝓨[i],l,t,m,r] * Params.TechnologyToStorage[t,s,m,𝓨[i]] * Params.YearSplit[l,𝓨[i]] for (t,m) ∈ charge_tm[s] if Params.TechnologyToStorage[t,s,m,𝓨[i]]>0)
              - sum(Vars.RateOfActivity[𝓨[i],l,t,m,r] / Params.TechnologyFromStorage[t,s,m,𝓨[i]] * Params.YearSplit[l,𝓨[i]] for (t,m) ∈ discharge_tm[s] if Params.TechnologyFromStorage[t,s,m,𝓨[i]]>0)) for l ∈ 𝓛)
              - sum((s == "S_Trade_Storage_$f" && Switch.switch_dispatch isa OneNodeStorage ? storage_ratio[𝓨[i],f,r] : 0) for f ∈ 𝓕 if Params.Tags.TagCanFuelBeTraded[f] != 0) == 0,
              base_name="S3_StorageRefilling|$(r)|$(s)|$(𝓨[i])")

    @constraint(model, Vars.StorageLevelYearStart[s,𝓨[i],r] + sum((s == "S_Trade_Storage_$f" && Switch.switch_dispatch isa OneNodeStorage ? storage_ratio[𝓨[i],f,r] : 0) for f ∈ 𝓕 if Params.Tags.TagCanFuelBeTraded[f] != 0) ==  Vars.StorageLevelYearFinish[s,𝓨[i],r],
    base_name="S4_StorageLevelYearFinish|$(s)|$(𝓨[i])|$(r)")

    for j ∈ eachindex(𝓛)
      @constraint(model,
      (j>1 ? Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j-1],r] +
      (sum((Params.TechnologyToStorage[t,s,m,𝓨[i]]>0 ? Vars.RateOfActivity[𝓨[i],𝓛[j-1],t,m,r] * Params.TechnologyToStorage[t,s,m,𝓨[i]] : 0) for (t,m) ∈ charge_tm[s]; init=0)
        - sum((Params.TechnologyFromStorage[t,s,m,𝓨[i]]>0 ? Vars.RateOfActivity[𝓨[i],𝓛[j-1],t,m,r] / Params.TechnologyFromStorage[t,s,m,𝓨[i]] : 0 ) for (t,m) ∈ discharge_tm[s]; init=0)) * Params.YearSplit[𝓛[j-1],𝓨[i]] : 0)
        + (j == 1 ? Vars.StorageLevelYearStart[s,𝓨[i],r] : 0)   == Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j],r],
        base_name="S2_StorageLevelTSStart|$(r)|$(s)|$(𝓨[i])|$(𝓛[j])")
      @constraint(model,
      Vars.TotalStorageCapacityAnnual[s,𝓨[i],r]
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
          Params.MinStorageCharge[r,s,𝓨[i]]*Vars.TotalStorageCapacityAnnual[s,𝓨[i],r]
          <= Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j],r],
          base_name="S5a_StorageChargeLowerLimit|$(s)|$(𝓨[i])|$(𝓛[j])|$(r)")
        end
      end
    end
    for (t,m) ∈ discharge_tm[s]
      if Params.TechnologyFromStorage[t,s,m,𝓨[i]]>0
        for r ∈ 𝓡 for j ∈ eachindex(𝓛)
          @constraint(model,
          Vars.RateOfActivity[𝓨[i],𝓛[j],t,m,r]/Params.TechnologyFromStorage[t,s,m,𝓨[i]]*Params.YearSplit[𝓛[j],𝓨[i]] <= Vars.StorageLevelTSStart[s,𝓨[i],𝓛[j],r],
          base_name="S6_StorageActivityLimit|$(s)|$(t)|$(𝓨[i])|$(𝓛[j])|$(r)|$(m)")
        end end
      end
    end
    if Switch.switch_dispatch isa NoDispatch
        for r ∈ 𝓡
            @constraint(model, Vars.TotalStorageCapacityAnnual[s,𝓨[i],r] == (sum(Vars.NewStorageCapacity[s,yy,r] for yy ∈ 𝓨 if (Params.OperationalLifeStorage[s] >= 𝓨[i]-yy && 𝓨[i]-yy >= 0)) + Params.ResidualStorageCapacity[r,s,𝓨[i]]),
            base_name="S1_jl_TotalStorageCapacityAnnual|$(s)|$(𝓨[i])|$(r)")
            @constraint(model, Vars.TotalStorageCapacityAnnual[s,𝓨[i],r] <= sum(Vars.TotalCapacityAnnual[𝓨[i],t,r] * Params.StorageE2PRatio[s]* 0.0036 * Switch.E2P_ratio_deviation_factor for (t,m) ∈ charge_tm[s] if Params.TechnologyToStorage[t,s,m,𝓨[i]]!=0),
            base_name="S7a_Add_E2PRatio_up|$(s)|$(𝓨[i])|$(r)")
            @constraint(model, Vars.TotalStorageCapacityAnnual[s,𝓨[i],r] >= sum(Vars.TotalCapacityAnnual[𝓨[i],t,r] * Params.StorageE2PRatio[s]* 0.0036 *(1/Switch.E2P_ratio_deviation_factor) for (t,m) ∈ charge_tm[s] if Params.TechnologyToStorage[t,s,m,𝓨[i]]!=0),
            base_name="S7b_Add_E2PRatio_low|$(s)|$(𝓨[i])|$(r)")
        end
    end
  end end
  print("Cstr: Storage 1 : ",Dates.now()-start,"\n")

  ######### Transportation Equations #############
  start=Dates.now()
  if Switch.switch_dispatch isa TwoNodes
    for y ∈ 𝓨
      for f ∈ intersect(Sets.Fuel, Params.Tags.TagFuelToSubsets["TransportFuels"])
          for l ∈ 𝓛 for mt ∈ 𝓜𝓽
            demand_split = sum(Params_full.SpecifiedAnnualDemand[r,f,y]*Params_full.ModalSplitByFuelAndModalType[r,f,y,mt]*Params_full.SpecifiedDemandProfile[r,f,l,y] for r in Region_Full if r!=𝓡[1])
            @constraint(model,
            demand_split == Vars.DemandSplitByModalType[mt,l,𝓡[2],f,y],
            base_name="T1_SpecifiedAnnualDemandByModalSplit|$(mt)|$(l)_ROE|$(f)|$(y)")
            @constraint(model,
            Params_full.SpecifiedAnnualDemand[𝓡[1],f,y]*Params_full.ModalSplitByFuelAndModalType[𝓡[1],f,y,mt]*Params_full.SpecifiedDemandProfile[𝓡[1],f,l,y] == Vars.DemandSplitByModalType[mt,l,𝓡[1],f,y],
            base_name="T1_SpecifiedAnnualDemandByModalSplit|$(mt)|$(l)|$(𝓡[1])|$(f)|$(y)")
          end end

        for mt ∈ 𝓜𝓽 for r ∈ 𝓡
          if sum(Params.Tags.TagTechnologyToModalType[:,:,mt]) != 0 && sum(Params.OutputActivityRatio[r,:,f,:,y]) != 0
            for l ∈ 𝓛
              @constraint(model,
              sum(Params.Tags.TagTechnologyToModalType[t,m,mt]*Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y]*Params.YearSplit[l,y] for (t,m) ∈ LoopSetOutput[(r,f,y)]) == Vars.ProductionSplitByModalType[mt,l,r,f,y],
              base_name="T2_ProductionOfTechnologyByModalSplit|$(mt)|$(l)|$(r)|$(f)|$(y)")
              @constraint(model,
              Vars.ProductionSplitByModalType[mt,l,r,f,y] >= Vars.DemandSplitByModalType[mt,l,r,f,y],
              base_name="T3_ModalSplitBalance|$(mt)|$(l)|$(r)|$(f)|$(y)")
            end
          end
        end end
      end

      for l ∈ 𝓛 for r ∈ 𝓡
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
      end end
    end
  else
    for r ∈ 𝓡 for y ∈ 𝓨
      for f ∈ intersect(Sets.Fuel, Params.Tags.TagFuelToSubsets["TransportFuels"])
        if Params.SpecifiedAnnualDemand[r,f,y] != 0
          for l ∈ 𝓛 for mt ∈ 𝓜𝓽
            @constraint(model,
            Params.SpecifiedAnnualDemand[r,f,y]*Params.ModalSplitByFuelAndModalType[r,f,y,mt]*Params.SpecifiedDemandProfile[r,f,l,y] == Vars.DemandSplitByModalType[mt,l,r,f,y],
            base_name="T1_SpecifiedAnnualDemandByModalSplit|$(mt)|$(l)|$(r)|$(f)|$(y)")
          end end
        end

        for mt ∈ 𝓜𝓽
          if sum(Params.Tags.TagTechnologyToModalType[:,:,mt]) != 0 && sum(Params.OutputActivityRatio[r,:,f,:,y]) != 0
            for l ∈ 𝓛
              @constraint(model,
              sum(Params.Tags.TagTechnologyToModalType[t,m,mt]*Vars.RateOfActivity[y,l,t,m,r]*Params.OutputActivityRatio[r,t,f,m,y]*Params.YearSplit[l,y] for (t,m) ∈ LoopSetOutput[(r,f,y)]) == Vars.ProductionSplitByModalType[mt,l,r,f,y],
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
  end

  print("Cstr: transport: ",Dates.now()-start,"\n")
  if Switch.switch_ramping == 1

    ############### Ramping #############
    start=Dates.now()
    for y ∈ 𝓨 for r ∈ 𝓡
      for (t,f) ∈ Maps.Set_Tech_FuelOut
        for i ∈ eachindex(𝓛)
          if i>1
            if Params.Tags.TagDispatchableTechnology[t]==1 && (Params.RampingUpFactor[t,y] != 0 || Params.RampingDownFactor[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0)
              @constraint(model,
              ((sum(Vars.RateOfActivity[y,𝓛[i],t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] for m ∈ Maps.Tech_MO[t] if Params.OutputActivityRatio[r,t,f,m,y] != 0)*Params.YearSplit[𝓛[i],y]) - (sum(Vars.RateOfActivity[y,𝓛[i-1],t,m,r]*Params.OutputActivityRatio[r,t,f,m,y] for m ∈ Maps.Tech_MO[t] if Params.OutputActivityRatio[r,t,f,m,y] != 0)*Params.YearSplit[𝓛[i-1],y]))
              == Vars.ProductionUpChangeInTimeslice[y,𝓛[i],f,t,r] - Vars.ProductionDownChangeInTimeslice[y,𝓛[i],f,t,r],
              base_name="R1_ProductionChange|$(y)|$(𝓛[i])|$(f)|$(t)|$(r)")
            end
            if Params.Tags.TagDispatchableTechnology[t]==1 && Params.RampingUpFactor[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
              # sampled hours represent elmod_hourstep real hours apart, so scale the
              # per-step ramp budget by that spacing (reduced-timeseries correctness).
              ramp_hours = max(Int(Switch.elmod_hourstep), 1)
              @constraint(model,
              Vars.ProductionUpChangeInTimeslice[y,𝓛[i],f,t,r] <= Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t]*Params.RampingUpFactor[t,y]*Params.YearSplit[𝓛[i],y]*ramp_hours,
              base_name="R2_RampingUpLimit|$(y)|$(𝓛[i])|$(f)|$(t)|$(r)")
            end
            if Params.Tags.TagDispatchableTechnology[t]==1 && Params.RampingDownFactor[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
              ramp_hours = max(Int(Switch.elmod_hourstep), 1)
              @constraint(model,
              Vars.ProductionDownChangeInTimeslice[y,𝓛[i],f,t,r] <= Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y]*Params.CapacityToActivityUnit[t]*Params.RampingDownFactor[t,y]*Params.YearSplit[𝓛[i],y]*ramp_hours,
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
        if Params.Tags.TagDispatchableTechnology[t]==1 && Params.ProductionChangeCost[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
          @constraint(model,
          sum((Vars.ProductionUpChangeInTimeslice[y,l,f,t,r] + Vars.ProductionDownChangeInTimeslice[y,l,f,t,r])*Params.ProductionChangeCost[t,y] for l ∈ 𝓛) == Vars.AnnualProductionChangeCost[y,t,r],
          base_name="RC1_AnnualProductionChangeCosts|$(y)|$(f)|$(t)|$(r)")
        end
        if Params.Tags.TagDispatchableTechnology[t]==1 && Params.ProductionChangeCost[t,y] != 0 && Params.AvailabilityFactor[r,t,y] > 0 && Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0
          @constraint(model,
          Vars.AnnualProductionChangeCost[y,t,r]/((1+Settings.TechnologyDiscountRate[r,t])^(y-Switch.StartYear+0.5)) == Vars.DiscountedAnnualProductionChangeCost[y,t,r],
          base_name="RC2_DiscountedAnnualProductionChangeCost|$(y)|$(f)|$(t)|$(r)")
        end
      end
      for t ∈ Sets.Technology
        if (Params.Tags.TagDispatchableTechnology[t] == 0 || sum(Params.OutputActivityRatio[r,t,f,m,y] for f ∈ Maps.Tech_Fuel[t] for m ∈ Maps.Tech_MO[t]; init=0.0) == 0 || Params.ProductionChangeCost[t,y] == 0 || Params.AvailabilityFactor[r,t,y] == 0 || Params.TotalAnnualMaxCapacity[r,t,y] == 0 || Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] == 0)
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
    # Production mode (switch_base_year_bounds_debugging == 0): slack vars don't
    # exist, so the base-year bounds are strict. Debug mode: slack vars carry a
    # BigM penalty in the objective so an infeasible base-year floor shows softly.
    debug = Switch.switch_base_year_bounds_debugging == 1
    for y ∈ 𝓨 for (t,f) ∈ Maps.Set_Tech_FuelOut for r ∈ 𝓡
        if Params.RegionalBaseYearProduction[r,t,f,y] != 0
          @constraint(model,
          Vars.ProductionByTechnologyAnnual[y,t,f,r] >= Params.RegionalBaseYearProduction[r,t,f,y]*(1-Settings.BaseYearSlack[f]) - (debug ? Vars.BaseYearBounds_TooHigh[r,t,f,y] : 0),
          base_name="BYB1_RegionalBaseYearProductionLowerBound|$(y)|$(r)|$(t)|$(f)")
        end

        if Params.RegionalBaseYearProduction[r,t,f,y] != 0
          @constraint(model,
          Vars.ProductionByTechnologyAnnual[y,t,f,r] <= Params.RegionalBaseYearProduction[r,t,f,y] + (debug ? Vars.BaseYearBounds_TooLow[r,t,f,y] : 0),
          base_name="BYB2_RegionalBaseYearProductionUpperBound|$(y)|$(r)|$(t)|$(f)")
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
      techs = [x for (x,y) ∈ Maps.Set_Tech_FuelIn if y == "Power"]
      @constraint(model,
      Vars.PeakingDemand[y,r] ==
        sum(Vars.UseByTechnologyAnnual[y,t,"Power",r]/GWh_to_PJ*Params.x_peakingDemand[r,se]/8760
          #Demand per Year in PJ             to Gwh     Highest peak hour value   /number hours per year
        for se ∈ 𝓢𝓮 for t ∈ setdiff(techs,Params.Tags.TagTechnologyToSubsets["StorageDummies"]) if Params.x_peakingDemand[r,se] != 0 && Params.Tags.TagTechnologyToSector[t,se] != 0)
      + Params.SpecifiedAnnualDemand[r,"Power",y]/GWh_to_PJ*Params.x_peakingDemand[r,"Power"]/8760,
      base_name="PC1_PowerPeakingDemand|$(y)|$(r)")

      @constraint(model,
      Vars.PeakingCapacity[y,r] ==
        sum((SumCapacityFactor[r,t,y] < length(𝓛) ? Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y]*RenewableCapacityFactorReduction*(SumCapacityFactor[r,t,y]/length(𝓛)) : 0)
        + (SumCapacityFactor[r,t,y] >= length(𝓛) ? Vars.TotalCapacityAnnual[y,t,r]*Params.AvailabilityFactor[r,t,y] : 0)
        for t ∈ setdiff(𝓣,Params.Tags.TagTechnologyToSubsets["StorageDummies"]) if ((t,"Power") in Maps.Set_Tech_FuelOut && sum(Params.OutputActivityRatio[r,t,"Power",m,y] for m ∈ Maps.Tech_MO[t]) != 0)),
        base_name="PC2_PowerPeakingCapacity|$(y)|$(r)")

      if y >Switch.set_peaking_startyear
        @constraint(model,
        Vars.PeakingCapacity[y,r] + (Switch.switch_peaking_with_trade == 1 ? sum(Vars.TotalTradeCapacity[y,"Power",rr,r] for rr ∈ [z for (f,x,z) in Maps.Set_Fuel_Regions if f == "Power" && x == r]) : 0)
        + (Switch.switch_peaking_with_storages == 1 ? sum(Vars.TotalCapacityAnnual[y,t,r] for t ∈ StorageDummies_techs if (sum(Params.OutputActivityRatio[r,t,"Power",m,y] for m ∈ Maps.Tech_MO[t];init=0) != 0 && sum(sum(Params.TechnologyToStorage[t,:,m,y]) for m ∈ Maps.Tech_MO[t];init=0) != 0)) : 0)
        >= Vars.PeakingDemand[y,r]*PeakingSlack,
        base_name="PC3_PeakingConstraint|$(y)|$(r)")
      end

      if Switch.switch_peaking_with_storages == 1
        if y > Switch.set_peaking_startyear
            @constraint(model, Vars.PeakingCapacity[y,r] >= MinThermalShare*Vars.PeakingDemand[y,r]*PeakingSlack,
            base_name="PC3b_PeakingConstraint_Thermal|$(y)|$(r)")
        end
      end

      if Switch.switch_peaking_minrun == 1
        for t ∈ 𝓣
          if (Params.Tags.TagTechnologyToSector[t,"Power"]==1 && Params.AvailabilityFactor[r,t,y]<=1 &&
            Params.Tags.TagDispatchableTechnology[t]==1 && Params.AvailabilityFactor[r,t,y] > 0 &&
            Params.TotalAnnualMaxCapacity[r,t,y] > 0 && Params.TotalTechnologyModelPeriodActivityUpperLimit[r,t] > 0 &&
            ((cap_has_ub[y,t,r] && cap_ub[y,t,r] > 0) ||
            (!cap_has_ub[y,t,r] && !cap_is_fixed[y,t,r]) ||
            (cap_is_fixed[y,t,r] && cap_fix_val[y,t,r] > 0)) &&
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
      +(Emp_Params.CoalSupply[r,y]*Emp_Params.CoalDigging[Switch.model_region,"Coal_Export","$(Switch.emissionPathway)_$(Switch.emissionScenario)",y]*Emp_Params.EFactorCoalJobs["Coal_Export",y]) for (t,f) ∈ Maps.Set_Tech_FuelIn)
      == Vars.TotalJobs[r,y],
      base_name="Jobs1_TotalJobs|$(r)|$(y)")
    end end
  end
  return considered_duals
end
