r"""Dump distinct VideoLocalIDs to a plain-text file for migrate.lua.

Usage: python migrate_ids.py [outfile] [dbfile]
  outfile  default ids.txt (next to this script)
  dbfile   default Z:\SQLite\Shoko.db3 (read-only)
"""
import sqlite3
import sys
outfile = sys.argv[1] if len(sys.argv) > 1 else "ids.txt"
dbfile = sys.argv[2] if len(sys.argv) > 2 else r"Z:\SQLite\Shoko.db3"

con = sqlite3.connect(f"file:{dbfile.replace(chr(92), '/')}?mode=ro", uri=True)
ids = [str(r[0]) for r in con.execute("SELECT DISTINCT VideoLocalID FROM VideoLocal_Place")]
con.close()

with open(outfile, "w") as f:
    f.write("\n".join(ids) + "\n")
print(f"wrote {len(ids)} ids to {outfile}")
