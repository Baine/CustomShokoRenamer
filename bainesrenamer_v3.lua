-- bainesrenamer_v3.lua - Shoko LuaRenamer script (tuned for Tofa)
--
-- PURPOSE
--   Moves every file into a two-level tree under a base import folder and
--   renames it to "<show> - <marker> - <episode title>". The base folder
--   (Anime/Hentai) and everything past the anime title is decided here; only
--   the top-level base folders plus Downloads/_drop are configured in Shoko.
--
-- TARGET TREE (matches tofa's naming scheme, docs.tofa.tv/name-your-media)
--   Movies:  <base>/Movies/<category>/<title> (year) [anidbid-id]/<title> (year).ext
--   Shows:   <base>/Shows/<category>/<title> (year)/Season NN [anidbid-id]/<title> - SxxExx - name.ext
--            <base>/Shows/<category>/<title> (year)/{Trailers|Specials|Extras}/...
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
-- reclassified. This replaces the old check against file.importfolder.name and
-- works for any file, wherever it was dropped from.
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

local function get_media_type()
  return anime.type == AnimeType.Movie and "Movies" or "Shows"
end

-- " (year)" when known and not already part of the title. Tofa wants the year
-- for both movies and shows (remakes / same-name titles). Kept separate from
-- the title so truncation never eats it.
local function get_year_suffix()
  local year = anime.airdate and tostring(anime.airdate.year)
  if year and not animename:match("%(%d%d%d%d%)$") then
    return " (" .. year .. ")"
  end
  return ""
end

-- Root folder name. Movies carry the AniDB tag here (they have no season
-- level); shows leave it to the Season folder and stay title+year, which is
-- exactly what tofa matches on.
local function get_anime_folder_name()
  local suffix = get_year_suffix()
  if anime.type == AnimeType.Movie then
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
local function get_primary_season()
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
-- carrying several types concatenates the groups (S01E01-E02S00E01).
local function get_marker()
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
local function get_content_folder()
  for i, ep in ipairs(episodes) do
    if ep.type == EpisodeType.Episode then return nil end
  end
  if episode.type == EpisodeType.Trailer then return "Trailers" end
  if episode.type == EpisodeType.Special then return "Specials" end
  return "Extras"
end

if anime.type == AnimeType.Movie then
  -- tofa movies carry only the title and year; an episode marker in a movie
  -- file would be a show-file signal and could break matching in a Movies
  -- library.
  filename = truncate_bytes(animename, maxfilenamelen - #get_year_suffix() - 5) .. get_year_suffix()
else
  local marker = get_marker()
  local episodename = get_episode_names()

  -- "<show> - <marker> - <episode title>"; the trailing " - " is stripped when
  -- there is no episode title. Parts are truncated individually and as a
  -- whole, always in bytes. The SxxExx marker is what tofa parses, so a show
  -- file is never skipped.
  filename = truncate_bytes(table.concat({
    truncate_bytes(animename, 80) .. " - ",
    marker .. " - ",
    truncate_bytes(episodename, 60),
  }, " "):cleanspaces(spacechar):gsub("%s*%-%s*$", ""), maxfilenamelen)
end

-- destination is the top-level base folder; everything below it is subfolder.
destination = base
local media_type, category, folder = get_media_type(), get_category(), get_anime_folder_name()
local content_folder = get_content_folder()
if content_folder then
  subfolder = { media_type, category, folder, content_folder }
elseif anime.type == AnimeType.Movie then
  subfolder = { media_type, category, folder }
else
  subfolder = { media_type, category, folder, get_season_folder() }
end
