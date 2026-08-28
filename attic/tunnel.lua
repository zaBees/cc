-- tunnel : sink a shaft to the diamond layer, then tunnel along it chasing veins
-- wget https://paste.rs/XXXXX tunnel
-- needs a pickaxe equipped and fuel in any slot

local DRY = true

local cfg = {
  length   = 32,      -- blocks forward
  height   = 2,       -- 1, 2 or 3
  dropDown = true,    -- unload downward at home (into the chest it places at the bottom)

  targetY  = -60,     -- tunnel at this height; deepslate diamond peaks around -59
  startY   = nil,     -- height it is standing at now; leave nil to ask GPS
  maxDrop  = 200,     -- refuse a descent longer than this, in case startY is wrong
  chest    = "minecraft:chest",   -- placed below the shaft bottom to unload into

  veinDepth = 12,     -- how many blocks of vein it will follow away from the tunnel
  veinMax   = 64,     -- hard cap on blocks mined per vein, in case of a huge blob
  ores = {            -- what counts as worth leaving the tunnel for
    ["minecraft:diamond_ore"] = true,
    ["minecraft:deepslate_diamond_ore"] = true,
  },
}

if not turtle then error("run this on a turtle, not a computer", 0) end

local FILE = "tunnel.state"
-- dist = where I am along the tunnel, mined = how far the tunnel goes,
-- off  = where I am relative to the tunnel line while chasing a vein (nil when on it)
local st = { dist = 0, mined = 0, off = nil, depth = 0, placed = false }

local function save()
  local f = fs.open(FILE .. ".tmp", "w")
  f.write(textutils.serialise(st))
  f.close()
  if fs.exists(FILE) then fs.delete(FILE) end
  fs.move(FILE .. ".tmp", FILE)
end

local function load()
  if not fs.exists(FILE) then return end
  local f = fs.open(FILE, "r")
  st = textutils.unserialise(f.readAll()) or st
  f.close()
end

-- fuel ---------------------------------------------------------------------

local function fuel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

local function topUp()
  for s = 1, 16 do
    turtle.select(s)
    if turtle.refuel(0) then turtle.refuel() end
  end
  turtle.select(1)
end

-- digging ------------------------------------------------------------------

-- gravel and sand fall back into the space; keep digging until it stays clear
local function clear(dig, detect)
  for _ = 1, 16 do
    if not detect() then return true end
    if not dig() then return false end   -- bedrock, or claim-protected
    os.sleep(0.4)
  end
  return false
end

-- movement -----------------------------------------------------------------
-- Every move is mirrored into st.off while off the tunnel line, so a turtle
-- killed mid-vein knows its way back on the next run.

local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }

local function right()
  turtle.turnRight()
  if st.off then st.off.t = (st.off.t + 1) % 4 save() end
end

local function left()
  turtle.turnLeft()
  if st.off then st.off.t = (st.off.t + 3) % 4 save() end
end

local function about() right() right() end

-- one block forward, digging and fighting whatever is in the way
local function step()
  clear(turtle.dig, turtle.detect)
  for _ = 1, 8 do
    if turtle.forward() then
      if st.off then
        local d = DIRS[st.off.t]
        st.off.x, st.off.z = st.off.x + d[1], st.off.z + d[2]
        save()
      end
      return true
    end
    turtle.attack()
    clear(turtle.dig, turtle.detect)
  end
  return false
end

local function stepUp()
  for _ = 1, 8 do
    clear(turtle.digUp, turtle.detectUp)
    if turtle.up() then
      if st.off then st.off.y = st.off.y + 1 save() end
      return true
    end
    turtle.attackUp()
  end
  return false
end

local function stepDown()
  for _ = 1, 8 do
    clear(turtle.digDown, turtle.detectDown)
    if turtle.down() then
      if st.off then st.off.y = st.off.y - 1 save() end
      return true
    end
    turtle.attackDown()
  end
  return false
end

local function ceiling()
  if cfg.height >= 2 then clear(turtle.digUp, turtle.detectUp) end
  if cfg.height >= 3 and stepUp() then
    clear(turtle.digUp, turtle.detectUp)
    stepDown()
  end
end

-- the shaft ---------------------------------------------------------------

local function findItem(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s end
  end
end

-- How far down we still have to go. Asks GPS first; cfg.startY is the manual
-- answer for a world with no GPS constellation.
local function plan()
  local y = cfg.startY
  if not y and gps then
    local _, gy = gps.locate(2)
    y = gy
  end
  if not y then
    return nil, "cannot tell how high I am: set cfg.startY, or build a GPS constellation"
  end
  local drop = y - cfg.targetY
  if drop < 0 then return nil, ("I am at y=%d, below the target y=%d"):format(y, cfg.targetY) end
  if drop > cfg.maxDrop then
    return nil, ("that is a %d block drop from y=%d; raise cfg.maxDrop if you mean it"):format(drop, y)
  end
  return drop, y
end

-- Straight down. Refuses to dig into liquid, which is the one thing down here
-- that ends the turtle rather than merely blocking it.
local function descend(drop)
  while st.depth < drop do
    local ok, below = turtle.inspectDown()
    if ok and (below.name:find("lava") or below.name:find("water")) then
      print(("%s at %d blocks down, stopping"):format(below.name, st.depth))
      return false
    end
    if not stepDown() then
      print("shaft blocked at " .. st.depth .. " blocks down")
      return false
    end
    st.depth = st.depth + 1
    save()
  end
  return true
end

local function placeChest()
  if st.placed then return true end
  local slot = findItem(cfg.chest)
  if not slot then return false end
  clear(turtle.digDown, turtle.detectDown)
  turtle.select(slot)
  local ok = turtle.placeDown()
  turtle.select(1)
  if ok then st.placed = true save() end
  return ok
end

-- veins --------------------------------------------------------------------

local function isOre(ok, data)
  return ok and data and cfg.ores[data.name] or false
end

local function face(t)
  while st.off.t ~= t do right() end
end

-- Walk back to the tunnel line from wherever in the vein we are. Digs on the
-- way, because gravel may have dropped into the path we came in through.
local function returnToLine()
  while st.off.y > 0 do if not stepDown() then return false end end
  while st.off.y < 0 do if not stepUp() then return false end end
  while st.off.z ~= 0 do
    face(st.off.z > 0 and 2 or 0)
    if not step() then return false end
  end
  while st.off.x ~= 0 do
    face(st.off.x > 0 and 3 or 1)
    if not step() then return false end
  end
  face(0)
  return true
end

-- Depth-first through the vein. Every branch puts the turtle back where it
-- started before returning, so the whole walk unwinds onto the tunnel line.
local function follow(depth)
  if depth <= 0 or st.off.n >= cfg.veinMax then return end

  if isOre(turtle.inspectUp()) and stepUp() then
    st.off.n = st.off.n + 1
    follow(depth - 1)
    stepDown()
  end

  if isOre(turtle.inspectDown()) and stepDown() then
    st.off.n = st.off.n + 1
    follow(depth - 1)
    stepUp()
  end

  for _ = 1, 4 do
    if isOre(turtle.inspect()) and step() then
      st.off.n = st.off.n + 1
      follow(depth - 1)
      about() step() about()          -- back out of the branch, facing as before
    end
    right()
  end
end

-- inventory ----------------------------------------------------------------

local function full()
  for s = 1, 16 do
    if turtle.getItemCount(s) == 0 then return false end
  end
  return true
end

local function unload()
  local drop = cfg.dropDown and turtle.dropDown or turtle.drop
  for s = 1, 16 do
    turtle.select(s)
    if turtle.getItemCount(s) > 0 then drop() end
  end
  turtle.select(1)
end

-- travel -------------------------------------------------------------------

local function goHome()
  about()
  while st.dist > 0 do
    if not step() then print("stuck on the way home at " .. st.dist) return false end
    st.dist = st.dist - 1
    save()
  end
  about()
  return true
end

local function goOut()
  while st.dist < st.mined do
    if not step() then print("stuck heading out at " .. st.dist) return false end
    st.dist = st.dist + 1
    save()
  end
  return true
end

-- main ---------------------------------------------------------------------

load()
topUp()

local drop, why = plan()

if DRY then
  if not drop then print("cannot plan the shaft: " .. why) end
  print(("tunnel: %d long, %d high at y=%d"):format(cfg.length, cfg.height, cfg.targetY))
  if drop then print(("shaft: %d blocks down from y=%d, %d done"):format(drop, why, st.depth)) end
  print(("chest: %s"):format(st.placed and "already placed"
    or (findItem(cfg.chest) and "in inventory" or "MISSING, put a " .. cfg.chest .. " in a slot")))
  print(("fuel: have %s, whole job needs about %d")
    :format(tostring(turtle.getFuelLevel()), 2 * cfg.length + (drop or 0)))
  print(("state: mined %d, currently %d out"):format(st.mined, st.dist))
  local names = {}
  for name in pairs(cfg.ores) do names[#names + 1] = name end
  print("chasing veins of: " .. table.concat(names, ", "))
  if st.off then print("WARNING: last run stopped inside a vein, it will walk back first") end
  print("set DRY = false to run it")
  return
end

if not drop then error(why, 0) end
if st.depth < drop and not findItem(cfg.chest) and not st.placed then
  error("put a " .. cfg.chest .. " in a slot: it goes under the shaft bottom to unload into", 0)
end

if not descend(drop) then return end
if not placeChest() then print("no chest placed, items will not unload") end

if st.off then
  -- Standing in a half-mined vein: finish it from here, because once we are
  -- back on the line the block we came in through is air and the rest of the
  -- vein is no longer reachable by the depth-first walk.
  print("resuming inside a vein, finishing it first")
  follow(cfg.veinDepth)
  if not returnToLine() then print("could not get back to the tunnel, move me there by hand") return end
  st.off = nil
  save()
end

if not goOut() then return end

while st.mined < cfg.length do
  -- always keep enough fuel to walk home from here, plus one vein detour
  if fuel() < st.dist + 2 * cfg.veinDepth + 2 then
    print("low fuel, heading home")
    break
  end

  if full() then
    print("full, unloading")
    if not goHome() then return end
    unload()
    if not goOut() then return end
  end

  if not step() then print("blocked at " .. st.mined) break end
  st.dist  = st.dist + 1
  st.mined = st.mined + 1
  save()

  -- Look for ore before cutting the ceiling, so ore in the ceiling block is
  -- still there to be seen.
  st.off = { x = 0, y = 0, z = 0, t = 0, n = 0 }
  save()
  follow(cfg.veinDepth)
  if st.off.n > 0 then
    print(("vein: %d blocks at %d out"):format(st.off.n, st.dist))
    if not returnToLine() then print("lost the tunnel line, move me back by hand") return end
  end
  st.off = nil
  save()

  ceiling()
end

if goHome() then
  unload()
  print(("done: %d down, tunnel is %d long"):format(st.depth, st.mined))
end
