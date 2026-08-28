-- test_probe.lua -- stubbed CC world for probe.lua. lua5.3 test_probe.lua
--
-- Drives the live path end to end: kit audit, rig build, floppy insert, startup
-- write, turtle place, self-boot poll, turnOn fallback, shared-disk readback.

local W = {                       -- the fake world
  files = {},                     -- path -> string
  posted = nil,
  turnedOn = false,
  placedTurtle = false,
  placedDrive = false,
  droppedFloppy = false,
  y = 0,                          -- 0 ground, 1 up
  front = { [0] = nil, [1] = nil },-- block in front, per level
  selected = 1,
  fuel = 100,
  inv = {
    [1] = { name = "computercraft:turtle_normal", count = 1 },
    [2] = { name = "computercraft:disk_drive", count = 1 },
    [3] = { name = "computercraft:disk", count = 1 },
    [4] = { name = "minecraft:coal", count = 64 },
    [5] = { name = "minecraft:cobblestone", count = 12 },
  },
  selfBoots = false,              -- flip to true to test the self-boot branch
}

_G.turtle = {
  getFuelLevel = function() return W.fuel end,
  select = function(n) W.selected = n; return true end,
  getItemDetail = function(n)
    local d = W.inv[n]
    if not d then return nil end
    return { name = d.name, count = d.count }   -- a copy, like CC
  end,
  refuel = function() return true end,
  inspect = function()
    local b = W.front[W.y]
    if not b then return false, "No block to inspect" end
    return true, { name = b, tags = { ["minecraft:mineable/pickaxe"] = true } }
  end,
  inspectUp = function()
    if W.y == 0 then return false, "No block to inspect" end
    return false, "No block to inspect"
  end,
  inspectDown = function() return true, { name = "minecraft:stone", tags = {} } end,
  dig = function() W.front[W.y] = nil; return true end,
  digUp = function() return true end,
  up = function() W.y = 1; return true end,
  down = function() W.y = 0; return true end,
  drop = function()
    assert(W.placedDrive, "floppy dropped before the drive was placed")
    W.droppedFloppy = true
    W.files["/disk"] = ""          -- the mount appears
    return true
  end,
  place = function()
    local item = W.inv[W.selected]
    if not item then return false, "nothing selected" end
    if item.name:find("disk_drive") then
      W.placedDrive = true; W.front[W.y] = item.name; return true
    end
    if item.name:find("turtle") then
      W.placedTurtle = true; W.front[W.y] = item.name; return true
    end
    return false, "cannot place that"
  end,
  turnRight = function() return true end,
}

_G.fs = {
  exists = function(p) return W.files[p] ~= nil end,
  open = function(p, mode)
    if mode == "r" then
      if not W.files[p] then return nil end
      local lines, i = {}, 0
      for l in (W.files[p] .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
      return {
        readLine = function() i = i + 1; return lines[i] end,
        close = function() end,
      }
    end
    return {
      write = function(_, s) W.files[p] = s end,
      close = function() end,
    }
  end,
}
-- CC handles are called with a dot, not a colon
local realOpen = _G.fs.open
_G.fs.open = function(p, mode)
  local h = realOpen(p, mode)
  if h and h.write then
    local w = h.write
    h.write = function(s) return w(nil, s) end
  end
  return h
end

local T2 = {
  getID = function() return 42 end,
  getLabel = function() return nil end,
  isOn = function() return W.selfBoots or W.turnedOn end,
  turnOn = function()
    W.turnedOn = true
    -- turtle 2 boots, the disk startup runs, and it writes to the shared disk
    W.files["/disk/result.txt"] =
      "startup ran on id 42\nback  : computercraft:turtle_normal tags=yes\nup    : computercraft:disk_drive tags=yes"
    return true
  end,
}

_G.peripheral = {
  getType = function(side)
    local b = W.front[W.y]
    if not b then return nil end
    return b:find("drive") and "drive" or "turtle"
  end,
  wrap = function(side)
    local b = W.front[W.y]
    if not b then return nil end
    if b:find("drive") then
      return {
        isDiskPresent = function() return W.droppedFloppy end,
        getDiskID = function() return 7 end,
        getMountPath = function() return "/disk" end,
      }
    end
    return T2
  end,
  getMethods = function() return { "getID", "isOn", "turnOn" } end,
}

_G.http = {
  post = function(url, body)
    W.posted = body
    return { readAll = function() return "https://paste.rs/TEST1" end, close = function() end }
  end,
}

local realOs = os
_G.os = setmetatable({
  sleep = function() end,
  getComputerID = function() return 7 end,
  getComputerLabel = function() return "probe" end,
}, { __index = realOs })

local out = {}
local realPrint = print
_G.print = function(s) out[#out + 1] = tostring(s) end

local chunk = assert(loadfile("probe.lua"))
chunk("go")

_G.print = realPrint
local text = table.concat(out, "\n")

local function has(pat, why)
  assert(text:find(pat), why .. "\n---- output ----\n" .. text)
end

assert(W.placedDrive, "never placed the drive")
assert(W.droppedFloppy, "never put the floppy in the drive")
assert(W.files["/disk/startup.lua"], "never wrote /disk/startup.lua")
assert(W.files["/disk/startup.lua"]:find("PLACER = 7"), "startup does not carry the placer id")
assert(load(W.files["/disk/startup.lua"], "startup"), "the written startup is not valid Lua")
assert(W.placedTurtle, "never placed the turtle")
assert(W.turnedOn, "never fell back to turnOn after the self-boot poll failed")
assert(W.posted and #W.posted > 0, "never posted the log")

has("computercraft:turtle_normal", "inventory dump missing the turtle id")
has("does NOT self%-boot", "did not report the self-boot answer")
has("/disk/startup.lua ran", "did not report question 3")
has("startup ran on id 42", "did not read the placed turtle's report back off the disk")

-- Regression: os.getComputerLabel() returns NO values on an unlabelled computer,
-- so tostring() called on it directly gets zero arguments and throws. The placed
-- turtle is always unlabelled, so its copy of startup.lua hits this first.
do
  local src = assert(W.files["/disk/startup.lua"], "no startup to re-run")
  local savedOs = _G.os
  _G.os = setmetatable({
    sleep = function() end,
    getComputerID = function() return 42 end,
    getComputerLabel = function() end,        -- unlabelled: returns nothing at all
  }, { __index = realOs })
  _G.print = function() end
  local ok, err = pcall(assert(load(src, "startup")))
  _G.print = realPrint
  _G.os = savedOs
  assert(ok, "startup.lua crashes on an unlabelled turtle: " .. tostring(err))
end

-- and the DRY path places nothing
for k in pairs(W.files) do W.files[k] = nil end
W.placedDrive, W.placedTurtle, W.turnedOn, W.droppedFloppy = false, false, false, false
W.front[0], W.front[1], W.y = nil, nil, 0
out = {}
_G.print = function(s) out[#out + 1] = tostring(s) end
assert(loadfile("probe.lua"))()
_G.print = realPrint
assert(not W.placedDrive and not W.placedTurtle, "DRY run touched the world")
assert(table.concat(out, "\n"):find("DRY"), "DRY run did not say so")

print("test_probe: all assertions passed")
