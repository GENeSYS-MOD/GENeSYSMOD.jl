Release Notes
=============

## Unregistered
- Fix calculation of resource costs when using duals (not using LCOE_calc switch) for fuels that are time independant

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
