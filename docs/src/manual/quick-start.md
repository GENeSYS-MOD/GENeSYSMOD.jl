# Quick Start

## Installation

1.	We suggest using [Visual Studio Code](https://code.visualstudio.com/).

2.	Download the latest stable version of [the Julia Programming Language (julialang.org)](https://julialang.org/downloads/).

3.	Install Julia extension in Visual Studio Code:
  * Click 'Extensions' buttion in Visual Studio Code on the left ribbon.
  * Search for 'Julia', then install. 

4.	Download an optimization solver and get a license:
  *	Gurobi
    - Academic licensed are issued by [Gurobi](https://www.gurobi.com/academia/academic-program-and-licenses/).
    - Commercial License.
  *	[CPLEX](https://www.ibm.com/products/ilog-cplex-optimization-studio/cplex-optimizer)
  *	[HiGHS](https://highs.dev/), open source solver.

5.	[Optional] This step is optional and can be skipped if you only want to run the model and do not need to look into the code behind the model. If you choose to clone, follow steps 6 and 7 as well, otherwise go to step 8. Clone the GitHub repository for [GENeSYSMOD.jl](https://github.com/GENeSYS-MOD/GENeSYSMOD.jl)
  *	Download git: [Git - Downloads](https://git-scm.com/)
  *	Navigate to the folder where you want the repo to be located.
  * Open Git Bash by right clicking in the chosen folder and choosing "Git Bash Here"
  * Type the following command in Git Bash:

```
git clone https://github.com/GENeSYS-MOD/GENeSYSMOD.jl.git
git pull
```

6.	[Optional] Open GENeSYS-MOD folder in Visual Studios
  *	File > Open folder

7.	[Optional] Change to Julia environment for GENeSYSMOD.jl.

8.  Open the Julia REPL by using the Alt+J+O command. The REPL(read-eval-print loop) is the interactive command line interface in Julia.

9.	Install packages in Visual Studio:
  *	In the REPL terminal, type ']' to change to enter pkg mode
  * Type 'add <package>', where package is equal to:
    - GENeSYSMOD
    - JuMP
    - Dates
    - XLSX
    - DataFrames
    - CSV	
    - Ipopt
    - <your chosen solver>

10.	You have now installed all packages necessary to run GENeSYS-MOD and can run a case by using the genesysmod function. Examples can be found in the tests.

## Running a case

Create a folder where you will be able to store your scripts, inputs and outputs of the model. 

If you have cloned the repository and plan on changing the code of the model locally, you can then include the following at the top of your script: 

```julia
Pkg.develop(path="..\\GENeSYSMOD.jl")
using GENeSYSMOD
```
Where you replace the path with the relative or absolute path to the package. Note the "\\".

Otherwise (**RECOMMENDED**), for simply running the model without modifying the model or constraints, use:
```julia
using GENeSYSMOD
```

You can then run the model by running the function `genesysmod` with the appropriate `Switch`.


## Using the published dataset

A dataset is published on the repository GENeSYS-MOD.data: (https://github.com/GENeSYS-MOD/GENeSYS_MOD.data)
This repository contains the data including the sources and assumptions necessay to run the model at a european level with a country resolution. Data for over regions may be added with time. 
It also contains the tools necessary to produce the input file for the model from this data. The tools are accessed via a jupyter notebook script. More information can be found on the repository.

You can directly retrieve preprocessed datafiles that are part of releases of the data repository for the main geographic scopes and storylines. To do this you can use the `fetch_data_release` function.

It is also possible to use the function `update_and_process_data` to automatically clone the data repository if needed, pull the latest changes and create the input files based on your own requirements of e.g. countries, and technologies to include, defined in the file `Set_filter_files.xlsx`. In order to do this, you first need to copy the file CondaPkg.toml to your work directory and add a call to CondaPkg to your code:
```julia
using CondaPkg
```