-- bainesrenamer_v4.lua - Shoko LuaRenamer script (tuned for Tofa, import folders extended)
--
-- PURPOSE
--   Every file is renamed and placed inside one of 16 import folders that are
--   configured in Shoko AND mounted by Plex as library roots (VFS). The import
--   folder already encodes base + media type + category, so the script only
--   adds the title folder (and the season folder / content folder for shows).
--
-- IMPORT FOLDERS (each is a Shoko import folder, type Destination)
--   Anime/Shows/GerDub    Anime/Shows/GerSub    Anime/Shows/Other    Anime/Shows/_manual
--   Hentai/Shows/GerDub   Hentai/Shows/GerSub   Hentai/Shows/Other   Hentai/Shows/_manual
--   Anime/Movies/GerDub   Anime/Movies/GerSub   Anime/Movies/Other   Anime/Movies/_manual
--   Hentai/Movies/GerDub  Hentai/Movies/GerSub  Hentai/Movies/Other  Hentai/Movies/_manual
--   plus the Downloads/_drop folder where files are dropped.
--
-- TARGET TREE (matches tofa's naming scheme, docs.tofa.tv/name-your-media)
--   Movies:  <import folder>/<title> (year) [anidbid-id]/<title> (year).ext
--   Shows:   <import folder>/<title> (year)/Season NN [anidbid-id]/<title> - SxxExx - name.ext
--            <import folder>/<title> (year)/{Trailers|Specials|Extras}/...
--
--     base        Anime (safe) or Hentai (anime.restricted)
--     media type  Movies (AniDB type Movie) or Shows (everything else)
--     category    GerDub | GerSub | Other | _manual   (see get_category)
--     year        from the air date (anime.year does not exist in the Lua env)
--     season NN   TMDB season number when available, else 1 (AniDB is
--                 single-season per entry, so AniDB fallback is season 1)
--     [anidbid-id]  AniDB ID tag: on the Season folder for shows (each season
--                 of a TMDB show is one AniDB entry), on the root folder for
--                 movies (which have no season level)
--     content     Trailers | Specials | Extras (see get_content_folder)
--
--     Example: Anime/Shows/GerDub/Tokidoki Bosotto to Roshippu to (2024)/
--              Season 01 [anidbid-11061]/Tokidoki Bosotto to Roshippu to - S01E01 - Folge 1.mkv
--
-- CONFIG --------------------------------------------------------------------
local maxfilenamelen = 190  -- bytes, safety margin below XFS's 255-byte segment limit
local animelanguage = Language.German    -- preferred anime title language
local episodelanguage = Language.German  -- preferred episode title language
local spacechar = " "
local mountroot = "/mnt/array"  -- parent of Anime/ and Hentai/, must match the import folder paths

-- XFS segments are limited to 255 bytes (not characters), so all truncation
-- must count UTF-8 bytes and must not split a multibyte character.
-- gmatch(".[\128-\191]*") walks the string one UTF-8 codepoint at a time.
local function truncate_bytes(s, maxbytes, ellipsis)
  ellipsis = ellipsis or "..."
  if #s <= maxbytes then return s end
  local budget = maxbytes - #ellipsis
  local parts, len = {}, 0
  for c in s:gmatch(".[\128-\191]*") do
    if len + #c > budget then break end
    parts[#parts + 1] = c
    len = len + #c
  end
  return table.concat(parts):gsub("%s+$", "") .. ellipsis
end

local function has(list, lang)
  return from(list or {}):contains(lang)
end

local animename = anime:getname(animelanguage) or anime.preferredname
local base = anime.restricted and "Hentai" or "Anime"

-- Language availability. file.media and file.anidb are optional (nil when the
-- file lacks a MediaInfo probe or a matching AniDB release), so every access
-- is guarded. AniDB is usually more accurate, but reports a single "Unknown"
-- language when there are none, hence the "#... > 0" checks.
local media_dubs = file.media and from(file.media.audio):select("language"):distinct() or fromNothing()
local media_subs = file.media and from(file.media.sublanguages):distinct() or fromNothing()
local adb_dubs = file.anidb and #file.anidb.media.dublanguages > 0 and from(file.anidb.media.dublanguages):distinct() or nil
local adb_subs = file.anidb and #file.anidb.media.sublanguages > 0 and from(file.anidb.media.sublanguages):distinct() or nil

local GerDub = has(adb_dubs, Language.German) or has(media_dubs, Language.German)
local GerSub = has(adb_subs, Language.German) or has(media_subs, Language.German)
local Other = has(adb_subs, Language.English) or has(adb_dubs, Language.English) or has(media_subs, Language.English) or has(media_dubs, Language.English)

-- Keep manual placement: a file that already sits in a category folder is not
-- reclassified. Works for any file, wherever it was dropped from.
local function category_from_path()
  local segs = {}
  for seg in file.path:gmatch("[^/]+") do segs[#segs + 1] = seg end
  for i = 1, #segs - 1 do
    if segs[i] == base then
      for j = i + 1, math.min(i + 2, #segs) do
        if segs[j] == "GerDub" or segs[j] == "GerSub" or segs[j] == "Other" or segs[j] == "_manual" then
          return segs[j]
        end
      end
    end
  end
  return nil
end

-- German dub wins over German sub wins over English (either track), anything
-- else lands in _manual for manual review instead of a catch-all folder.
local function get_category()
  return category_from_path() or (GerDub and "GerDub") or (GerSub and "GerSub") or (Other and "Other") or "_manual"
end

-- TMDB movie linked to the file's primary episode, or nil. AniDB movie entries
-- often hold several films (episodes 1..N); each one is usually its own TMDB
-- movie, and the per-episode cross-reference tells them apart.
local function get_tmdb_movie()
  if not tmdb or not tmdb.movies or not episode or not episode.id then return nil end
  for i, m in ipairs(tmdb.movies) do
    if tostring(m.anidbepisodeid) == tostring(episode.id) then return m end
  end
  return nil
end

-- TMDB episode of the show that the file's primary episode is linked to, or
-- nil. When present it governs season, episode number and folder, so the
-- layout mirrors TMDB even when AniDB typed the episode as something else
-- (Cyborg 009's TV episodes are "Other" on AniDB but season 1 on TMDB).
local function get_tmdb_episode()
  if not tmdb or not tmdb.episodes or not episode or not episode.id then return nil end
  for i, te in ipairs(tmdb.episodes) do
    if tostring(te.anidbepisodeid) == tostring(episode.id) then return te end
  end
  return nil
end

-- AniDB type decides, but TMDB knows better: entries AniDB types as OVA are
-- often movies (Final Fantasy VII: Advent Children is OVA on AniDB, a movie on
-- TMDB). Any TMDB movie cross-reference then makes the whole entry a movie.
-- A TV series, however, can carry specials that TMDB classifies as movies
-- (Sherlock Hound); only the cross-referenced episode is a movie then.
-- Conversely, a movie-typed entry can hold TV episodes (Cyborg 009: Call of
-- Justice packs its 3 movies and 12 TV episodes in one AniDB entry): a file
-- whose episode links to a TMDB show is a show episode, not a movie.
local function has_tmdb_show_episode()
  return get_tmdb_episode() ~= nil
end

local function is_movie()
  if anime.type == AnimeType.Movie then
    return not has_tmdb_show_episode()
  end
  if anime.type == AnimeType.OVA and tmdb and tmdb.movies and #tmdb.movies > 0 then return true end
  return get_tmdb_movie() ~= nil
end

local function get_media_type()
  return is_movie() and "Movies" or "Shows"
end

-- " (year)" when known and not already part of the title. Tofa wants the year
-- for both movies and shows (remakes / same-name titles). Kept separate from
-- the title so truncation never eats it.
local function get_year_suffix(title)
  local year = anime.airdate and tostring(anime.airdate.year)
  if year and not title:match("%(%d%d%d%d%)$") then
    return " (" .. year .. ")"
  end
  return ""
end

-- TMDB show owning the file's episodes, or nil. The show id is on the
-- episode cross-refs, the names on the show list.
local function get_tmdb_show()
  if not tmdb or not tmdb.episodes or not tmdb.shows then return nil end
  for i, te in ipairs(tmdb.episodes) do
    for j, s in ipairs(tmdb.shows) do
      if tostring(s.id) == tostring(te.showid) then return s end
    end
  end
  return nil
end

-- Display name of the series: the TMDB show name when the file has TMDB
-- cross-references (Sign, Twilight and Roots all belong to ".hack"), else the
-- AniDB title. Used for the root folder AND the file prefix, so the file
-- always names the show it lives under.
local function get_show_name()
  local s = get_tmdb_show()
  if s then
    local name = s.preferredname or s.defaultname
    if name then return name end
  end
  return animename
end

-- How many episodes of the anime link to the given TMDB movie. More than one
-- means several files share the movie's folder and still need part numbers.
local function tmdb_movie_count(id)
  local n = 0
  for i, m in ipairs(tmdb.movies or {}) do
    if tostring(m.id) == tostring(id) then n = n + 1 end
  end
  return n
end

-- Root folder name. TMDB structure wins: one anime can be spread over several
-- AniDB entries (Sign, Twilight and Roots are seasons of ".hack"), and they
-- must share one show folder. Falls back to the AniDB title when the file has
-- no TMDB cross-reference. Movies use the TMDB movie of the file's episode
-- when there is one (a multi-part movie becomes one folder per film); the
-- anidbid tag keeps same-name movies apart and they have no season level.
local function get_anime_folder_name()
  if is_movie() then
    local m = get_tmdb_movie()
    if m then
      local name = m.preferredname or m.defaultname
      if name then
        local suffix = m.airdate and not name:match("%(%d%d%d%d%)$")
            and (" (" .. tostring(m.airdate.year) .. ")") or ""
        return truncate_bytes(name, 255 - #suffix - 5) .. suffix .. " [tmdbid-" .. m.id .. "]"
      end
    end
  else
    local s = get_tmdb_show()
    if s then
      local name = s.preferredname or s.defaultname
      if name then
        local suffix = s.airdate and not name:match("%(%d%d%d%d%)$")
            and (" (" .. tostring(s.airdate.year) .. ")") or ""
        return truncate_bytes(name, 255 - #suffix - 5) .. suffix
      end
    end
  end
  local suffix = get_year_suffix(animename)
  if is_movie() then
    suffix = suffix .. " [anidbid-" .. anime.id .. "]"
  end
  return truncate_bytes(animename, 255 - #suffix - 5) .. suffix
end

-- AniDB has no seasons, so the season in the marker comes from TMDB when
-- available (matched by episode type+number), else defaults to 1.
local function get_season(t, num)
  for i, te in ipairs(tmdb.episodes) do
    if te.type == t and te.number == num then
      return te.seasonnumber or 1
    end
  end
  return 1
end

-- The Season folder mirrors TMDB's season numbering for the file's regular
-- episode; a file with only specials/trailers never reaches this function.
-- An episode with a TMDB cross-reference uses that TMDB season directly, so a
-- show episode that AniDB typed as "Other" (Cyborg 009) still lands in the
-- right season.
local function get_primary_season()
  local te = get_tmdb_episode()
  if te and te.seasonnumber then return te.seasonnumber end
  for i, ep in ipairs(episodes) do
    if ep.type == EpisodeType.Episode then
      return get_season(EpisodeType.Episode, ep.number)
    end
  end
  return 1
end

local function get_season_folder()
  return "Season " .. string.format("%02d", get_primary_season()) .. " [anidbid-" .. anime.id .. "]"
end

-- Padding is determined from the number of episodes of the same type in the
-- anime (#tostring gives the required digit count), at least 2 digits.
local function format_marker(season, num, pad)
  return "S" .. string.format("%02d", season) .. "E" .. string.format("%0" .. pad .. "d", num)
end

-- Consecutive episodes of one type collapse into a range: S01E01-E02.
-- Season is only meaningful for regular episodes; specials etc. use S00.
local function format_group(t, nums)
  table.sort(nums)
  local pad = math.max(#tostring(anime.episodecounts[t] or 0), 2)
  local season = t == EpisodeType.Episode and get_season(t, nums[1]) or 0
  local parts = {}
  local first = nums[1]
  local prev = first
  for i = 2, #nums + 1 do
    local n = nums[i]
    if not n or n ~= prev + 1 then
      parts[#parts + 1] = format_marker(season, first, pad) .. (first == prev and "" or "-E" .. string.format("%0" .. pad .. "d", prev))
      first = n
    end
    prev = n
  end
  return table.concat(parts)
end

-- Consecutive episodes of the same type share a group (S01E01-E02); a file
-- carrying several types concatenates the groups (S01E01-E02S00E01). A file
-- without regular episodes whose primary episode has a TMDB cross-reference
-- takes that TMDB season and number instead of the S00 of its AniDB type.
-- ponytail: multi-episode files of that kind use only the primary episode.
local function get_marker()
  local te = get_tmdb_episode()
  if te and not (episode.type == EpisodeType.Episode) then
    local pad = math.max(#tostring(anime.episodecounts.Episode or 0), 2)
    return format_marker(te.seasonnumber or 1, te.number, pad)
  end
  local groups, order = {}, {}
  for i, ep in ipairs(episodes) do
    if not groups[ep.type] then
      groups[ep.type] = {}
      order[#order + 1] = ep.type
    end
    groups[ep.type][#groups[ep.type] + 1] = ep.number
  end
  local parts = {}
  for i, t in ipairs(order) do
    parts[#parts + 1] = format_group(t, groups[t])
  end
  return table.concat(parts)
end

-- Episode names use the preferred language with an English fallback. A single
-- episode returns its name directly; several episodes are joined with "/".
local function get_episode_names()
  if #episodes == 1 then
    return episode:getname(episodelanguage) or episode:getname(Language.English) or ""
  end
  local names = {}
  for i, ep in ipairs(episodes) do
    local name = ep:getname(episodelanguage) or ep:getname(Language.English) or ""
    if name ~= "" then names[#names + 1] = name end
  end
  return table.concat(names, "/")
end

-- Only files without a regular episode leave the main folder; they land in
-- Trailers, Specials or a general Extras folder (credits, parodies, ...).
-- tofa treats these folder names as extras and keeps them out of the library.
-- An episode with a TMDB cross-reference is a real show episode and stays in
-- its season folder, whatever AniDB typed it as.
local function get_content_folder()
  if get_tmdb_episode() then return nil end
  for i, ep in ipairs(episodes) do
    if ep.type == EpisodeType.Episode then return nil end
  end
  if episode.type == EpisodeType.Trailer then return "Trailers" end
  if episode.type == EpisodeType.Special then return "Specials" end
  return "Extras"
end

local content_folder = get_content_folder()

if is_movie() then
  -- tofa movies carry only the title and year; an episode marker in a movie
  -- file would be a show-file signal and could break matching in a Movies
  -- library. But an AniDB entry of type Movie can hold several movies (episodes
  -- 1..N); those must be told apart or every file resolves to the same name
  -- and the relocation service deletes the loser. When an episode links to its
  -- own TMDB movie the file gets that movie's name and folder; the part number
  -- remains only for episodes that share a folder. The same applies to extras:
  -- two trailers of a movie would otherwise both be "Title (year)" inside the
  -- Trailers folder.
  local m = get_tmdb_movie()
  local title = animename
  local suffix = nil
  if m then
    local name = m.preferredname or m.defaultname
    if name then
      title = name
      suffix = m.airdate and not name:match("%(%d%d%d%d%)$")
          and (" (" .. tostring(m.airdate.year) .. ")") or ""
    end
  end
  if not suffix then suffix = get_year_suffix(title) end
  if content_folder then
    local tagmap = { Trailers = "Trailer", Specials = "Special" }
    local tag = tagmap[content_folder] or "Extra"
    local num = episode and episode.number or 0
    suffix = suffix .. " - " .. tag .. " " .. string.format("%02d", num)
  elseif episode and episode.number then
    local need_part
    if m then
      need_part = tmdb_movie_count(m.id) > 1
    else
      need_part = (anime.episodecounts.Episode or 0) > 1
    end
    if need_part then
      local pad = math.max(#tostring(anime.episodecounts.Episode), 2)
      suffix = suffix .. " - " .. string.format("%0" .. pad .. "d", episode.number)
    end
  end
  filename = truncate_bytes(title, maxfilenamelen - #suffix - 5) .. suffix
else
  local marker = get_marker()
  local episodename = get_episode_names()

  -- "<show> - <marker> - <episode title>"; the trailing " - " is stripped when
  -- there is no episode title. Parts are truncated individually and as a
  -- whole, always in bytes. The SxxExx marker is what tofa parses, so a show
  -- file is never skipped. The show prefix is the TMDB show name (or AniDB
  -- fallback): a file in ".hack (2002)/Season 03" must read ".hack", or tofa
  -- would hunt for a third season of ".hack//Roots".
  filename = truncate_bytes(table.concat({
    truncate_bytes(get_show_name(), 80) .. " - ",
    marker .. " - ",
    truncate_bytes(episodename, 60),
  }, " "):cleanspaces(spacechar):gsub("%s*%-%s*$", ""), maxfilenamelen)
end

-- destination is the import folder (a Plex VFS library root); the media type
-- and category are part of its path, so only the title folder (+ season or
-- content for shows) goes into subfolder.
local media_type, category, folder = get_media_type(), get_category(), get_anime_folder_name()
destination = mountroot .. "/" .. base .. "/" .. media_type .. "/" .. category
if content_folder then
  subfolder = { folder, content_folder }
elseif is_movie() then
  subfolder = { folder }
else
  subfolder = { folder, get_season_folder() }
end
