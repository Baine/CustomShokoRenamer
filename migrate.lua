-- migrate.lua - interim transition script for the v4 import folder migration.
--
-- Drives Shoko's batch relocation using the DEFAULT relocation preset (the one
-- you edit in the UI to contain bainesrenamer_v4.lua). Shoko moves + renames
-- each file and updates VideoLocal_Place itself, so no place rows are touched
-- here.
--
-- Requires: Shoko running + reachable, Lua 5.1 with luasocket + json.
--           File IDs come from a text file (one per line), because the LuaSQL
--           sqlite3 build here is too old for the current Shoko DB file.
--
-- Usage:
--   python migrate_ids.py ids.txt
--   lua migrate.lua <apikey> ids.txt [baseurl] [batchsize] [--preview]
--     apikey     Shoko API key (required)
--     ids.txt    file with one VideoLocalID per line (required)
--     baseurl    default http://localhost:8111
--     batchsize  files per API call, default 500
--     --preview  dry run: report new paths without moving anything
--
-- allowRelocationInsideDestination=true is required because the current files
-- already sit inside Destination-type import folders (VideoRelocationService.cs:746).

local apikey = arg[1]
local idsfile = arg[2]
if not apikey or not idsfile then
  io.stderr:write("usage: lua migrate.lua <apikey> <ids.txt> [baseurl] [batchsize] [--preview]\n")
  os.exit(2)
end

local args = {}
for i = 3, #arg do args[#args + 1] = arg[i] end
local baseurl, batchsize, preview = "http://localhost:8111", 500, false
for _, a in ipairs(args) do
  if a == "--preview" then preview = true
  elseif a:match("^http") then baseurl = a
  else batchsize = tonumber(a) or batchsize end
end

local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("json")
http.TIMEOUT = 600

local ids = {}
for line in io.lines(idsfile) do
  local id = tonumber(line)
  if id then ids[#ids + 1] = id end
end
print(string.format("collected %d file ids", #ids))

local endpoint = preview and "/api/v3/Relocation/Preview" or "/api/v3/Relocation/Relocate"
local query = "?move=true&rename=true&allowRelocationInsideDestination=true&deleteEmptyDirectories=true"

local total_ok, total_fail = 0, 0
local failed = {}

for i = 1, #ids, batchsize do
  local last = math.min(i + batchsize - 1, #ids)
  -- Build a bare ID array for Relocate, or the preview body for Preview.
  local body
  if preview then
    local payload = {}
    for j = i, last do payload[#payload + 1] = ids[j] end
    body = json.encode({ fileIDs = payload })
  else
    local parts = {}
    for j = i, last do parts[#parts + 1] = tostring(ids[j]) end
    body = "[" .. table.concat(parts, ",") .. "]"
  end

  local resp, code = http.request{
    method = "POST",
    url = baseurl .. endpoint .. query,
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = tostring(#body),
      apikey = apikey,
    },
    source = ltn12.source.string(body),
  }

  if code ~= 200 then
    print(string.format("batch %d-%d HTTP %s: %s", i, last, tostring(code), tostring(resp)))
    for j = i, last do failed[#failed + 1] = ids[j] end
  else
    local ok, results = pcall(json.decode, resp)
    local n = last - i + 1
    if not ok or type(results) ~= "table" then
      print(string.format("batch %d-%d could not parse response, %d files flagged", i, last, n))
      for j = i, last do failed[#failed + 1] = ids[j] end
    else
      local batch_ok = 0
      for _, r in ipairs(results) do
        if r.isSuccess or r.IsSuccess then batch_ok = batch_ok + 1 else failed[#failed + 1] = r.fileID or r.FileID end
      end
      total_ok, total_fail = total_ok + batch_ok, total_fail + (n - batch_ok)
      print(string.format("batch %d-%d: %d ok, %d failed", i, last, batch_ok, n - batch_ok))
    end
  end
end

print(string.format("done: %d ok, %d failed", total_ok, total_fail))
if #failed > 0 then
  local f = io.open("migrate_failed.txt", "w")
  for _, id in ipairs(failed) do f:write(id, "\n") end
  f:close()
  print("failed ids written to migrate_failed.txt")
end
