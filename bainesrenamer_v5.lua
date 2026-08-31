-- bainesrenamer_v5.lua - Shoko LuaRenamer script (tuned for Tofa/Silo, import folders extended)
--
-- PURPOSE
--   Every file is renamed and placed inside one of 16 import folders that are
--   configured in Shoko AND mounted by Plex as library roots (VFS). The import
--   folder already encodes base + media type + category, so the script only
--   adds the title folder (and the season folder / content folder for shows).
--
-- IMPORT FOLDERS (each is a Shoko import folder, type Destination)
--   Anime/Shows/GerDub    Anime/Shows/GerSub    Anime/Shows/Others    Anime/Shows/_manual
--   Hentai/Shows/GerDub   Hentai/Shows/GerSub   Hentai/Shows/Others   Hentai/Shows/_manual
--   Anime/Movies/GerDub   Anime/Movies/GerSub   Anime/Movies/Others   Anime/Movies/_manual
--   Hentai/Movies/GerDub  Hentai/Movies/GerSub  Hentai/Movies/Others  Hentai/Movies/_manual
--   plus the Downloads/_drop folder where files are dropped.
--
-- TARGET TREE (matches tofa's naming scheme, docs.tofa.tv/name-your-media)
--   Movies:  <import folder>/<title> (year) [tmdbid-id]/<title> (year).ext
--   Shows:   <import folder>/<title> (year) [tmdbid-id]/Season NN [anidbid-id]/<title> - SxxExx - name.ext
--            <import folder>/<title> (year) [id]/Extras/...
--
--     base        Anime (safe) or Hentai (anime.restricted)
--     media type  Movies (AniDB type Movie) or Shows (everything else)
--     category    GerDub | GerSub | Others | _manual   (see get_category)
--     year        from the air date (anime.year does not exist in the Lua env)
--     season NN   TMDB season number when available, else 1 (AniDB is
--                 single-season per entry, so AniDB fallback is season 1)
--     episode     TMDB episode number when cross-referenced, otherwise the
--                 AniDB number with type-appropriate padding
--     [anidbid-id]  AniDB ID tag: on the Season folder for shows (each season
--                 of a TMDB show is one AniDB entry), on the root folder for
--                 movies without a TMDB cross-reference
--     [tmdbid-id]  TMDB ID tag: on the root folder for TMDB-linked movies and
--                 shows, so Silo can identify the title without guessing
--     [anidbfile-id]  alternative filename suffix used only when the normal
--                 target already exists; manual links have no such fallback
--     content     Extras (see get_content_folder)
--
--     Example: Anime/Shows/GerDub/Tokidoki Bosotto to Roshippu to (2024) [tmdbid-12345]/
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
local function cleaned_bytes(s)
  local len = 0
  for c in s:gmatch(".[\128-\191]*") do
    local replacement = not remove_illegal_chars and replace_illegal_chars
        and illegal_chars_map and illegal_chars_map[c] or nil
    len = len + #(replacement or c)
  end
  return len
end

local function truncate_bytes(s, maxbytes, ellipsis)
  ellipsis = ellipsis or "..."
  if cleaned_bytes(s) <= maxbytes then return s end
  local budget = maxbytes - cleaned_bytes(ellipsis)
  local parts, len = {}, 0
  for c in s:gmatch(".[\128-\191]*") do
    local replacement = not remove_illegal_chars and replace_illegal_chars
        and illegal_chars_map and illegal_chars_map[c] or nil
    local bytes = #(replacement or c)
    if len + bytes > budget then break end
    parts[#parts + 1] = c
    len = len + bytes
  end
  return table.concat(parts):gsub("%s+$", "") .. ellipsis
end

local function has(list, lang)
  return from(list or {}):contains(lang)
end

local animename = anime:getname(animelanguage) or anime.preferredname
local base = anime.restricted and "Hentai" or "Anime"

-- Choose the script's primary episode independently of the order supplied by
-- LuaRenamer. Normal content wins, then specials/other material, followed by
-- credits, trailers and parodies. Episodes of the primary anime stay ahead of
-- links to other anime that may share the same file.
local episode_type_priority = {
  [EpisodeType.Episode] = 1,
  [EpisodeType.Special] = 2,
  [EpisodeType.Other] = 3,
  [EpisodeType.Credits] = 4,
  [EpisodeType.Trailer] = 5,
  [EpisodeType.Parody] = 6,
}

local ordered_episodes = {}
for i, ep in ipairs(episodes) do ordered_episodes[i] = ep end
table.sort(ordered_episodes, function(a, b)
  local a_primary = not a.animeid or tostring(a.animeid) == tostring(anime.id)
  local b_primary = not b.animeid or tostring(b.animeid) == tostring(anime.id)
  if a_primary ~= b_primary then return a_primary end
  local a_priority = episode_type_priority[a.type] or 99
  local b_priority = episode_type_priority[b.type] or 99
  if a_priority ~= b_priority then return a_priority < b_priority end
  if (a.number or 0) ~= (b.number or 0) then return (a.number or 0) < (b.number or 0) end
  return tostring(a.id or "") < tostring(b.id or "")
end)
local primary_episode = ordered_episodes[1] or episode

-- Lua cannot inspect the final target itself. The plugin evaluates this
-- alternative only after resolving destination/subfolder and only on collision.
local anidb_collision_tag = file.anidb and file.anidb.id
    and (" [anidbfile-" .. tostring(file.anidb.id) .. "]") or nil

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
--
-- "Other" is accepted as a legacy source folder and normalized to "Others",
-- so remaining files in the old path migrate automatically on relocation.
local function category_from_path()
  local segs = {}
  for seg in file.path:gmatch("[^/]+") do segs[#segs + 1] = seg end
  for i = 1, #segs - 1 do
    if segs[i] == base then
      for j = i + 1, math.min(i + 2, #segs) do
        if segs[j] == "GerDub" or segs[j] == "GerSub" or segs[j] == "_manual" then
          return segs[j]
        elseif segs[j] == "Other" or segs[j] == "Others" then
          return "Others"
        end
      end
    end
  end
  return nil
end

-- German dub wins over German sub wins over English (either track), anything
-- else lands in _manual for manual review instead of a catch-all folder.
local function get_category()
  return category_from_path() or (GerDub and "GerDub") or (GerSub and "GerSub") or (Other and "Others") or "_manual"
end

-- TMDB movie linked to the file's primary episode, or nil. AniDB movie entries
-- often hold several films (episodes 1..N); each one is usually its own TMDB
-- movie, and the per-episode cross-reference tells them apart. The plugin
-- exposes every AniDB episode link of a movie as anidbepisodeids.
local function get_tmdb_movie()
  if not tmdb or not tmdb.movies or not primary_episode or not primary_episode.id then return nil end
  local match = nil
  for i, m in ipairs(tmdb.movies) do
    for j, id in ipairs(m.anidbepisodeids or {}) do
      if tostring(id) == tostring(primary_episode.id) then
        if match and match ~= m then return nil end
        match = m
      end
    end
  end
  return match
end

local function get_tmdb_episode_matches(ep)
  ep = ep or primary_episode
  if not tmdb or not tmdb.episodes or not ep or not ep.id then return {} end
  local matches = {}
  for i, te in ipairs(tmdb.episodes) do
    for j, id in ipairs(te.anidbepisodeids or {}) do
      if tostring(id) == tostring(ep.id) then
        matches[#matches + 1] = te
        break
      end
    end
  end
  return matches
end

-- TMDB episode of the show that the file's primary episode is linked to, or
-- nil. Several matches remain usable when they all belong to one show, season
-- and type; get_marker then emits their TMDB numbers as a range. A genuinely
-- ambiguous match falls back to AniDB instead of depending on list order.
local function get_tmdb_episode(ep)
  local matches = get_tmdb_episode_matches(ep)
  local match = matches[1]
  if not match then return nil end
  for i = 2, #matches do
    local te = matches[i]
    if tostring(te.showid) ~= tostring(match.showid)
        or (te.seasonnumber or 1) ~= (match.seasonnumber or 1)
        or te.type ~= match.type then
      return nil
    end
  end
  return match
end

-- Only normal AniDB episodes use TMDB numbering. The one intentional exception
-- is an AniDB "Other" which TMDB identifies as a real episode in a regular
-- season (Cyborg 009). Specials/credits/trailers remain Extras with C/S/T/P/O.
local function is_regular_content(ep, te)
  if ep.type == EpisodeType.Episode then return true end
  return ep.type == EpisodeType.Other and te and te.type == EpisodeType.Episode
      and (te.seasonnumber or 1) > 0
end

-- If the selected primary episode has no cross-reference, use an unambiguous
-- regular TMDB episode from the same file instead. Conflicting shows still
-- fall back to AniDB rather than depending on episode list order.
local function get_file_tmdb_episode()
  local primary = get_tmdb_episode(primary_episode)
  if primary then return primary end
  local match = nil
  for i, ep in ipairs(ordered_episodes) do
    local te = get_tmdb_episode(ep)
    if te and is_regular_content(ep, te) then
      if match and tostring(match.showid) ~= tostring(te.showid) then return nil end
      match = match or te
    end
  end
  return match
end

-- Resolve the current file's cross-references once. A renamer invocation is
-- scoped to one file, and all later decisions must use the same match.
local tmdb_movie = get_tmdb_movie()
local tmdb_episode = get_file_tmdb_episode()

-- AniDB type decides, but TMDB knows better: entries AniDB types as OVA are
-- often movies (Final Fantasy VII: Advent Children is OVA on AniDB, a movie on
-- TMDB). Any TMDB movie cross-reference then makes the whole entry a movie.
-- A TV series, however, can carry specials that TMDB classifies as movies
-- (Sherlock Hound); only the cross-referenced episode is a movie then.
-- Conversely, a movie-typed entry can hold TV episodes (Cyborg 009: Call of
-- Justice packs its 3 movies and 12 TV episodes in one AniDB entry): a file
-- whose episode links to a TMDB show is a show episode, not a movie.
local function is_movie()
  if anime.type == AnimeType.Movie then
    return tmdb_episode == nil
  end
  if anime.type == AnimeType.OVA and tmdb and tmdb.movies and #tmdb.movies > 0 then return true end
  return tmdb_movie ~= nil
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

-- TMDB show owning the file's primary episode, or nil. The show id is on the
-- matched episode cross-ref, the names are on the show list. Using the matched
-- episode matters when one AniDB entry has links to more than one TMDB show.
local function get_tmdb_show()
  if not tmdb_episode or not tmdb or not tmdb.shows then return nil end
  for i, s in ipairs(tmdb.shows) do
    if tostring(s.id) == tostring(tmdb_episode.showid) then return s end
  end
  return nil
end

local tmdb_show = get_tmdb_show()
local root_tmdb_movie = tmdb_movie
local root_tmdb_show = tmdb_show
local root_tmdb_show_id = tmdb_episode and tmdb_episode.showid or nil

-- Display name of the series: the TMDB show name when the file has a TMDB
-- cross-reference or inherits one unambiguous show from linked sibling
-- episodes (Sign, Twilight and Roots all belong to ".hack"), else the AniDB
-- title. Used for the root folder AND the file prefix.
local function get_show_name()
  local s = root_tmdb_show
  if s then
    local name = s.preferredname or s.defaultname
    if name then return name end
  end
  if root_tmdb_show_id then return "TMDB Show" end
  return animename
end

-- Root folder name. TMDB structure wins: one anime can be spread over several
-- AniDB entries (Sign, Twilight and Roots are seasons of ".hack"), and they
-- must share one show folder. Falls back to the AniDB title when the file has
-- no TMDB cross-reference. Movies use the TMDB movie of the file's episode
-- when there is one (a multi-part movie becomes one folder per film) and they
-- have no season level.
local function get_anime_folder_name(movie)
  if movie then
    local m = root_tmdb_movie
    if m then
      local name = m.preferredname or m.defaultname or animename
      local suffix = m.airdate and not name:match("%(%d%d%d%d%)$")
          and (" (" .. tostring(m.airdate.year) .. ")") or get_year_suffix(name)
      local tag = " [tmdbid-" .. tostring(m.id) .. "]"
      return truncate_bytes(name, 255 - #suffix - #tag) .. suffix .. tag
    end
  else
    local s = root_tmdb_show
    if root_tmdb_show_id then
      -- Never derive a TMDB root from the current AniDB entry: several AniDB
      -- seasons of one show must remain in exactly the same root even when the
      -- TMDB title/date metadata is temporarily incomplete.
      local name = s and (s.preferredname or s.defaultname) or "TMDB Show"
      name = name or "TMDB Show"
      local suffix = s and s.airdate and not name:match("%(%d%d%d%d%)$")
          and (" (" .. tostring(s.airdate.year) .. ")") or ""
      local tag = " [tmdbid-" .. tostring(root_tmdb_show_id) .. "]"
      return truncate_bytes(name, 255 - #suffix - #tag) .. suffix .. tag
    end
  end
  local suffix = get_year_suffix(animename)
  if movie then
    suffix = suffix .. " [anidbid-" .. anime.id .. "]"
  end
  return truncate_bytes(animename, 255 - #suffix) .. suffix
end

-- The Season folder mirrors TMDB's season numbering for the file's regular
-- episode; a file with only specials/trailers never reaches this function.
-- An episode with a TMDB cross-reference uses that TMDB season directly, so a
-- show episode that AniDB typed as "Other" (Cyborg 009) still lands in the
-- right season.
local function get_primary_season()
  for i, ep in ipairs(ordered_episodes) do
    local te = get_tmdb_episode(ep)
    if is_regular_content(ep, te) and te and root_tmdb_show_id
        and tostring(te.showid) == tostring(root_tmdb_show_id) then
      return te.seasonnumber or 1
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

local marker_prefixes = {
  [EpisodeType.Credits] = "C",
  [EpisodeType.Special] = "S",
  [EpisodeType.Trailer] = "T",
  [EpisodeType.Parody] = "P",
  [EpisodeType.Other] = "O",
}

local function format_group_marker(t, season, num, pad)
  if t == EpisodeType.Episode then return format_marker(season, num, pad) end
  return (marker_prefixes[t] or "O") .. string.format("%0" .. pad .. "d", num)
end

-- Consecutive episodes of one type collapse into a range: S01E01-E02 or
-- C01-C02. TMDB-numbered groups derive their padding from the TMDB numbers;
-- AniDB fallbacks keep the type count and established C/S/T/P/O prefixes.
local function format_group(t, nums, tmdb_season)
  table.sort(nums)
  local marker_type = t
  local pad
  local season
  if tmdb_season ~= nil then
    marker_type = EpisodeType.Episode
    season = tmdb_season
    pad = 2
    for i, num in ipairs(nums) do pad = math.max(pad, #tostring(num)) end
  else
    pad = math.max(#tostring(anime.episodecounts[t] or 0), 2)
    season = t == EpisodeType.Episode and 1 or 0
  end
  local range_prefix = marker_type == EpisodeType.Episode and "E" or (marker_prefixes[marker_type] or "O")
  local parts = {}
  local first = nums[1]
  local prev = first
  for i = 2, #nums + 1 do
    local n = nums[i]
    if not n or n ~= prev + 1 then
      parts[#parts + 1] = format_group_marker(marker_type, season, first, pad)
          .. (first == prev and "" or "-" .. range_prefix .. string.format("%0" .. pad .. "d", prev))
      first = n
    end
    prev = n
  end
  return table.concat(parts)
end

-- Regular AniDB episodes linked to TMDB use TMDB season and episode number.
-- This matters for absolute AniDB numbering (One Piece AniDB E326 can be TMDB
-- S09E08). Multi-episode files group consecutive TMDB numbers into ranges;
-- unlinked episodes and Extras retain the AniDB type/number fallback.
local function get_marker()
  local groups, regular_order, extra_order = {}, {}, {}
  for i, ep in ipairs(ordered_episodes) do
    local matches = get_tmdb_episode_matches(ep)
    local te = get_tmdb_episode(ep)
    local regular = is_regular_content(ep, te)
    if not regular then te = nil end
    local key
    if te then
      local season = te.seasonnumber or 1
      key = "tmdb:" .. tostring(te.showid) .. ":" .. tostring(season)
      if not groups[key] then
        groups[key] = { type = EpisodeType.Episode, season = season, nums = {}, seen = {} }
        regular_order[#regular_order + 1] = key
      end
      for j, match in ipairs(matches) do
        local numkey = tostring(match.number)
        if not groups[key].seen[numkey] then
          groups[key].nums[#groups[key].nums + 1] = match.number
          groups[key].seen[numkey] = true
        end
      end
    else
      key = "anidb:" .. tostring(ep.type)
      if not groups[key] then
        groups[key] = { type = ep.type, nums = {} }
        local order = regular and regular_order or extra_order
        order[#order + 1] = key
      end
      groups[key].nums[#groups[key].nums + 1] = ep.number
    end
  end
  local parts = {}
  for _, order in ipairs({ regular_order, extra_order }) do
    for i, key in ipairs(order) do
      local group = groups[key]
      parts[#parts + 1] = format_group(group.type, group.nums, group.season)
    end
  end
  return table.concat(parts)
end

-- Episode names use the preferred language with an English fallback. A single
-- episode returns its name directly; several episodes are joined with "/".
local function get_episode_names()
  if #ordered_episodes == 1 then
    return primary_episode:getname(episodelanguage) or primary_episode:getname(Language.English) or ""
  end
  local names = {}
  for i, ep in ipairs(ordered_episodes) do
    local name = ep:getname(episodelanguage) or ep:getname(Language.English) or ""
    if name ~= "" then names[#names + 1] = name end
  end
  return table.concat(names, "/")
end

-- Only files without a regular episode leave the main folder. Specials,
-- openings, endings, trailers and all other non-episode content share Extras;
-- their C/S/T/P/O markers keep equal AniDB numbers distinct.
-- tofa treats these folder names as extras and keeps them out of the library.
-- Only the explicit AniDB-Other -> regular TMDB episode exception stays in a
-- season folder despite its AniDB type.
local function get_content_folder()
  for i, ep in ipairs(ordered_episodes) do
    if is_regular_content(ep, get_tmdb_episode(ep)) then return nil end
  end
  return "Extras"
end

local content_folder = get_content_folder()
local movie = is_movie()

-- A Special with its own episode-level TMDB movie cross-reference is not an
-- extra of the parent movie/show: TMDB treats it as a standalone movie. Keep
-- the Extras fallback below for unlinked specials and sole-candidate matches.
if movie and tmdb_movie and primary_episode
    and primary_episode.type == EpisodeType.Special then
  content_folder = nil
end

-- Extras and specials often have no episode-level TMDB cross-reference. When
-- the AniDB entry has exactly one TMDB movie/show, it is still unambiguous and
-- should share the same TMDB root as the regular content. The plugin exposes
-- shows for the whole Shoko series but TMDB episodes only for the current file,
-- so an unlinked regular episode must inherit the sole series-level show without
-- looking for sibling episode links here. Its season/episode numbering still
-- falls back to AniDB. Multiple candidates keep the AniDB root.
if content_folder then
  if not root_tmdb_movie and tmdb and tmdb.movies and #tmdb.movies == 1 then
    root_tmdb_movie = tmdb.movies[1]
  end
end

local sole_tmdb_show = tmdb and tmdb.shows and #tmdb.shows == 1 and tmdb.shows[1] or nil
if not movie and not root_tmdb_show and sole_tmdb_show then
  root_tmdb_show = sole_tmdb_show
end
if not root_tmdb_show_id and root_tmdb_show then
  root_tmdb_show_id = root_tmdb_show.id
end

-- AniDB sometimes represents one TMDB movie as both a complete file and an
-- alternative split release ("Complete Movie", "Part 1 of 2", ...). Common
-- media servers stack files ending in pt1/pt2/etc. The title check keeps other
-- multi-episode movie entries on the existing, neutral 01/02 numbering.
local function get_movie_multipart_suffix(m)
  if not m or #(m.anidbepisodeids or {}) <= 1 or not primary_episode then return nil end
  local names = {}
  local english_name = primary_episode:getname(Language.English)
  local preferred_name = primary_episode:getname(episodelanguage)
  if english_name then names[#names + 1] = english_name end
  if preferred_name then names[#names + 1] = preferred_name end
  for i, name in ipairs(names) do
    local normalized = name and name:lower():match("^%s*(.-)%s*$") or nil
    if normalized == "complete movie" then return "" end
    if normalized then
      local part, total = normalized:match("^part%s+(%d+)%s+of%s+(%d+)$")
      part, total = tonumber(part), tonumber(total)
      if part and total and part >= 1 and part <= total then
        return " - pt" .. tostring(part)
      end
    end
  end
  return nil
end

if movie then
  -- tofa movies carry only the title and year; an episode marker in a movie
  -- file would be a show-file signal and could break matching in a Movies
  -- library. But an AniDB entry of type Movie can hold several movies (episodes
  -- 1..N); those must be told apart or every file resolves to the same name
  -- and the relocation service deletes the loser. When an episode links to its
  -- own TMDB movie the file gets that movie's name and folder; the part number
  -- remains only for episodes that share a folder. The same applies to extras:
  -- two trailers of a movie would otherwise both be "Title (year)" inside the
  -- Extras folder.
  local m = root_tmdb_movie
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
    suffix = suffix .. " - " .. get_marker()
        .. " [anidbid-" .. tostring(anime.id) .. "]"
  elseif primary_episode and primary_episode.number then
    local multipart_suffix = get_movie_multipart_suffix(m)
    if multipart_suffix ~= nil then
      suffix = suffix .. multipart_suffix
    else
      local need_part
      if m then
        need_part = #(m.anidbepisodeids or {}) > 1
      else
        need_part = (anime.episodecounts.Episode or 0) > 1
      end
      if need_part then
        local pad = math.max(#tostring(anime.episodecounts.Episode), 2)
        suffix = suffix .. " - " .. string.format("%0" .. pad .. "d", primary_episode.number)
      end
    end
  end
  filename = truncate_bytes(title, maxfilenamelen - #suffix - 5) .. suffix
  if anidb_collision_tag then
    collision_filename = truncate_bytes(title, maxfilenamelen - #suffix - #anidb_collision_tag - 5)
        .. suffix .. anidb_collision_tag
  end
else
  local marker = get_marker()
  local episodename = get_episode_names()
  local extra_tag = content_folder and (" [anidbid-" .. tostring(anime.id) .. "]") or ""

  -- "<show> - <marker> - <episode title>"; the trailing " - " is stripped when
  -- there is no episode title. Parts are truncated individually and as a
  -- whole, always in bytes. The SxxExx marker is what tofa parses, so a show
  -- file is never skipped. The show prefix is the TMDB show name (or AniDB
  -- fallback): a file in ".hack (2002)/Season 03" must read ".hack", or tofa
  -- would hunt for a third season of ".hack//Roots".
  local filename_base = table.concat({
    truncate_bytes(get_show_name(), 80) .. " - ",
    marker .. " - ",
    truncate_bytes(episodename, 60),
  }, " "):cleanspaces(spacechar):gsub("%s*%-%s*$", "")
  filename = truncate_bytes(filename_base, maxfilenamelen - #extra_tag) .. extra_tag
  if anidb_collision_tag then
    collision_filename = truncate_bytes(filename_base, maxfilenamelen - #extra_tag - #anidb_collision_tag)
        .. extra_tag .. anidb_collision_tag
  end
end

-- destination is the import folder (a Plex VFS library root); the media type
-- and category are part of its path, so only the title folder (+ season or
-- content for shows) goes into subfolder.
local media_type = movie and "Movies" or "Shows"
local category, folder = get_category(), get_anime_folder_name(movie)
destination = mountroot .. "/" .. base .. "/" .. media_type .. "/" .. category
if content_folder then
  subfolder = { folder, content_folder }
elseif movie then
  subfolder = { folder }
else
  subfolder = { folder, get_season_folder() }
end
