-- Migration: seed the 16 extended import folders for the v4 layout.
-- Run this while Shoko is STOPPED, then restart Shoko and verify the folders
-- appear in the UI.
--
-- New tree (each is a Destination import folder, matching bainesrenamer_v4.lua):
--   Anime|Hentai / Shows|Movies / GerDub|GerSub|Other|_manual
--
-- The existing 8 category folders (IDs 2-9) are kept for now: the files still
-- physically live there until the transition script relocates them. They are
-- removed in the cleanup step at the end of the file.

INSERT INTO ImportFolder (ImportFolderName, ImportFolderLocation, IsDropSource, IsDropDestination, IsWatched) VALUES
  ('Anime-Shows-GerDub',  '/mnt/array/Anime/Shows/GerDub/',  0, 1, 0),
  ('Anime-Shows-GerSub',  '/mnt/array/Anime/Shows/GerSub/',  0, 1, 0),
  ('Anime-Shows-Other',   '/mnt/array/Anime/Shows/Other/',   0, 1, 0),
  ('Anime-Shows-_manual', '/mnt/array/Anime/Shows/_manual/', 0, 1, 0),
  ('Anime-Movies-GerDub',  '/mnt/array/Anime/Movies/GerDub/',  0, 1, 0),
  ('Anime-Movies-GerSub',  '/mnt/array/Anime/Movies/GerSub/',  0, 1, 0),
  ('Anime-Movies-Other',   '/mnt/array/Anime/Movies/Other/',   0, 1, 0),
  ('Anime-Movies-_manual', '/mnt/array/Anime/Movies/_manual/', 0, 1, 0),
  ('Hentai-Shows-GerDub',  '/mnt/array/Hentai/Shows/GerDub/',  0, 1, 0),
  ('Hentai-Shows-GerSub',  '/mnt/array/Hentai/Shows/GerSub/',  0, 1, 0),
  ('Hentai-Shows-Other',   '/mnt/array/Hentai/Shows/Other/',   0, 1, 0),
  ('Hentai-Shows-_manual', '/mnt/array/Hentai/Shows/_manual/', 0, 1, 0),
  ('Hentai-Movies-GerDub',  '/mnt/array/Hentai/Movies/GerDub/',  0, 1, 0),
  ('Hentai-Movies-GerSub',  '/mnt/array/Hentai/Movies/GerSub/',  0, 1, 0),
  ('Hentai-Movies-Other',   '/mnt/array/Hentai/Movies/Other/',   0, 1, 0),
  ('Hentai-Movies-_manual', '/mnt/array/Hentai/Movies/_manual/', 0, 1, 0);

-- Verify: every file should end up under the new folders after the transition.
SELECT ImportFolderID, COUNT(*) AS places FROM VideoLocal_Place GROUP BY ImportFolderID ORDER BY ImportFolderID;

-- ============================================================================
-- CLEANUP — only AFTER the transition script reports success and the verify
-- query above shows the old folders (IDs 2-9) at 0 places.
-- ============================================================================

-- -- Double check before deleting.
-- SELECT ImportFolderID, COUNT(*) FROM VideoLocal_Place WHERE ImportFolderID BETWEEN 2 AND 9 GROUP BY ImportFolderID;
--
-- DELETE FROM ImportFolder WHERE ImportFolderID BETWEEN 2 AND 9;
-- -- The old directories under /mnt/array/Anime/GerDub etc. are then empty and
-- -- can be removed on disk; the .plexignore_* / filter.txt files in them move
-- -- to the new 16 Plex VFS library roots.
