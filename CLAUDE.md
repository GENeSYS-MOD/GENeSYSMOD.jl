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
- `datastructures.jl` — `Sets`, `Parameters`, `Variables`, `Maps`, `Settings`,
  `Variable_Parameters` structs.
- `utils.jl` — `create_daa` (builds parameter `DenseAxisArray`s),
  `convert_jump_container_to_df`.

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

## Performance

- The build and results phases have been optimized; `optimize!` (the solver)
  dominates total runtime. Micro-optimizing build/results has diminishing
  returns — solve time needs model-size reduction or solver tuning.
- The storage constraint block in `genesysmod_equ.jl` is the largest single
  constraint contributor and is the next structural target.

## Input data

The input Excel files are generated from the separate **`GENeSYS_MOD.data`**
repository: per-parameter CSVs → combined Excel via the Python tools in
`Conversion Script/`. That data repo is not part of this repository.
