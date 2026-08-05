local maxfilenamelen = 190
local animelanguage = Language.German
local episodelanguage = Language.German
local spacechar = " "

-- XFS segments are limited to 255 bytes, so truncate by bytes (not unicode chars)
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

-- AniDB is usually more accurate, but reports a single Unknown language when there is none
local media_dubs = file.media and from(file.media.audio):select("language"):distinct() or fromNothing()
local media_subs = file.media and from(file.media.sublanguages):distinct() or fromNothing()
local adb_dubs = file.anidb and #file.anidb.media.dublanguages > 0 and from(file.anidb.media.dublanguages):distinct() or nil
local adb_subs = file.anidb and #file.anidb.media.sublanguages > 0 and from(file.anidb.media.sublanguages):distinct() or nil

local GerDub = has(adb_dubs, Language.German) or has(media_dubs, Language.German)
local GerSub = has(adb_subs, Language.German) or has(media_subs, Language.German)
local Other = has(adb_subs, Language.English) or has(adb_dubs, Language.English) or has(media_subs, Language.English) or has(media_dubs, Language.English)

-- Keep manual placement: a file already in a category folder is not reclassified
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

local function get_category()
  return category_from_path() or (GerDub and "GerDub") or (GerSub and "GerSub") or (Other and "Other") or "_manual"
end

local function get_media_type()
  return anime.type == AnimeType.Movie and "Movies" or "Shows"
end

local function get_anime_folder_name()
  local title = animename
  local suffix = " [anidbid-" .. anime.id .. "]"
  if anime.type ~= AnimeType.Movie then
    local year = anime.airdate and tostring(anime.airdate.year)
    if year and not title:match("%(%d%d%d%d%)$") then
      suffix = " (" .. year .. ")" .. suffix
    end
  end
  return truncate_bytes(title, 255 - #suffix - 5) .. suffix
end

-- AniDB has no seasons, so the marker season comes from TMDB when available, else 01
local function get_season(t, num)
  for i, te in ipairs(tmdb.episodes) do
    if te.type == t and te.number == num then
      return te.seasonnumber or 1
    end
  end
  return 1
end

-- Padding is determined from the number of episodes of the same type in the anime, at least 2 digits
local function format_marker(season, num, pad)
  return "S" .. string.format("%02d", season) .. "E" .. string.format("%0" .. pad .. "d", num)
end

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

-- Consecutive episodes of the same type share a group (S01E01-E02); mixed types are concatenated (S01E01S00E01)
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

-- Files containing a regular episode stay in the main folder even if a special is included
local function get_content_folder()
  for i, ep in ipairs(episodes) do
    if ep.type == EpisodeType.Episode then return nil end
  end
  if episode.type == EpisodeType.Trailer then return "Trailers" end
  if episode.type == EpisodeType.Special then return "Specials" end
  return "Extras"
end

local marker = get_marker()
local episodename = get_episode_names()

filename = truncate_bytes(table.concat({
  truncate_bytes(animename, 80) .. " - ",
  marker .. " - ",
  truncate_bytes(episodename, 60),
}, " "):cleanspaces(spacechar):gsub("%s*%-%s*$", ""), maxfilenamelen)

destination = base
subfolder = { get_media_type(), get_category(), get_anime_folder_name() }
local content_folder = get_content_folder()
if content_folder then subfolder[#subfolder + 1] = content_folder end
