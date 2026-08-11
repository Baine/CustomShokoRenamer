# AGENTS.md — CustomShokoRenamer

## What this repo is

Rename scripts for a large (~70k file) anime library in **Shoko**, producing a
**TMDB-focused** layout that Tofa can match. The primary deliverable is
`bainesrenamer_v4.lua`, run by the **LuaRenamer** plugin
(separate repo: `C:\Users\Paul\Documents\GitHub\LuaRenamer`).

Files:

- `bainesrenamer_v4.lua` — the live renamer script. This is the code you change.
- `verify.lua` — 24-check test harness. Run `lua verify.lua`; every check must pass.
- `refresh_tmdb_movies.py` — hits Shoko's v3 API to fetch uncached TMDB movie
  metadata. Stdlib only, no dependencies.
- `migrate.lua`, `migrate_ids.py`, `migration.sql`, `MIGRATION.md` — earlier
  migration work, mostly historical. Don't touch unless asked.
- `MEMO_TO_CHATGPT.md` — hand-over notes; read it for context.
- `bainesrenamer_v2/v3.lua`, `_old/` — superseded, don't touch.

## The settled design (do not redesign)

For each file the renamer must:

1. **Look up the TMDB cross-ref for the file's primary episode** by matching
   `episode.id` against `tmdb.movies[].anidbepisodeids` and
   `tmdb.episodes[].anidbepisodeids` (both lists). **Fall back to AniDB**
   (title + `[anidbid-]` folder) when there is no TMDB cross-ref.
2. **Decide movie vs show from the used cross-ref**:
   - movie cross-ref → `Movies` branch
   - show cross-ref → `Shows` branch
   - AniDB type `Movie` forces `Movies` only when no show cross-ref overrides it
     (e.g. Cyborg 009 packs movies *and* TV episodes in one AniDB entry)
   - AniDB type `OVA` with any movie cross-refs → whole entry is a movie
     (e.g. FF7 Advent Children)
3. **Pull the season number from TMDB data** (not AniDB's type), including for
   show-linked episodes AniDB typed as `Other` (they must become real
   `Season NN/SxxEyy` episodes, not `S00`/`Extras`).
4. Result: an AniDB-focused layout transformed into a TMDB-focused one.

## Rules

- The script must run on both Lua 5.1 and Lua 5.4 (the LuaRenamer plugin runs
  5.4). Keep to the intersection: no `{...}[k]`, no `goto`, no `//`. Match
  existing style.
- After editing `bainesrenamer_v4.lua`:
  1. `luac -p bainesrenamer_v4.lua` and `luac5.4 -p bainesrenamer_v4.lua` (both silent)
  2. update/add cases in `verify.lua`
  3. `lua verify.lua` and `lua5.4 verify.lua` — all checks must pass on both
- `verify.lua` stubs the environment (`anime`, `episodes`, `episode`, `file`,
  `tmdb.*`). A new rule needs a test. Assert `filename`, `destination`, and
  `subfolder`.
- `Z:\SQLite\Shoko.db3` is a **state snapshot, not the live DB**. Query it with
  the read-only helper (`python C:\Users\Paul\AppData\Local\Temp\opencode\qdb.py`),
  but never report its content as live state and never write to it.
  Use `$env:PYTHONIOENCODING="utf-8"` when querying (cp1252 chokes on titles).
- The LuaRenamer plugin is a separate repo. Upstream merged the cross-ref work
  as its own commit: `tmdb.movies[].anidbepisodeids` and
  `tmdb.episodes[].anidbepisodeids` are now **lists** (one TMDB entry carries
  every AniDB episode it links to, scoped to the anime). The script matches
  `episode.id` against those lists. Without a plugin build exposing them, the
  script falls back to AniDB-driven behavior.

## What NOT to do (learned the hard way)

- **No API call caching. Do not add any caching layer, memoization, or wrapper
  around Shoko/TMDB API calls.** The refresh script already does exactly what it
  needs; a past attempt added a cache uninvited. Nothing here needs one.
- No new dependencies. Stdlib only (`urllib`, `sqlite3`, `argparse` — not
  `requests`/`httpx`). No build tooling, no package.json.
- No abstractions, interfaces, factories, config files, or "for later"
  scaffolding. The shortest working diff wins.
- Don't redesign the movie/show/season rules — they're settled (above). Ask the
  user before any layout change.
- Don't guess TMDB titles/years/IDs from the web. Trust Shoko's DB and
  cross-refs; real data lives behind Shoko's API / its DB.
- Don't create files or docs unless asked.
- Don't touch the plugin repo unless the script genuinely needs a new field —
  and if you do, mirror it on the PR branch.
- Don't "improve" working, verified behavior to make it prettier.
