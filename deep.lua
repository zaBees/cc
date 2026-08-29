-- deep: pull the current programs out of https://github.com/zaBees/cc and
-- replace the local copies. Written because the two-line ritual --
-- `delete quarry` then a long wget -- is retyped every time a fix ships, and
-- forgetting the delete makes CC print "File already exists" and download
-- nothing, which reads like success.
--
--   deep            every program below
--   deep quarry     just that one
--
-- Configs are never touched: quarry.conf and quarry.state stay as they are.

local RAW   = "https://raw.githubusercontent.com/zaBees/cc/deepseek/"
local FILES = { quarry = "quarry.lua", deep = "deep.lua", alert = "alert.lua" }

-- The /main/ URL is CDN-cached and has served a previous build more than two
-- minutes after a push. A unique query string is part of the cache key and is
-- ignored by the server, so it fetches what was actually pushed.
local function fetch(file)
  local url = RAW .. file .. "?t=" .. tostring(os.epoch("utc"))
  local h, why = http.get(url)
  if not h then return nil, tostring(why) end
  local body = h.readAll()
  h.close()
  if not body or #body == 0 then return nil, "came back empty" end
  -- GitHub answers a bad path with an HTML 404 page, which downloads happily
  -- and then fails to load as Lua hours later.
  if body:sub(1, 1) == "<" then return nil, "not Lua -- got an HTML page" end
  return body
end

-- fletcher32, arithmetic only: CC:Tweaked is Lua 5.2 and has no bitwise ops.
-- Same routine as attic/sumfile.lua, so the two numbers are comparable.
local function fletcher32(s)
  if #s % 2 == 1 then s = s .. "\0" end
  local s1, s2 = 0, 0
  for i = 1, #s, 2 do
    local a, b = string.byte(s, i, i + 1)
    s1 = (s1 + a + b * 256) % 65535
    s2 = (s2 + s1) % 65535
    if i % 16385 == 0 then os.sleep(0) end
  end
  return s2 * 65536 + s1
end

-- Write beside the target and move into place, so a download that fails
-- halfway leaves the working copy alone. A turtle mid-job still has a program.
local function install(name, body)
  local tmp = name .. ".new"
  if fs.exists(tmp) then fs.delete(tmp) end
  local f = fs.open(tmp, "w")
  if not f then return false, "cannot write " .. tmp end
  f.write(body)
  f.close()
  if fs.exists(name) then fs.delete(name) end   -- wget's own refusal, by hand
  fs.move(tmp, name)
  return true
end

local wanted = { ... }
local todo = {}
if #wanted == 0 then
  for name, file in pairs(FILES) do todo[name] = file end
else
  for _, name in ipairs(wanted) do
    if not FILES[name] then
      local known = {}
      for k in pairs(FILES) do known[#known + 1] = k end
      error(("no such program: %s (have %s)"):format(name, table.concat(known, ", ")), 0)
    end
    todo[name] = FILES[name]
  end
end

local failed, tried = 0, 0
for name, file in pairs(todo) do
  tried = tried + 1
  local body, why = fetch(file)
  if not body then
    print(("%s: FAILED -- %s"):format(name, why))
    failed = failed + 1
  else
    local ok, err = install(name, body)
    if ok then
      print(("%s: %d bytes, fletcher32 %d"):format(name, #body, fletcher32(body)))
    else
      print(("%s: FAILED -- %s"):format(name, err))
      failed = failed + 1
    end
  end
end

if failed > 0 then
  print(("%d of %d failed -- those old copies are untouched"):format(failed, tried))
else
  print("up to date. quarry.conf and quarry.state were not touched.")
end
