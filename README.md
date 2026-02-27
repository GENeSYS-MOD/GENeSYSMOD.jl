[![Model docs](https://img.shields.io/badge/Model%20docs%20-%20blue)](https://genesysmod.readthedocs.io/en/latest/index.html#)
[![Julia docs](https://img.shields.io/badge/.jl%20docs%20-%20stable%20-%20blue)](https://genesys-mod.github.io/GENeSYSMOD.jl/)
[![CI](https://github.com/GENeSYS-MOD/GENeSYSMOD.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/GENeSYS-MOD/GENeSYSMOD.jl/actions/workflows/ci.yml)

# GENeSYSMOD.jl
The Global Energy System Model - or GENeSYS-MOD - is an open source cross-sectoral energy system model aimed at long-term developments of the energy system.

GENeSYS-MOD is originally based on the Open-Source Energy Modeling System (OSeMOSYS) framework. While still part of the OSeMOSYS family of models, various aspects have been redesigned, expanded, or added. GENeSYS-MOD is a linear program, minimizing total system costs. Energy demands are exogenously predefined and the model needs to provide the necessary capacities to meet them. The modeling framework is very flexible in its use cases. Based on research question and input data, calculations can be done from a household-basis to a global aggregation of regions.

The model covers the sectors electricity, buildings, industry, and transport. It also includes all linkages between those sectors, as well as flexibility options and energy trade between regions.

You can learn more about the model, its origins and mathematical formulation in the [Model documentation](https://genesysmod.readthedocs.io/en/latest/about.html).
You can learn more about the Julia implementation and the Julia specific features in the [docs](https://genesys-mod.github.io/GENeSYSMOD.jl/).
