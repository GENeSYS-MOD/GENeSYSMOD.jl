Release Notes
=============

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
