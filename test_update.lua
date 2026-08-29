-- test_update.lua -- lua5.3 test_update.lua
-- Stubs CC's http, fs and os around update.lua and checks the three things
-- that would cost an in-game round trip: a bad download must not touch the
-- working copy, the cache-buster must be on the URL, and the printed
-- fletcher32 must be the one attic/sumfile.lua would print for the same bytes.

local PROG = "update.lua"

local W
local function reset(o)
  o = o or {}
  W = {
    files   = { quarry = "OLD QUARRY", update = "OLD UPDATE" },
    bodies  = o.bodies or { ["quarry.lua"] = "-- new quarry\n",
                            ["update.lua"] = "-- new update\n",
                            ["alert.lua"]  = "-- new alert\n" },
    fail    = o.fail or {},          -- file -> true: http.get returns nil
    urls    = {},
    out     = {},
  }
end

local function mkenv()
  local env = { math = math, string = string, table = table, pairs = pairs,
                ipairs = ipairs, tostring = tostring, tonumber = tonumber,
                error = error, select = select, type = type }
  env._G = env
  env.print = function(s) W.out[#W.out + 1] = tostring(s) end
  env.os = { epoch = function() return 1234567 end, sleep = function() end }
  env.http = { get = function(url)
    W.urls[#W.urls + 1] = url
    local file = url:match("/([%w_%.]+)%?") or url:match("/([%w_%.]+)$")
    if W.fail[file] then return nil, "connection refused" end
    local body = W.bodies[file]
    if not body then return nil, "404" end
    return { readAll = function() return body end, close = function() end }
  end }
  env.fs = {
    exists = function(n) return W.files[n] ~= nil end,
    delete = function(n) W.files[n] = nil end,
    move   = function(a, b) W.files[b], W.files[a] = W.files[a], nil end,
    open   = function(n, mode)
      if mode ~= "w" then return nil end
      local buf = {}
      return { write = function(s) buf[#buf + 1] = s end,
               close = function() W.files[n] = table.concat(buf) end }
    end,
  }
  return env
end

local function run(...)
  local env = mkenv()
  local chunk = assert(loadfile(PROG, "t", env))
  local ok, err = pcall(chunk, ...)
  return ok, err, table.concat(W.out, "\n")
end

-- 1. a plain run replaces both programs ------------------------------------
reset()
local ok, err, out = run()
assert(ok, "update crashed: " .. tostring(err))
assert(W.files.quarry == "-- new quarry\n", "quarry was not replaced: " .. tostring(W.files.quarry))
assert(W.files.update == "-- new update\n", "update did not replace itself")
assert(W.files.alert == "-- new alert\n", "alert was not fetched: " .. tostring(W.files.alert))
assert(out:find("up to date"), "it did not report success:\n" .. out)
assert(not W.files["quarry.new"], "the temp file was left behind")

-- 2. the cache-buster is on every URL --------------------------------------
-- raw.githubusercontent's /main/ URL served a stale build for over two minutes
-- after a push on 2026-08-28, which looks exactly like a push that never landed
for _, url in ipairs(W.urls) do
  assert(url:find("?t=", 1, true), "no cache-buster on " .. url)
end

-- 3. a failed download leaves the working copy alone ------------------------
reset({ fail = { ["quarry.lua"] = true } })
ok, err, out = run()
assert(ok, "a failed download crashed the run: " .. tostring(err))
assert(W.files.quarry == "OLD QUARRY", "a failed download clobbered the working copy")
assert(out:find("quarry: FAILED"), "the failure was not reported:\n" .. out)
assert(out:find("1 of 3 failed"), "the tally is wrong:\n" .. out)

-- and an HTML 404 page is a failure, not a program
reset({ bodies = { ["quarry.lua"] = "<html>404</html>", ["update.lua"] = "-- u\n",
                   ["alert.lua"] = "-- a\n" } })
ok, err, out = run()
assert(W.files.quarry == "OLD QUARRY", "an HTML error page was installed as Lua")
assert(out:find("HTML page"), "it did not say what came back:\n" .. out)

-- an empty body is a failure too
reset({ bodies = { ["quarry.lua"] = "", ["update.lua"] = "-- u\n",
                   ["alert.lua"] = "-- a\n" } })
ok, err, out = run()
assert(W.files.quarry == "OLD QUARRY", "an empty download replaced the program")

-- 4. one named program, and only that one ----------------------------------
reset()
ok, err, out = run("quarry")
assert(ok, "a named update crashed: " .. tostring(err))
assert(W.files.quarry == "-- new quarry\n", "the named program was not updated")
assert(W.files.update == "OLD UPDATE", "it updated a program it was not asked for")

-- an unknown name stops rather than silently doing nothing
reset()
ok, err = run("qaurry")
assert(not ok, "a typo was accepted")
assert(tostring(err):find("no such program"), "unhelpful error: " .. tostring(err))

-- 5. the fletcher32 matches attic/sumfile.lua's ----------------------------
-- same bytes, same number, or the in-game print cannot be checked against a
-- local one and the whole verification story falls over
local function sumfile(s)
  if #s % 2 == 1 then s = s .. "\0" end
  local s1, s2 = 0, 0
  for i = 1, #s, 2 do
    local a, b = string.byte(s, i, i + 1)
    s1 = (s1 + a + b * 256) % 65535
    s2 = (s2 + s1) % 65535
  end
  return s2 * 65536 + s1
end
local body = "-- new quarry\n"
reset()
ok, err, out = run("quarry")
assert(out:find(("quarry: %d bytes, fletcher32 %d"):format(#body, sumfile(body)), 1, true),
  "the printed checksum is not sumfile.lua's:\n" .. out)

-- an odd number of bytes is the padding case, and it must not shift the count
reset({ bodies = { ["quarry.lua"] = "odd" } })
ok, err, out = run("quarry")
assert(out:find("quarry: 3 bytes, fletcher32 " .. sumfile("odd"), 1, true),
  "odd-length body checksummed or counted wrong:\n" .. out)

print("test_update: all assertions passed")
