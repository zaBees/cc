-- Runs the BOOT template's config handling against a stubbed floppy + child,
-- proving a deployed turtle now TAKES the deployer's quarry.conf on every boot
-- (so a gpsChannel changed on turtle 1 reaches it) while KEEPING its own
-- startX/Y/Z so a modem-less turtle is not left asking for coordinates forever.
--
-- Fails against the pre-2026-08-31 boot script, which copied the config only
-- when the child had none: the child kept its stale gpsChannel.

local function extractBoot()
  local src = assert(io.open("quarry.lua")):read("*a")
  local boot = src:match("local BOOT = %[==%[(.-)%]==%]")
  assert(boot, "BOOT template not found in quarry.lua")
  return boot:format(2, "false")   -- N = 2, MANUAL = false
end

-- A tiny in-memory fs, enough for the boot script's file work.
local function makeFs(files)
  local F = files
  local function reader(path)
    local data = F[path]
    if not data then return nil end
    local pos = 1
    return {
      readAll = function() return data end,
      readLine = function()
        if pos > #data then return nil end
        local nl = data:find("\n", pos, true)
        local line
        if nl then line = data:sub(pos, nl - 1); pos = nl + 1
        else line = data:sub(pos); pos = #data + 1 end
        return line
      end,
      close = function() end,
    }
  end
  local function writer(path, append)
    local buf = append and (F[path] or "") or ""
    return {
      write     = function(_, s) buf = buf .. s end,
      writeLine = function(_, s) buf = buf .. (s or "") .. "\n"; F[path] = buf end,
      close     = function() F[path] = buf end,
    }
  end
  return {
    exists = function(p) return F[p] ~= nil end,
    open   = function(p, mode)
      if mode == "r" then return reader(p) end
      local w = writer(p, mode == "a")
      -- methods are called as h.write(...) in the template, so bind self
      return setmetatable({}, { __index = function(_, k)
        return function(...) return w[k](w, ...) end
      end })
    end,
    copy   = function(from, to) F[to] = F[from] end,
    delete = function(p) F[p] = nil end,
  }, F
end

-- Run the boot script's main() with just enough of CraftOS stubbed that it
-- reaches the config copy, equips a modem, and stops before really mining.
local function runBoot(childFiles, floppyFiles)
  local files = {}
  for k, v in pairs(childFiles)  do files[k] = v end
  for k, v in pairs(floppyFiles) do files["/disk/" .. k] = v end
  local fs, F = makeFs(files)

  local notes = {}
  local env = setmetatable({
    fs = fs,
    os = { sleep = function() end, setComputerLabel = function() end,
           getComputerLabel = function() return nil end },
    peripheral = { getType = function(side)
      return side == "left" and "modem" or "minecraft:diamond_pickaxe" end,
      call = function() return nil end },
    turtle = {
      getItemDetail = function(s)
        if s == nil or s == 1 then return { name = "minecraft:coal", count = 64 } end
        if s == 2 then return { name = "computercraft:wireless_modem", count = 1 } end
        return nil
      end,
      select = function() end, refuel = function() end,
      getFuelLevel = function() return 10000 end,
      getEquippedLeft = function() return "computercraft:wireless_modem" end,
      getEquippedRight = function() return "minecraft:diamond_pickaxe" end,
      equipLeft = function() return true end, equipRight = function() return true end,
    },
    shell = { run = function() return true end },
    ipairs = ipairs, pairs = pairs, type = type, tostring = tostring,
    pcall = pcall, print = function() end, string = string, table = table,
  }, { __index = _G })
  -- the template calls a bare note(); route it into our collector
  env.note = function(...) notes[#notes + 1] = table.concat({ ... }, " ") end

  -- The template passes the floppy path as its vararg (local D = ...).
  local chunk = assert(load(extractBoot(), "boot", "t", env))
  chunk("/disk")
  return F, table.concat(notes, "\n")
end

-- Case 1: child has a STALE gpsChannel; deployer's floppy config is newer and
-- pins no coordinates. The child must end up on the deployer's config.
do
  local F = runBoot(
    { ["quarry.conf"] = "gpsChannel = 1\ndry = false\n" },
    { ["quarry.conf"] = "gpsChannel = 6767\ndry = false\n",
      ["quarry"] = "-- program\n" })
  assert(F["quarry.conf"]:find("gpsChannel = 6767", 1, true),
    "the child kept its stale config instead of taking the deployer's:\n" .. F["quarry.conf"])
  assert(not F["quarry.conf"]:find("gpsChannel = 1", 1, true),
    "the child's old gpsChannel survived the overwrite:\n" .. F["quarry.conf"])
  print("case 1 (force overwrite): PASS")
end

-- Case 2: a modem-less child found itself from hand-typed coordinates. The
-- deployer's config pins none, so those coordinates must be carried across --
-- losing them is the "asks for coordinates forever" bug.
do
  local F = runBoot(
    { ["quarry.conf"] = "gpsChannel = 0\nstartX = 100\nstartY = -59\nstartZ = -8\nstartDir = 2\n" },
    { ["quarry.conf"] = "gpsChannel = 6767\ndry = false\n",
      ["quarry"] = "-- program\n" })
  assert(F["quarry.conf"]:find("gpsChannel = 6767", 1, true),
    "the modem-less child did not take the deployer's config:\n" .. F["quarry.conf"])
  for _, want in ipairs({ "startX = 100", "startY = -59", "startZ = -8", "startDir = 2" }) do
    assert(F["quarry.conf"]:find(want, 1, true),
      "the child lost " .. want .. " -- it will ask for coordinates forever:\n" .. F["quarry.conf"])
  end
  print("case 2 (modem-less keeps its coordinates): PASS")
end

-- Case 3: the deployer's OWN config pins coordinates (a manual deploy). Those
-- win; the child's stale coordinates are dropped, not appended alongside.
do
  local F = runBoot(
    { ["quarry.conf"] = "startX = 1\nstartY = 2\nstartZ = 3\n" },
    { ["quarry.conf"] = "gpsChannel = 0\nstartX = 500\nstartY = -59\nstartZ = 9\n",
      ["quarry"] = "-- program\n" })
  assert(F["quarry.conf"]:find("startX = 500", 1, true),
    "the deployer's pinned coordinates did not win:\n" .. F["quarry.conf"])
  assert(not F["quarry.conf"]:find("startX = 1", 1, true),
    "the child's stale coordinates were kept alongside the deployer's -- conflict:\n" .. F["quarry.conf"])
  print("case 3 (floppy pin wins): PASS")
end

print("all boot-config checks passed")
