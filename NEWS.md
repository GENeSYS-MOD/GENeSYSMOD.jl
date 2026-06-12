Release Notes
=============

## Unreleased
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
- `load_reduced_timeserie = 1` skips the timeseries-reduction NLP and loads a
  previously written reduced timeseries from `inputdir` (pairs with
  `write_reduced_timeserie`).
- Further build-pipeline performance work (dataload parameter fills, smoothing
  window, SumCapacityFactor): model formulation untouched, MPS-verified identical.

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
