# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

GENeSYS-MOD.jl — a Julia/JuMP linear-optimization model of energy systems.
It reads scenario data from Excel, builds a large LP, solves it
(HiGHS / Gurobi / CPLEX), and writes results.

## Running

- **Tests:** `julia --project -e 'using Pkg; Pkg.test()'` (or `]test`).
  Test scripts live in `test/` (`test.jl`, `test_middleearth.jl`,
  `test_europe.jl`). `runtests.jl` must not call `Pkg.develop` — CI runs in a
  sandboxed test environment where `Pkg` is not available.
- **Entry point:** `genesysmod(; elmod_daystep, elmod_hourstep, solver,
  DNLPsolver, ...)` in `src/genesysmod_main.jl`. `genesysmod_build_model(...)`
  builds the model without solving.
- **Inputs:** `RegularParameters_*.xlsx` + `Timeseries_*.xlsx` in `inputdir`.

## Architecture (`src/`)

- `genesysmod_main.jl` — entry points + run pipeline (build → solve → results);
  prints a build/solve/results time breakdown.
- `genesysmod_dataload.jl` — reads the input Excel; `make_mapping`, `read_sets`.
- `genesysmod_dec.jl` — JuMP variable declarations.
- `genesysmod_equ.jl` — constraint generation. Largest file; the build hot path.
  Prints per-section timings (`Cstr: ...`).
- `genesysmod_bounds.jl`, `genesysmod_settings.jl` — bounds and run settings.
- `genesysmod_variable_parameter.jl`, `genesysmod_results.jl`,
  `genesysmod_results_raw.jl` — post-solve result processing.
- `genesysmod_db.jl` — DuckDB result + input-data databases (writers, `Scenario`
  keying, handle release/retry).
- `genesysmod_errorcheck.jl` — input-data validation (port of
  `genesysmod_errorcheck.gms`).
- `datastructures.jl` — `Sets`, `Parameters`, `Variables`, `Maps`, `Settings`,
  `Variable_Parameters` structs.
- `utils.jl` — `create_daa` (builds parameter `DenseAxisArray`s),
  `convert_jump_container_to_df`.

## Outputs, databases & input checks

- **Result CSVs** are written when `switch_processed_results = 1`. Processed
  outputs are rounded to 4 digits (GAMS parity).
- **DuckDB database** (`switch_results_db = 1`): one file, `genesysmod_db.duckdb`
  in `resultdir` (results + input data merged) — processed tables (`output_*`),
  raw variables (`raw_*`), `Variable_Parameters` intermediates (`varpar_*`) and
  selected duals (`duals_*`). Every table carries a `Scenario` column
  (= `extr_str_results`): re-running a scenario first purges its rows from every
  table, a new scenario name appends. Independent of the CSV switch.
- **Run configuration** is recorded with the results: every `Switch` field is
  written to an `output_switches` table/CSV, so a run's exact setup travels with
  its outputs.
- **Input-data dump**: `switch_test_data_load = 1` dumps the fully processed
  input parameters into the same file as `input_*` tables (one per parameter
  and per set, real dimension names, `Params.Tags` included) and stops before
  the solve; `switch_dump_input_data = 1` writes the same dump and continues.
- Raw dumps and DB tables use **real dimension names** (Region, Technology, Fuel,
  Year, …), not `x1..xN`.
- DB handles are released at run end (`release_dbs()`, exported); a write blocked
  by an external reader holding the file is queued and flushed via
  `retry_db_writes()` (exported) rather than crashing the run.
- **Input-data checks** (`genesysmod_errorcheck.jl`, run after bounds /
  scenario data): `switch_errorcheck` — `0` skip, `1` report-only, `2` (default)
  abort on hard checks. Full offender lists go to `Errorcheck_<nthhour>_<date>.txt`.

## Conventions & gotchas

- `𝓨` (`Sets.Year`) must be **sorted ascending** — intertemporal logic uses
  positional `𝓨[i-1]` / `𝓨[i+1]`. `read_sets` sorts it.
- Parameters use `inherit_base_world`: data stored only under region `World` is
  inherited by every region. Many parameters are World-only by design.
- `Vars.RateOfActivity` is a **`SparseAxisArray`** declared over
  `(t,m) ∈ Maps.Set_Tech_MO`. Index only valid `(t,m)` pairs — iterate
  `m ∈ Maps.Tech_MO[t]`, never all modes — or you get a `KeyError`.
- `Variable_Parameters.RateOfProductionByTechnologyByMode` /
  `RateOfUseByTechnologyByMode` are sparse `Dict`s keyed `(y,l,t,m,f,r)`;
  read with `get(d, key, 0.0)`.
- Year-keyed settings (`PhaseIn` / `PhaseOut` in `genesysmod_settings.jl`) are
  interpolated to every modelled year via `_fill_year_dict`, so the model runs
  at any time resolution.
- Code uses Unicode set aliases: `𝓨` year, `𝓡` region, `𝓣` technology,
  `𝓕` fuel, `𝓜` mode, `𝓛` timeslice, `𝓢` storage, `𝓔` emission. 2-space indent
  inside functions.
- `switch_endogenous_specifieddemandforecasting` (default 1) forecasts later-year
  demand from the base year via `SpecifiedDemandDevelopment`; set 0 to use the
  per-year values in `Par_SpecifiedAnnualDemand` directly.

## Performance

- The build and results phases have been optimized; `optimize!` (the solver)
  dominates total runtime. Micro-optimizing build/results has diminishing
  returns — solve time needs model-size reduction or solver tuning.
- The storage constraint block in `genesysmod_equ.jl` is the largest single
  constraint contributor and is the next structural target.

## Reference implementation (GAMS)

This package is a port of the original GAMS model in the separate
**`GENeSYS_MOD.gms`** repository.

- `genesysmod_equ.jl` mirrors `genesysmod_equ.gms`; constraint names match.
  GAMS `$` conditions map to Julia `if` / guarded loops (`not X` → `== 0`);
  parameter index order must match exactly.
- `genesysmod_scenariodata_europe.jl` mirrors
  `genesysmod_scenariodata_europe.gms`. In GAMS the `emissionPathway` switch
  picks an `$ifthen` branch (`NECPEssentials` / `REPowerEU` / `Green` /
  `Trinity`); the Julia version selects the equivalent branch by scenario.
  The `NECPEssentials` branch adds the `NECPCapacityPlans` data, the
  `necp_released` set, and the `NECPCapacityExpansion` constraints.

## Input data

The input Excel files are generated from the separate **`GENeSYS_MOD.data`**
repository: per-parameter CSVs → combined Excel via the Python tools in
`Conversion Script/`. That data repo is not part of this repository.
