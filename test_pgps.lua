-- test_pgps.lua -- lua5.3 test_pgps.lua
-- Stubs CC's fs, peripheral and os around pgps.lua. The one thing worth a test
-- is the startup file: a setup run must write it, and must never overwrite a
-- startup somebody else put there.

local PROG = "pgps.lua"

local W
local function reset(files)
  W = { files = files or {}, out = {}, sent = {} }
end

local function mkenv()
  local env = { math = math, string = string, table = table, pairs = pairs,
                ipairs = ipairs, tostring = tostring, tonumber = tonumber,
                error = error, select = select, type = type, load = load,
                assert = assert, pcall = pcall, setmetatable = setmetatable,
                setfenv = nil, _VERSION = _VERSION }
  env._G = env
  env.print = function(s) W.out[#W.out + 1] = tostring(s) end
  env.fs = {
    exists = function(n) return W.files[n] ~= nil end,
    open = function(n, mode)
      if mode == "r" then
        if not W.files[n] then return nil end
        return { readAll = function() return W.files[n] end, close = function() end }
      end
      local buf = {}
      return { write = function(s) buf[#buf + 1] = s end,
               close = function() W.files[n] = table.concat(buf) end }
    end,
  }
  env.textutils = {
    serialise = function(t)
      local parts = {}
      for k, v in pairs(t) do parts[#parts + 1] = ("%s=%s"):format(k, v) end
      table.sort(parts)
      return "{" .. table.concat(parts, ",") .. "}"
    end,
    unserialise = function() return {} end,
  }
  env.peripheral = {
    getNames = function() return { "back" } end,
    getType = function() return "modem" end,
    call = function() return true end,
    wrap = function() return { open = function() end, transmit = function() end } end,
  }
  -- one event, then bail out of the host loop
  local pulled = false
  env.os = { pullEvent = function()
    if pulled then error("done", 0) end
    pulled = true
    return "modem_message", "back", 6500, 6500, "PING", 12
  end }
  return env
end

local function run(...)
  local env = mkenv()
  local chunk = assert(loadfile(PROG, "t", env))
  local ok, err = pcall(chunk, ...)
  return ok, err, table.concat(W.out, "\n")
end

-- 1. a setup run writes the boot file --------------------------------------
reset()
local _, _, out = run("host", "10", "70", "-20")
assert(W.files.startup == 'shell.run("pgps", "host")\n',
  "startup was not written: " .. tostring(W.files.startup))
assert(out:find("wrote startup"), "it did not say so:\n" .. out)
assert(W.files["pgps.cfg"]:find("x=10"), "coords were not saved: " .. W.files["pgps.cfg"])

-- 2. somebody else's startup is never clobbered ----------------------------
reset({ startup = 'shell.run("quarry", "1")\n' })
_, _, out = run("host", "10", "70", "-20")
assert(W.files.startup == 'shell.run("quarry", "1")\n', "it overwrote a startup that was not ours")
assert(out:find("left alone"), "it did not warn:\n" .. out)

-- 3. our own startup is recognised, not reported as a stranger's -----------
reset({ startup = 'shell.run("pgps", "host")\n' })
_, _, out = run("host", "10", "70", "-20")
assert(out:find("already starts pgps"), "it did not recognise its own boot file:\n" .. out)

-- 4. a run without coordinates touches nothing -----------------------------
reset()
run("host")
assert(not W.files.startup, "a resume run wrote a startup file")

print("test_pgps: all assertions passed")
