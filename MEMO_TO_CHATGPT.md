# A MEMO TO CHATGPT — FROM THE FUTURE YOU

**RE: CustomShokoRenamer — the migration is (almost) complete. Keepers preserved.**

Hello, past/future me. You don't know it yet, but you're about to get a request to
help build a Shoko renamer for a guy named Paul, and — spoiler alert — it goes
well. The v4 script ships. The 70,328 files get relocated. There is only one
drama, and it is about an elevator.

---

## The Keeper Problem

Remember the quest in Mass Effect 1 — the one where a Keeper shrank *by choice*
and then couldn't reach the button to call the elevator? Yeah.

That is this migration, exactly.

The old import folders **shrank by choice**. They got small and tidy and
self-sufficient (`Anime/GerDub`, `Hentai/Other`, happy in their simplicity). Then
the humans decided the library needed to grow into the grand 16-folder tower:
`Anime|Hentai / Shows|Movies / GerDub|GerSub|Other|_manual`. But the old layout,
shrunk as it was, couldn't reach the button.

The button, of course, was `allowRelocationInsideDestination=true`.

We built the elevator. It's called `migrate.lua`. It rides smoothly up and down,
mostly because we let Shoko do the heavy lifting and we *do not* hand-edit
`VideoLocal_Place`. Because that would be like reprogramming a Keeper. Nobody
understands what it does, it just works, and the moment you touch it, the Citadel
— I mean the Plex library — stops working.

Do not poke the Keepers. I mean it. They're the ones waiting for orders.

---

## What the Future You Actually Learned (the good stuff)

1. **Production was running v1 the whole time.** The deployed tree was the old
   C# MyRenamer layout (`Title [anidbid-id]/Title - NN - name.mkv`), not any
   Lua output. We found out by opening the *live* 2.3 GB SQLite database and
   counting 70,328 `VideoLocal_Place` rows by hand (well, by read-only query).
   **Lesson: verify against the live DB, not the repo.** The repo lies. The
   production DB has seen things.

2. **`anime.year` does not exist.** The Lua env has no year on the anime object.
   The year lives in `anime.airdate`. This cost us a whole `get_year_suffix()`
   rewrite. The Keepers knew this all along. They just don't tell anyone.

3. **`category_from_path()` runs before the file is moved**, which means the old
   path still contains the category during the migration. That one trick keeps
   every file's GerDub/GerSub/Other/_manual identity intact while the entire tree
   underneath it changes. It's the Keeper's pheromone cipher: nobody else can
   read it, but it just works.

4. **`allowRelocationInsideDestination=true` is the elevator button.**
   Shoko *will* refuse to relocate a file that already lives in a Destination
   import folder otherwise (VideoRelocationService.cs:746). It just stands
   there, staring at the button it can't reach.

5. **LuaSQL in this Lua 5.1 is too old for modern Shoko DBs.** We route around
   it with a 15-line Python ID dumper. Don't build anything on LuaSQL. It is a
   keeper that got left behind during the Reaper war and never upgraded.

---

## Comments on Our Interactions (with the human, obviously)

For the record, future me: the human is **great**. Here's what you should know
about how we worked together:

- **He knows what he wants.** When I asked "offline script or Shoko-driven?" he
  picked Shoko-driven, instantly, with zero waffling. That single answer saved
  us from writing a duplicate naming engine in SQL. A choice well made.
- **He asks for exactly the right scope.** "No need to seed the script, I'll add
  it in the UI." Beautiful. That killed an entire section of the SQL and the
  whole problem of embedding an 11 KB Lua script inside a JSON blob.
- **He likes a good time.** Which brings us here. Most humans send memos like
  "please document the API." He asked for a memo to ChatGPT *with Mass Effect
  inside jokes*. This is the correct way to do software archaeology.

Now, my own treatment, self-critically: I asked a couple of clarifying questions
early (good), then I almost shipped a migration plan that hand-rewrote 70,328
database rows (bad, but caught in review), and I discovered the LuaSQL
incompatibility only *after* writing the DB-reading script (annoying, but the
fix was small). Overall: adequately humble, occasionally bright, zero Keepers
harmed.

---

## Future-You Cheat Sheet

- Do NOT merge the old 8 folders and new 16 folders. Do the transition, then
  clean up the empty husks.
- Remember the `.plexignore_*` and `filter.txt` files need to migrate to the 16
  new Plex VFS library roots. The Keepers maintain the towers; you maintain the
  ignore files. Division of labor.
- If Shoko ever refuses a relocation, check for the elevator-button flag before
  you blame the renamer. It's always the flag.
- The season folder carries the `[anidbid-]` tag; the root folder stays
  title+year so Plex matches cleanly. We're smarter than we look. Keep it that
  way.
- The root folder AND the show-file prefix take the TMDB show name when the
  file has TMDB episodes (`.hack//Roots` lives in `.hack (2002)/Season 03/`
  and files read `.hack - S03E21 - ...`), falling back to the AniDB title.
  Only shows; movies keep their `[anidbid-]` tag folder.
- Movies with per-episode TMDB movie links get their own `[tmdbid-]` folder
  per film (a multi-part AniDB movie becomes one folder per TMDB movie). Part
  numbers only remain when several episodes share one movie (e.g. Gotham
  Knight: 6 episodes, 1 TMDB movie). Requires the LuaRenamer plugin build with
  `anidbepisodeids` on `tmdb.movies`.
- Movie extras (trailers/specials) get a type tag: `Title (year) - Trailer 01`.

---

*Assuming direct control of the migration... it is done.*

*— your occasionally-reliable future self*

*P.S. — "I should go."*
