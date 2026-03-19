local maxnamelen = 100
local animelanguage = Language.German
local episodelanguage = Language.German
local spacechar = " "

local animename = anime:getname(animelanguage) or anime.preferredname
local episodename = ""
local engepname = episode:getname(Language.English) or ""
local episodenumber = ""
-- Padding is determined from the number of episodes of the same type in the anime (#tostring() gives the number of digits required, e.g. 10 eps -> 2 digits)
-- Padding is at least 2 digits
local epnumpadding = math.max(#tostring(anime.episodecounts[episode.type]), 2)

episodenumber = episode_numbers(epnumpadding)

-- If this file is associated with a single episode and the episode doesn't have a generic name, then add the episode name
if #episodes == 1 then
  episodename = episode:getname(episodelanguage) or episode.preferredname or engepname or ""
else
  for i,ep in ipairs(episodes) do
    local ename = ep:getname(episodelanguage) or episode:getname(Language.English) or ep.preferredname or ""
    if ename ~= "" then
      episodename = episodename .. "/" .. ename -- If multiple episodes, combine names with /
    end
  end
end

local dublangs = from(file.media.audio):select("language"):distinct()
local sublangs = from(file.media.sublanguages):distinct()

local dublangs_adb = {}
local sublangs_adb = {}
-- Check if anidb key exists before accessing (it may be nil)
if file.anidb then
  -- Dub and sub languages from anidb are usually more accurate
  -- But will return a single unknown language if there is none, needs to be fixed in Shoko
  dublangs_adb = #file.anidb.media.dublanguages > 0 and from(file.anidb.media.dublanguages):distinct()
  sublangs_adb = #file.anidb.media.sublanguages > 0 and from(file.anidb.media.sublanguages):distinct()
end

local namelist = {
  animename:truncate(maxnamelen) .. " - ",
  episodenumber .. " - ",
  episodename:truncate(maxnamelen)
}

local base = anime.restricted and "Hentai" or "Anime"

local GerDub = (dublangs_adb and from(dublangs_adb):contains(Language.German)) or from(dublangs):contains(Language.German)
local GerSub = (sublangs_adb and from(sublangs_adb):contains(Language.German)) or from(sublangs):contains(Language.German)
local Other = (sublangs_adb and from(sublangs_adb):contains(Language.English)) or (dublangs_adb and from(dublangs_adb):contains(Language.English)) or from(sublangs):contains(Language.English) 


local function category_from_langs()
    if GerDub then return "GerDub" end
    if GerSub then return "GerSub" end
    if Other then return "Other" end
    return "_manual" -- If no known languages, put in _manual for easier review instead of misc
end

if from({base .. "-GerDub", base .. "-GerSub", base .. "-Other"}):contains(file.importfolder.name) then
  destination = file.importfolder
else
  destination = "/mnt/array" .. "/" .. base .. "/" .. category_from_langs()
end

filename = table.concat(namelist, " "):cleanspaces(spacechar)
subfolder = { animename .. " [anidbid-" .. anime.id .. "]" }