Release Notes
=============

## v4.4.1
- Emission-limit constraints (E8/E9/E10/E13) are only generated when a real limit is
  set (`< 999999`) instead of always adding a toothless `<= ~1e6` row; dual lookups
  for these limits (endogenous CO2 price, `CarbonPrice`) return 0 when the constraint
  is absent instead of erroring.
- Results (and dispatch) are written on any feasible primal solution
  (`primal_status == FEASIBLE_POINT`), not only a certified `OPTIMAL` — a
  crossover-free barrier solution is no longer silently dropped.
- `TagTimeIndependentFuel` is now read from the input data
  (`Par_TagTimeIndependentFuel` sheet) instead of a hard-coded fuel list.
- Base-year debug slack variables (`BaseYearBounds_*`, `HeatingSlack`) are only built
  when `switch_base_year_bounds_debugging == 1` (leaner production LP); the BigM
  penalty is lowered 9999 → 1000.
- Group capacity limits (TCC3/TCC4) are only built on the investment path; ramping
  limits are scaled by `elmod_hourstep`; `CapacityFactor` values below 0.01 are zeroed
  after timeseries reduction; Gurobi runs with `NumericFocus=1` and `ScaleFlag=2`.
- The input-data database dump now also includes `Params.Tags`.
- Fixes: `df_total_capacity` no longer drops technologies via a stray subset;
  `read_emissions` reads `AnnualEmissions_*.csv` (was the storage-capacity file); the
  empty-trade dummy uses an existing fuel; empty per-technology sums use `init=0.0`.
- HiGHS now requires `1.22` (needed for the bitmask `iis_strategy`).

## v4.4.0
- **DuckDB result + input databases.** With `switch_results_db = 1`, all outputs
  (processed result tables, raw variables, `Variable_Parameters` intermediates) are
  written to a single `genesysmod_results_db.duckdb` in the result directory. Every
  table carries a `Scenario` column (= `extr_str_results`): re-running a scenario first
  purges its rows from *every* table, a new scenario name appends — multi-run
  comparisons become a SQL query instead of CSV merging. `switch_processed_results`
  now gates only the CSV files; the database is independent. Database handles are
  released at the end of each run (`release_dbs()`, exported); writes blocked by an
  external reader (Tableau, DBeaver) no longer crash the run — they are queued and
  flushed via `retry_db_writes()` (exported) after closing the file. For Tableau via
  the DuckDB JDBC/taco connector, a `.tdc` with `CAP_CREATE_TEMP_TABLES=no` /
  `CAP_SELECT_INTO=no` avoids temp-table errors when creating 3+ groups.
- `switch_test_data_load = 1` dumps the fully processed input parameters (one table
  per parameter, real dimension names) to `genesysmod_inputdata_db.duckdb` and stops
  before the solve; `switch_dump_input_data = 1` writes the same dump but continues
  into the solve.
- Raw CSV dumps and database tables now use real dimension names (Region, Technology,
  Fuel, Year, ...) instead of `x1..xN` / `dim1..dimN`, derived automatically from the
  model sets.
- **Input-data error checks** (port of `genesysmod_errorcheck.gms`), run after
  bounds/scenariodata: hard checks abort the run (missing sector tags /
  OperationalLife / CapacityToActivityUnit / CapacityFactor, trade inconsistencies,
  ModalSplit sums > 1, demand without producer, min > max bounds, emission limit below
  exogenous floor, demand-profile/YearSplit normalization, storage link orphans,
  negative values, base-year group-capacity cone), soft checks warn. Full offender
  lists go to `Errorcheck_<nthhour>_<date>.txt`. `switch_errorcheck`: 0 = skip,
  1 = report-only, 2 (default) = abort on hard errors.
- Processed result tables are rounded to 4 digits (GAMS parity), removing the e-09
  noise rows produced by barrier runs without crossover. Fixed `output_model` writing
  literal `:Col => value` Pair strings into every cell; elapsed time is now numeric
  seconds.
- New `switch_endogenous_specifieddemandforecasting` (default 1 = unchanged legacy
  behaviour: demand for later years is forecast from the base year via
  `SpecifiedDemandDevelopment` growth). Set to 0 to use the per-year values from
  `Par_SpecifiedAnnualDemand` directly — for datasets that provide explicit demand
  trajectories per year.
- `load_reduced_timeserie = 1` skips the timeseries-reduction NLP and loads a
  previously written reduced timeseries from `inputdir` (pairs with
  `write_reduced_timeserie`).
- Further build-pipeline performance work (dataload parameter fills, smoothing
  window, SumCapacityFactor): model formulation untouched, MPS-verified identical.
- Selected duals can be written to the DuckDB results database: with
  `switch_results_db = 1`, `genesysmod_getspecifiedduals` / `genesysmod_getdualsbyname`
  also write their (constraint, dual) frames to `duals_<label>` tables, keyed by
  scenario like the other result tables.
- The exact run configuration is recorded with the results: a new `output_switches`
  table maps every `Switch` field to its value (processed-result CSVs and the DuckDB).
- Additional input-data error checks: cost year-gaps (a cost parameter nonzero in
  some modelled years but zero in an intermediate year, which `create_daa` does not
  interpolate — effectively free to build in the gap); and, with
  `switch_base_year_bounds`, base-year production exceeding the residual fleet's
  maximum generation (hard) or the fuel's demand (warning).

## v4.3.0
- Added a new tag ``TagRegionToSubsets``, two new parameters ``GroupTotalAnnualMaxCapacity`` and ``GroupTotalAnnualMinCapacity``, as well as two new constraints ``TCC3`` and ``TCC4``. These are fully optional, but allow for flexible creation of aggregated upper and lower bounds for installed capacities.
- Improved iis handling behavior, especially with the open HiGHS solver.
- Fixed an issue with old technology names in ramping bounds. 

## v4.2.0
- Major performance and memory-efficiency improvements to the model run pipeline (build and results processing). On the Europe test case: total runtime ~-39%, peak RAM ~-39%, results-processing phase ~-94%. The optimization model is unchanged — solver objective values are identical before/after.
- Results processing: the 6-D `RateOfProductionByTechnologyByMode` and `RateOfUseByTechnologyByMode` containers in `Variable_Parameters` are now sparse `Dict`s instead of dense `DenseAxisArray`s. Downstream code indexing these must use `get(d, key, 0.0)`.
- Constraint generation: hoisted repeated computations and cached JuMP bound queries; `CA3c` guarded by `CanBuildTechnology`; storage constraints iterate precomputed `(tech, mode)` pairs.
- Data loading: single-pass `make_mapping`; faster `create_daa` hierarchy fill.
- `convert_jump_container_to_df` rewritten to iterate only non-zero entries; added a `Dict` method.
- Added a build/solve/results time-breakdown printout to model runs.
- Fix calculation of resource costs when using duals (not using LCOE_calc switch) for fuels that are time independant.
- Implementing changes of [PR 38 of the GAMS version](https://github.com/GENeSYS-MOD/GENeSYS_MOD.gms/pull/38) to be aligned between both.

## v4.1.1
- Fixed an issue with the testing scripts when installing via package 

## v4.1.0
- Add function to retrieve updated datafiles from the data repository via cloning, pulling and processing using custom filter file and corresponding tests.
- Add function to retrieve generic datafiles from releases of the data repository and corresponding tests.
- Fix missing definition of AnnualMaxNewCapacity for Dummy Technologies.
- change of julia minimun requirements
- Various fixes to Dispatch
- Possibility to pass argeument to solver through a dictionary in solver_attr and to activate logging via solver_log
  
## v4.0.0
- First registered release
- Feature parity with the GAMS version of GENeSYS-MOD (GENeSYS_MOD.gms) v4.0.2
- Compatible with data from the GENeSYS_MOD.data in v1.0.4
