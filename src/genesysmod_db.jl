"""
DuckDB result/input writers.

Two database files, both living in the result directory:

  * `genesysmod_results_db.duckdb`  — model outputs (raw variables, VarPar,
    processed result tables). Every table carries a `Scenario` column set to
    `extr_str_results`; writing the same scenario again overwrites exactly
    those rows (DELETE + INSERT in one transaction), a new scenario appends.
    `Region`/`Pathway` context columns are included so several model regions
    or pathways can share one file.
  * `genesysmod_inputdata_db.duckdb` — the processed input parameters written
    by `switch_test_data_load` (one table per parameter, one `SET_*` table per
    index set). Mirrors the former SQLite dump, now with real dimension names.

Open either file with DBeaver (DuckDB driver, read-only while a run writes),
DuckDB CLI, Python (`duckdb` package) or Julia.
"""

# ---------------------------------------------------------------------------
# Axis naming: derive real dimension names by matching a container's axes
# against the model's Sets. Falls back to dim1..dimN when no set matches.
# ---------------------------------------------------------------------------

# Sparse containers (axes not recoverable from the container): name registry.
const _SPARSE_DIM_NAMES = Dict{Symbol,Vector{Symbol}}(
    :RateOfActivity => [:Year, :Timeslice, :Technology, :Mode, :Region],
    :Import         => [:Year, :Timeslice, :Fuel, :Region, :Region2],
    :Export         => [:Year, :Timeslice, :Fuel, :Region, :Region2],
)

function _set_candidates(Sets)
    # Order matters: first match wins; reduced sets before *_full. Matching is
    # set-based (order-insensitive) because `remove_dummy_regions!` mutates
    # Sets.Region_full after the parameter DAAs were built, so a Region axis
    # may still contain "World" while the Sets vector no longer does.
    cands = Tuple{Symbol,Set}[]
    for (name, field) in (
        (:Year, :Year), (:Timeslice, :Timeslice), (:Mode, :Mode_of_operation),
        (:Region, :Region_full), (:Technology, :Technology), (:Fuel, :Fuel),
        (:Storage, :Storage), (:Emission, :Emission), (:Sector, :Sector),
        (:ModalType, :ModalType), (:Year_full, :Year_full),
        (:Timeslice_full, :Timeslice_full),
    )
        hasfield(typeof(Sets), field) || continue
        v = getfield(Sets, field)
        v isa AbstractVector || continue
        s = Set(v)
        push!(cands, (name, s))
        if name == :Region && "World" ∉ s
            push!(cands, (name, union(s, Set(["World"]))))
        end
    end
    return cands
end

"""
Dimension names for a DenseAxisArray by matching each axis against Sets.
A repeated set name gets a 2-suffix (Region, Region2, ...).
"""
function _axis_names(daa::JuMP.Containers.DenseAxisArray, Sets)
    cands = _set_candidates(Sets)
    names = Symbol[]
    for ax in axes(daa)
        saxv = Set(ax)
        hit = findfirst(c -> c[2] == saxv, cands)
        base = hit === nothing ? Symbol("dim", length(names) + 1) : cands[hit][1]
        n = base
        k = 2
        while n ∈ names
            n = Symbol(base, k)
            k += 1
        end
        push!(names, n)
    end
    return names
end

"Header for `JuMP.Containers.rowtable`: dimension names + a value column."
function _rowtable_header(container, name::Symbol, Sets; value_col::Symbol=:Value)
    if container isa JuMP.Containers.DenseAxisArray
        return vcat(_axis_names(container, Sets), [value_col])
    elseif haskey(_SPARSE_DIM_NAMES, name)
        return vcat(_SPARSE_DIM_NAMES[name], [value_col])
    end
    return nothing  # caller keeps rowtable's default x1..xN names
end

# ---------------------------------------------------------------------------
# DuckDB plumbing
# ---------------------------------------------------------------------------

const RESULTS_DB_FILENAME = "genesysmod_results_db.duckdb"
const INPUTDATA_DB_FILENAME = "genesysmod_inputdata_db.duckdb"

_results_db_path(Switch) = joinpath(Switch.resultdir[], RESULTS_DB_FILENAME)
_inputdata_db_path(Switch) = joinpath(Switch.resultdir[], INPUTDATA_DB_FILENAME)

# One cached handle per database file per process. DuckDB does not allow a
# second handle on the same file within one process (and closing a handle
# whose query results are still alive does not release the file lock), so all
# writers and any same-process readers must share this connection.
const _DB_HANDLES = Dict{String,DuckDB.DB}()

function _db_connect(path::AbstractString)
    get!(_DB_HANDLES, abspath(path)) do
        DBInterface.connect(DuckDB.DB, path)
    end
end

"""
    release_dbs()

Close all DuckDB handles held by this Julia process (results + input-data
databases). Closing checkpoints the .wal into the main file and releases the
file lock, so the .duckdb can be opened in DBeaver etc. without ending the
Julia session. Called automatically at the end of a model run; safe to call
manually any time — the next write simply reopens the file.
"""
function release_dbs()
    for (path, db) in collect(_DB_HANDLES)
        try
            DBInterface.close!(db)
        catch e
            @warn "Could not close database handle" path exception=e
        end
        delete!(_DB_HANDLES, path)
    end
    # Query-result finalizers may still hold references into the database;
    # collect them so the file lock is actually dropped.
    GC.gc()
    return
end

_quote_ident(s) = "\"" * replace(string(s), "\"" => "\"\"") * "\""

_table_exists(con, table) =
    !isempty(DataFrame(DBInterface.execute(con,
        "SELECT 1 FROM information_schema.tables WHERE table_name = ?", [string(table)])))

"""
Write `df` into `table`, replacing any rows of the same scenario.
Creates the table from the DataFrame schema on first use. INSERT BY NAME, so
column order may differ between runs; a genuinely different schema errors —
drop the table (or delete the db file) after structural changes.
"""
function _db_write_scenario!(con, table, df::DataFrame, scenario::AbstractString)
    isempty(df) && return
    tq = _quote_ident(table)
    reg = "df_" * string(table)
    DuckDB.register_data_frame(con, df, reg)
    try
        DBInterface.execute(con, "BEGIN TRANSACTION")
        if _table_exists(con, table)
            DBInterface.execute(con, "DELETE FROM $tq WHERE Scenario = ?", [scenario])
            DBInterface.execute(con, "INSERT INTO $tq BY NAME SELECT * FROM $(_quote_ident(reg))")
        else
            DBInterface.execute(con, "CREATE TABLE $tq AS SELECT * FROM $(_quote_ident(reg))")
        end
        DBInterface.execute(con, "COMMIT")
    catch
        DBInterface.execute(con, "ROLLBACK")
        rethrow()
    finally
        DuckDB.unregister_data_frame(con, reg)
    end
    return
end

"""
Pending database writes that failed because the file was locked by an
external program (Tableau, DBeaver, ...). Each entry is a label plus a
closure that re-executes the full write. Flushed via `retry_db_writes()`.
"""
const _PENDING_DB_WRITES = Vector{Pair{String,Function}}()

"""
Run a database write; if it fails (typically: file locked by an external
reader), queue it for `retry_db_writes()` and continue the run instead of
crashing — the solve result and all CSV outputs are unaffected.
"""
function _db_attempt(f::Function, label::AbstractString)
    try
        f()
    catch e
        push!(_PENDING_DB_WRITES, String(label) => f)
        @warn """Could not write to the DuckDB database — it is most likely locked by another
program (Tableau, DBeaver, a second Julia session, ...).
The model run CONTINUES and all CSV outputs are unaffected.
=> Close the program that holds the file open, then call `retry_db_writes()`
   in this Julia session to write the queued results.""" write=label exception=e
    end
    return
end

"""
    retry_db_writes()

Re-attempt every database write that failed earlier in this session (file
locked by Tableau/DBeaver/...). Writes are replayed in their original order;
anything that fails again stays in the queue. Call after closing the program
that held the database file open.
"""
function retry_db_writes()
    if isempty(_PENDING_DB_WRITES)
        println("No pending database writes.")
        return
    end
    pending = copy(_PENDING_DB_WRITES)
    empty!(_PENDING_DB_WRITES)
    for (label, f) in pending
        try
            f()
            println("  written: $(label)")
        catch e
            push!(_PENDING_DB_WRITES, label => f)
            @warn "Still cannot write '$(label)' — is the database file still open elsewhere? Queue kept; close the file and call retry_db_writes() again." exception=e
        end
    end
    if isempty(_PENDING_DB_WRITES)
        release_dbs()
        println("All queued database writes completed; database handles released.")
    else
        println("$(length(_PENDING_DB_WRITES)) write(s) still pending.")
    end
    return
end

"""
Purge a scenario from EVERY table of the results database that carries a
`Scenario` column. Called once at the start of a run's DB phase: the
per-table DELETE in `_db_write_scenario!` only covers tables the new run
writes again — a re-run writing fewer tables (different switches, power-only
vs all-fuels variable sets, ...) would otherwise leave stale rows of the
same scenario behind in the untouched tables.
"""
function db_purge_scenario(Switch, extr_str)
    path = _results_db_path(Switch)
    isfile(path) || haskey(_DB_HANDLES, abspath(path)) || return
    con = _db_connect(path)
    tables = DataFrame(DBInterface.execute(con,
        "SELECT DISTINCT table_name FROM information_schema.columns " *
        "WHERE column_name = 'Scenario' AND table_schema = 'main'"))
    for t in tables.table_name
        DBInterface.execute(con,
            "DELETE FROM $(_quote_ident(t)) WHERE Scenario = ?", [String(extr_str)])
    end
    isempty(tables.table_name) ||
        println("  Results: db purged scenario '$(extr_str)' from $(length(tables.table_name)) tables")
    return
end

"""
Add the scenario/context key columns in front of a result DataFrame. Columns
the table already carries (e.g. `PathwayScenario` in the processed outputs)
are left untouched.
"""
function _with_run_context(df::DataFrame, Switch, extr_str)
    out = copy(df)
    # The processed result tables are assembled from untyped `[]` columns
    # (eltype Any), which DuckDB's scan cannot map to a logical type. Narrow
    # them to their actual element type; anything DuckDB cannot store
    # (mixed-type columns, Pairs, Periods, ...) is stringified.
    db_ok(T) = T <: Union{Missing, Number, AbstractString, Bool, Dates.Date, Dates.DateTime}
    for name in names(out)
        col = out[!, name]
        if eltype(col) === Any
            col = identity.(col)
        end
        if !db_ok(eltype(col))
            col = String[ismissing(x) ? "" : string(x) for x in col]
        end
        out[!, name] = col
    end
    ctx = (
        :Scenario => String(extr_str),
        :ModelRegion => Switch.model_region,
        :Pathway => Switch.emissionPathway,
        :PathwayScenario => "$(Switch.emissionPathway)_$(Switch.emissionScenario)",
    )
    add = [col => fill(val, nrow(out)) for (col, val) in ctx if !hasproperty(out, col)]
    isempty(add) || insertcols!(out, 1, add...)
    return out
end

# ---------------------------------------------------------------------------
# Results database
# ---------------------------------------------------------------------------

"""
Write the processed result tables (the same DataFrames the output_*.csv
writers produce) into `genesysmod_results_db.duckdb`, keyed by scenario.
"""
function write_processed_results_db(tables::AbstractDict, Sets, Switch, extr_str)
    con = _db_connect(_results_db_path(Switch))
    for (tname, df) in tables
        _db_write_scenario!(con, tname, _with_run_context(df, Switch, extr_str), String(extr_str))
    end
    return
end

"""
Write raw model variables, the VarPar intermediates and Demand/RateOfDemand
into `genesysmod_results_db.duckdb` (tables prefixed raw_/varpar_), keyed by
scenario like the processed tables.
"""
function write_raw_results_db(model, VarPar, Params, Sets, Switch, extr_str)
    con = _db_connect(_results_db_path(Switch))
    for v in _registered_variables(model)
        v ∈ [:cost, :z] && continue
        container = model[v]
        header = _rowtable_header(container, v, Sets)
        tbl = header === nothing ? JuMP.Containers.rowtable(value, container) :
                                   JuMP.Containers.rowtable(value, container; header=header)
        df = DataFrame(tbl)
        # keep db lean: zero rows carry no information for raw inspection
        df = df[df[!, end] .!= 0, :]
        _db_write_scenario!(con, "raw_" * string(v), _with_run_context(df, Switch, extr_str), String(extr_str))
    end
    for field in fieldnames(typeof(VarPar))
        daa = getfield(VarPar, field)
        daa isa JuMP.Containers.DenseAxisArray || continue
        df = DataFrame(JuMP.Containers.rowtable(value, daa; header=_rowtable_header(daa, field, Sets)))
        df = df[df[!, end] .!= 0, :]
        _db_write_scenario!(con, "varpar_" * string(field), _with_run_context(df, Switch, extr_str), String(extr_str))
    end
    for (nm, daa) in ((:Demand, Params.Demand), (:RateOfDemand, Params.RateOfDemand))
        df = DataFrame(JuMP.Containers.rowtable(value, daa; header=_rowtable_header(daa, nm, Sets)))
        df = df[df[!, end] .!= 0, :]
        _db_write_scenario!(con, "raw_" * string(nm), _with_run_context(df, Switch, extr_str), String(extr_str))
    end
    return
end

"""
Write a duals frame — the (constraint-name, dual-value) DataFrame produced by
`genesysmod_getspecifiedduals` / `genesysmod_getdualsbyname` — into
`genesysmod_results_db.duckdb` as `duals_<label>`, keyed by scenario like the
other result tables (columns renamed to `Constraint`/`Dual`). Empty frame is a
no-op; wrapped in `_db_attempt` so a locked file never aborts the run.
"""
function write_duals_db(df::DataFrame, label::AbstractString, Switch, extr_str)
    isempty(df) && return
    out = DataFrame(Constraint = string.(df[!, 1]), Dual = Float64.(df[!, 2]))
    con = _db_connect(_results_db_path(Switch))
    table = "duals_" * string(label)
    _db_attempt(() -> _db_write_scenario!(con, table,
        _with_run_context(out, Switch, extr_str), String(extr_str)), table)
    return
end

# ---------------------------------------------------------------------------
# Input-data database (switch_test_data_load)
# ---------------------------------------------------------------------------

"""
Dump the processed input data to `genesysmod_inputdata_db.duckdb` — one table
per parameter (real dimension names), one `SET_*` table per index set.
Successor of the former SQLite dump; the file is recreated on every dump.
"""
function dump_inputs_db(case, switch::Switch)
    Params = case["Params"]
    Sets   = case["Sets"]
    dbpath = _inputdata_db_path(switch)
    # Recreate content. The file cannot be deleted if this process already
    # holds the handle, so drop all existing tables through it instead.
    if haskey(_DB_HANDLES, abspath(dbpath))
        con = _db_connect(dbpath)
        for t in DataFrame(DBInterface.execute(con,
                "SELECT table_name FROM information_schema.tables WHERE table_schema = 'main'")).table_name
            DBInterface.execute(con, "DROP TABLE IF EXISTS $(_quote_ident(t))")
        end
    else
        isfile(dbpath) && rm(dbpath)
        con = _db_connect(dbpath)
    end
    ntables = 0
    for field in fieldnames(typeof(Params))
        daa = getfield(Params, field)
        daa isa JuMP.Containers.DenseAxisArray || continue
        try
            df = DataFrame(JuMP.Containers.rowtable(identity, daa; header=_rowtable_header(daa, field, Sets)))
            isempty(df) && continue
            reg = "df_in"
            DuckDB.register_data_frame(con, df, reg)
            DBInterface.execute(con, "CREATE TABLE $(_quote_ident(field)) AS SELECT * FROM $(_quote_ident(reg))")
            DuckDB.unregister_data_frame(con, reg)
            ntables += 1
        catch e
            @warn "Could not dump parameter $(field)" exception=e
        end
    end
    for field in fieldnames(typeof(Sets))
        s = getfield(Sets, field)
        s isa AbstractVector || continue
        try
            reg = "df_set"
            DuckDB.register_data_frame(con, DataFrame(value = collect(s)), reg)
            DBInterface.execute(con, "CREATE TABLE $(_quote_ident("SET_" * string(field))) AS SELECT * FROM $(_quote_ident(reg))")
            DuckDB.unregister_data_frame(con, reg)
            ntables += 1
        catch e
            @warn "Could not dump set $(field)" exception=e
        end
    end
    println("Input data dumped to $(dbpath) ($(ntables) tables).")
    return dbpath
end
