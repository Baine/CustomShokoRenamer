# Migration plan: old 8-folder layout -> v4 16-folder layout

Moves the 70,328 existing files from the old category-only tree into the new
`Anime|Hentai / Shows|Movies / GerDub|GerSub|Other|_manual` layout **using Shoko
itself** as the engine (v4 Lua renamer + batch relocation API). No file moves or
`VideoLocal_Place` writes are done by hand.

## Why this works
- `bainesrenamer_v4.lua` computes destination, subfolder and filename purely from
  Shoko metadata (`anime`, `episodes`, `tmdb`), not from the current path — so it
  renames existing files correctly even though they sit in the old tree.
- The relocation service physically moves the file and updates
  `VideoLocal_Place` (ManagedFolderID + RelativePath) atomically
  (VideoRelocationService.cs:1142,1157). No SQL on place rows needed.
- `file.path` still contains the old category segment, so `category_from_path()`
  preserves each file's GerDub/GerSub/Other/_manual placement.

## Phases

### 0. Backup (mandatory)
- Stop Shoko.
- Copy `Z:\SQLite\Shoko.db3` + `-wal` + `-shm`, and `Queue.db3` to a backup dir.
- Start Shoko again.

### 1. Seed the 16 import folders
- Apply `migration.sql` while Shoko is **stopped** (INSERT section only).
- Restart Shoko. Verify all 16 new folders appear in the UI
  (Settings -> Import Folders). Old 8 folders stay for now.
- The folders are created on disk lazily by the relocation service
  (VideoRelocationService.cs:1032-1038), so no mkdir needed.

### 2. Configure the v4 renamer
- In the UI, edit the **default** relocation preset (currently
  "Baines-LUARenamer", stored as StoredRelocationPreset row 9) and paste
  `bainesrenamer_v4.lua` into its script field. Keep `UseExistingAnimeLocation`
  = **false** (it would pin files to their old locations) and keep it the
  default preset.
- Ensure `Plugins.Renamer.MoveOnImport` and `RenameOnImport` are on (or pass the
  query params in step 3).

### 3. Dry run (optional but recommended)
- `python migrate_ids.py ids.txt`
- `lua migrate.lua <apikey> ids.txt http://localhost:8111 500 --preview`
- Inspect the output paths for a few files to confirm destinations look right.

### 4. Relocate everything
- `python migrate_ids.py ids.txt`
- `lua migrate.lua <apikey> ids.txt http://localhost:8111 500`
- `migrate_ids.py` dumps all distinct `VideoLocalID`s (read-only) to a text file;
  `migrate.lua` POSTs them in batches to `/api/v3/Relocation/Relocate` with
  `move=true&rename=true&allowRelocationInsideDestination=true`.
  `allowRelocationInsideDestination` is **required**: the current files already
  sit inside Destination-type import folders (VideoRelocationService.cs:746).
- Rerun until output shows 0 failed; failed IDs are written to
  `migrate_failed.txt` for targeted retries.

### 5. Verify
- SQL (from migration.sql): `SELECT ImportFolderID, COUNT(*) FROM VideoLocal_Place GROUP BY ImportFolderID`
  -> IDs 10-25 hold the files, IDs 2-9 should be 0.
- `lua verify.lua` still passes (it asserts against the script, unaffected).

### 6. Cleanup (only after verification)
- Run the commented CLEANUP section of `migration.sql` (DELETE old folder rows 2-9).
- Remove the now-empty old dirs `/mnt/array/Anime/GerDub/` etc. on disk.
- Move `.plexignore_*` / `filter.txt` into the 16 new Plex VFS library roots.
- Update the Plex library/VFS root mapping: 8 old roots -> 16 new roots.

## Notes
- Preset `StoredRelocationPresetID` is seeded/updated by the UI only, never by
  SQL — the GUID is derived (UUIDv5 of `StoredRelocationPipe-{id}`), so no SQL
  needs to touch that table.
- `migrate_ids.py` exists because the LuaSQL sqlite3 build in this Lua 5.1 is
  too old to open the current Shoko DB; IDs are handed to `migrate.lua` via a
  plain-text file instead.
- Files in the `_drop` folder (currently 863) are relocated too; the v4 script
  categorizes them by language since their path has no base segment.
- If you prefer previewing per preset explicitly: `POST /Relocation/Preset/{id}/Preview`.
