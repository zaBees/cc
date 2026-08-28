-- stub CC:Tweaked in 3 dimensions and run tunnel.lua against a fake world
-- lua5.3 test_tunnel.lua
local W

local function key(x, y, z) return ("%d,%d,%d"):format(x, y, z) end

local function reset(o)
  o = o or {}
  W = { x = 0, y = 0, z = 0, h = 0, fuel = o.fuel or 1e9, stack = o.stack or 64,
        slots = {}, items = {}, air = {}, ore = {}, dropped = 0, trips = 0,
        files = o.files or {}, log = {}, dug = 0, startY = o.startY or -55,
        placed = nil, homeY = -(o.startY or -55) + -60 }
  for i = 1, 16 do W.slots[i] = 0 end
  if o.chest ~= false then W.slots[16] = 1 W.items[16] = "minecraft:chest" end
  for k, v in pairs(o.ore or {}) do W.ore[k] = v end
  W.liquid = {}
  for k, v in pairs(o.liquid or {}) do W.liquid[k] = v end
  for _, k in ipairs(o.air or {}) do W.air[k] = true end
  for i = 1, (o.pre or 0) do W.air[key(0, 0, i)] = true; W.air[key(0, 1, i)] = true end
  if o.at then W.x, W.y, W.z, W.h = o.at[1], o.at[2], o.at[3], o.at[4] end
end

local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }

local function ahead()
  local d = DIRS[W.h]
  return W.x + d[1], W.y, W.z + d[2]
end

-- the turtle starts in open air at y=0, z<=0; everything else is stone until dug
local function block(x, y, z)
  local k = key(x, y, z)
  if W.air[k] then return nil end
  if W.placed == k then return "minecraft:chest" end
  if W.ore[k] then return W.ore[k] end
  if W.liquid and W.liquid[k] then return W.liquid[k] end
  if y >= 0 and z <= 0 then return nil end
  return "minecraft:stone"
end

local function give()
  for i = 1, 16 do
    if not W.items[i] and W.slots[i] < W.stack then W.slots[i] = W.slots[i] + 1 return true end
  end
  return false            -- inventory full: the item is lost, as in game
end

local function mine(x, y, z)
  if not block(x, y, z) then return false end
  W.air[key(x, y, z)] = true
  W.ore[key(x, y, z)] = nil
  W.dug = W.dug + 1
  give()
  return true
end

local function move(x, y, z)
  if W.fuel <= 0 then return false end
  if block(x, y, z) then return false end
  W.fuel = W.fuel - 1
  W.x, W.y, W.z = x, y, z
  if W.z < 0 then error("WALKED PAST HOME to z=" .. W.z, 0) end
  return true
end

local function ser(t)
  local out = {}
  for k, v in pairs(t) do
    local val = type(v) == "table" and ser(v) or tostring(v)
    out[#out + 1] = ("%s=%s"):format(k, val)
  end
  return "{" .. table.concat(out, ",") .. "}"
end

local function mkenv()
  local env = setmetatable({}, { __index = _G })
  env.print = function(...) W.log[#W.log + 1] = table.concat({ ... }, " ") end
  env.os = { sleep = function() end }
  env.textutils = {
    serialise = ser,
    unserialise = function(s) local f = load("return " .. s) return f and f() or nil end,
  }
  env.fs = {
    exists = function(n) return W.files[n] ~= nil end,
    delete = function(n) W.files[n] = nil end,
    move   = function(a, b) W.files[b], W.files[a] = W.files[a], nil end,
    open   = function(n, m)
      if m == "w" then
        local buf = {}
        return { write = function(s) buf[#buf + 1] = s end,
                 close = function() W.files[n] = table.concat(buf) end }
      end
      return { readAll = function() return W.files[n] end, close = function() end }
    end,
  }
  local sel = 1
  env.gps = { locate = function() return 0, W.startY, 0 end }
  local function look(x, y, z)
    local b = block(x, y, z)
    if not b then return false, "No block to inspect" end
    return true, { name = b }
  end
  env.turtle = {
    getFuelLevel = function() return W.fuel end,
    refuel       = function() return false end,
    select       = function(s) sel = s end,
    getItemCount = function(s) return W.slots[s] end,
    getItemDetail = function(s)
      s = s or sel
      if W.slots[s] == 0 then return nil end
      return { name = W.items[s] or "minecraft:cobblestone", count = W.slots[s] }
    end,
    placeDown = function()
      if block(W.x, W.y - 1, W.z) then return false end
      if W.slots[sel] == 0 then return false end
      W.placed = key(W.x, W.y - 1, W.z)
      W.air[W.placed] = nil
      W.slots[sel] = W.slots[sel] - 1
      if W.slots[sel] == 0 then W.items[sel] = nil end
      return true
    end,

    detect     = function() return block(ahead()) ~= nil end,
    detectUp   = function() return block(W.x, W.y + 1, W.z) ~= nil end,
    detectDown = function() return block(W.x, W.y - 1, W.z) ~= nil end,
    inspect     = function() return look(ahead()) end,
    inspectUp   = function() return look(W.x, W.y + 1, W.z) end,
    inspectDown = function() return look(W.x, W.y - 1, W.z) end,
    dig     = function() return mine(ahead()) end,
    digUp   = function() return mine(W.x, W.y + 1, W.z) end,
    digDown = function() return mine(W.x, W.y - 1, W.z) end,

    forward = function() return move(ahead()) end,
    up      = function() return move(W.x, W.y + 1, W.z) end,
    down    = function() return move(W.x, W.y - 1, W.z) end,
    turnLeft  = function() W.h = (W.h + 3) % 4 end,
    turnRight = function() W.h = (W.h + 1) % 4 end,

    attack = function() return false end,
    attackUp = function() return false end,
    attackDown = function() return false end,

    drop     = function() end,
    dropDown = function()
      if W.z ~= 0 or W.x ~= 0 or W.y ~= W.homeY then
        error(("UNLOADED AWAY FROM HOME at %d,%d,%d"):format(W.x, W.y, W.z), 0)
      end
      for i = 1, 16 do W.dropped = W.dropped + W.slots[i]; W.slots[i] = 0 end
      W.trips = W.trips + 1
    end,
  }
  return env
end

local SRC = (...) or "tunnel.lua"
local function run(dry)
  local src = io.open(SRC):read("a")
  if not dry then src = src:gsub("local DRY = true", "local DRY = false", 1) end
  assert(load(src, "tunnel", "t", mkenv()))()
end

local fails = 0
local function check(name, cond, extra)
  if cond then print("ok   " .. name)
  else print("FAIL " .. name .. (extra and ("  -- " .. extra) or "")); fails = fails + 1 end
end
local function state()
  return ("at=%d,%d,%d h=%d dropped=%d trips=%d dug=%d fuel=%s")
    :format(W.x, W.y, W.z, W.h, W.dropped, W.trips, W.dug, tostring(W.fuel))
end
local function oreLeft()
  local n = 0
  for _ in pairs(W.ore) do n = n + 1 end
  return n
end

local D = "minecraft:diamond_ore"

-- cfg.targetY is -60 and the stub GPS says y=-55, so every run sinks a 5 block
-- shaft first. One run digs 5 shaft + 1 chest hole + 32 forward + 32 ceiling.
local SHAFT = 5
local function shaftAir()
  local a = {}
  for i = 1, SHAFT do a[#a + 1] = key(0, -i, 0) end
  return a
end

reset {}
run(false)
check("clean run: down the shaft, tunnel, home again",
  W.x == 0 and W.z == 0 and W.y == W.homeY and W.h == 0, state())
check("clean run: 70 items in the chest, one unload", W.dropped == 70 and W.trips == 1, state())
check("clean run: chest placed under the shaft bottom",
  W.placed == key(0, W.homeY - 1, 0), tostring(W.placed))

-- a 4-block vein hanging off the tunnel at z=5, two blocks out and one up
reset { ore = { [key(1, -SHAFT, 5)] = D, [key(2, -SHAFT, 5)] = D,
                [key(2, -SHAFT, 6)] = D, [key(2, -SHAFT + 1, 6)] = D } }
run(false)
check("vein: every diamond mined", oreLeft() == 0, ("%d left; %s"):format(oreLeft(), state()))
check("vein: back on the line and home afterwards",
  W.x == 0 and W.z == 0 and W.y == W.homeY and W.h == 0, state())
check("vein: tunnel still finished at full length",
  W.files["tunnel.state"]:match("mined=32") ~= nil, W.files["tunnel.state"])

-- ore in the ceiling block, only visible before ceiling() cuts it away
reset { ore = { [key(0, -SHAFT + 1, 7)] = D, [key(0, -SHAFT + 2, 7)] = D } }
run(false)
check("ceiling vein: followed upwards", oreLeft() == 0, ("%d left; %s"):format(oreLeft(), state()))

-- killed part way down the shaft
reset { at = { 0, -2, 0, 0 }, air = { key(0, -1, 0), key(0, -2, 0) },
        files = { ["tunnel.state"] = "{dist=0,mined=0,depth=2,placed=false}" } }
run(false)
check("resume mid-shaft: finishes the shaft and the tunnel",
  W.y == W.homeY and W.z == 0 and W.dropped == 70 - 2, state())

-- killed part way along a vein, one block off the line
reset {
  at = { 1, -SHAFT, 5, 1 },
  air = shaftAir(),
  ore = { [key(2, -SHAFT, 5)] = D },
  files = { ["tunnel.state"] = "{dist=5,mined=5,depth=5,placed=true,off={x=1,y=0,z=0,t=1,n=1}}" },
}
run(false)
check("resume mid-vein: walks back to the line and finishes",
  W.x == 0 and W.z == 0 and W.y == W.homeY and W.h == 0 and oreLeft() == 0, state())

-- lava under the shaft
reset { liquid = { [key(0, -3, 0)] = "minecraft:lava" } }
run(false)
check("lava: stops digging down instead of dropping into it",
  W.y == -2 and W.dropped == 0, state())

-- no chest to unload into
reset { chest = false }
local ok, err = pcall(run, false)
check("no chest: refuses to start with a clear message",
  not ok and tostring(err):find("minecraft:chest") ~= nil, tostring(err))

reset { stack = 2 }   -- 15 usable slots x 2 = 30 capacity, so it must round trip
run(false)
check("small stacks: round trips and still finishes", W.z == 0 and W.trips > 1, state())

reset { fuel = 20 }
run(false)
check("low fuel: comes home rather than stranding", W.z == 0 and W.fuel >= 0, state())

reset {}
run(true)
check("DRY moves nothing", W.y == 0 and W.dug == 0 and W.dropped == 0, state())

os.exit(fails == 0 and 0 or 1)
