-- Verification harness for bainesrenamer (Lua 5.1 and Lua 5.4)
-- Run: lua verify.lua [script.lua]  (defaults to bainesrenamer_v5.lua)

string.cleanspaces = function(self, char)
  return (self:match("^%s*(.-)%s*$"):gsub("%s+", char or " "))
end

local Language = { German = "de", English = "en" }
local AnimeType = { Movie = "Movie", OVA = "OVA", TVSeries = "TVSeries" }
local EpisodeType = { Episode = "Episode", Special = "Special", Trailer = "Trailer", Credits = "Credits", Other = "Other", Parody = "Parody" }

local function linq(list)
  return {
    __linq = true,
    contains = function(_, v)
      for i = 1, #list do if list[i] == v then return true end end
      return false
    end,
    distinct = function()
      local seen, out = {}, {}
      for i = 1, #list do
        if not seen[list[i]] then seen[list[i]] = true; out[#out + 1] = list[i] end
      end
      return linq(out)
    end,
    select = function(_, key)
      local out = {}
      for i = 1, #list do out[i] = list[i][key] end
      return linq(out)
    end,
  }
end
local function from(list)
  if type(list) == "table" and list.__linq then return list end
  return linq(list)
end
local function fromNothing() return linq({}) end

local function make_anime(overrides)
  local a = {
    id = 3, restricted = false, type = AnimeType.TVSeries,
    preferredname = "Preferred",
    _de = nil, _en = nil,
    getname = function(self, lang)
      if lang == Language.German and self._de then return self._de end
      if lang == Language.English and self._en then return self._en end
      return nil
    end,
    episodecounts = { Episode = 24, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 },
  }
  for k, v in pairs(overrides) do a[k] = v end
  if a.airdate == nil then a.airdate = { year = 2021 } end
  return a
end

local function make_ep(number, type, titles)
  titles = titles or {}
  return {
    number = number, type = type,
    getname = function(_, lang)
      if lang == Language.German and titles.de then return titles.de end
      if lang == Language.English and titles.en then return titles.en end
      return nil
    end,
  }
end

local function set_id(ep, id)
  ep.id = id
  return ep
end

-- loadfile the script with a custom env on both 5.1 (setfenv) and 5.4
-- (loadfile's third argument).
local function loadfile_env(file, env)
  if setfenv then
    local chunk = loadfile(file)
    setfenv(chunk, env)
    return chunk
  end
  return loadfile(file, "t", env)
end

local passed = 0
local function run(name, stubs, checks)
  local env = setmetatable({}, { __index = _G })
  for k, v in pairs(stubs) do env[k] = v end
  env.Language, env.AnimeType, env.EpisodeType = Language, AnimeType, EpisodeType
  env.from, env.fromNothing = from, fromNothing
  env.tmdb = { episodes = stubs.tmdb_episodes or {}, shows = stubs.tmdb_shows or {}, movies = stubs.tmdb_movies or {} }
  local chunk = loadfile_env(arg and arg[1] or "bainesrenamer_v5.lua", env)
  chunk()
  for _, check in ipairs(checks) do
    check(env, name)
    passed = passed + 1
  end
  print("ok: " .. name)
end

local function eq(name, want_filename, want_subfolder, want_destination)
  return function(e)
    assert(e.filename == want_filename, name .. " filename: got '" .. e.filename .. "' want '" .. want_filename .. "'")
    assert(e.destination == want_destination, name .. " destination: got '" .. tostring(e.destination) .. "' want '" .. want_destination .. "'")
    assert(#e.subfolder == #want_subfolder, name .. " subfolder count: got " .. #e.subfolder .. " want " .. #want_subfolder)
    for i, want in ipairs(want_subfolder) do
      assert(e.subfolder[i] == want, name .. " subfolder[" .. i .. "]: got '" .. tostring(e.subfolder[i]) .. "' want '" .. want .. "'")
    end
  end
end

run("Old plugin data does not guess a TMDB season", {
  anime = make_anime({ _de = "Example Show" }),
  episodes = { make_ep(3, EpisodeType.Episode, { de = "Folge 3" }) },
  episode = make_ep(3, EpisodeType.Episode, { de = "Folge 3" }),
  file = {
    path = "/mnt/array/Downloads/_drop/somefile.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_episodes = { { type = EpisodeType.Episode, number = 3, seasonnumber = 2 } },
}, { eq("NoLegacyGuess", "Example Show - S01E03 - Folge 3", { "Example Show (2021)", "Season 01 [anidbid-3]" }, "/mnt/array/Anime/Shows/GerDub") })

run("TMDB show folder over anidb title", {
  anime = make_anime({ id = 4324, _de = ".hack//Roots", airdate = { year = 2006 } }),
  episodes = { set_id(make_ep(21, EpisodeType.Episode, { de = "Defeat" }), 432421) },
  episode = set_id(make_ep(21, EpisodeType.Episode, { de = "Defeat" }), 432421),
  file = {
    path = "/mnt/array/Downloads/_drop/roots.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "8864", preferredname = ".hack", airdate = { year = 2002 } } },
  tmdb_episodes = { { anidbepisodeids = { 432421 }, type = EpisodeType.Episode, number = 21, seasonnumber = 3, showid = "8864" } },
}, { eq("TmdbShow", ".hack - S03E21 - Defeat", { ".hack (2002) [tmdbid-8864]", "Season 03 [anidbid-4324]" }, "/mnt/array/Anime/Shows/GerDub") })

run("TMDB episode number overrides AniDB absolute number", {
  anime = make_anime({ id = 69, _de = "One Piece", airdate = { year = 1999 }, episodecounts = { Episode = 1200, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(326, EpisodeType.Episode, { de = "The Mysterious Band of Pirates!" }), 326001) },
  episode = set_id(make_ep(326, EpisodeType.Episode, { de = "The Mysterious Band of Pirates!" }), 326001),
  file = {
    path = "/mnt/array/Downloads/_drop/one-piece-326.avi",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "9999", preferredname = "One Piece", airdate = { year = 1999 } } },
  tmdb_episodes = {
    { anidbepisodeids = { 326001 }, type = EpisodeType.Episode, number = 8, seasonnumber = 9, showid = "9999" },
  },
}, { eq("TmdbEpisodeNumber", "One Piece - S09E08 - The Mysterious Band of Pirates!", { "One Piece (1999) [tmdbid-9999]", "Season 09 [anidbid-69]" }, "/mnt/array/Anime/Shows/GerDub") })

run("Multi-episode file uses TMDB episode range", {
  anime = make_anime({ id = 69, _de = "One Piece", airdate = { year = 1999 }, episodecounts = { Episode = 1200, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = {
    set_id(make_ep(326, EpisodeType.Episode, { de = "Teil 1" }), 326001),
    set_id(make_ep(327, EpisodeType.Episode, { de = "Teil 2" }), 327001),
  },
  episode = set_id(make_ep(326, EpisodeType.Episode, { de = "Teil 1" }), 326001),
  file = {
    path = "/mnt/array/Downloads/_drop/one-piece-326-327.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "9999", preferredname = "One Piece", airdate = { year = 1999 } } },
  tmdb_episodes = {
    { anidbepisodeids = { 326001 }, type = EpisodeType.Episode, number = 8, seasonnumber = 9, showid = "9999" },
    { anidbepisodeids = { 327001 }, type = EpisodeType.Episode, number = 9, seasonnumber = 9, showid = "9999" },
  },
}, { eq("TmdbEpisodeRange", "One Piece - S09E08-E09 - Teil 1/Teil 2", { "One Piece (1999) [tmdbid-9999]", "Season 09 [anidbid-69]" }, "/mnt/array/Anime/Shows/GerDub") })

run("AniDB season entry 1 shares its TMDB show root", {
  anime = make_anime({ id = 100, _de = "Shared Show First Entry", airdate = { year = 2015 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode, { de = "Erste Staffel" }), 10001) },
  episode = set_id(make_ep(1, EpisodeType.Episode, { de = "Erste Staffel" }), 10001),
  file = {
    path = "/mnt/array/Downloads/_drop/shared-s1.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "555", preferredname = "Shared Show", airdate = { year = 2015 } } },
  tmdb_episodes = {
    { anidbepisodeids = { 10001 }, type = EpisodeType.Episode, number = 1, seasonnumber = 1, showid = "555" },
  },
}, { eq("SharedRootS1", "Shared Show - S01E01 - Erste Staffel", { "Shared Show (2015) [tmdbid-555]", "Season 01 [anidbid-100]" }, "/mnt/array/Anime/Shows/GerDub") })

run("AniDB season entry 2 shares its TMDB show root", {
  anime = make_anime({ id = 200, _de = "Shared Show Second Entry", airdate = { year = 2017 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode, { de = "Zweite Staffel" }), 20001) },
  episode = set_id(make_ep(1, EpisodeType.Episode, { de = "Zweite Staffel" }), 20001),
  file = {
    path = "/mnt/array/Downloads/_drop/shared-s2.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "555", preferredname = "Shared Show", airdate = { year = 2015 } } },
  tmdb_episodes = {
    { anidbepisodeids = { 20001 }, type = EpisodeType.Episode, number = 1, seasonnumber = 2, showid = "555" },
  },
}, { eq("SharedRootS2", "Shared Show - S02E01 - Zweite Staffel", { "Shared Show (2015) [tmdbid-555]", "Season 02 [anidbid-200]" }, "/mnt/array/Anime/Shows/GerDub") })

run("TMDB show is selected from the primary episode cross-ref", {
  anime = make_anime({ id = 77, _de = "AniDB Mixed Entry", airdate = { year = 2019 } }),
  episodes = { set_id(make_ep(6, EpisodeType.Episode, { de = "Folge 6" }), 2002) },
  episode = set_id(make_ep(6, EpisodeType.Episode, { de = "Folge 6" }), 2002),
  file = {
    path = "/mnt/array/Downloads/_drop/mixed.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = {
    { id = "11", preferredname = "Wrong Show", airdate = { year = 2018 } },
    { id = "22", preferredname = "Right Show", airdate = { year = 2020 } },
  },
  tmdb_episodes = {
    { anidbepisodeids = { 1001 }, type = EpisodeType.Episode, number = 6, seasonnumber = 9, showid = "11" },
    { anidbepisodeids = { 2002 }, type = EpisodeType.Episode, number = 6, seasonnumber = 4, showid = "22" },
  },
}, { eq("PrimaryTmdbShow", "Right Show - S04E06 - Folge 6", { "Right Show (2020) [tmdbid-22]", "Season 04 [anidbid-77]" }, "/mnt/array/Anime/Shows/GerDub") })

run("TMDB show ID survives missing show metadata", {
  anime = make_anime({ id = 78, _de = "AniDB Fallback Title", airdate = { year = 2021 } }),
  episodes = { set_id(make_ep(2, EpisodeType.Episode, { de = "Folge 2" }), 7802) },
  episode = set_id(make_ep(2, EpisodeType.Episode, { de = "Folge 2" }), 7802),
  file = {
    path = "/mnt/array/Downloads/_drop/missing-show.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_episodes = {
    { anidbepisodeids = { 7802 }, type = EpisodeType.Episode, number = 2, seasonnumber = 3, showid = "78000" },
  },
}, { eq("MissingTmdbShow", "TMDB Show - S03E02 - Folge 2", { "TMDB Show [tmdbid-78000]", "Season 03 [anidbid-78]" }, "/mnt/array/Anime/Shows/GerDub") })

run("Anidb title fallback when no TMDB show", {
  anime = make_anime({ id = 4324, _de = ".hack//Roots", airdate = { year = 2006 } }),
  episodes = { make_ep(21, EpisodeType.Episode, { de = "Defeat" }) },
  episode = make_ep(21, EpisodeType.Episode, { de = "Defeat" }),
  file = {
    path = "/mnt/array/Downloads/_drop/roots.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
}, { eq("AnidbFallback", ".hack//Roots - S01E21 - Defeat", { ".hack//Roots (2006)", "Season 01 [anidbid-4324]" }, "/mnt/array/Anime/Shows/GerDub") })

run("Movie trailer gets type tag", {
  anime = make_anime({ id = 882, type = AnimeType.Movie, airdate = { year = 1987 }, preferredname = "Dirty Pair", episodecounts = { Episode = 1, Special = 2, Trailer = 2, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { make_ep(1, EpisodeType.Trailer) },
  episode = make_ep(1, EpisodeType.Trailer),
  file = { path = "/mnt/array/Downloads/_drop/t.mkv", media = nil, anidb = nil },
}, { eq("MovieTrailer", "Dirty Pair (1987) - T01 [anidbid-882]", { "Dirty Pair (1987) [anidbid-882]", "Extras" }, "/mnt/array/Anime/Movies/_manual") })

run("Movie special gets type tag", {
  anime = make_anime({ id = 882, type = AnimeType.Movie, airdate = { year = 1987 }, preferredname = "Dirty Pair", episodecounts = { Episode = 1, Special = 2, Trailer = 2, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { make_ep(2, EpisodeType.Special) },
  episode = make_ep(2, EpisodeType.Special),
  file = { path = "/mnt/array/Downloads/_drop/s.mkv", media = nil, anidb = nil },
}, { eq("MovieSpecial", "Dirty Pair (1987) - S02 [anidbid-882]", { "Dirty Pair (1987) [anidbid-882]", "Extras" }, "/mnt/array/Anime/Movies/_manual") })

run("Movie extra without episode cross-ref uses sole TMDB root", {
  anime = make_anime({ id = 882, type = AnimeType.Movie, airdate = { year = 1987 }, preferredname = "Dirty Pair", episodecounts = { Episode = 1, Special = 2, Trailer = 2, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Trailer), 88201) },
  episode = set_id(make_ep(1, EpisodeType.Trailer), 88201),
  file = { path = "/mnt/array/Downloads/_drop/t.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "999", anidbepisodeids = {}, preferredname = "Dirty Pair", airdate = { year = 1987 } },
  },
}, { eq("MovieExtraTmdb", "Dirty Pair (1987) - T01 [anidbid-882]", { "Dirty Pair (1987) [tmdbid-999]", "Extras" }, "/mnt/array/Anime/Movies/_manual") })

run("Movie special with its own TMDB movie link is standalone", {
  anime = make_anime({ id = 8694, type = AnimeType.Movie, _de = "A Certain Magical Index: The Movie - The Miracle of Endymion", airdate = { year = 2013 }, episodecounts = { Episode = 1, Special = 1, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Special), 869401) },
  episode = set_id(make_ep(1, EpisodeType.Special), 869401),
  file = {
    path = "/mnt/array/Downloads/_drop/omake.mkv",
    media = nil,
    anidb = { media = { dublanguages = {}, sublanguages = { "de" } } },
  },
  tmdb_movies = {
    { id = "672553", anidbepisodeids = { 869401 }, preferredname = "A Certain Magical Index: The Movie - The Miracle of Endymion - Omake", airdate = { year = 2013 } },
  },
}, { eq("StandaloneOmake", "A Certain Magical Index: The Movie - The Miracle of Endymion - Omake (2013)", { "A Certain Magical Index: The Movie - The Miracle of Endymion - Omake (2013) [tmdbid-672553]" }, "/mnt/array/Anime/Movies/GerSub") })

run("Show opening without episode cross-ref uses sole TMDB root", {
  anime = make_anime({ id = 15561, _de = "World's End Harem", airdate = { year = 2021 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Credits, { de = "Opening" }), 1556101) },
  episode = set_id(make_ep(1, EpisodeType.Credits, { de = "Opening" }), 1556101),
  file = {
    path = "/mnt/array/Anime/Shows/GerDub/World's End Harem (2021)/Extras/opening.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "103409", preferredname = "World’s End Harem", airdate = { year = 2022 } } },
}, { eq("ShowOpening", "World’s End Harem - C01 - Opening [anidbid-15561]", { "World’s End Harem (2022) [tmdbid-103409]", "Extras" }, "/mnt/array/Anime/Shows/GerDub") })

run("Show special without episode cross-ref uses sole TMDB root", {
  anime = make_anime({ id = 15561, _de = "World's End Harem", airdate = { year = 2021 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Special, { de = "Bonusfolge" }), 1556199) },
  episode = set_id(make_ep(1, EpisodeType.Special, { de = "Bonusfolge" }), 1556199),
  file = {
    path = "/mnt/array/Anime/Shows/GerDub/World's End Harem (2021)/Specials/bonus.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "103409", preferredname = "World’s End Harem", airdate = { year = 2022 } } },
}, { eq("ShowSpecial", "World’s End Harem - S01 - Bonusfolge [anidbid-15561]", { "World’s End Harem (2022) [tmdbid-103409]", "Extras" }, "/mnt/array/Anime/Shows/GerDub") })

run("Show trailer uses T prefix and type-specific padding", {
  anime = make_anime({ _de = "Series X", episodecounts = { Episode = 12, Special = 0, Trailer = 120, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { make_ep(7, EpisodeType.Trailer, { de = "Vorschau" }) },
  episode = make_ep(7, EpisodeType.Trailer, { de = "Vorschau" }),
  file = { path = "/mnt/array/Downloads/_drop/trailer.mkv", media = nil, anidb = { media = { dublanguages = { "de" }, sublanguages = {} } } },
}, { eq("TrailerMarker", "Series X - T007 - Vorschau [anidbid-3]", { "Series X (2021)", "Extras" }, "/mnt/array/Anime/Shows/GerDub") })

run("Show parody uses P prefix", {
  anime = make_anime({ _de = "Series X" }),
  episodes = { make_ep(2, EpisodeType.Parody, { de = "Parodie" }) },
  episode = make_ep(2, EpisodeType.Parody, { de = "Parodie" }),
  file = { path = "/mnt/array/Downloads/_drop/parody.mkv", media = nil, anidb = { media = { dublanguages = { "de" }, sublanguages = {} } } },
}, { eq("ParodyMarker", "Series X - P02 - Parodie [anidbid-3]", { "Series X (2021)", "Extras" }, "/mnt/array/Anime/Shows/GerDub") })

run("Show other uses O prefix", {
  anime = make_anime({ _de = "Series X" }),
  episodes = { make_ep(3, EpisodeType.Other, { de = "Sonstiges" }) },
  episode = make_ep(3, EpisodeType.Other, { de = "Sonstiges" }),
  file = { path = "/mnt/array/Downloads/_drop/other.mkv", media = nil, anidb = { media = { dublanguages = { "de" }, sublanguages = {} } } },
}, { eq("OtherMarker", "Series X - O03 - Sonstiges [anidbid-3]", { "Series X (2021)", "Extras" }, "/mnt/array/Anime/Shows/GerDub") })

run("Regular episode without cross-ref uses sole series-level TMDB show", {
  anime = make_anime({ id = 15561, _de = "World's End Harem", airdate = { year = 2021 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode, { de = "Folge 1" }), 1556102) },
  episode = set_id(make_ep(1, EpisodeType.Episode, { de = "Folge 1" }), 1556102),
  file = {
    path = "/mnt/array/Downloads/_drop/episode.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "103409", preferredname = "World’s End Harem", airdate = { year = 2022 } } },
}, { eq("RegularSoleShow", "World’s End Harem - S01E01 - Folge 1", { "World’s End Harem (2022) [tmdbid-103409]", "Season 01 [anidbid-15561]" }, "/mnt/array/Anime/Shows/GerDub") })

run("Unlinked regular episode inherits the sole series-level TMDB show", {
  anime = make_anime({ id = 19930, _de = "AniDB Shou 3 Ashibe QQ Goma-chan", airdate = { year = 2016 }, episodecounts = { Episode = 24, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(7, EpisodeType.Episode, { de = "Episode 7" }), 1993007) },
  episode = set_id(make_ep(7, EpisodeType.Episode, { de = "Episode 7" }), 1993007),
  file = { path = "/mnt/array/Downloads/_drop/episode7.mkv", media = nil, anidb = nil },
  tmdb_shows = {
    { id = "319455", preferredname = "Shou 3 Ashibe QQ Goma-chan", airdate = { year = 2016 } },
  },
}, { eq("PartialShowMap", "Shou 3 Ashibe QQ Goma-chan - S01E07 - Episode 7", { "Shou 3 Ashibe QQ Goma-chan (2016) [tmdbid-319455]", "Season 01 [anidbid-19930]" }, "/mnt/array/Anime/Shows/_manual") })

run("Ambiguous show extra keeps AniDB fallback", {
  anime = make_anime({ id = 88, _de = "Mixed Show", airdate = { year = 2020 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Credits, { de = "Opening" }), 8801) },
  episode = set_id(make_ep(1, EpisodeType.Credits, { de = "Opening" }), 8801),
  file = {
    path = "/mnt/array/Downloads/_drop/opening.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = {
    { id = "881", preferredname = "First Show", airdate = { year = 2020 } },
    { id = "882", preferredname = "Second Show", airdate = { year = 2021 } },
  },
}, { eq("AmbiguousExtra", "Mixed Show - C01 - Opening [anidbid-88]", { "Mixed Show (2020)", "Extras" }, "/mnt/array/Anime/Shows/GerDub") })

run("Multi-episode movie -> own TMDB movie folders", {
  anime = make_anime({ id = 348, type = AnimeType.Movie, airdate = { year = 1996 }, preferredname = "Shadow Skill (1996)", episodecounts = { Episode = 3, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode), 501) },
  episode = set_id(make_ep(1, EpisodeType.Episode), 501),
  file = { path = "/mnt/array/Downloads/_drop/shadow1.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "1001", anidbepisodeids = { 501 }, preferredname = "Shadow Skill: After the Battle", airdate = { year = 1996 } },
    { id = "1002", anidbepisodeids = { 502 }, preferredname = "Shadow Skill: The Second", airdate = { year = 1996 } },
    { id = "1003", anidbepisodeids = { 503 }, preferredname = "Shadow Skill: The Third", airdate = { year = 1996 } },
  },
}, { eq("TmdbMovieFolder", "Shadow Skill: After the Battle (1996)", { "Shadow Skill: After the Battle (1996) [tmdbid-1001]" }, "/mnt/array/Anime/Movies/_manual") })

run("Multiple episodes -> same TMDB movie keeps part numbers", {
  anime = make_anime({ id = 5611, type = AnimeType.Movie, airdate = { year = 2008 }, preferredname = "Batman: Gotham Knight", episodecounts = { Episode = 6, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(2, EpisodeType.Episode), 602) },
  episode = set_id(make_ep(2, EpisodeType.Episode), 602),
  file = { path = "/mnt/array/Downloads/_drop/gotham2.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "2001", anidbepisodeids = { 601, 602, 603 }, preferredname = "Batman: Gotham Knight", airdate = { year = 2008 } },
  },
}, { eq("TmdbMovieShared", "Batman: Gotham Knight (2008) - 02", { "Batman: Gotham Knight (2008) [tmdbid-2001]" }, "/mnt/array/Anime/Movies/_manual") })

run("Complete movie alongside split files keeps the plain movie name", {
  anime = make_anime({ id = 728, type = AnimeType.Movie, airdate = { year = 1982 }, preferredname = "Arcadia of My Youth", episodecounts = { Episode = 3, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode, { en = "Complete Movie" }), 72801) },
  episode = set_id(make_ep(1, EpisodeType.Episode, { en = "Complete Movie" }), 72801),
  file = { path = "/mnt/array/Downloads/_drop/arcadia-complete.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "1531453", anidbepisodeids = { 72801, 72802, 72803 }, preferredname = "Captain Harlock: Arcadia of My Youth", airdate = { year = 1982 } },
  },
}, { eq("CompleteMovie", "Captain Harlock: Arcadia of My Youth (1982)", { "Captain Harlock: Arcadia of My Youth (1982) [tmdbid-1531453]" }, "/mnt/array/Anime/Movies/_manual") })

run("First split movie file gets a media-server part suffix", {
  anime = make_anime({ id = 728, type = AnimeType.Movie, airdate = { year = 1982 }, preferredname = "Arcadia of My Youth", episodecounts = { Episode = 3, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(2, EpisodeType.Episode, { en = "Part 1 of 2" }), 72802) },
  episode = set_id(make_ep(2, EpisodeType.Episode, { en = "Part 1 of 2" }), 72802),
  file = { path = "/mnt/array/Downloads/_drop/arcadia-part1.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "1531453", anidbepisodeids = { 72801, 72802, 72803 }, preferredname = "Captain Harlock: Arcadia of My Youth", airdate = { year = 1982 } },
  },
}, { eq("SplitMoviePart1", "Captain Harlock: Arcadia of My Youth (1982) - pt1", { "Captain Harlock: Arcadia of My Youth (1982) [tmdbid-1531453]" }, "/mnt/array/Anime/Movies/_manual") })

run("Second split movie file gets a media-server part suffix", {
  anime = make_anime({ id = 728, type = AnimeType.Movie, airdate = { year = 1982 }, preferredname = "Arcadia of My Youth", episodecounts = { Episode = 3, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(3, EpisodeType.Episode, { en = "Part 2 of 2" }), 72803) },
  episode = set_id(make_ep(3, EpisodeType.Episode, { en = "Part 2 of 2" }), 72803),
  file = { path = "/mnt/array/Downloads/_drop/arcadia-part2.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "1531453", anidbepisodeids = { 72801, 72802, 72803 }, preferredname = "Captain Harlock: Arcadia of My Youth", airdate = { year = 1982 } },
  },
}, { eq("SplitMoviePart2", "Captain Harlock: Arcadia of My Youth (1982) - pt2", { "Captain Harlock: Arcadia of My Youth (1982) [tmdbid-1531453]" }, "/mnt/array/Anime/Movies/_manual") })

run("Three-part movie uses the declared part number", {
  anime = make_anime({ id = 729, type = AnimeType.Movie, airdate = { year = 1983 }, preferredname = "Three Part Movie", episodecounts = { Episode = 4, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(4, EpisodeType.Episode, { en = "Part 3 of 3" }), 72904) },
  episode = set_id(make_ep(4, EpisodeType.Episode, { en = "Part 3 of 3" }), 72904),
  file = { path = "/mnt/array/Downloads/_drop/three-part-3.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "1531454", anidbepisodeids = { 72901, 72902, 72903, 72904 }, preferredname = "Three Part Movie", airdate = { year = 1983 } },
  },
}, { eq("SplitMoviePart3", "Three Part Movie (1983) - pt3", { "Three Part Movie (1983) [tmdbid-1531454]" }, "/mnt/array/Anime/Movies/_manual") })

run("TMDB episode linked to several AniDB episodes matches by membership", {
  anime = make_anime({ id = 7, _de = "Multi Link", airdate = { year = 2021 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode, { de = "Folge 1" }), 901) },
  episode = set_id(make_ep(1, EpisodeType.Episode, { de = "Folge 1" }), 901),
  file = {
    path = "/mnt/array/Downloads/_drop/multi.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "55", preferredname = "Multi Link", airdate = { year = 2021 } } },
  tmdb_episodes = {
    { anidbepisodeids = { 901, 902 }, type = EpisodeType.Episode, number = 1, seasonnumber = 2, showid = "55" },
  },
}, { eq("TmdbEpisodeShared", "Multi Link - S02E01 - Folge 1", { "Multi Link (2021) [tmdbid-55]", "Season 02 [anidbid-7]" }, "/mnt/array/Anime/Shows/GerDub") })

run("OVA typed movie via TMDB cross-ref", {
  anime = make_anime({ id = 1208, type = AnimeType.OVA, airdate = { year = 2005 }, preferredname = "Final Fantasy VII: Advent Children", episodecounts = { Episode = 6, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode), 39865) },
  episode = set_id(make_ep(1, EpisodeType.Episode), 39865),
  file = { path = "/mnt/array/Downloads/_drop/ac.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "647", anidbepisodeids = { 39865 }, preferredname = "Final Fantasy VII: Advent Children", airdate = { year = 2005 } },
    { id = "59300", anidbepisodeids = { 100202 }, preferredname = "On the Way to a Smile", airdate = { year = 2009 } },
    { id = "1225938", anidbepisodeids = { 157050 }, preferredname = "Dirge of Cerberus", airdate = { year = 2006 } },
  },
}, { eq("OvaMovie", "Final Fantasy VII: Advent Children (2005)", { "Final Fantasy VII: Advent Children (2005) [tmdbid-647]" }, "/mnt/array/Anime/Movies/_manual") })

run("OVA movie episode without TMDB link falls back", {
  anime = make_anime({ id = 1208, type = AnimeType.OVA, airdate = { year = 2005 }, preferredname = "Final Fantasy VII: Advent Children", episodecounts = { Episode = 6, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(4, EpisodeType.Episode), 42410) },
  episode = set_id(make_ep(4, EpisodeType.Episode), 42410),
  file = { path = "/mnt/array/Downloads/_drop/ac4.mkv", media = nil, anidb = nil },
  tmdb_movies = {
    { id = "647", anidbepisodeids = { 39865 }, preferredname = "Final Fantasy VII: Advent Children", airdate = { year = 2005 } },
  },
}, { eq("OvaMovieFallback", "Final Fantasy VII: Advent Children (2005) - 04", { "Final Fantasy VII: Advent Children (2005) [anidbid-1208]" }, "/mnt/array/Anime/Movies/_manual") })

run("OVA without TMDB movie stays a show", {
  anime = make_anime({ id = 4324, type = AnimeType.OVA, _de = ".hack//Roots", airdate = { year = 2006 } }),
  episodes = { make_ep(21, EpisodeType.Episode, { de = "Defeat" }) },
  episode = make_ep(21, EpisodeType.Episode, { de = "Defeat" }),
  file = {
    path = "/mnt/array/Downloads/_drop/roots.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
}, { eq("OvaShow", ".hack//Roots - S01E21 - Defeat", { ".hack//Roots (2006)", "Season 01 [anidbid-4324]" }, "/mnt/array/Anime/Shows/GerDub") })

run("TV show normal ep stays a show despite movie-linked specials", {
  anime = make_anime({ id = 617, type = AnimeType.TVSeries, _de = "Die Abenteuer des Sherlock Holmes", airdate = { year = 1984 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode, { de = "Eine raetselhafte Entfuehrung" }), 144470) },
  episode = set_id(make_ep(1, EpisodeType.Episode, { de = "Eine raetselhafte Entfuehrung" }), 144470),
  file = {
    path = "/mnt/array/Downloads/_drop/sherlock1.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "21296", preferredname = "Sherlock Hound", airdate = { year = 1984 } } },
  tmdb_episodes = { { anidbepisodeids = { 144470 }, type = EpisodeType.Episode, number = 1, seasonnumber = 1, showid = "21296" } },
  tmdb_movies = {
    { id = "332324", anidbepisodeids = { 144477 }, preferredname = "Sherlock Hound: The Hound of the Baskervilles", airdate = { year = 1984 } },
    { id = "674707", anidbepisodeids = { 181241 }, preferredname = "Sherlock Hound: The Emerald Coronet", airdate = { year = 1984 } },
  },
}, { eq("SherlockShowEp", "Sherlock Hound - S01E01 - Eine raetselhafte Entfuehrung", { "Sherlock Hound (1984) [tmdbid-21296]", "Season 01 [anidbid-617]" }, "/mnt/array/Anime/Shows/GerDub") })

run("TV show special with TMDB movie link becomes a standalone movie", {
  anime = make_anime({ id = 617, type = AnimeType.TVSeries, _de = "Die Abenteuer des Sherlock Holmes", airdate = { year = 1984 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Special, { de = "Der Hund von Baskerville" }), 144477) },
  episode = set_id(make_ep(1, EpisodeType.Special, { de = "Der Hund von Baskerville" }), 144477),
  file = {
    path = "/mnt/array/Downloads/_drop/sherlock-movie1.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_movies = {
    { id = "332324", anidbepisodeids = { 144477 }, preferredname = "Sherlock Hound: The Hound of the Baskervilles", airdate = { year = 1984 } },
    { id = "674707", anidbepisodeids = { 181241 }, preferredname = "Sherlock Hound: The Emerald Coronet", airdate = { year = 1984 } },
  },
}, { eq("SherlockMovieSpecial", "Sherlock Hound: The Hound of the Baskervilles (1984)", { "Sherlock Hound: The Hound of the Baskervilles (1984) [tmdbid-332324]" }, "/mnt/array/Anime/Movies/GerDub") })

run("Movie-typed entry: movie ep gets its own TMDB movie folder", {
  anime = make_anime({ id = 12277, type = AnimeType.Movie, _de = "Cyborg 009: Call of Justice", airdate = { year = 2016 }, episodecounts = { Episode = 3, Other = 12, Special = 0, Trailer = 0, Credits = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode, { de = "Movie 1" }), 179015) },
  episode = set_id(make_ep(1, EpisodeType.Episode, { de = "Movie 1" }), 179015),
  file = {
    path = "/mnt/array/Downloads/_drop/cb009-m1.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_movies = {
    { id = "419095", anidbepisodeids = { 179015 }, preferredname = "Cyborg 009: Call of Justice 1", airdate = { year = 2016 } },
    { id = "419096", anidbepisodeids = { 179016 }, preferredname = "Cyborg 009: Call of Justice 2", airdate = { year = 2016 } },
    { id = "419098", anidbepisodeids = { 179017 }, preferredname = "Cyborg 009: Call of Justice 3", airdate = { year = 2016 } },
  },
  tmdb_episodes = {
    { anidbepisodeids = { 189696 }, type = EpisodeType.Episode, number = 1, seasonnumber = 1, showid = "70178" },
    { anidbepisodeids = { 189695 }, type = EpisodeType.Episode, number = 2, seasonnumber = 1, showid = "70178" },
  },
}, { eq("CyborgMovie", "Cyborg 009: Call of Justice 1 (2016)", { "Cyborg 009: Call of Justice 1 (2016) [tmdbid-419095]" }, "/mnt/array/Anime/Movies/GerDub") })

run("Movie-typed entry: show-linked TV ep goes to Shows", {
  anime = make_anime({ id = 12277, type = AnimeType.Movie, _de = "Cyborg 009: Call of Justice", airdate = { year = 2016 }, episodecounts = { Episode = 3, Other = 12, Special = 0, Trailer = 0, Credits = 0, Parody = 0 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Other, { de = "Folge 1" }), 189696) },
  episode = set_id(make_ep(1, EpisodeType.Other, { de = "Folge 1" }), 189696),
  file = {
    path = "/mnt/array/Downloads/_drop/cb009-e1.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
  tmdb_shows = { { id = "70178", preferredname = "Cyborg 009: Call of Justice", airdate = { year = 2016 } } },
  tmdb_episodes = {
    { anidbepisodeids = { 189696 }, type = EpisodeType.Episode, number = 1, seasonnumber = 1, showid = "70178" },
    { anidbepisodeids = { 189695 }, type = EpisodeType.Episode, number = 2, seasonnumber = 1, showid = "70178" },
  },
  tmdb_movies = {
    { id = "419095", anidbepisodeids = { 179015 }, preferredname = "Cyborg 009: Call of Justice 1", airdate = { year = 2016 } },
  },
}, { eq("CyborgShowEp", "Cyborg 009: Call of Justice - S01E01 - Folge 1", { "Cyborg 009: Call of Justice (2016) [tmdbid-70178]", "Season 01 [anidbid-12277]" }, "/mnt/array/Anime/Shows/GerDub") })

run("Movie with year", {
  anime = make_anime({ id = 5, type = AnimeType.Movie, airdate = { year = 1988 }, preferredname = "Movie Title", episodecounts = { Episode = 1, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { make_ep(1, EpisodeType.Episode) },
  episode = make_ep(1, EpisodeType.Episode),
  file = { path = "/mnt/array/Downloads/_drop/other.mkv", media = nil, anidb = nil },
}, { eq("Movie", "Movie Title (1988)", { "Movie Title (1988) [anidbid-5]" }, "/mnt/array/Anime/Movies/_manual") })

run("Movie no year", {
  anime = make_anime({ id = 5, type = AnimeType.Movie, airdate = false, preferredname = "Old Film", episodecounts = { Episode = 1, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { make_ep(1, EpisodeType.Episode) },
  episode = make_ep(1, EpisodeType.Episode),
  file = { path = "/mnt/array/Downloads/_drop/other.mkv", media = nil, anidb = nil },
}, { eq("MovieNoYear", "Old Film", { "Old Film [anidbid-5]" }, "/mnt/array/Anime/Movies/_manual") })

run("Multi-episode movie gets part number", {
  anime = make_anime({ id = 6, type = AnimeType.Movie, airdate = { year = 1999 }, preferredname = "Triple Feature", episodecounts = { Episode = 3, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { make_ep(2, EpisodeType.Episode) },
  episode = make_ep(2, EpisodeType.Episode),
  file = { path = "/mnt/array/Downloads/_drop/part2.mkv", media = nil, anidb = nil },
}, { eq("MoviePart2", "Triple Feature (1999) - 02", { "Triple Feature (1999) [anidbid-6]" }, "/mnt/array/Anime/Movies/_manual") })

run("Single-episode movie keeps plain name", {
  anime = make_anime({ id = 6, type = AnimeType.Movie, airdate = { year = 1999 }, preferredname = "Triple Feature", episodecounts = { Episode = 1, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { make_ep(1, EpisodeType.Episode) },
  episode = make_ep(1, EpisodeType.Episode),
  file = { path = "/mnt/array/Downloads/_drop/part1.mkv", media = nil, anidb = nil },
}, { eq("MoviePart1", "Triple Feature (1999)", { "Triple Feature (1999) [anidbid-6]" }, "/mnt/array/Anime/Movies/_manual") })

run("Episode range + special concat", {
  anime = make_anime({ _de = "Series X" }),
  episodes = {
    make_ep(1, EpisodeType.Episode, { de = "Teil 1" }),
    make_ep(2, EpisodeType.Episode, { de = "Teil 2" }),
    make_ep(1, EpisodeType.Special),
  },
  episode = make_ep(1, EpisodeType.Episode, { de = "Teil 1" }),
  file = { path = "/mnt/array/Downloads/_drop/x.mkv", media = nil, anidb = { media = { dublanguages = { "de" }, sublanguages = {} } } },
}, { eq("Range", "Series X - S01E01-E02S01 - Teil 1/Teil 2", { "Series X (2021)", "Season 01 [anidbid-3]" }, "/mnt/array/Anime/Shows/GerDub") })

run("Special-only -> Extras", {
  anime = make_anime({ _de = "Series X" }),
  episodes = { make_ep(1, EpisodeType.Special) },
  episode = make_ep(1, EpisodeType.Special),
  file = { path = "/mnt/array/Downloads/_drop/x.mkv", media = nil, anidb = { media = { dublanguages = { "de" }, sublanguages = {} } } },
}, { eq("Special", "Series X - S01 [anidbid-3]", { "Series X (2021)", "Extras" }, "/mnt/array/Anime/Shows/GerDub") })

run("English audio only -> Others (not _manual)", {
  anime = make_anime({ _de = "Series X" }),
  episodes = { make_ep(1, EpisodeType.Episode) },
  episode = make_ep(1, EpisodeType.Episode),
  file = {
    path = "/mnt/array/Downloads/_drop/x.mkv",
    media = { audio = { { language = "en" } }, sublanguages = {} },
    anidb = nil,
  },
}, { eq("EngAudio", "Series X - S01E01", { "Series X (2021)", "Season 01 [anidbid-3]" }, "/mnt/array/Anime/Shows/Others") })

run("_manual path preserved over GerDub media", {
  anime = make_anime({ _de = "Series X" }),
  episodes = { make_ep(1, EpisodeType.Episode) },
  episode = make_ep(1, EpisodeType.Episode),
  file = {
    path = "/mnt/array/Anime/Shows/_manual/Series X/x.mkv",
    media = nil,
    anidb = { media = { dublanguages = { "de" }, sublanguages = {} } },
  },
}, { eq("Manual", "Series X - S01E01", { "Series X (2021)", "Season 01 [anidbid-3]" }, "/mnt/array/Anime/Shows/_manual") })

run("byte truncation stays in limits", {
  anime = make_anime({ _de = string.rep("Ä", 300) .. " Titular" }),
  episodes = { make_ep(1, EpisodeType.Episode, { de = string.rep("Ü", 200) }) },
  episode = make_ep(1, EpisodeType.Episode, { de = string.rep("Ü", 200) }),
  file = { path = "/mnt/array/Downloads/_drop/x.mkv", media = nil, anidb = { media = { dublanguages = { "de" }, sublanguages = {} } } },
}, { function(e, name)
  assert(e.destination == "/mnt/array/Anime/Shows/GerDub", name .. " destination: got '" .. e.destination .. "'")
  assert(#e.filename <= 190, name .. " filename > 190 bytes: " .. #e.filename)
  assert(#e.subfolder[1] <= 255, name .. " show folder > 255 bytes: " .. #e.subfolder[1])
  assert(e.subfolder[1]:match("%(2021%)$"), name .. " year missing: " .. e.subfolder[1])
  assert(e.subfolder[2]:match("%[anidbid%-3%]$"), name .. " season anidbid tag missing: " .. e.subfolder[2])
end })

run("TMDB root tag survives byte truncation", {
  anime = make_anime({ id = 77, _de = "Fallback", airdate = { year = 2022 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode), 7701) },
  episode = set_id(make_ep(1, EpisodeType.Episode), 7701),
  file = { path = "/mnt/array/Downloads/_drop/long.mkv", media = nil, anidb = nil },
  tmdb_shows = { { id = "987654321", preferredname = string.rep("Ä", 160), airdate = { year = 2022 } } },
  tmdb_episodes = {
    { anidbepisodeids = { 7701 }, type = EpisodeType.Episode, number = 1, seasonnumber = 1, showid = "987654321" },
  },
}, { function(e, name)
  assert(e.filename == string.rep("Ä", 38) .. "... - S01E01", name .. " filename mismatch: " .. e.filename)
  assert(e.destination == "/mnt/array/Anime/Shows/_manual", name .. " destination: got '" .. e.destination .. "'")
  assert(#e.subfolder == 2, name .. " subfolder count: got " .. #e.subfolder .. " want 2")
  assert(#e.subfolder[1] <= 255, name .. " show folder > 255 bytes: " .. #e.subfolder[1])
  assert(e.subfolder[1]:match("%(2022%) %[tmdbid%-987654321%]$"), name .. " TMDB tag missing: " .. e.subfolder[1])
  assert(e.subfolder[2] == "Season 01 [anidbid-77]", name .. " season folder mismatch: " .. e.subfolder[2])
end })

run("TMDB-linked special remains an Extra", {
  anime = make_anime({ id = 10, _de = "Series X" }),
  episodes = { set_id(make_ep(1, EpisodeType.Special, { de = "Bonus" }), 1001) },
  episode = set_id(make_ep(1, EpisodeType.Special, { de = "Bonus" }), 1001),
  file = { path = "/mnt/array/Downloads/_drop/special.mkv", media = nil, anidb = nil },
  tmdb_shows = { { id = "55", preferredname = "Series X", airdate = { year = 2021 } } },
  tmdb_episodes = {
    { id = 501, anidbepisodeids = { 1001 }, type = EpisodeType.Special, number = 1, seasonnumber = 0, showid = "55" },
  },
}, { eq("LinkedSpecial", "Series X - S01 - Bonus [anidbid-10]", { "Series X (2021) [tmdbid-55]", "Extras" }, "/mnt/array/Anime/Shows/_manual") })

run("Shared-root Extras retain their AniDB identity", {
  anime = make_anime({ id = 200, _de = "Shared Show Second Entry", airdate = { year = 2017 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Credits, { de = "Opening" }), 20001) },
  episode = set_id(make_ep(1, EpisodeType.Credits, { de = "Opening" }), 20001),
  file = { path = "/mnt/array/Downloads/_drop/shared-op.mkv", media = nil, anidb = nil },
  tmdb_shows = { { id = "555", preferredname = "Shared Show", airdate = { year = 2015 } } },
}, { eq("SharedExtraId", "Shared Show - C01 - Opening [anidbid-200]", { "Shared Show (2015) [tmdbid-555]", "Extras" }, "/mnt/array/Anime/Shows/_manual") })

run("TMDB root without airdate does not use the AniDB season year", {
  anime = make_anime({ id = 200, _de = "Shared Show Second Entry", airdate = { year = 2017 } }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode), 20001) },
  episode = set_id(make_ep(1, EpisodeType.Episode), 20001),
  file = { path = "/mnt/array/Downloads/_drop/shared-s2.mkv", media = nil, anidb = nil },
  tmdb_shows = { { id = "555", preferredname = "Shared Show" } },
  tmdb_episodes = {
    { id = 502, anidbepisodeids = { 20001 }, type = EpisodeType.Episode, number = 1, seasonnumber = 2, showid = "555" },
  },
}, { eq("StableRootNoDate", "Shared Show - S02E01", { "Shared Show [tmdbid-555]", "Season 02 [anidbid-200]" }, "/mnt/array/Anime/Shows/_manual") })

run("One AniDB episode can cover a TMDB episode range", {
  anime = make_anime({ id = 12, _de = "Combined Show" }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode), 1201) },
  episode = set_id(make_ep(1, EpisodeType.Episode), 1201),
  file = { path = "/mnt/array/Downloads/_drop/combined.mkv", media = nil, anidb = nil },
  tmdb_shows = { { id = "66", preferredname = "TMDB Candidate", airdate = { year = 2021 } } },
  tmdb_episodes = {
    { id = 601, anidbepisodeids = { 1201 }, type = EpisodeType.Episode, number = 7, seasonnumber = 2, showid = "66" },
    { id = 602, anidbepisodeids = { 1201 }, type = EpisodeType.Episode, number = 8, seasonnumber = 2, showid = "66" },
  },
}, { eq("CombinedEpisode", "TMDB Candidate - S02E07-E08", { "TMDB Candidate (2021) [tmdbid-66]", "Season 02 [anidbid-12]" }, "/mnt/array/Anime/Shows/_manual") })

run("Cross-show episode mapping falls back instead of taking the first", {
  anime = make_anime({ id = 13, _de = "Ambiguous Show" }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode), 1301) },
  episode = set_id(make_ep(1, EpisodeType.Episode), 1301),
  file = { path = "/mnt/array/Downloads/_drop/ambiguous.mkv", media = nil, anidb = nil },
  tmdb_shows = {
    { id = "66", preferredname = "First Candidate", airdate = { year = 2021 } },
    { id = "77", preferredname = "Second Candidate", airdate = { year = 2021 } },
  },
  tmdb_episodes = {
    { id = 603, anidbepisodeids = { 1301 }, type = EpisodeType.Episode, number = 7, seasonnumber = 2, showid = "66" },
    { id = 604, anidbepisodeids = { 1301 }, type = EpisodeType.Episode, number = 8, seasonnumber = 2, showid = "77" },
  },
}, { eq("AmbiguousEpisode", "Ambiguous Show - S01E01", { "Ambiguous Show (2021)", "Season 01 [anidbid-13]" }, "/mnt/array/Anime/Shows/_manual") })

run("Unlinked episode in a mixed file keeps AniDB season fallback", {
  anime = make_anime({ id = 69, _de = "One Piece", airdate = { year = 1999 }, episodecounts = { Episode = 1200, Special = 0, Trailer = 0, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = {
    set_id(make_ep(326, EpisodeType.Episode), 326001),
    set_id(make_ep(327, EpisodeType.Episode), 327001),
  },
  episode = set_id(make_ep(326, EpisodeType.Episode), 326001),
  file = { path = "/mnt/array/Downloads/_drop/mixed.mkv", media = nil, anidb = nil },
  tmdb_shows = { { id = "9999", preferredname = "One Piece", airdate = { year = 1999 } } },
  tmdb_episodes = {
    { id = 701, anidbepisodeids = { 326001 }, type = EpisodeType.Episode, number = 8, seasonnumber = 9, showid = "9999" },
  },
}, { eq("MixedLinked", "One Piece - S09E08S01E0327", { "One Piece (1999) [tmdbid-9999]", "Season 09 [anidbid-69]" }, "/mnt/array/Anime/Shows/_manual") })

run("Unlinked primary Other uses the regular episode TMDB root", {
  anime = make_anime({
    id = 7309, restricted = true, _de = "Shinshou Genmukan", airdate = { year = 2010 },
    episodecounts = { Episode = 4, Special = 0, Trailer = 0, Credits = 0, Other = 2, Parody = 0 },
  }),
  episodes = {
    set_id(make_ep(1, EpisodeType.Other, { de = "Bonus" }), 730901),
    set_id(make_ep(1, EpisodeType.Episode, { de = "Teil 1" }), 730911),
    set_id(make_ep(2, EpisodeType.Episode, { de = "Teil 2" }), 730912),
  },
  episode = set_id(make_ep(1, EpisodeType.Other, { de = "Bonus" }), 730901),
  file = {
    path = "/mnt/array/Downloads/_drop/shinshou.mkv", media = nil,
    anidb = { media = { dublanguages = {}, sublanguages = { "de" } } },
  },
  tmdb_shows = {
    { id = "100907", preferredname = "Genmukan: The Sin of Desire & Shame", airdate = { year = 2003 } },
  },
  tmdb_episodes = {
    { id = 7101, anidbepisodeids = { 730911 }, type = EpisodeType.Episode, number = 1, seasonnumber = 2, showid = "100907" },
    { id = 7102, anidbepisodeids = { 730912 }, type = EpisodeType.Episode, number = 2, seasonnumber = 2, showid = "100907" },
  },
}, { eq(
  "PrimaryOtherFallback",
  "Genmukan: The Sin of Desire & Shame - S02E01-E02O01 - Teil 1/Teil 2/Bonus",
  { "Genmukan: The Sin of Desire & Shame (2003) [tmdbid-100907]", "Season 02 [anidbid-7309]" },
  "/mnt/array/Hentai/Shows/GerSub"
) })

run("Lua selects its primary episode by the configured type priority", {
  anime = make_anime({
    id = 3, _de = "Series X",
    episodecounts = { Episode = 1, Special = 1, Other = 1, Credits = 1, Trailer = 1, Parody = 1 },
  }),
  episodes = {
    make_ep(1, EpisodeType.Other, { de = "Other" }),
    make_ep(1, EpisodeType.Credits, { de = "Credits" }),
    make_ep(1, EpisodeType.Special, { de = "Special" }),
    make_ep(1, EpisodeType.Episode, { de = "Episode" }),
    make_ep(1, EpisodeType.Trailer, { de = "Trailer" }),
    make_ep(1, EpisodeType.Parody, { de = "Parody" }),
  },
  episode = make_ep(1, EpisodeType.Other, { de = "Other" }),
  file = { path = "/mnt/array/Downloads/_drop/mixed-types.mkv", media = nil, anidb = nil },
}, { eq(
  "LuaEpisodePriority",
  "Series X - S01E01S01O01C01T01P01 - Episode/Special/Other/Credits/Trailer/Parody",
  { "Series X (2021)", "Season 01 [anidbid-3]" },
  "/mnt/array/Anime/Shows/_manual"
) })

run("Multi-episode movie Extra keeps the marker range", {
  anime = make_anime({ id = 20, type = AnimeType.Movie, preferredname = "Movie X", episodecounts = { Episode = 1, Special = 0, Trailer = 2, Credits = 0, Other = 0, Parody = 0 } }),
  episodes = { make_ep(1, EpisodeType.Trailer), make_ep(2, EpisodeType.Trailer) },
  episode = make_ep(1, EpisodeType.Trailer),
  file = { path = "/mnt/array/Downloads/_drop/trailers.mkv", media = nil, anidb = nil },
}, { eq("MovieExtraRange", "Movie X (2021) - T01-T02 [anidbid-20]", { "Movie X (2021) [anidbid-20]", "Extras" }, "/mnt/array/Anime/Movies/_manual") })

run("replacement characters stay inside the byte limit", {
  anime = make_anime({ id = 30, _de = "Fallback" }),
  episodes = { set_id(make_ep(1, EpisodeType.Episode, { de = string.rep(":", 100) }), 3001) },
  episode = set_id(make_ep(1, EpisodeType.Episode, { de = string.rep(":", 100) }), 3001),
  file = { path = "/mnt/array/Downloads/_drop/replace.mkv", media = nil, anidb = nil },
  replace_illegal_chars = true,
  remove_illegal_chars = false,
  illegal_chars_map = { [":"] = "：" },
  tmdb_shows = { { id = "777", preferredname = string.rep(":", 100), airdate = { year = 2021 } } },
  tmdb_episodes = {
    { id = 801, anidbepisodeids = { 3001 }, type = EpisodeType.Episode, number = 1, seasonnumber = 1, showid = "777" },
  },
}, { function(e, name)
  local cleaned_folder = e.subfolder[1]:gsub(":", "：")
  local cleaned_filename = e.filename:gsub(":", "：") .. ".mkv"
  assert(#cleaned_folder <= 255, name .. " cleaned folder > 255 bytes: " .. #cleaned_folder)
  assert(#cleaned_filename <= 255, name .. " cleaned filename > 255 bytes: " .. #cleaned_filename)
  assert(cleaned_folder:match("%[tmdbid%-777%]$"), name .. " TMDB tag missing after truncation")
end })

run("AniDB file ID is reserved for the collision filename", {
  anime = make_anime({ id = 40, _de = "Release Show" }),
  episodes = { make_ep(2, EpisodeType.Episode, { de = "Folge 2" }) },
  episode = make_ep(2, EpisodeType.Episode, { de = "Folge 2" }),
  file = {
    path = "/mnt/array/Downloads/_drop/release.mkv",
    media = nil,
    anidb = { id = 123456, media = { dublanguages = { "de" }, sublanguages = {} } },
  },
}, { function(e, name)
  assert(e.filename == "Release Show - S01E02 - Folge 2", name .. " primary filename changed: " .. tostring(e.filename))
  assert(e.collision_filename == "Release Show - S01E02 - Folge 2 [anidbfile-123456]",
      name .. " collision filename mismatch: " .. tostring(e.collision_filename))
  assert(e.destination == "/mnt/array/Anime/Shows/GerDub", name .. " destination mismatch")
end })

run("Manual link has no collision filename", {
  anime = make_anime({ id = 41, _de = "Manual Show" }),
  episodes = { make_ep(1, EpisodeType.Episode) },
  episode = make_ep(1, EpisodeType.Episode),
  file = { path = "/mnt/array/Downloads/_drop/manual.mkv", media = nil, anidb = nil },
}, { function(e, name)
  assert(e.filename == "Manual Show - S01E01", name .. " primary filename mismatch")
  assert(e.collision_filename == nil, name .. " manual link unexpectedly received a collision filename")
end })

print(string.format("%d checks passed", passed))
