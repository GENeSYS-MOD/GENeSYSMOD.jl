"""
Returns a `DataFrame` with the values of the variables from the JuMP container `var`.
The column names of the `DataFrame` can be specified for the indexing columns in `dim_names`,
and the name of the data value column by a Symbol `value_col` e.g. :Value
"""
function convert_jump_container_to_df(var::JuMP.Containers.DenseAxisArray;
    dim_names::Vector{Symbol}=Vector{Symbol}(),
    value_col::Symbol=:Value)

    if isempty(var)
        return DataFrame()
    end

    if length(dim_names) == 0
        dim_names = [Symbol("dim$i") for i in 1:length(var.axes)]
    end

    if length(dim_names) != length(var.axes)
        throw(ArgumentError("Length of given name list does not fit the number of variable dimensions"))
    end

    tup_dim = (dim_names...,)
    # Skip the copy when the container already holds plain numbers
    var_val = eltype(var) <: Number ? var : value.(var)

    # Iterate only the nonzero entries instead of the full Cartesian product
    ax = var_val.axes
    data_arr = var_val.data
    nz = findall(!iszero, data_arr)

    if isempty(nz)
        push!(dim_names, :Value)
        return DataFrame([[] for i in dim_names], dim_names)
    end

    df = DataFrame([NamedTuple{tup_dim}(map(getindex, ax, Tuple(idx))) for idx in nz])
    df[!, value_col] = [data_arr[idx] for idx in nz]
    return df
end

function convert_jump_container_to_df(var::JuMP.Containers.SparseAxisArray;
    dim_names::Vector{Symbol}=Vector{Symbol}(),
    value_col::Symbol=:Value)

    if isempty(var)
        return DataFrame()
    end

    # Use axes from SparseAxisArray
    if length(dim_names) == 0
        dim_names = [Symbol("dim$i") for i in 1:length(var.axes)]
    end

    if length(dim_names) != length(var.names)
        throw(ArgumentError("Length of given name list does not fit the number of variable dimensions"))
    end

    tup_dim = (dim_names...,)
    var_val = eltype(var) <: Number ? var : value.(var)

    keys = eachindex(var)
    if !isempty(keys)
        pairs_nz = [(ind, var_val[ind...]) for ind in keys if var_val[ind...] != 0]
        df = DataFrame([NamedTuple{tup_dim}(p[1]) for p in pairs_nz])
        df[!, value_col] = [p[2] for p in pairs_nz]
    else
        push!(dim_names, :Value)
        df = DataFrame([[] for i in dim_names], dim_names)
    end
    return df
end

"""
Creates DenseAxisArrays containing the input parameters to the model considering hierarchy
with base region data and world data.

The function creates a DenseAxisArray for a given parameter indexed by the given sets. The
values are intialized to 0. If copy world is true, the value for the region world are copied.
If inherit_base_world is 1, missing data will be fetched from the base region if they exist
and again from the world region if necessary.
"""
function create_daa(in_data::XLSX.XLSXFile, tab_name, els...;inherit_base_world=false,copy_world=false, base_region="DE") # els contains the Sets, col_names is the name of the columns in the df as symbols
    df = DataFrame(XLSX.gettable(in_data[tab_name];first_row=1))
    # Initialize all combinations to zero:
    A = JuMP.Containers.DenseAxisArray(
        zeros(length.(els)...), els...)
    # Fill in values from Excel
    for r in eachrow(df)
        try
            A[r[1:end-1]...] = r.Value
        catch err
            @debug err
        end
    end
    # Fill other values using base region
    if inherit_base_world
        other_regions = filter(r -> r != base_region && r != "World", collect(els[1]))
        for x in Base.Iterators.product(other_regions, els[2:end]...)
            if A[x...] == 0.0
                base_val = A[base_region, x[2:end]...]
                if base_val != 0.0
                    A[x...] = base_val
                else
                    world_val = A["World", x[2:end]...]
                    if world_val != 0.0
                        A[x...] = world_val
                    end
                end
            end
        end
    end
    if copy_world
        for x in Base.Iterators.product(els[2:end]...)
            world_val = A["World", x...]
            for r in els[1]
                A[r, x...] = world_val
            end
        end
    end
    #if tab_name == "Par_CapacityToActivityUnit"
        #for x in Base.Iterators.product(els...)
            #if A[base_region, x[2:end]...] != 0.0
            #    A[x...] = A[base_region, x[2:end]...]
            #elseif A["World", x[2:end]...] != 0.0
            #    A[x...] = A["World", x[2:end]...]
            #else
            #    A[x...] = 0.0
            #end
        #end
    #end
    if tab_name == "Par_EmissionsPenalty"
        for x in Base.Iterators.product(els[2:end]...)
            base_val = A[base_region, x...]
            for r in els[1]
                A[r, x...] = base_val
            end
        end
    end
    return A
end

function read_subsets(in_data::XLSX.XLSXFile, tab_name)
    df = DataFrame(XLSX.gettable(in_data[tab_name];first_row=1))

    A=Dict()
    for sub in unique(df.Subset)
        A[sub]=[x for x in df[df.Subset .== sub .&& df.Value .== 1,1]]
    end
    return A
end

#= function create_daa(in_data::XLSX.XLSXFile, tab_name, cdims)
    df = DataFrame(XLSX.gettable(in_data[tab_name];first_row=1))

    # Initialize all combinations to zero:
    A = JuMP.Containers.DenseAxisArray(
        zeros(length.([unique(df[:,x]) for x in 1:cdims])...), [unique(df[:,x]) for x in 1:cdims]...)
    # Fill in values from Excel
    for r in eachrow(df)
        try
            A[r[1:end-1]...] = r.Value
        catch err
            @debug err
        end
    end
    return A
end =#

function create_daa(in_data::DataFrame, tab_name, els...) # els contains the Sets, col_names is the name of the columns in the df as symbols
    df = in_data
    # Initialize all combinations to zero:
    A = JuMP.Containers.DenseAxisArray(
        zeros(length.(els)...), els...)
    # Fill in values from Excel
    for r in eachrow(df)
        try
            A[r[1:end-1]...] = r.y
        catch err
            @debug err
        end
    end
    return A
end

"""
Create dense axis array initialized at a given value.
"""
function create_daa_init(in_data, tab_name,init_value=0, els...;inherit_base_world=false,copy_world=false, base_region="DE") # els contains the Sets, col_names is the name of the columns in the df as symbols
    df = DataFrame(XLSX.gettable(in_data[tab_name];first_row=1))
    # Initialize all combinations to zero:
    A = JuMP.Containers.DenseAxisArray(
        ones(length.(els)...)*init_value, els...)
    # Fill in values from Excel
    for r in eachrow(df)
        try
            A[r[1:end-1]...] = r.Value
        catch err
            @debug err
        end
    end
    # Fill other values using base region
    if inherit_base_world
        other_regions = filter(r -> r != base_region && r != "World", collect(els[1]))
        for x in Base.Iterators.product(other_regions, els[2:end]...)
            if A[x...] == init_value
                base_val = A[base_region, x[2:end]...]
                if base_val != init_value
                    A[x...] = base_val
                else
                    world_val = A["World", x[2:end]...]
                    if world_val != init_value
                        A[x...] = world_val
                    end
                end
            end
        end
    end
    if copy_world
        for x in Base.Iterators.product(els[2:end]...)
            world_val = A["World", x...]
            for r in els[1]
                A[r, x...] = world_val
            end
        end
    end
    #if tab_name == "Par_CapacityToActivityUnit"
        #for x in Base.Iterators.product(els...)
            #if A[base_region, x[2:end]...] != init_value
            #    A[x...] = A[base_region, x[2:end]...]
            #elseif A["World", x[2:end]...] != init_value
            #    A[x...] = A["World", x[2:end]...]
            #else
            #    A[x...] = init_value
            #end
        #end
    #end
    if tab_name == "Par_EmissionsPenalty"
        for x in Base.Iterators.product(els[2:end]...)
            base_val = A[base_region, x...]
            for r in els[1]
                A[r, x...] = base_val
            end
        end
    end
    return A
end

function specified_demand_profile(time_series_data,Sets)

    # Read table from Excel to DataFrame
    # Tbl = XLSX.gettable(time_series_data["Par_SpecifiedDemandProfile"];first_row=1)
    Tbl = XLSX.gettable(time_series_data["Par_SpecifiedDemandProfile"];
        header=false,
        infer_eltypes=true,
        column_labels=[:Region, :Fuel, :Timeslice, :Year, :Value])
    # return Tbl
    df = DataFrame(Tbl)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(Sets.Region_full), length(Sets.Fuel), length(Sets.Timeslice), length(Sets.Year)),
        Sets.Region_full, Sets.Fuel, Sets.Timeslice, Sets.Year)
    for r in eachrow(df)
        try
            A[r[1:end-1]...] = r.Value
        catch err
            @debug err
        end
    end

    # Instantiate data to zero
    # A = zeros(Ti())

    # for r in eachrow(df)
    #     println(r)
    # end

    return A
end

function year_split(time_series_data,Sets)

    # Read table from Excel to DataFrame
    # Tbl = XLSX.gettable(time_series_data["Par_SpecifiedDemandProfile"];first_row=1)
    Tbl = XLSX.gettable(time_series_data["Par_YearSplit"];
        header=false,
        infer_eltypes=true,
        column_labels=[:Timeslice, :Year, :Value])
    # return Tbl
    df = DataFrame(Tbl)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(Sets.Timeslice), length(Sets.Year)),
        Sets.Timeslice, Sets.Year)
    for r in eachrow(df)
        try
            A[r[1:end-1]...] = r.Value
        catch err
            @debug err
        end
    end

    # Instantiate data to zero
    # A = zeros(Ti())

    # for r in eachrow(df)
    #     println(r)
    # end

    return A
end

function capacity_factor(time_series_data,Sets)

    # Read table from Excel to DataFrame
    # Tbl = XLSX.gettable(time_series_data["Par_SpecifiedDemandProfile"];first_row=1)
    Tbl = XLSX.gettable(time_series_data["Par_CapacityFactor"];
        header=false,
        infer_eltypes=true,
        column_labels=[:Region, :Technology, :Timeslice, :Year, :Value])
    # return Tbl
    df = DataFrame(Tbl)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(Sets.Region_full), length(Sets.Technology), length(Sets.Timeslice), length(Sets.Year)),
        Sets.Region_full, Sets.Technology, Sets.Timeslice, Sets.Year)
    for r in eachrow(df)
        try
            A[r[1:end-1]...] = r.Value
        catch err
            @debug err
        end
    end

    # Instantiate data to zero
    # A = zeros(Ti())

    # for r in eachrow(df)
    #     println(r)
    # end

    return A
end

function read_x_peakingDemand(time_series_data,Sets)

    # Read table from Excel to DataFrame
    # Tbl = XLSX.gettable(time_series_data["Par_SpecifiedDemandProfile"];first_row=1)
    Tbl = XLSX.gettable(time_series_data["x_peaking_demand"];
        header=false,
        infer_eltypes=true,
        column_labels=[:Region, :Sector, :Value])
    # return Tbl
    df = DataFrame(Tbl)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(Sets.Region_full), length(Sets.Sector)),
        Sets.Region_full, Sets.Sector)
    for r in eachrow(df)
        try
            A[r[1:end-1]...] = r.Value
        catch err
            @debug err
        end
    end

    # Instantiate data to zero
    # A = zeros(Ti())

    # for r in eachrow(df)
    #     println(r)
    # end

    return A
end

"""
Write a text file containing the iis.

The function is used to write the iis to a file. By default the file is written in the working
directory and is named iis.txt. The function compute_conflict!(model) must be run beforehands.
The iis contains the set of constraint causing the infeasibility.
"""
function print_iis(model;filename="iis")
    list_of_conflicting_constraints = ConstraintRef[]
    for (F, S) in list_of_constraint_types(model)
        for con in all_constraints(model, F, S)
            if get_attribute(con, MOI.ConstraintConflictStatus()) == MOI.IN_CONFLICT
                push!(list_of_conflicting_constraints, con)
            end
        end
    end

    open("$(filename).txt", "w") do file
        for r in list_of_conflicting_constraints
            write(file, string(r)*"\n")
        end
    end
end

"""
Extension of split function to take lists of substrings and keep delimiters

"""
function split_by_substrings(text::AbstractString, substrings::Vector{<:AbstractString}; keepdelim=true)
    result = [text]
    delimiters = []
    for substr in substrings
        new_result = []
        for part in result
            pieces = split(part, substr, keepempty=true)
            for i in eachindex(pieces)
                push!(new_result,pieces[i])
                if i != length(pieces) && keepdelim == true
                    push!(new_result,substr)
                end
            end
        end
        result = new_result
        #result = [piece for part in result for piece in split(part, substr)]
    end
    return result
end

"""
Helper function to simplify the iis file and make the analysis easier.

The function simplify the iis by finding the equation of type x = 0 and reoplacing x in the other equations instead of doing that by hand.
The round_numerics and digits optional parameters can also be used to reduce the length of equation by rounding numbers.
It allows a faster analysis of iis files.
"""
function simplify_iis(file_path;output_filename="simplified_iis",round_numerics=true,digits=3)
    constraints = String[]

    # Read the file
    open(file_path) do file
        for line in eachline(file)
            # Extract equations or constraints
            push!(constraints, line)
        end
    end

    constraints_to_simplify = []
    simplified_constraints = []
    null_constraint_vars = []

    for con in constraints
        sides=split(con,"==")

        if length(sides) == 2
            lhs=sides[1]
            rhs=sides[2]
            lhs_els = split(lhs,['+','-'])
            if parse(Float64,rhs) == 0 && length(lhs_els) == 1
                push!(null_constraint_vars,lhs_els[1])
            else
                push!(constraints_to_simplify,con)
            end
        else
            push!(constraints_to_simplify,con)
        end
    end

    for con in constraints_to_simplify
        pieces = split_by_substrings(con,["==",">=","<="])
        lhs = pieces[1]
        sign = pieces[2]
        rhs = pieces[3]
        els=split(lhs,[' '])
        for var in null_constraint_vars
            var=strip(var) # remove leading and trailing whitespace
            if any(occursin(var, string) for string in els)
                for idx in findall(occursin(var, string) for string in els)
                    if idx == 1
                        deleteat!(els,idx)
                    else
                        i=0
                        while !(els[idx-i] == "+" || els[idx-i] == "-" || els[idx-i] == ":") && (idx-i != 0)
                            deleteat!(els,idx-i)
                            i+=1
                        end
                        if (idx-i != 0) && (els[idx-i] == "+" || els[idx-i] == "-")
                            deleteat!(els,idx-i)
                        end
                    end
                end
            end
        end

        if round_numerics == true
            for i in eachindex(els)
                if tryparse(Float64,els[i]) !== nothing
                    els[i]= "$(round(parse(Float64,els[i]);digits=digits))"
                end
            end
        end

        new_con=join(els)*sign*rhs
        push!(simplified_constraints,new_con)
    end

    open("$(output_filename).txt", "w") do file
        for r in simplified_constraints
            write(file, string(r)*"\n")
        end
    end
end

# assumption: the region is the first axe (otherwise do not use this function)
function aggregate_daa(full_daa, considered_region, full_region, mode::Sum, els...)
    new_daa = JuMP.Containers.DenseAxisArray(
        zeros(length(considered_region),length.(els)...), considered_region, els...)
    for x in Base.Iterators.product(els...)
        new_daa[considered_region[1],x...] = full_daa[considered_region[1],x...]
        new_daa[considered_region[2],x...] = sum(full_daa[r,x...] for r in full_region) - full_daa[considered_region[1],x...]
        if length(considered_region) >2
            new_daa[considered_region[3],x...] = full_daa[considered_region[3],x...]
        end
    end
    return new_daa
end

function aggregate_daa(full_daa, considered_region, full_region, mode::Mean, els...)
    new_daa = JuMP.Containers.DenseAxisArray(
        zeros(length(considered_region),length.(els)...), considered_region, els...)
    for x in Base.Iterators.product(els...)
        new_daa[considered_region[1],x...] = full_daa[considered_region[1],x...]
        new_daa[considered_region[2],x...] = (sum(full_daa[r,x...] for r in full_region) - full_daa[considered_region[1],x...])/(length(full_region)-1)
        if length(considered_region) >2
            new_daa[considered_region[3],x...] = full_daa[considered_region[3],x...]
        end
    end
    return new_daa
end

function aggregate_cross_daa(full_daa, considered_region, full_region, mode::Sum, els...)
    new_daa = JuMP.Containers.DenseAxisArray(
        zeros(length(considered_region),length(considered_region),length.(els)...), considered_region, considered_region, els...)
    for x in Base.Iterators.product(els...)
        new_daa[considered_region[1],considered_region[2],x...] = sum(full_daa[considered_region[1],r,x...] for r in full_region) - full_daa[considered_region[1],considered_region[1],x...]
        new_daa[considered_region[2],considered_region[1],x...] = sum(full_daa[r,considered_region[1],x...] for r in full_region) - full_daa[considered_region[1],considered_region[1],x...]
    end
    return new_daa
end

function aggregate_cross_daa(full_daa, considered_region, full_region, mode::Mean, els...)
    new_daa = JuMP.Containers.DenseAxisArray(
        zeros(length(considered_region),length(considered_region),length.(els)...), considered_region, considered_region, els...)
    for x in Base.Iterators.product(els...)
        new_daa[considered_region[1],considered_region[2],x...] = (sum(full_daa[considered_region[1],r,x...] for r in full_region) - full_daa[considered_region[1],considered_region[1],x...])/(length(full_region)-1)
        new_daa[considered_region[2],considered_region[1],x...] = (sum(full_daa[r,considered_region[1],x...] for r in full_region) - full_daa[considered_region[1],considered_region[1],x...])/(length(full_region)-1)
    end
    return new_daa
end


function read_capacities(; file, nam, year, technology, region)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(year), length(technology), length(region)),
        year, technology, region)

    open(file, "r") do f
        while !eof(f)
            line = readline(f)
            if startswith(line, nam)
                y = parse(Int, split(split(line, "[")[2], ",")[1])
                tech = split(split(line, "[")[2], ",")[2]
                r = split(split(split(line, "[")[2], ",")[3], "]")[1]
                if tech ∈ technology && y ∈ year && r ∈ region
                    A[y, tech, r] = parse(Float64, split(split(split(split(line, "[")[2], ",")[3], "]")[2], "= ")[2])
                end
            end
        end
    end
    return A
end

function read_trade_capacities(; file, nam, year, technology, region)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(year), length(technology), length(region), length(region)),
        year, technology, region, region)

    open(file, "r") do f
        while !eof(f)
            line = readline(f)
            if startswith(line, nam)
                parts = split(line, "[")[2]
                y = parse(Int, split(parts, ",")[1])
                tech = split(parts, ",")[2]
                region1 = split(parts, ",")[3]
                region2 = split(split(parts, ",")[4], "]")[1]
                value = parse(Float64, split(split(line, "]")[2], "= ")[2])

                if y ∈ year && region1 ∈ region && region2 ∈ region && tech ∈ technology
                    A[y, tech, region1, region2] = value
                end
            end
        end
    end
    return A
end

function read_storage_capacities(; file, nam, year, technology, region)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(technology), length(year), length(region)),
        technology, year, region)

    open(file, "r") do f
        while !eof(f)
            line = readline(f)
            if startswith(line, nam)
                parts = split(line, "[")

                y = parse(Int, split(parts[2], ",")[2])
                tech = split(parts[2],",")[1]
                r = split(split(parts[2],",")[3],"]")[1]

                value = parse(Float64, split(split(line, "]")[2], "= ")[2])

                if r ∈ region && tech ∈ technology && y ∈ year
                    A[tech, y, r] = value
                end
            end
        end
    end
    return A
end

function read_emissions_txt(;file, nam, year, emission, region)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(year), length(emission), length(region)),
        year, emission, region)

    open(file, "r") do f
        while !eof(f)
            line = readline(f)
            if startswith(line, nam)
                parts = split(line, "[")

                y = parse(Int, split(parts[2], ",")[1])
                em = split(parts[2],",")[2]
                r = split(split(parts[2],",")[3],"]")[1]

                value = parse(Float64, split(split(line, "]")[2], "= ")[2])
                if r ∈ region && em ∈ emission && y ∈ year
                    A[y, em, r] = value
                end
            end
        end
    end
    return A
end

function read_nettrade_txt(;file,nam, year, fuel, region)
    A = JuMP.Containers.DenseAxisArray(
        zeros(length(year), length(fuel), length(region)),
        year, fuel, region)

    open(file, "r") do f
        while !eof(f)
            line = readline(f)
            if startswith(line, nam)
                parts = split(line, "[")

                y = parse(Int, split(parts[2], ",")[1])
                fu = split(parts[2],",")[2]
                r = split(split(parts[2],",")[3],"]")[1]

                value = parse(Float64, split(split(line, "]")[2], "= ")[2])
                if r ∈ region && fu ∈ fuel && y ∈ year
                    A[y, fu, r] = value
                end
            end
        end
    end
    return A
end

function violations(model, tol=1e-7)
	res = []
	if termination_status(model) == INFEASIBLE &&
	   dual_status(model) == INFEASIBILITY_CERTIFICATE
		for (F, S) in list_of_constraint_types(model)
			cons = all_constraints(model, F, S)
			for i in eachindex(cons)
				if isassigned(cons, i)
					con = cons[i]
					if abs(dual(con)) > tol
						push!(res, con)
					end
				end
			end
		end
	end
	println(res)
    return res
end
