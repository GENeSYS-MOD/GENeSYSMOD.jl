"""Interactive manager for the GENeSYS-MOD DuckDB results database.

Lists the scenarios (model runs) stored in a database, and lets you
  re[n]ame  rename a scenario (fix a mislabelled extr_str) across all tables
  [s]plit   copy selected scenarios into a separate .duckdb (backup/archive),
            optionally including the shared (non-scenario) tables such as the
            input_* dump, and optionally purging them from the source (= move)
  [p]urge   delete selected scenarios from every scenario-keyed table
  [c]ompact rewrite the database file to reclaim disk space after purges
  [r]efresh re-scan, [q]uit

Works on any GENeSYS-MOD DuckDB: scenario-keyed tables are discovered by their
`Scenario` column (results db AND dispatch db); tables without one (input_*,
SET_* ...) are treated as shared.

Usage:  python Scripts/manage_results_db.py [path/to/db.duckdb]
        default: Results/genesysmod_db.duckdb (relative to the repo root)

The database must not be open elsewhere (close DBeaver/Julia first; a running
model/dispatch holds the file only briefly since the read-only fix).
"""
import os
import shutil
import sys
import datetime

import duckdb

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DB = os.path.join(REPO, "Results", "genesysmod_db.duckdb")


def q_ident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def connect(path, read_only=False):
    try:
        return duckdb.connect(path, read_only=read_only)
    except duckdb.IOException as e:
        sys.exit(f"Cannot open {path}:\n  {e}\nClose other programs holding it (DBeaver, Julia) and retry.")


def scan(con):
    """Return (scenario_tables, shared_tables, {scenario: total_rows})."""
    tables = [r[0] for r in con.execute(
        "SELECT table_name FROM information_schema.tables WHERE table_schema='main'").fetchall()]
    scen_tables, shared = [], []
    for t in tables:
        cols = {r[0] for r in con.execute(
            "SELECT column_name FROM information_schema.columns WHERE table_name = ?", [t]).fetchall()}
        (scen_tables if "Scenario" in cols else shared).append(t)
    counts = {}
    for t in scen_tables:
        for sc, n in con.execute(f"SELECT Scenario, count(*) FROM {q_ident(t)} GROUP BY Scenario").fetchall():
            counts[sc] = counts.get(sc, 0) + n
    return sorted(scen_tables), sorted(shared), counts


def show(counts, scen_tables, shared):
    print(f"\n{len(scen_tables)} scenario-keyed tables, {len(shared)} shared tables (input_*, ...)")
    if not counts:
        print("  -- no scenarios in this database --")
        return []
    scens = sorted(counts)
    print(f"  {'#':>3}  {'scenario':40} {'rows':>12}")
    for i, sc in enumerate(scens):
        print(f"  {i:>3}  {sc:40} {counts[sc]:>12,}")
    return scens


def pick(scens, prompt):
    raw = input(f"{prompt} (indices, comma-separated; empty = cancel): ").strip()
    if not raw:
        return []
    try:
        idx = [int(x) for x in raw.replace(" ", "").split(",")]
        sel = [scens[i] for i in idx]
    except (ValueError, IndexError):
        print("  invalid selection");  return []
    print("  selected:", ", ".join(sel))
    return sel


def rename(con, scen_tables, scens):
    sel = pick(scens, "scenario to rename (exactly one)")
    if len(sel) != 1:
        if len(sel) > 1:
            print("  pick exactly one")
        return
    old = sel[0]
    new = input(f"new name for '{old}': ").strip()
    if not new or new == old:
        print("  cancelled");  return
    if new in scens and input(f"  '{new}' already exists - MERGE '{old}' into it? [y/N]: ").strip().lower() != "y":
        return
    n = 0
    for t in scen_tables:
        res = con.execute(f"UPDATE {q_ident(t)} SET Scenario = ? WHERE Scenario = ?", [new, old]).fetchall()
        n += res[0][0] if res else 0
    print(f"  renamed '{old}' -> '{new}' ({n:,} rows)")


def purge(con, scen_tables, sel):
    for sc in sel:
        n = 0
        for t in scen_tables:
            res = con.execute(f"DELETE FROM {q_ident(t)} WHERE Scenario = ?", [sc]).fetchall()
            n += res[0][0] if res else 0
        print(f"  purged {sc} ({n:,} rows)")
    con.execute("CHECKPOINT")
    print("  checkpoint done (run [c]ompact to reclaim disk space)")


def split(con, src_path, scen_tables, shared, sel):
    default = f"genesysmod_db_backup_{datetime.date.today():%Y%m%d}.duckdb"
    name = input(f"target file [{os.path.join(os.path.dirname(src_path), default)}]: ").strip() \
        or os.path.join(os.path.dirname(src_path), default)
    if os.path.abspath(name) == os.path.abspath(src_path):
        print("  target must differ from the source");  return
    include_shared = input("also copy shared tables (input_* dump, ...)? [y/N]: ").strip().lower() == "y"
    con.execute(f"ATTACH '{name}' AS tgt")
    copied = 0
    try:
        for t in scen_tables:
            has = con.execute(f"SELECT count(*) FROM {q_ident(t)} WHERE Scenario IN "
                              f"({','.join('?' * len(sel))})", sel).fetchone()[0]
            if has == 0:
                continue
            tq = q_ident(t)
            exists = con.execute("SELECT count(*) FROM information_schema.tables "
                                 "WHERE table_catalog='tgt' AND table_name = ?", [t]).fetchone()[0]
            sql_sel = f"SELECT * FROM {tq} WHERE Scenario IN ({','.join('?' * len(sel))})"
            if exists:
                con.execute(f"DELETE FROM tgt.main.{tq} WHERE Scenario IN ({','.join('?' * len(sel))})", sel)
                con.execute(f"INSERT INTO tgt.main.{tq} BY NAME {sql_sel}", sel)
            else:
                con.execute(f"CREATE TABLE tgt.main.{tq} AS {sql_sel}", sel)
            copied += has
        if include_shared:
            for t in shared:
                tq = q_ident(t)
                con.execute(f"DROP TABLE IF EXISTS tgt.main.{tq}")
                con.execute(f"CREATE TABLE tgt.main.{tq} AS SELECT * FROM {tq}")
        con.execute("CHECKPOINT tgt")
    finally:
        con.execute("DETACH tgt")
    print(f"  copied {copied:,} scenario rows"
          + (" + shared tables" if include_shared else "") + f" -> {name}")
    if input("purge the copied scenarios from the SOURCE (turn the split into a move)? [y/N]: ").strip().lower() == "y":
        purge(con, scen_tables, sel)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DB
    if not os.path.isfile(path):
        sys.exit(f"database not found: {path}")
    print(f"database: {path}  ({os.path.getsize(path)/1e6:,.0f} MB)")
    con = connect(path)
    scen_tables, shared, counts = scan(con)
    scens = show(counts, scen_tables, shared)
    while True:
        cmd = input("\n[s]plit  [p]urge  re[n]ame  [c]ompact  [r]efresh  [q]uit > ").strip().lower()
        if cmd == "q":
            break
        elif cmd == "r":
            scen_tables, shared, counts = scan(con)
            scens = show(counts, scen_tables, shared)
        elif cmd == "n":
            rename(con, scen_tables, scens)
            scen_tables, shared, counts = scan(con)
            scens = show(counts, scen_tables, shared)
        elif cmd == "s":
            sel = pick(scens, "scenarios to split out")
            if sel:
                split(con, path, scen_tables, shared, sel)
                scen_tables, shared, counts = scan(con)
                scens = show(counts, scen_tables, shared)
        elif cmd == "p":
            sel = pick(scens, "scenarios to PURGE")
            if sel and input(f"type 'purge' to delete {len(sel)} scenario(s) permanently: ").strip() == "purge":
                purge(con, scen_tables, sel)
                scen_tables, shared, counts = scan(con)
                scens = show(counts, scen_tables, shared)
        elif cmd == "c":
            # rewrite the whole database into a fresh file, then swap it in:
            # DuckDB CHECKPOINT does not return already-allocated blocks, so a
            # copy-rewrite is the reliable way to shrink after purges.
            con.close()
            tmp = path + ".compact"
            if os.path.exists(tmp):
                os.remove(tmp)
            size0 = os.path.getsize(path)
            c2 = duckdb.connect(tmp)
            c2.execute(f"ATTACH '{path}' AS src (READ_ONLY)")
            for (t,) in c2.execute("SELECT table_name FROM information_schema.tables "
                                   "WHERE table_catalog='src' AND table_schema='main'").fetchall():
                c2.execute(f"CREATE TABLE {q_ident(t)} AS SELECT * FROM src.main.{q_ident(t)}")
            c2.execute("DETACH src")
            c2.close()
            bak = path + ".pre_compact.bak"
            shutil.move(path, bak)
            shutil.move(tmp, path)
            print(f"  compacted {size0/1e6:,.0f} MB -> {os.path.getsize(path)/1e6:,.0f} MB "
                  f"(original kept as {os.path.basename(bak)} - delete it once verified)")
            con = connect(path)
        else:
            print("  ? s / p / c / r / q")
    con.close()


if __name__ == "__main__":
    main()
