"""
Input-data error checks, mirroring genesysmod_errorcheck.gms.

Runs right after data load (before the model is built) so obvious data
problems abort with a named list of offenders instead of surfacing later as
an infeasible or misbehaving model.

Hard checks (model aborts, like the GAMS `abort`):
  1. Technology missing from TagTechnologyToSector
  2. TradeCosts missing for a traded fuel with a defined TradeRoute
     (TradeCosts is derived from TradeCostFactor × TradeRoute, so the
      Par_TradeCostFactor input is what is actually missing)
  3. ModalSplit sums > 1 per ModalGroup / ModalSubgroup
  4. OperationalLife missing for a Technology (dummy/infeasibility techs are
     exempt — their parameters are filled programmatically later)
  5. CapacityFactor zero across all timeslices although AvailabilityFactor
     and TotalAnnualMaxCapacity are set
  6. CapacityToActivityUnit missing although AvailabilityFactor is set
  7. TradeCapacity / CommissionedTradeCapacity set without a TradeRoute

  8. Demand without any producer: SpecifiedAnnualDemand set but no technology
     in the region outputs the fuel and no TradeRoute can import it
  9. Min > Max bound pairs (TotalAnnualMin/MaxCapacity, AnnualMin/Max
     NewCapacity, GroupMin/MaxCapacity, activity lower/upper limits)
 10. Annual emission limit below the exogenous emission floor (global and
     regional)
 11. SpecifiedDemandProfile defined but not summing to 1 over the timeslices
 12. YearSplit not summing to 1 over the timeslices
 13. Storage orphans: chargeable but never dischargeable (or vice versa);
     active storage without OperationalLifeStorage
 14. Negative values in physically nonnegative parameters (costs,
     capacities, demands, factors, lifetimes)
 24. Base-year group-capacity cone: for every (tech subset, region subset)
     with a binding GroupTotalAnnualMin/MaxCapacity in the start year, the
     summed ResidualCapacity must lie inside [GroupMin, GroupMax] — new
     builds are typically fixed to 0 in the start year, so a residual fleet
     outside the cone is hard-infeasible

Warnings (printed, run continues):
 15. AvailabilityFactor missing although ResidualCapacity is set
 16. Technology efficiency > 1 (input sum < output sum) outside the
     Resources / Transportation sectors
 17. ResidualCapacity above TotalAnnualMaxCapacity (GAMS records this as
     ToSmallResidualCapacity)
 18. Demand year-gaps: demand in the start year but exactly zero in a later
     modelled year (missing per-year rows are silently zero since
     switch_endogenous_specifieddemandforecasting defaults to 0)
 19. Asymmetric TradeRoutes (route defined one way only)
 20. Share parameters above 1 (AvailabilityFactor, CapacityFactor,
     MinStorageCharge, ModalSplit entries)
 21. REMinProductionTarget without any RE-tagged technology producing the fuel
 22. Dead capacity: Residual/MaxCapacity given for a technology with no
     input or output activity ratio anywhere
 23. Switch/data mismatches (switch_reserve on but ReserveMargin all zero;
     employment calculation on but no employment data file)

`Switch.switch_errorcheck`:
  0 = skip all checks
  1 = run and REPORT everything, but continue (escape hatch for datasets
      with known gaps that the model tolerates)
  2 = GAMS behaviour (default): abort the run when a hard check fails,
      warnings never abort
"""
function genesysmod_errorcheck(Sets, Params, Switch)
    Switch.switch_errorcheck != 0 || return

    𝓡 = Sets.Region_full
    𝓣 = Sets.Technology
    𝓕 = Sets.Fuel
    𝓨 = Sets.Year
    𝓛 = Sets.Timeslice
    𝓜 = Sets.Mode_of_operation
    𝓜𝓽 = Sets.ModalType
    𝓢𝓮 = Sets.Sector

    nerrors = 0
    # log shows at most this many offenders per check; the file gets all of
    # them (Errorcheck_<nthhour>_<date>.txt in the result dir, like the IIS)
    maxshow = 20
    findings = String[]
    function report!(kind, name, offenders, msg)
        isempty(offenders) && return
        shown = first(offenders, maxshow)
        if kind === :error
            @error "$(name): $(msg)" offenders=shown total=length(offenders)
            nerrors += 1
        else
            @warn "$(name): $(msg)" offenders=shown total=length(offenders)
        end
        push!(findings,
            "[$(kind === :error ? "ERROR" : "WARNING")] $(name): $(msg) ($(length(offenders)) offender(s))\n" *
            join(("  " * string(o) for o in offenders), "\n"))
    end

    dummy_techs = Set(get(Params.Tags.TagTechnologyToSubsets, "DummyTechnology", String[]))

    # 1 — Technology missing from Sector list
    off = [t for t ∈ 𝓣 if t ∉ dummy_techs && all(Params.Tags.TagTechnologyToSector[t,se] == 0 for se ∈ 𝓢𝓮)]
    report!(:error, "TechMissingFromSectorList", off,
        "Technology missing from the Sector list. Check Par_TagTechnologyToSector.")

    # 2 — TradeCosts missing for a traded fuel with a TradeRoute
    # (TradeCosts = TradeCostFactor × TradeRoute, so a zero here means the
    #  Par_TradeCostFactor input is missing for that fuel)
    off = Tuple{String,String,String}[]
    for f ∈ 𝓕
        Params.Tags.TagCanFuelBeTraded[f] != 0 || continue
        for r ∈ 𝓡, rr ∈ 𝓡
            if any(Params.TradeRoute[r,rr,f,y] != 0 for y ∈ 𝓨) &&
               all(Params.TradeCosts[r,f,y,rr] == 0 for y ∈ 𝓨)
                push!(off, (r, f, rr))
            end
        end
    end
    report!(:error, "TradeCostsMissingFromTradeRoute", off,
        "TradeCosts missing for a traded fuel with a defined TradeRoute. Check Par_TradeCostFactor.")

    # 3 — ModalSplit definition (sum over group must be <= 1)
    if !isempty(𝓜𝓽)
        for (group, label) ∈ (("TransportModes", "ModalGroup"), ("ModalSubgroups", "SubGroup"))
            mts = [mt for mt ∈ 𝓜𝓽 if Params.Tags.TagModalTypeToModalGroups[mt,group] != 0]
            isempty(mts) && continue
            off = [(f, r, y) for f ∈ 𝓕 for r ∈ 𝓡 for y ∈ 𝓨
                   if round(sum(Params.ModalSplitByFuelAndModalType[r,f,y,mt] for mt ∈ mts), digits=4) > 1]
            report!(:error, "ModalSplitByModalTypeDefinition ($label)", off,
                "Sum of ModalTypes in a $(label) exceeds 1. Check Par_ModalSplitByFuel.")
        end
    end

    # 4 — OperationalLife missing
    off = [t for t ∈ 𝓣 if t ∉ dummy_techs && Params.OperationalLife[t] == 0]
    report!(:error, "OperationalLifeMissing", off,
        "OperationalLife missing for a Technology. Check Par_OperationalLife.")

    # 5 — CapacityFactor zero everywhere although AF + MaxCapacity set
    off = Tuple{String,String,Int}[]
    for r ∈ 𝓡, t ∈ 𝓣, y ∈ 𝓨
        if Params.AvailabilityFactor[r,t,y] != 0 && Params.TotalAnnualMaxCapacity[r,t,y] != 0 &&
           all(Params.CapacityFactor[r,t,l,y] == 0 for l ∈ 𝓛)
            push!(off, (r, t, y))
        end
    end
    report!(:error, "CapacityFactorDataMissing", off,
        "CapacityFactor is zero in every timeslice for an available technology. Check the hourly data file.")

    # 6 — CapacityToActivityUnit missing although AF set
    off = [(r, t) for r ∈ 𝓡 for t ∈ 𝓣
           if t ∉ dummy_techs && Params.CapacityToActivityUnit[t] == 0 &&
              any(Params.AvailabilityFactor[r,t,y] != 0 for y ∈ 𝓨)]
    report!(:error, "CapacityToActivityUnitDataMissing", off,
        "CapacityToActivityUnit missing for a Technology. Check Par_CapacityToActivityUnit.")

    # 7 — Trade capacities without a TradeRoute
    off = Tuple{String,String,String,Int,String}[]
    for r ∈ 𝓡, rr ∈ 𝓡, f ∈ 𝓕, y ∈ 𝓨
        if Params.TradeRoute[r,rr,f,y] == 0
            Params.TradeCapacity[r,rr,f,y] != 0 && push!(off, ("TradeCapacity", r, f, y, rr))
            Params.CommissionedTradeCapacity[r,rr,f,y] != 0 && push!(off, ("CommissionedTradeCapacity", r, f, y, rr))
        end
    end
    report!(:error, "TradeCapacityMismatch", off,
        "TradeCapacity/CommissionedTradeCapacity set without a TradeRoute. Check the trade input data.")

    # technologies with any activity ratio anywhere (used by checks 8 + 22)
    active_techs = Set(t for t ∈ 𝓣
        if any(Params.OutputActivityRatio[r,t,f,m,y] != 0 || Params.InputActivityRatio[r,t,f,m,y] != 0
               for r ∈ 𝓡 for f ∈ 𝓕 for m ∈ 𝓜 for y ∈ 𝓨))

    # 8 — Demand without any producer or import route
    off = Tuple{String,String}[]
    for r ∈ 𝓡, f ∈ 𝓕
        any(Params.SpecifiedAnnualDemand[r,f,y] != 0 for y ∈ 𝓨) || continue
        produced = any(Params.OutputActivityRatio[r,t,f,m,y] != 0 for t ∈ 𝓣 for m ∈ 𝓜 for y ∈ 𝓨)
        produced && continue
        tradeable = Params.Tags.TagCanFuelBeTraded[f] != 0 &&
            any(Params.TradeRoute[rr,r,f,y] != 0 || Params.TradeRoute[r,rr,f,y] != 0 for rr ∈ 𝓡 for y ∈ 𝓨)
        tradeable || push!(off, (r, f))
    end
    report!(:error, "DemandWithoutProducer", off,
        "SpecifiedAnnualDemand set but no technology outputs the fuel in the region and no TradeRoute can import it.")

    # 9 — Min > Max bound pairs
    off = Tuple{String,String,String,Int}[]
    for r ∈ 𝓡, t ∈ 𝓣, y ∈ 𝓨
        if Params.TotalAnnualMaxCapacity[r,t,y] < 999999 &&
           Params.TotalAnnualMinCapacity[r,t,y] > Params.TotalAnnualMaxCapacity[r,t,y]
            push!(off, ("TotalAnnualMin>Max", r, t, y))
        end
        if Params.AnnualMaxNewCapacity[r,t,y] < 999999 &&
           Params.AnnualMinNewCapacity[r,t,y] > Params.AnnualMaxNewCapacity[r,t,y]
            push!(off, ("AnnualMinNew>MaxNew", r, t, y))
        end
        if Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y] < 999999 &&
           Params.TotalTechnologyAnnualActivityLowerLimit[r,t,y] > Params.TotalTechnologyAnnualActivityUpperLimit[r,t,y]
            push!(off, ("ActivityLower>Upper", r, t, y))
        end
    end
    gmax = Params.GroupTotalAnnualMaxCapacity
    gmin = Params.GroupTotalAnnualMinCapacity
    for ts ∈ axes(gmax)[1], rs ∈ axes(gmax)[2], y ∈ axes(gmax)[3]
        if gmax[ts,rs,y] < 999999 && gmin[ts,rs,y] > gmax[ts,rs,y]
            push!(off, ("GroupMin>Max", string(ts), string(rs), y))
        end
    end
    report!(:error, "MinAboveMax", off,
        "A minimum bound exceeds its maximum counterpart — instantly infeasible.")

    # 10 — Emission limit below the exogenous emission floor
    off = Tuple{String,String,Int}[]
    for e ∈ Sets.Emission, y ∈ 𝓨
        if Params.AnnualEmissionLimit[e,y] < 999999 &&
           sum(Params.AnnualExogenousEmission[r,e,y] for r ∈ 𝓡) > Params.AnnualEmissionLimit[e,y]
            push!(off, ("Global", e, y))
        end
        for r ∈ 𝓡
            if Params.RegionalAnnualEmissionLimit[r,e,y] < 999999 &&
               Params.AnnualExogenousEmission[r,e,y] > Params.RegionalAnnualEmissionLimit[r,e,y]
                push!(off, (r, e, y))
            end
        end
    end
    report!(:error, "EmissionLimitBelowExogenous", off,
        "AnnualEmissionLimit is below the exogenous emissions — the limit cannot be met.")

    # 11 — SpecifiedDemandProfile defined but not summing to 1
    off = Tuple{String,String,Int,Float64}[]
    for r ∈ 𝓡, f ∈ 𝓕, y ∈ 𝓨
        Params.SpecifiedAnnualDemand[r,f,y] != 0 || continue
        s = sum(Params.SpecifiedDemandProfile[r,f,l,y] for l ∈ 𝓛)
        # all-zero profile = time-independent fuel handled via the yearly
        # balance; only a present-but-malformed profile is an error
        if s != 0 && abs(s - 1) > 1e-3
            push!(off, (r, f, y, round(s, digits=5)))
        end
    end
    report!(:error, "DemandProfileNotNormalized", off,
        "SpecifiedDemandProfile does not sum to 1 over the timeslices for a demanded fuel.")

    # 12 — YearSplit sums to 1
    off = [(y, round(sum(Params.YearSplit[l,y] for l ∈ 𝓛), digits=6)) for y ∈ 𝓨
           if abs(sum(Params.YearSplit[l,y] for l ∈ 𝓛) - 1) > 1e-6]
    report!(:error, "YearSplitNotNormalized", off,
        "YearSplit does not sum to 1 over the timeslices.")

    # 13 — Storage orphans
    off = Tuple{String,String}[]
    tts = Params.TechnologyToStorage
    tfs = Params.TechnologyFromStorage
    for s ∈ Sets.Storage
        can_charge    = any(tts[t,s,m,y] != 0 for t ∈ axes(tts)[1] for m ∈ axes(tts)[3] for y ∈ axes(tts)[4])
        can_discharge = any(tfs[t,s,m,y] != 0 for t ∈ axes(tfs)[1] for m ∈ axes(tfs)[3] for y ∈ axes(tfs)[4])
        can_charge && !can_discharge && push!(off, (s, "chargeable but never dischargeable"))
        !can_charge && can_discharge && push!(off, (s, "dischargeable but never chargeable"))
        if (can_charge || can_discharge) && Params.OperationalLifeStorage[s] == 0
            push!(off, (s, "OperationalLifeStorage missing"))
        end
    end
    report!(:error, "StorageLinkOrphan", off,
        "Inconsistent storage charge/discharge links or missing OperationalLifeStorage. Check Par_TechnologyToStorage/Par_TechnologyFromStorage.")

    # 14 — Negative values in physically nonnegative parameters
    off = Tuple{Symbol,Int,Float64}[]
    for pname ∈ (:CapitalCost, :FixedCost, :VariableCost, :SpecifiedAnnualDemand,
                 :ResidualCapacity, :TotalAnnualMaxCapacity, :TotalAnnualMinCapacity,
                 :AnnualMinNewCapacity, :AnnualMaxNewCapacity, :CapacityFactor,
                 :AvailabilityFactor, :OperationalLife, :CapitalCostStorage,
                 :ResidualStorageCapacity, :TradeCapacity, :CapacityToActivityUnit)
        daa = getfield(Params, pname)
        nneg = count(<(0), daa.data)
        nneg > 0 && push!(off, (pname, nneg, minimum(daa.data)))
    end
    report!(:error, "NegativeValues", off,
        "Negative entries in physically nonnegative parameters (parameter, count, most negative value).")

    # 24 — Base-year group-capacity cone vs residual fleet
    gmax = Params.GroupTotalAnnualMaxCapacity
    gmin = Params.GroupTotalAnnualMinCapacity
    y0 = Switch.StartYear ∈ collect(axes(gmax)[3]) ? Switch.StartYear : first(𝓨)
    off = Tuple{String,String,Int,String}[]
    for ts ∈ axes(gmax)[1], rs ∈ axes(gmax)[2]
        techs = intersect(get(Params.Tags.TagTechnologyToSubsets, ts, String[]), 𝓣)
        regs  = intersect(get(Params.Tags.TagRegionToSubsets, rs, String[]), 𝓡)
        (isempty(techs) || isempty(regs)) && continue
        tot = sum(Params.ResidualCapacity[r,t,y0] for r ∈ regs for t ∈ techs)
        mn, mx = gmin[ts,rs,y0], gmax[ts,rs,y0]
        if mn > 0 && tot < mn
            push!(off, (string(ts), string(rs), Int(y0),
                "residual $(round(tot, digits=4)) < GroupMin $(mn)"))
        end
        if mx < 999999 && tot > mx
            push!(off, (string(ts), string(rs), Int(y0),
                "residual $(round(tot, digits=4)) > GroupMax $(mx)"))
        end
    end
    report!(:error, "BaseYearGroupCapacityCone", off,
        "Summed ResidualCapacity in the start year falls outside the group capacity cone — hard-infeasible since start-year new builds are fixed to 0.")

    # 15 — WARNING: AvailabilityFactor missing although ResidualCapacity set
    off = [(r, t, y) for r ∈ 𝓡 for t ∈ 𝓣 for y ∈ 𝓨
           if Params.ResidualCapacity[r,t,y] != 0 && Params.AvailabilityFactor[r,t,y] == 0]
    report!(:warn, "AvailabilityFactorMissing", off,
        "AvailabilityFactor missing for a Technology with ResidualCapacity. Check Par_AvailabilityFactor.")

    # 16 — WARNING: efficiency > 1 outside Resources/Transportation
    off = Tuple{String,String,Int,Int}[]
    for t ∈ 𝓣
        (Params.Tags.TagTechnologyToSector[t,"Resources"] != 0 ||
         Params.Tags.TagTechnologyToSector[t,"Transportation"] != 0) && continue
        for r ∈ 𝓡, m ∈ 𝓜, y ∈ 𝓨
            sout = sum(Params.OutputActivityRatio[r,t,f,m,y] for f ∈ 𝓕)
            sin  = sum(Params.InputActivityRatio[r,t,f,m,y] for f ∈ 𝓕)
            if sout != 0 && sin != 0 && sin / sout < 1
                push!(off, (r, t, m, y))
            end
        end
    end
    report!(:warn, "TechnologyEfficiencies", off,
        "Technology efficiency above 1 (input sum < output sum) outside Resources/Transportation.")

    # 17 — WARNING: ResidualCapacity above TotalAnnualMaxCapacity
    off = [(r, t, y, Params.ResidualCapacity[r,t,y], Params.TotalAnnualMaxCapacity[r,t,y])
           for r ∈ 𝓡 for t ∈ 𝓣 for y ∈ 𝓨
           if Params.TotalAnnualMaxCapacity[r,t,y] < 999999 &&
              Params.ResidualCapacity[r,t,y] > Params.TotalAnnualMaxCapacity[r,t,y]]
    report!(:warn, "ResidualAboveMaxCapacity", off,
        "ResidualCapacity exceeds TotalAnnualMaxCapacity (GAMS: ToSmallResidualCapacity). The capacity bound will clip existing capacity.")

    # 18 — WARNING: demand year-gaps (start-year demand, zero later)
    off = Tuple{String,String,Int}[]
    for r ∈ 𝓡, f ∈ 𝓕
        Params.SpecifiedAnnualDemand[r,f,𝓨[1]] != 0 || continue
        for y ∈ 𝓨[2:end]
            Params.SpecifiedAnnualDemand[r,f,y] == 0 && push!(off, (r, f, y))
        end
    end
    report!(:warn, "DemandYearGap", off,
        "Demand set in the start year but exactly zero in a later year — missing per-year rows are silently zero (switch_endogenous_specifieddemandforecasting=0).")

    # 19 — WARNING: asymmetric trade routes
    off = Tuple{String,String,String}[]
    for f ∈ 𝓕
        Params.Tags.TagCanFuelBeTraded[f] != 0 || continue
        for r ∈ 𝓡, rr ∈ 𝓡
            r == rr && continue
            if any(Params.TradeRoute[r,rr,f,y] != 0 for y ∈ 𝓨) &&
               all(Params.TradeRoute[rr,r,f,y] == 0 for y ∈ 𝓨)
                push!(off, (r, rr, f))
            end
        end
    end
    report!(:warn, "AsymmetricTradeRoute", off,
        "TradeRoute defined in one direction only. Check Par_TradeRoute for the reverse direction.")

    # 20 — WARNING: share parameters above 1
    off = Tuple{String,String}[]
    for (pname, daa) ∈ (("AvailabilityFactor", Params.AvailabilityFactor),
                        ("CapacityFactor", Params.CapacityFactor),
                        ("MinStorageCharge", Params.MinStorageCharge))
        n = count(>(1 + 1e-9), daa.data)
        n > 0 && push!(off, (pname, "$(n) entries > 1 (max $(round(maximum(daa.data), digits=4)))"))
    end
    if !isempty(𝓜𝓽)
        n = count(>(1 + 1e-9), Params.ModalSplitByFuelAndModalType.data)
        n > 0 && push!(off, ("ModalSplitByFuelAndModalType", "$(n) entries > 1"))
    end
    report!(:warn, "ShareAboveOne", off,
        "Share-type parameters contain values above 1.")

    # 21 — WARNING: RE target without RE-tagged producer
    off = Tuple{String,String,Int}[]
    for r ∈ 𝓡, f ∈ 𝓕, y ∈ 𝓨
        Params.REMinProductionTarget[r,f,y] > 0 || continue
        has_re = any(Params.Tags.RETagTechnology[r,t,y] != 0 &&
                     any(Params.OutputActivityRatio[r,t,f,m,y] != 0 for m ∈ 𝓜) for t ∈ 𝓣)
        has_re || push!(off, (r, f, y))
    end
    report!(:warn, "RETargetWithoutRETech", off,
        "REMinProductionTarget set but no RE-tagged technology produces the fuel in the region.")

    # 22 — WARNING: dead capacity (capacity data for techs without any activity ratio)
    off = Tuple{String,String}[]
    for t ∈ setdiff(𝓣, active_techs)
        t ∈ dummy_techs && continue
        any(Params.ResidualCapacity[r,t,y] != 0 for r ∈ 𝓡 for y ∈ 𝓨) &&
            push!(off, (t, "ResidualCapacity set"))
        any(0 < Params.TotalAnnualMaxCapacity[r,t,y] < 999999 for r ∈ 𝓡 for y ∈ 𝓨) &&
            push!(off, (t, "TotalAnnualMaxCapacity set"))
    end
    report!(:warn, "DeadCapacity", off,
        "Capacity data given for a technology that has no input or output activity ratio anywhere.")

    # 23 — WARNING: switch/data mismatches
    off = Tuple{String,String}[]
    if Switch.switch_reserve == 1 && all(Params.ReserveMargin[r,y] == 0 for r ∈ 𝓡 for y ∈ 𝓨)
        push!(off, ("switch_reserve", "enabled but ReserveMargin is zero everywhere"))
    end
    if Switch.switch_employment_calculation == 1 && isempty(Switch.employment_data_file)
        push!(off, ("switch_employment_calculation", "enabled but employment_data_file is empty"))
    end
    report!(:warn, "SwitchDataMismatch", off,
        "A switch is enabled but the data it needs is missing.")

    # Full offender lists to file, IIS-style naming, before any abort
    if !isempty(findings)
        fn = joinpath(Switch.resultdir[], "Errorcheck_$(Switch.elmod_nthhour)_$(today()).txt")
        open(fn, "w") do f
            println(f, "genesysmod_errorcheck — $(Dates.now())")
            println(f, "model_region=$(Switch.model_region) pathway=$(Switch.emissionPathway) scenario=$(Switch.emissionScenario)")
            println(f, "="^80)
            for block in findings
                println(f, block)
                println(f)
            end
        end
        println("Build:   errorcheck : findings written to $(fn)")
    end

    if nerrors > 0
        if Switch.switch_errorcheck == 2
            error("genesysmod_errorcheck: $(nerrors) input-data check(s) failed — see the error log above. " *
                  "Fix the input data, or lower switch_errorcheck to continue anyway.")
        else
            @warn "genesysmod_errorcheck: $(nerrors) input-data check(s) failed (continuing; set switch_errorcheck=2 to abort on these)"
        end
    else
        println("Build:   errorcheck : no hard input-data errors")
    end
    return
end
