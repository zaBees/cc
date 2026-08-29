-- quarry : three turtles read a chunk-snapped claim with mod-5 branches
-- wget https://raw.githubusercontent.com/zaBees/cc/main/quarry.lua quarry
-- usage:  quarry <1|2|3> [--check|recall|deploy]
--
-- Phase 1: claim maths, branch/spine iterators, --check.
-- Phase 2: one turtle, one branch -- trunk descent, spine travel, vein chase,
--          save every block, resume from quarry.state.

local DRY = true

-- Lua 5.2 (Cobalt) in CC:Tweaked -- no // and no bitwise operators anywhere.

local CONF  = "quarry.conf"
local STATE = "quarry.state"

-- config -------------------------------------------------------------------
-- Scalars, then bare block names under [section] headers. Deliberately not
-- Lua, so a typo prints a line number instead of killing the miner.

local NUM = {
  topY         = 60,    -- highest level mined; surface builds live above it
  bottomY      = -59,   -- safety floor. bedrock scatters -63..-60
  turtles      = 3,
  chunksX      = 3,     -- claim width in chunks; the branches cut across this axis
  chunksZ      = 3,     -- claim length in chunks; the spine runs along this axis
  veinMax      = 64,    -- hard cap on blocks per vein chase
  veinDepth    = 12,    -- how far a vein chase may wander off the branch
  fuelMargin   = 64,    -- spare fuel kept on top of the walk home
  tripBlocks   = 96,    -- blocks carried before the inventory forces a depot run
  fuelShare    = 128,   -- coal in the hold that sends a turtle home to bank it
  fuelKeep     = 2000,  -- tank level topped up from coal in the hold, at its own box
  sharePerDock = 16,    -- coal one dock may take from a SHARED depot
  lavaFloor    = 4000,  -- scoop a passing lava source when the tank is under this
  saveSamples  = 200,   -- --check writes the state file this many times to time it
}
local STR = {
  oreTags      = "c:ores",
}
local BOOL = {
  deepestFirst = true,
  lava         = true,   -- the scoop was proven in-game 2026-08-27, bucket came back
  forageCoal   = true,   -- a dry depot climbs to topY to mine coal, rather than stopping
  dry          = false,  -- set live at the user's instruction, 2026-08-27
}

local LISTS = {
  -- additive to oreTags; c:ores already covers most of these, they are here so
  -- the file shows you where to add what the pack calls things.
  oreNames = {
    "create:zinc_ore", "create:deepslate_zinc_ore",
    "mekanism:osmium_ore", "mekanism:deepslate_osmium_ore",
    "mekanism:tin_ore", "mekanism:deepslate_tin_ore",
    "mekanism:lead_ore", "mekanism:deepslate_lead_ore",
    "mekanism:uranium_ore", "mekanism:deepslate_uranium_ore",
    "mekanism:fluorite_ore", "mekanism:deepslate_fluorite_ore",
  },
  -- set any entry here and ONLY these are mined, oreTags and oreNames ignored
  only = {},
  -- junk tier: dug and carried like anything else, dumped first when a slot
  -- is needed. Not a skip list -- a turtle cannot decline what it digs.
  blacklist = {
    "minecraft:stone", "minecraft:cobblestone", "minecraft:deepslate",
    "minecraft:cobbled_deepslate", "minecraft:tuff", "minecraft:granite",
    "minecraft:diorite", "minecraft:andesite", "minecraft:dirt",
    "minecraft:gravel", "minecraft:sand", "minecraft:sandstone",
    "minecraft:calcite", "minecraft:smooth_basalt", "minecraft:clay",
  },
  fuel = {
    "minecraft:coal", "minecraft:charcoal",
    "minecraft:coal_block", "minecraft:lava_bucket",
  },
}

local DEFAULT_CONF = [[
# quarry.conf -- edit with: edit quarry.conf
# Written on first run. Delete it to get these defaults back.
# name = value for the numbers, bare block names under the [headers].

topY         = 60      # highest level mined -- nothing above this is touched
bottomY      = -59     # lowest level mined, and the trunk's safety floor.
                       # The two together are the range: -59 and -40 mine those
                       # 20 levels and nothing else.
deepestFirst = true    # mine the deepest level first and work up
dry          = false   # true = plan the route and touch nothing. false = mine for real.
turtles      = 3
chunksX      = 3       # claim width in chunks; branches cut across this axis
chunksZ      = 3       # claim length in chunks; the spine runs along this axis
                       # 3x3 keeps the start chunk and its eight neighbours. 5x5 or
                       # 3x5 mine more, but every turtle must share these two values
                       # (like topY) or their branches will not line up -- and the
                       # player must keep every chunk loaded or a branch strands.
veinMax      = 64      # blocks per vein chase, hard cap
veinDepth    = 12      # how far a chase may wander off the branch
fuelMargin   = 64      # spare fuel kept on top of the walk home
tripBlocks   = 96      # blocks carried before the inventory forces a depot run
fuelShare    = 128     # coal in the hold that sends a turtle home to bank it for the others
fuelKeep     = 2000    # coal in the hold is burnt up to this tank level at its OWN depot
sharePerDock = 16      # coal one dock may take from a SHARED depot; a cap, not a reserve
forageCoal   = true    # depot dry = climb to topY and mine for coal. false = stop instead
lava         = true    # the --check scoop was proven on this server: the bucket came back
lavaFloor    = 4000    # scoop a source the branch passes when the tank is below this
oreTags      = c:ores  # the 1.21.1 tag. forge:ores is gone, do not put it back

# startX/startY/startZ override GPS, for when gps.locate will not answer. With
# them set the heading cannot be measured, so startDir must be given too:
# 0, 1, 2, 3 = facing +z, -x, -z, +x. Position is then dead-reckoned, and a
# turtle that loses quarry.state cannot find itself again -- fixing GPS is
# better if you can. A turtle needs an equipped wireless modem for GPS; with
# all four of these set it needs no modem at all, because nothing asks GPS.
# They are a starting value, not a sensor: once quarry.state has a position and
# a heading of its own, that is what the turtle believes.
# startDir = 0
# startX = 0
# startY = 64
# startZ = 0

[oreNames]
# additive to oreTags. One block name per line.
%ORENAMES%

[only]
# non-empty here means mine EXACTLY these and nothing else.

[blacklist]
# junk tier: carried, never chased, dumped first when a slot is needed.
%BLACKLIST%

[fuel]
%FUEL%
]]

local cfg   = {}
local lists = {}

local function seedConf()
  local function block(t)
    local out = {}
    for _, v in ipairs(t) do out[#out + 1] = v end
    return table.concat(out, "\n")
  end
  local text = DEFAULT_CONF
    :gsub("%%ORENAMES%%",  block(LISTS.oreNames))
    :gsub("%%BLACKLIST%%", block(LISTS.blacklist))
    :gsub("%%FUEL%%",      block(LISTS.fuel))
  local f = fs.open(CONF, "w")
  f.write(text)
  f.close()
end

-- Returns cfg, lists, or nil plus a message naming the offending line.
local function readConf()
  local c, l, section = {}, {}, nil
  for k, v in pairs(NUM)  do c[k] = v end
  for k, v in pairs(STR)  do c[k] = v end
  for k, v in pairs(BOOL) do c[k] = v end
  for k, v in pairs(LISTS) do
    l[k] = {}
    for _, name in ipairs(v) do l[k][#l[k] + 1] = name end
  end

  if not fs.exists(CONF) then return c, l, "seeded" end

  for k in pairs(l) do l[k] = {} end          -- the file replaces the defaults

  local f = fs.open(CONF, "r")
  local text = f.readAll()
  f.close()

  local n = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local head = line:match("^%[(%w+)%]$")
      if head then
        if not l[head] then return nil, nil, ("%s:%d: unknown section [%s]"):format(CONF, n, head) end
        section = head
      else
        local k, v = line:match("^([%w_]+)%s*=%s*(.+)$")
        if k then
          section = nil
          if NUM[k] then
            local num = tonumber(v)
            if not num then return nil, nil, ("%s:%d: %s wants a number, got %q"):format(CONF, n, k, v) end
            c[k] = num
          elseif BOOL[k] ~= nil then       -- not `BOOL[k]`: a false default is still a key
            if v ~= "true" and v ~= "false" then
              return nil, nil, ("%s:%d: %s wants true or false, got %q"):format(CONF, n, k, v)
            end
            c[k] = (v == "true")
          elseif STR[k] then
            c[k] = v
          elseif k == "startX" or k == "startY" or k == "startZ" then
            local num = tonumber(v)
            if not num then return nil, nil, ("%s:%d: %s wants a number, got %q"):format(CONF, n, k, v) end
            c[k] = num
          elseif k == "startDir" then
            local num = tonumber(v)
            if not num or num < 0 or num > 3 or num % 1 ~= 0 then
              return nil, nil, ("%s:%d: startDir wants 0, 1, 2 or 3 (+z, -x, -z, +x), got %q")
                :format(CONF, n, v)
            end
            c[k] = num
          else
            return nil, nil, ("%s:%d: unknown setting %q"):format(CONF, n, k)
          end
        elseif section then
          if not line:match("^[%w_]+:[%w_/]+$") then
            return nil, nil, ("%s:%d: %q is not a block name like minecraft:coal_ore"):format(CONF, n, line)
          end
          l[section][#l[section] + 1] = line
        else
          return nil, nil, ("%s:%d: %q is not name = value and no [section] is open"):format(CONF, n, line)
        end
      end
    end
  end
  return c, l, "read"
end

-- state --------------------------------------------------------------------
-- Carries the task, not coordinates: GPS answers where, this answers what.

local st = {
  index  = 1,
  level  = nil,     -- y of the level being worked
  branch = nil,     -- z of the branch owned right now
  leg    = nil,     -- "west" | "east" | nil, nil until the leg is under way
  along  = 0,       -- blocks from the spine down that leg, whichever way it cuts
  plan   = nil,     -- the four legs of a row pair, in order; see pairPlan
  step   = nil,     -- which of them is being cut
  task   = "boot",  -- boot | descend | spine | branch | vein | depot | forage | park
  -- GPS exists here, so position is absolute and the state carries it: a
  -- turtle killed mid-branch reads this, re-locates, and walks back.
  x = nil, y = nil, z = nil,
  dir = nil,        -- 0 +z, 1 -x, 2 -z, 3 +x
  home = nil,       -- the block it was launched from; the depot is found in phase 3
  dug = 0, chased = 0, floor = nil,
  -- phase 3
  depot   = nil,    -- { x, y, z, dump = dir, fuel = dir } -- found, never configured
  done    = {},     -- ["y:z"] = true for a branch this turtle has finished
  cut     = {},     -- ["y:z"] = { west = true, east = true } for a row in progress
  carried = 0,      -- blocks dug since the last dump; tripBlocks forces a trip
  trips   = 0, hauled = 0, junked = 0, scooped = 0,
  lava    = {},     -- sources seen this trip, merged into /disk/lava.txt when docked
  lavaSeen = {},    -- dedupe for the above, so one source is not queued twice
}

local function save()
  local f = fs.open(STATE .. ".tmp", "w")
  f.write(textutils.serialise(st))
  f.close()
  if fs.exists(STATE) then fs.delete(STATE) end
  fs.move(STATE .. ".tmp", STATE)
end

local function load()
  if not fs.exists(STATE) then return false end
  local f = fs.open(STATE, "r")
  local t = textutils.unserialise(f.readAll())
  f.close()
  if type(t) == "table" then st = t return true end
  return false
end

-- claim maths --------------------------------------------------------------
-- Two anchors on purpose: the claim snaps to chunk borders so a player in the
-- centre chunk keeps it all loaded; the branch pattern anchors to the block
-- the turtle started on.

local function claimOf(x, z, conf)
  local cx, cz = math.floor(x / 16), math.floor(z / 16)
  local nx, nz = conf and conf.chunksX or 3, conf and conf.chunksZ or 3
  -- n chunks centred on chunk c, so 3 spans c-1..c+1 and the start chunk stays
  -- in the middle. An even n leans one chunk toward -c so the centre is inside.
  local function span(c, n)
    -- math.floor, not /: CC is Lua 5.2 (all doubles) but the test harness is
    -- Lua 5.3, where a bare / makes 1.0 print as "1.0" and breaks the report.
    if n % 2 == 1 then return c - math.floor((n - 1) / 2), c + math.floor((n - 1) / 2) end
    return c - math.floor(n / 2) + 1, c + math.floor(n / 2)
  end
  local cxLo, cxHi = span(cx, nx)
  local czLo, czHi = span(cz, nz)
  local c = {
    cx = cx, cz = cz,
    cxLo = cxLo, cxHi = cxHi, czLo = czLo, czHi = czHi,
    xMin = cxLo * 16, xMax = cxHi * 16 + 15,
    zMin = czLo * 16, zMax = czHi * 16 + 15,
  }
  c.xLen  = c.xMax - c.xMin + 1
  c.zLen  = c.zMax - c.zMin + 1
  c.spine = c.xMin + math.floor(c.xLen / 2)   -- branches run xLen/2 each way
  c.west  = c.spine - c.xMin                  -- blocks from spine to the west rim
  c.east  = c.xMax - c.spine                  -- and to the east rim
  return c
end

-- z of turtle i's third, and the trunk at its centre. The trunk sits on the
-- spine line, so every block of it is a spine block: three trunks cost nothing.
local function thirdOf(c, i, n)
  local w = math.floor(c.zLen / n)
  local lo = c.zMin + (i - 1) * w
  local hi = (i == n) and c.zMax or (lo + w - 1)
  return lo, hi, lo + math.floor((hi - lo) / 2)
end

-- The pattern: a branch is sunk wherever z == 2y (mod 5), measured from the
-- claim's own corner and from absolute y. Reading the first branch on each
-- level going up gives 1,3,5,2,4 -- 20% dug for 100% seen, and 20% is the
-- floor for 1-wide.
--
-- Both terms come from the world, never from quarry.conf. That is deliberate:
-- every turtle standing anywhere in the same chunk region computes the
-- identical pattern, so their branch mouths line up and "an air mouth is
-- already taken" works. Keying it to the turtle's own start block did not,
-- and keying it to a config value would break the moment one turtle's
-- quarry.conf drifted from another's.
local function isBranch(c, y, z)
  return (z - c.zMin - 2 * y) % 5 == 0
end

local function branchZs(c, y)
  local out = {}
  for z = c.zMin, c.zMax do
    if isBranch(c, y, z) then out[#out + 1] = z end
  end
  return out
end

-- Deepest first by default; stopping early then loses only the cheapest levels.
local function levels(c2)
  local out = {}
  for y = c2.bottomY, c2.topY do out[#out + 1] = y end
  if c2.deepestFirst then return out end
  local rev = {}
  for i = #out, 1, -1 do rev[#rev + 1] = out[i] end
  return rev
end

-- A branch at (y,z) digs one cross-section cell and sees five: its own, y+-1
-- in its column, and z+-1 at its own level. Anything the claim rim leaves
-- outside that plus-shape is genuinely never looked at, so count it.
local function unseenRim(c, lo, hi)
  local seen, total = {}, 0
  for y = lo, hi do
    for _, z in ipairs(branchZs(c, y)) do
      seen[y .. "," .. z] = true
      seen[(y - 1) .. "," .. z] = true
      seen[(y + 1) .. "," .. z] = true
      seen[y .. "," .. (z - 1)] = true
      seen[y .. "," .. (z + 1)] = true
    end
  end
  local miss, edge = 0, 0
  for y = lo, hi do
    for z = c.zMin, c.zMax do
      total = total + 1
      if not seen[y .. "," .. z] then
        miss = miss + 1
        if z == c.zMin or z == c.zMax or y == lo or y == hi then edge = edge + 1 end
      end
    end
  end
  return miss, total, edge
end

-- What the whole claim costs. Movement is the only thing that burns fuel, so
-- the estimate is a move count: mining walks every dug block out and back,
-- then every full inventory pays a return down the trunk to the floor depot.
local function survey(c, conf)
  local ys = levels(conf)
  local r = {
    levels = #ys, branches = 0, dug = 0, moves = 0,
    minB = math.huge, maxB = 0,
    volume = c.xLen * c.zLen * (conf.topY - conf.bottomY + 1),
  }
  local n = conf.turtles
  local w = math.floor(c.zLen / n)
  for _, y in ipairs(ys) do
    local nb = #branchZs(c, y)
    r.branches = r.branches + nb
    if nb < r.minB then r.minB = nb end
    if nb > r.maxB then r.maxB = nb end

    -- the spine spans z; each branch adds the rest of its row
    local dug = c.zLen + nb * (c.xLen - 1)
    r.dug = r.dug + dug

    local depth = y - conf.bottomY                        -- depot is at the floor
    local branchMoves = nb * 2 * (c.west + c.east)        -- out and back, each leg
    local spineMoves  = n * 2 * w                         -- each turtle sweeps its third
    local trunkMoves  = n * 2 * depth                     -- up to the level and back
    local trips       = math.ceil(dug / conf.tripBlocks)
    local tripMoves   = trips * 2 * (depth + math.floor((c.west + c.east) / 4) + math.floor(w / 4))
    r.moves = r.moves + branchMoves + spineMoves + trunkMoves + tripMoves
  end
  r.pct = r.dug / r.volume * 100
  return r
end

-- --check ------------------------------------------------------------------

local out = {}
local function say(...)
  local line = table.concat({ ... }, " ")
  out[#out + 1] = line
  print(line)
end
local function sayf(fmt, ...) say(fmt:format(...)) end

local function upload()
  if not http then say("no http, report not uploaded") return end
  local ok, h = pcall(http.post, "https://paste.rs/", table.concat(out, "\n"))
  if ok and h then
    print("report -> " .. h.readAll())
    h.close()
  else
    print("upload failed")
  end
end

-- Nobody may be watching this screen. /startup brings a turtle back after a
-- chunk reload or a server restart with the player miles away, so a question
-- that waits forever is a mine that never restarts. Every question here answers
-- itself after ASK_TIMEOUT with what the program used to do on its own, and
-- says in the log that nobody answered -- an unattended answer reads as one.
-- Short, because most of these are confirmations of what the run was going to
-- do anyway and a turtle nobody is watching should get on with it. The two
-- that need the player to physically do something pass their own longer wait.
local ASK_TIMEOUT = 10

local function ask(prompt, default, wait)
  wait = wait or ASK_TIMEOUT
  say(prompt)
  sayf("         (type and press enter -- %ds of silence and I take \"%s\")",
    wait, default)
  local answer
  local lived = pcall(parallel.waitForAny,
    function() answer = read() end,
    function() os.sleep(wait) end)
  if not lived or answer == nil then
    sayf("         nobody answered, taking \"%s\"", default)
    return default, false
  end
  answer = answer:match("^%s*(.-)%s*$")
  if answer == "" then answer = default end
  sayf("         answered \"%s\"", answer)
  return answer, true
end

-- startX/startY/startZ pin the position and startDir states the heading, which
-- together are everything GPS would have provided. A turtle running on those
-- never calls gps.locate, so it does not need a wireless modem either -- the
-- kit audit, the deploy handover and the boot script all read this.
local function manualFix(conf)
  return conf.startX ~= nil and conf.startY ~= nil and conf.startZ ~= nil
     and conf.startDir ~= nil
end

-- A turtle reaches gps.locate only through an equipped WIRELESS modem, and
-- "wireless" is not the same question as "is there a modem". CC's gps.locate
-- walks the sides looking for one whose isWireless() is true, so a WIRED modem
-- equips happily, reports its type as "modem" exactly as a wireless one does,
-- and still yields no fix ever. Those are two different problems with two
-- different answers, so this tells them apart rather than reporting "modem"
-- for both. The pickaxe is not a peripheral, so it reads as nil here.
-- First slot whose item id matches the pattern. Defined up here because the
-- modem check needs it: everything from the equip dance down uses this one.
-- A predicate is accepted as well as a pattern, for the one question a pattern
-- cannot answer: "is this storage" is the STORAGE word list and there is only
-- ever one of that list [RESUME, settled].
local function slotLike(pat)
  local like = (type(pat) == "function") and pat
    or function(n) return n:find(pat) end
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and like(d.name) then return s, d.name, d.count end
  end
end

-- turtle.getEquippedLeft/Right name the upgrade itself, which peripheral.getType
-- cannot: a pickaxe is not a peripheral, so under getType an armed side and an
-- EMPTY side both read as nil. That is the whole reason the boot script has to
-- equip blind and undo it if the pickaxe fell out. Ask for the name when the
-- method is there. It is not in references/peripherals.md -- that dump was
-- taken from a computer, which has no turtle API at all -- so it is called
-- through pcall and the old getType route stays as the fallback, which is also
-- what an older CC:Tweaked gets. Returns an item table on this build; a string
-- would do as well, so both shapes are read.
local function equippedItem(side)
  local fn = turtle and turtle[side == "left" and "getEquippedLeft" or "getEquippedRight"]
  if not fn then return nil, false end
  local ok, d = pcall(fn)
  if not ok then return nil, false end
  if type(d) == "table" then return d.name, true end
  if type(d) == "string" then return d, true end
  return nil, true                  -- the method answered: that side is EMPTY
end

-- One door to a peripheral, because pcall prepends its own success flag and
-- the answer is the SECOND value -- a mistake this file has now made five
-- separate times [RESUME, corrections]. A FAILED call puts an error STRING
-- where the answer goes, and an error string is a non-empty string: every
-- guard of the form `type(x) == "string"` waves it straight through, and the
-- error text is then printed as if it were the answer. Returns nil when the
-- call did not live, so "it would not answer" and "it answered nil" are the
-- same thing to every caller here, which is what they all want.
local function periph(fn, ...)
  local ok, res = pcall(fn, ...)
  if ok then return res end
end

local function isModemName(n)
  n = tostring(n or "")
  return n:find("wireless_modem") ~= nil or n:find("ender_modem") ~= nil
     or n:find("modem") ~= nil
end

-- Wired and wireless modems both report their peripheral type as "modem" and
-- gps.locate only ever answers through a wireless one, so the two are told
-- apart by name where a name is available and by isWireless() where it is not.
local function equippedSides()
  local out = {}
  for _, side in ipairs({ "left", "right" }) do
    local name, asked = equippedItem(side)
    if name and isModemName(name) then
      if name:find("wireless_modem") or name:find("ender_modem") then
        out[side] = "wireless modem"
      else
        local okw, wireless = pcall(peripheral.call, side, "isWireless")
        out[side] = (okw and wireless == false) and "wired modem" or "wireless modem"
      end
    elseif name then
      out[side] = name                -- a pickaxe, or anything else equipped
    elseif not asked then
      -- no getEquipped* on this build: fall back to the peripheral type, which
      -- sees a modem and nothing else
      local ok, t = pcall(peripheral.getType, side)
      if ok and t then
        out[side] = t
        if t == "modem" then
          local okw, wireless = pcall(peripheral.call, side, "isWireless")
          -- an old build with no isWireless is not evidence of a wired modem
          out[side] = (okw and wireless == false) and "wired modem" or "wireless modem"
        end
      end
    end
  end
  return out
end

local function modemSide()
  local e = equippedSides()
  if e.left  == "wireless modem" then return "left" end
  if e.right == "wireless modem" then return "right" end
end

local function hasModem()
  return modemSide() ~= nil
end

local function hasWiredModem()
  local e = equippedSides()
  return (e.left == "wired modem") or (e.right == "wired modem")
end

-- Where the floppy is actually mounted. "/disk" is only the FIRST drive's
-- mount: a second one anywhere on the turtle mounts at "/disk2", "/disk3" and
-- so on, and every hard-coded /disk path then silently misses -- the deployer
-- writes a boot script the new turtle cannot see, and a turtle started off the
-- floppy does not recognise that it is on one. The drive answers this itself,
-- through getMountPath, so ask it rather than guessing the name.
-- Left and right hold equipped upgrades on a turtle, never a block, so the
-- drive can only be on the other four sides -- but asking all six costs
-- nothing and covers a computer running this too.
-- The side is worth having as well as the path: disk.setLabel addresses the
-- DRIVE, not the mount, so anything that wants to write on the floppy itself
-- needs to know which side answered.
local function diskDrive()
  for _, side in ipairs({ "top", "bottom", "front", "back", "left", "right" }) do
    local okt, t = pcall(peripheral.getType, side)
    if okt and t == "drive" then
      local okm, mp = pcall(peripheral.call, side, "getMountPath")
      if okm and type(mp) == "string" and mp ~= "" then
        return side, (mp:sub(1, 1) == "/") and mp or ("/" .. mp)
      end
    end
  end
end

local function diskPath()
  local _, mp = diskDrive()
  if mp then return mp end
  -- no drive answered: fall back to the conventional name if it is there
  return fs.exists("/disk") and "/disk" or nil
end

-- A modem sitting in a slot is not a modem on a side, and only a side answers
-- gps.locate. If one is aboard and neither side holds it, put it on.
--
-- equip SWAPS: it exchanges the SELECTED slot with that side's upgrade. Equip
-- off the wrong slot and the pickaxe lands in the inventory and the turtle
-- cannot dig -- so the selection is verified by reading the slot back before
-- anything is equipped, never inferred from turtle.select's return.
--
-- Which side to use is the other half. getEquippedLeft/Right name what is
-- there, so the empty side is known outright. Without them a pickaxe and an
-- empty side both read as nil, and the only way to find out is the boot
-- script's move: equip, look at what came off in the hand, and undo it if that
-- was the pickaxe.
local function ensureModem()
  if hasModem() then return true end
  local slot = slotLike("wireless_modem") or slotLike("ender_modem")
  if not slot then return false, "no wireless modem is equipped and none is aboard" end

  turtle.select(slot)
  local okd, d = pcall(turtle.getItemDetail)
  if not okd or not d or not isModemName(d.name) then
    return false, ("slot %d does not hold a modem after selecting it (%s), so "):format(
      slot, tostring(okd and d and d.name or "empty"))
      .. "equipping would swap out the pickaxe instead"
  end

  local e = equippedSides()
  local _, named = equippedItem("left")
  if named then
    -- the sides are known by name: use the empty one, or the one that is not
    -- the pickaxe, and never touch a side holding a tool when the other is free
    local side = (e.left == nil and "left") or (e.right == nil and "right")
      or (not tostring(e.left):find("pickaxe") and "left")
      or (not tostring(e.right):find("pickaxe") and "right")
    if not side then return false, "both sides hold a pickaxe, so there is nowhere to put a modem" end
    local ok = select(2, pcall(side == "left" and turtle.equipLeft or turtle.equipRight))
    if ok == false then return false, "the modem would not equip on " .. side end
    if hasModem() then
      sayf("equipped: a modem was in a slot and not on a side -- fitted it on %s", side)
      return true, side
    end
    return false, "the modem went on " .. side .. " but no wireless modem reads back"
  end

  -- No getEquipped*: equip blind and undo it if the pickaxe fell out.
  local okR = select(2, pcall(turtle.equipRight))
  local came = select(2, pcall(turtle.getItemDetail))
  if type(came) == "table" and tostring(came.name):find("pickaxe") then
    pcall(turtle.equipRight)          -- pickaxe back on the right, modem in hand
    pcall(turtle.equipLeft)           -- modem goes left instead
  end
  if hasModem() then
    local e = equippedSides()
    sayf("equipped: a modem was in a slot and not on a side -- fitted it on %s",
      e.left == "wireless modem" and "left" or "right")
    return true
  end
  return false, "the modem would not equip on either side (equipRight " .. tostring(okR) .. ")"
end

-- gps.locate's own default is 2s, which is one round trip to four hosts and no
-- slack. A rebuilt constellation at the edge of modem range answers late rather
-- than not at all, and this is called about four times in a whole run, so the
-- extra wait is free and a false NO FIX is not. Raised from 5s to 10s on the
-- user's instruction 2026-08-28: a whole run pays 40s at worst, and a NO FIX
-- underground costs a trip out to the turtle.
local GPS_TIMEOUT = 10

-- GPS, then the config pin, then the questions -- in that order, on the user's
-- instruction 2026-08-29. GPS goes first because it is the only thing here that
-- actually LOOKS: the pin and the state file are both records of where the
-- turtle was put, and neither of them can tell that somebody has picked it up
-- and moved it. It is skipped only where it cannot work at all -- no wireless
-- modem equipped means no fix is possible -- so a turtle running on a pin with
-- no modem pays nothing for being asked first.
--
-- "No modem equipped" is not the same as "no modem", and it used to be treated
-- as one: a turtle carrying a wireless modem in a slot has everything it needs
-- for GPS and was falling through to dead reckoning anyway. ensureModem puts it
-- on a side first, so the question this asks is whether a fix is POSSIBLE, not
-- whether somebody remembered to equip it.
local function locate(conf)
  if gps and (hasModem() or ensureModem()) then
    local ok, x, y, z = pcall(gps.locate, GPS_TIMEOUT)
    if ok and x then return math.floor(x), math.floor(y), math.floor(z), "gps" end
  end
  -- Then the turtle's own dead reckoning. Underground there may be no
  -- constellation to reach: a wireless modem's range shrinks with depth, and
  -- the hosts sit near the surface a hundred-odd blocks above the claim floor
  -- [in-game 2026-08-28, log td7FE]. quarry.state is written every block and
  -- carries the heading GPS never gives, so a turtle that has been running
  -- already knows where it is -- and it beats the pin, which names a launch
  -- block that a running turtle left long ago.
  if st.x and st.y and st.z and st.dir then
    return st.x, st.y, st.z, "quarry.state"
  end
  -- Then the pin. It is exactly right for a turtle that has not moved yet,
  -- which is what a freshly deployed one is, and wrong for every other.
  if conf.startX and conf.startY and conf.startZ then
    return conf.startX, conf.startY, conf.startZ, "quarry.conf"
  end
  -- And last, nothing -- which is locateOrAsk's cue to ask the player.
  return nil, nil, nil, "no fix"
end


-- Tell the player something only they can fix. It always goes into the log, so
-- the uploaded paste carries it either way, and it goes out over rednet as well
-- when there is a wireless modem to send it with -- `alert` on a computer in
-- range prints it. Best effort on purpose: a modem's range shrinks with depth,
-- which is the same physics that keeps GPS off the claim floor, so a turtle at
-- y=-59 may well be talking to nobody. Once per kind per run: a full depot is
-- one fact, not one per stack.
local notified = {}
local function notify(kind, msg)
  if notified[kind] then return end
  notified[kind] = true
  sayf("notify : %s", msg)
  local side = modemSide()
  if not side or type(rednet) ~= "table" then return end
  pcall(rednet.open, side)
  pcall(rednet.broadcast, ("quarry%s: %s"):format(tostring(st.index or 1), msg), "quarry")
end

-- gps.locate's second argument is a debug flag, and with it on the api prints
-- what it actually saw -- which sides it tried, how many hosts answered,
-- whether they agreed -- straight to the terminal, where an uploaded log never
-- sees it. Three sessions were spent guessing at a NO FIX that the api was
-- willing to explain all along. Borrow print for the call so the next paste
-- carries the answer instead of another theory.
--
-- Borrow it from _G, not from here. shell.run gives a program its own
-- environment table, and the rom apis keep their own: `print = f` in this file
-- only ever shadowed print for quarry itself, so gps.locate went on writing to
-- a terminal nobody was reading and the capture came back empty -- which the
-- report then printed as "it printed nothing at all" [paste fXOYd, 2026-08-28,
-- a turtle with a wireless modem equipped and no host in range]. printError
-- goes with it: the no-modem line is the one verdict that comes out that way.
local function gpsDebug()
  local lines = {}
  local function grab(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(t, " ")
  end
  local G = _G
  local p, pe = G.print, G.printError
  G.print, G.printError = grab, grab
  pcall(gps.locate, GPS_TIMEOUT, true)
  G.print, G.printError = p, pe
  return lines
end

-- A NO FIX has three causes wanting three different answers, and the first
-- version of this line listed them all at once: "equip a wireless modem, or set
-- startX/Y/Z". In-game 2026-08-28 that read as a lie -- gps.locate answered
-- when the user tried it by hand and the run still refused to start -- because
-- the message never said which cause it actually was. It says now, it says what
-- gps.locate itself saw, and it goes through say() so the uploaded log carries
-- the evidence instead of one bare CRASHED line.
local function noFix()
  local e = equippedSides()
  local sides = ("left=%s right=%s"):format(tostring(e.left or "none"),
                                            tostring(e.right or "none"))
  sayf("gps    : equipped %s", sides)
  sayf("gps    : asking gps.locate again with debug on (%ds)", GPS_TIMEOUT)
  local seen = gpsDebug()
  if #seen == 0 then say("gps    : (it printed nothing at all)") end
  for _, line in ipairs(seen) do sayf("gps    : %s", line) end

  if hasWiredModem() and not hasModem() then
    return "no position fix: the equipped modem is WIRED, not wireless (" .. sides
      .. "). gps.locate only ever answers through a wireless modem -- it checks "
      .. "isWireless() and skips the rest. Swap it for a wireless modem."
  end
  if not hasModem() then
    return "no position fix: NO WIRELESS MODEM IS EQUIPPED (" .. sides .. "). GPS "
      .. "needs the modem ON the turtle, not in a slot: select it and run "
      .. "`equip right`, or run `quarry --check`, which reports both sides."
  end
  return "no position fix: a wireless modem IS equipped (" .. sides .. ") and no "
    .. "GPS host answered in " .. GPS_TIMEOUT .. "s. See the gps lines above for "
    .. "what it saw. Hosts must be running, in loaded chunks, and in range of "
    .. "HERE -- range falls off with depth. Or set startX/Y/Z in quarry.conf."
end

-- Rewrite -- or add -- the four pin lines in a quarry.conf body. The shipped
-- defaults carry them commented out, so the pattern eats an optional #:
-- otherwise a pin lands in the file underneath a comment still saying it is
-- unset, and the next reader believes the comment.
local function pinBody(body, vals)
  body = "\n" .. body            -- so a key on the very first line still matches
  for _, k in ipairs({ "startX", "startY", "startZ", "startDir" }) do
    if vals[k] then
      local pat = "\n[ \t]*#?[ \t]*" .. k .. "[ \t]*=[^\n]*"
      local rep = ("\n%s = %d"):format(k, vals[k])
      if body:find(pat) then body = body:gsub(pat, rep, 1)
      else body = body .. rep:sub(2) .. "\n" end
    end
  end
  return body:sub(2)
end

-- The reverse of a pin: comment out any active startX/Y/Z/startDir so they stop
-- overriding GPS. A turtle that is picked up and put down somewhere new keeps
-- its old pin otherwise, and mines the old claim from the new spot. The lines
-- are commented, not deleted, so the numbers are still there to read -- and a
-- line already commented is left alone, so this is idempotent.
local function unpinBody(body)
  body = "\n" .. body
  for _, k in ipairs({ "startX", "startY", "startZ", "startDir" }) do
    body = body:gsub("\n([ \t]*" .. k .. "[ \t]*=[^\n]*)", "\n# %1")
  end
  return body:sub(2)
end

-- A run that cannot find itself used to stop here, with the player standing
-- next to a turtle that would not listen to the coordinates they could read
-- off their own screen. Ask for them instead, and write them into quarry.conf
-- so the next reboot does not ask again. Nothing is assumed: a missing or
-- unparseable answer, or nobody at the keyboard at all, gives the old error.
-- What a player actually reads off F3 for a heading, alongside the raw 0..3.
-- "Facing: south (Towards positive Z)" -- so south, +z and z all mean 0.
local HEADINGS = {
  ["0"] = 0, ["+z"] = 0, ["z"] = 0, ["south"] = 0, ["s"] = 0,
  ["1"] = 1, ["-x"] = 1, ["west"]  = 1, ["w"] = 1,
  ["2"] = 2, ["-z"] = 2, ["north"] = 2, ["n"] = 2,
  ["3"] = 3, ["+x"] = 3, ["x"] = 3, ["east"]  = 3, ["e"] = 3,
}

local function locateOrAsk(conf)
  local x, y, z, how = locate(conf)
  if x then return x, y, z, how end

  sayf("position: %s", noFix())
  say("position: I can run on coordinates typed by hand instead. Press F3 and")
  say("          read off the block I am standing ON. Enter on its own gives up.")
  local vals = {}
  for _, q in ipairs({ { "startX", "my x?" }, { "startY", "my y?" }, { "startZ", "my z?" },
                       { "startDir",
                         "which way am I facing? 0 = +z south, 1 = -x west, 2 = -z north, 3 = +x east" } }) do
    local v
    while true do
      local a = ask("position: " .. q[2], ""):lower()
      -- F3 says "Facing: south (Towards positive Z)", so that is what a player
      -- has in front of them and what they type. "+z" was typed in-game and
      -- thrown away [log nznpx], taking the three good coordinates with it.
      v = tonumber(a)
      if q[1] == "startDir" then
        v = HEADINGS[a] or v
        if v and (v < 0 or v > 3) then v = nil end
      end
      if v then break end
      -- Enter on its own is still "give up": nobody is at the keyboard on a
      -- /startup reboot, and guessing a position is worse than stopping.
      if a == "" then
        say("position: no coordinates given, so I have taken none of them.")
        return nil, nil, nil, "no fix"
      end
      -- One bad answer used to discard the other three. Ask again for the one
      -- that did not read, and keep what is already good.
      sayf("position: I cannot read \"%s\". Try again, or enter on its own to give up.", a)
    end
    vals[q[1]] = math.floor(v)
  end
  for k, v in pairs(vals) do conf[k] = v end

  local body = ""
  local h = fs.open(CONF, "r")
  if h then body = h.readAll() h.close() end
  local w = fs.open(CONF, "w")
  if w then
    w.write(pinBody(body, conf))
    w.close()
    sayf("position: written into %s -- %d,%d,%d facing %d. Delete those four lines",
      CONF, conf.startX, conf.startY, conf.startZ, conf.startDir)
    say("          when GPS works again, or I will keep believing them.")
  else
    say("position: could not write them into quarry.conf, so this run only.")
  end
  return conf.startX, conf.startY, conf.startZ, "typed"
end

local function findItem(name)
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and d.name == name then return s end
  end
end

-- Issue #530 had lava buckets deleted by placeDown in 1.16.1. Prove it works
-- on this server before a slot is spent carrying one for the rest of the job.
local function checkLava()
  local empty = findItem("minecraft:bucket")
  local full  = findItem("minecraft:lava_bucket")
  if full then
    sayf("lava   : a full lava_bucket is in slot %d -- refuel it first, then re-check", full)
    return
  end
  if not empty then
    say("lava   : no empty bucket in inventory, scoop test skipped")
    return
  end
  local side
  for _, probe in ipairs({ { "front", turtle.inspect }, { "down", turtle.inspectDown }, { "up", turtle.inspectUp } }) do
    -- pcall prepends its own success flag, so inspect's two returns land third
    local ok, found, data = pcall(probe[2])
    if ok and found and data and tostring(data.name):find("lava") then side = probe[1] break end
  end
  if not side then
    say("lava   : bucket ready, but no lava adjacent -- park over a source and re-run --check")
    return
  end
  if DRY then
    sayf("lava   : DRY -- would scoop the %s source with slot %d and check the fuel rose", side, empty)
    return
  end
  local before = turtle.getFuelLevel()
  turtle.select(empty)
  local place = side == "down" and turtle.placeDown or (side == "up" and turtle.placeUp or turtle.place)
  local lived, put = pcall(place)
  local ok = lived and put ~= false
  local got = findItem("minecraft:lava_bucket")
  if got then pcall(turtle.select, got) pcall(turtle.refuel) end
  local after = turtle.getFuelLevel()
  turtle.select(1)
  local back = findItem("minecraft:bucket")
  sayf("lava   : scoop %s, fuel %s -> %s, bucket %s",
    ok and "ok" or "FAILED", tostring(before), tostring(after),
    back and "returned" or "GONE -- do not carry one, issue #530 is live here")
end

-- What counts as a storage block, matched as a substring of the block id. A
-- modpack renames these a dozen ways -- sophisticatedstorage:barrel,
-- :iron_barrel, :limited_barrel_1, ironchest:diamond_chest,
-- expandedstorage:*_chest, quark:*_chest -- and enumerating every tier of every
-- mod is a losing game, so this matches on the word instead. One list feeds
-- four questions: what can be a depot, what is never dug, what stays in the
-- hold as kit, and what the kit audit counts.
--
-- Only inventories that accept ANY item belong here. A Storage Drawer, a
-- Functional Storage drawer and a Mekanism bin each lock to one item type, so a
-- mixed dump into one fails on the second stack and the run halts with "the
-- depot chest is full" -- which is why "drawer" and "bin" are deliberately not
-- on this list.
-- ponytail: substring words, not a config list. Add a [containers] section to
-- quarry.conf if a pack ever ships storage none of these words name.
local STORAGE = { "chest", "barrel", "shulker", "crate", "item_vault" }

local function hasWord(list, name)
  name = tostring(name)
  for _, p in ipairs(list) do if name:find(p, 1, true) then return true end end
  return false
end

-- kit audit ----------------------------------------------------------------
-- What the whole mine needs, and what is actually in this turtle's inventory.
-- Item ids are matched by pattern rather than by exact name on purpose: the
-- exact ids for a Mining Turtle and a floppy in this pack are not in the
-- peripheral dump, so anything unrecognised is printed verbatim instead of
-- being silently ignored. One run and we know the real names.

local KIT = {
  { key = "turtle",   label = "mining turtle",
    match = function(n) return n:find("turtle") end,
    why = "the other turtles, placed at their own trunks" },
  { key = "chest",    label = "storage block",
    match = function(n) return hasWord(STORAGE, n) end,
    why = "one per turtle, under its own trunk" },
  { key = "drive",    label = "disk drive",
    match = function(n) return n:find("disk_drive") end,
    why = "the shared lava map, and the only way to hand code to a turtle" },
  { key = "floppy",   label = "floppy disk",
    match = function(n) return n:find("disk") and not n:find("disk_drive") end,
    why = "goes in the drive" },
  { key = "modem",    label = "wireless modem",
    match = function(n) return n:find("wireless_modem") or n:find("ender_modem") end,
    why = "GPS. A turtle with no modem cannot locate itself, so it cannot resume" },
  { key = "bucket",   label = "empty bucket",
    match = function(n) return n == "minecraft:bucket" end,
    why = "one per turtle. Lava scooping is confirmed working on this server" },
  { key = "fuel",     label = "coal or charcoal",
    match = function(n) return n:find("coal") or n:find("charcoal") end,
    why = "a stack per turtle to start. The whole claim wants about 3,300" },
}

-- What the mine needs follows quarry.conf, never a hard-coded three. A two
-- turtle mine was failing its own audit over the third turtle and the third
-- bucket it would never place, and turtles = 1 could not pass at all.
-- Modems are the other half of it: with the position pinned by hand nothing
-- ever calls gps.locate, so a modem is not kit, it is a spare part.
-- A container each, not one for the mine. One box meant every dock from every
-- turtle ended at the same block, down a spine that is one wide, so two
-- turtles walking to it from opposite ends met head-on and neither could pass
-- [in-game 2026-08-29, logs qhVSH and fPSF1: twelve give-ways each, then both
-- gave up]. With a depot under its own trunk no turtle leaves its own third to
-- bank, so the meetings stop happening rather than being recovered from.
local function kitWants(conf)
  local n = conf.turtles or 1
  -- A solo mine deploys nobody and shares its lava map with nobody, so the
  -- drive and the floppy are dead weight -- and the audit used to refuse a
  -- one-turtle kit that was in fact complete [HARVEST-PLAN C1]. Everything else
  -- already scales with n: turtle = 0, one container, one bucket, 64 coal.
  local solo = n == 1
  return { turtle = n - 1, chest = n,
           drive = solo and 0 or 1, floppy = solo and 0 or 1,
           modem = manualFix(conf) and 0 or n, bucket = n, fuel = 64 * n }
end

local function auditKit(conf)
  local want = kitWants(conf)
  local have, unknown = {}, {}
  for _, k in ipairs(KIT) do have[k.key] = 0 end
  -- a modem already equipped on this turtle is one it does not need as an item
  if hasModem() then have.modem = have.modem + 1 end
  for sl = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, sl)
    if ok and d then
      local hit
      for _, k in ipairs(KIT) do
        if k.match(d.name) then have[k.key] = have[k.key] + d.count hit = true break end
      end
      if not hit then unknown[#unknown + 1] = ("%s x%d"):format(d.name, d.count) end
    end
  end

  local short = {}
  sayf("kit    : what a %d turtle mine needs, against what is in this turtle",
    conf.turtles or 1)
  for _, k in ipairs(KIT) do
    local n, w = have[k.key], want[k.key]
    sayf("         %-16s %3d of %3d  %s", k.label, n, w,
      n >= w and "ok" or ("SHORT " .. (w - n) .. " -- " .. k.why))
    if n < w then short[#short + 1] = ("%d %s"):format(w - n, k.label) end
  end
  if want.modem == 0 then
    say("         no modem is wanted: quarry.conf pins the position, so nothing")
    say("         here ever calls gps.locate.")
  end
  if #unknown > 0 then
    sayf("         not recognised: %s", table.concat(unknown, ", "))
    say("         (tell me those names -- they are how the audit learns this pack)")
  end
  if #short == 0 then
    say("         nothing missing. Everything the mine needs is aboard.")
  else
    sayf("         MISSING: %s", table.concat(short, ", "))
  end
  return #short == 0
end

local function timeSave(n)
  local t0 = os.epoch and os.epoch("utc") or (os.clock() * 1000)
  for _ = 1, n do save() end
  local t1 = os.epoch and os.epoch("utc") or (os.clock() * 1000)
  return (t1 - t0) / n, t1 - t0
end

local function check(conf, l, source, index)
  local x, y, z, how = locate(conf)
  sayf("quarry --check   turtle %d of %d   %s", index, conf.turtles, DRY and "DRY" or "LIVE")
  sayf("config : %s (%s)", CONF, source)
  if st.halt then sayf("last   : the last run stopped -- %s", st.halt) end

  -- A modem in a slot is not a modem on a side, so fit it before reporting on
  -- it -- the whole point of --check is to leave the turtle ready to run.
  -- A modem in a slot is not a modem on a side, so fit it before reporting on
  -- it -- the whole point of --check is to leave the turtle ready to run. It
  -- says so itself when it fits one; what is left to report here is the case
  -- where a modem is aboard and could NOT be fitted.
  local fitted, whyFit = ensureModem()
  local e = equippedSides()
  sayf("equipped: left=%s  right=%s", tostring(e.left or "tool or empty"),
    tostring(e.right or "tool or empty"))
  if not fitted and whyFit then sayf("equipped: %s", tostring(whyFit)) end

  if not x then
    say("position: NO FIX -- gps.locate returned nothing and quarry.conf sets no startX/Y/Z")
    if hasWiredModem() and not hasModem() then
      say("         CAUSE: the equipped modem is WIRED. gps.locate checks")
      say("         isWireless() and skips anything that is not. Swap it.")
    elseif not hasModem() then
      say("         CAUSE: no wireless modem is equipped. GPS needs one. Put a")
      say("         wireless modem in a slot, select it, and run: equip right")
    else
      say("         A wireless modem is equipped, so this is range or a missing host.")
    end
    sayf("         asking gps.locate again with debug on (%ds):", GPS_TIMEOUT)
    local seen = gpsDebug()
    if #seen == 0 then say("         (it printed nothing at all)") end
    for _, line in ipairs(seen) do sayf("         %s", line) end
    say("         startX/startY/startZ is a fallback, not a fix: a turtle told its")
    say("         position once cannot re-locate after a freeze, so resume degrades.")
    say("Claim maths needs a position. The kit audit does not, so it follows.")
    auditKit(conf)
    return
  end
  sayf("position: %d,%d,%d (%s)", x, y, z, how)
  if how == "quarry.state" then
    say("         WARNING: gps.locate did not answer HERE, so that is the position")
    say("         quarry.state was last saved at, with the heading it saved too.")
    say("         A run will start on it. Underground that is normal -- modem range")
    say("         falls off with depth and the hosts are far above. If this turtle")
    say("         has been moved by hand since, delete quarry.state first.")
  end
  if how == "quarry.conf" then
    say("         WARNING: that came from quarry.conf, not GPS. Calibration finds")
    say("         the heading by moving one block and watching the position change,")
    say("         and a config coordinate never changes, so a run needs startDir")
    say("         set as well -- 0, 1, 2 or 3 for +z, -x, -z, +x.")
    if conf.startDir then
      sayf("         startDir = %d, so a run will start. Position is dead-reckoned",
        conf.startDir)
      say("         from here: if this turtle loses quarry.state it cannot find")
      say("         itself again. Fixing GPS is still the better answer.")
    else
      say("         startDir is NOT set, so a run will refuse to start.")
    end
  end

  local c = claimOf(x, z, conf)

  sayf("claim  : chunks %d..%d by %d..%d", c.cxLo, c.cxHi, c.czLo, c.czHi)
  sayf("corners: x %d..%d, z %d..%d  (%dx%d)", c.xMin, c.xMax, c.zMin, c.zMax, c.xLen, c.zLen)
  sayf("spine  : x=%d, branches run %d west and %d east", c.spine, c.west, c.east)
  for i = 1, conf.turtles do
    local lo, hi, trunk = thirdOf(c, i, conf.turtles)
    sayf("turtle %d: z %d..%d, trunk at x=%d z=%d%s", i, lo, hi, c.spine, trunk,
      i == index and "   <- this one" or "")
  end
  say("trunks sit on the spine line, so they cost no extra digging")

  sayf("levels : y %d..%d, %d levels, %s first",
    conf.bottomY, conf.topY, conf.topY - conf.bottomY + 1,
    conf.deepestFirst and "deepest" or "highest")
  say("nothing outside that range is mined. Bedrock can stop the trunk higher than")
  say("bottomY -- a failed dig is the real floor -- and levels under it are dropped.")

  -- The pattern read back off the maths rather than asserted, and deliberately
  -- sampled at a fixed y=0..9 rather than at bottomY: that makes the line a
  -- stable fingerprint you can compare between two turtles' reports. If all
  -- three print the same claim corners and the same string here, they agree.
  local seq = {}
  for yy = 0, 9 do
    for zz = c.zMin, c.zMin + 4 do
      if isBranch(c, yy, zz) then seq[#seq + 1] = zz - c.zMin + 1 break end
    end
  end
  sayf("pattern: z == 2y (mod 5) off the claim corner, first branch = %s  (at y=0..9)",
    table.concat(seq, ","))

  local r = survey(c, conf)
  sayf("branches: %d total, %d-%d per level", r.branches, r.minB, r.maxB)
  sayf("dug    : %d of %d blocks (%.1f%%)", r.dug, r.volume, r.pct)

  local miss, total, edge = unseenRim(c, conf.bottomY, conf.topY)
  sayf("unseen : %d of %d cross-section cells (%.2f%%), %d of them on the claim face",
    miss, total, miss / total * 100, edge)
  if miss > edge then
    sayf("         WARNING: %d unseen cells are in the INTERIOR. The stagger is not", miss - edge)
    say("         tiling. Do not run this until that is nought.")
  elseif miss > 0 then
    say("         The interior is covered exactly. What is missed is the outermost")
    say("         z column, and the top and bottom levels, where the branch that")
    say("         would have seen them lies outside the claim. A neighbouring claim")
    say("         reads the z rim; nothing reads above topY, by design.")
  end

  -- the tank is whatever THIS turtle reports, not the plan's assumed 20,000:
  -- an advanced turtle holds far more, and printing "of 20000" beside a level
  -- of 51,183 reads like a bug in the turtle rather than a bug in this line.
  local lim = 20000
  if turtle and turtle.getFuelLimit then
    local okl, v = pcall(turtle.getFuelLimit)
    if okl and type(v) == "number" then lim = v end
  end
  sayf("fuel   : about %d moves for the whole claim, %d coal, %.1f per turtle tank",
    r.moves, math.ceil(r.moves / 80), r.moves / lim)
  local have = turtle and turtle.getFuelLevel() or 0
  sayf("         this turtle holds %s of %d", tostring(have), lim)

  local ms, tot = timeSave(conf.saveSamples)
  sayf("state  : %s, %.2f ms per save, %d ms for %d writes (a move is 400 ms)",
    STATE, ms, tot, conf.saveSamples)
  if ms > 40 then say("         WARNING: that is over a tenth of a move, saving every block will cost you") end

  checkLava()
  auditKit(conf)

  local only = #l.only > 0
  sayf("ore    : %s", only
    and ("only these " .. #l.only .. " blocks")
    or  (conf.oreTags .. " plus " .. #l.oreNames .. " named blocks"))
  sayf("junk   : %d blacklisted blocks, dumped first when a slot is needed", #l.blacklist)
  sayf("fuels  : %s", table.concat(l.fuel, ", "))
  say("build  : phases 1-5 -- mining, depot cycle, three turtles, deploy.")
end

-- movement -----------------------------------------------------------------
-- Phase 2. Position is ABSOLUTE: GPS answers where the turtle is, so
-- tunnel.lua's relative-offset bookkeeping is dropped entirely. st.x/y/z is
-- the block it stands on, st.dir the way it faces, and every move saves both.

local DIRS = { [0] = { 0, 1 }, [1] = { -1, 0 }, [2] = { 0, -1 }, [3] = { 1, 0 } } -- S W N E

-- Never dig one of these: a broken turtle drops its whole inventory on the
-- floor, and a broken chest is the user's storage. Not configurable [plan 8].
-- "lootr" catches the whole Lootr namespace -- lootr:lootr_chest and friends
-- replace generated loot containers (mineshaft chest minecarts included), and
-- a turtle can neither break them nor take from them: the break event is
-- cancelled for a non-sneaking player, and every face exposes zero slots. So
-- they are an obstruction to route around and a coordinate to hand the user.
local DENY = { "turtle", "computer", "disk_drive", "lootr" }

-- Phase 3 lives below the branch code but is needed inside it. Declared here,
-- assigned there.
local makeRoom, dock, watchLava, nextBranch, branchCost, forage, probeDepot, doneKey
local carryingContainer
local giveWay

local halt     = nil    -- why the run stopped, the moment it must stop
local obstacle = nil    -- a deny-list block in the way: ends a leg, not the run
local jammed   = false  -- another turtle held the way past every retry [plan 8]
local jamWhy   = nil    -- and what it was, for the run that gives up on it
local claim    = nil    -- this run's claim, so the routing code can find a mouth
local left     = {}     -- deny-list blocks refused, name -> { n, at } for report
local rejected = {}     -- blocks passed over whose name says "ore" -- pack ids
local tagless  = false  -- true if inspect gave no tags table, so c:ores is blind

local function fuelLevel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

local function protected(name)
  return hasWord(DENY, name) or hasWord(STORAGE, name)
end

local function room()
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then return true end end
  return false
end

local function isFuelItem(l, name)
  for _, n in ipairs(l.fuel) do if n == name then return true end end
  return false
end

-- A bucket is kit, not fuel, even though lava_bucket is on the fuel list.
local function isCoalish(l, name)
  return isFuelItem(l, name) and not tostring(name):find("bucket", 1, true)
end

-- How much of the hold is coal. This is the number that decides whether a find
-- is worth a trip home, so it counts items and not slots.
local function fuelAboard(l)
  local n = 0
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and isCoalish(l, d.name) then n = n + d.count end
  end
  return n
end

-- Burn only what the config calls fuel. turtle.refuel() would happily eat a
-- wooden plank, or the chest the depot needs.
-- ponytail: 1000 is a flat floor, not a computed one -- the ride down is about
-- 400 moves and doubling that is cheaper than threading the claim through here.
local DEPLOY_TANK = 1000

local function topUp(l)
  -- Deployment is not finished while the depot is still in the hold, and the
  -- coal is then the mine's starting stock, not this turtle's tank [plan 13].
  -- Burning it all here strands turtles 2 and 3 at an empty fuel chest, so
  -- only the ride down is taken and the rest is left for the box.
  -- This used to be a once-computed flag: hold the coal back if the tank is
  -- ALREADY above DEPLOY_TANK, burn the stack whole if it is not. A turtle
  -- placed with an empty tank fails that test on its first slot and puts the
  -- mine's whole 192-coal kit into its own tank [in-game 2026-08-28, log
  -- zog32]. What it needs is a partial burn, the same one burnFrom does.
  local holding = carryingContainer()
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and isFuelItem(l, d.name) then
      local n = d.count
      if holding and isCoalish(l, d.name) then
        n = math.max(0, math.min(n, math.ceil((DEPLOY_TANK - fuelLevel()) / 80)))
      end
      if n > 0 then
        turtle.select(s)
        pcall(turtle.refuel, n)
      end
      if n < d.count then
        sayf("fuel   : keeping %d %s for the depot, tank is %d",
          d.count - n, d.name, fuelLevel())
      end
    end
  end
  turtle.select(1)
end

-- The way is clear, or halt says why it will never be. Three guards, none of
-- them optional: never dig into a full inventory (the drop is destroyed and
-- issue #1046 closed that as expected behaviour), never dig the deny list,
-- and keep digging while gravel keeps falling in.
local function clear(dig, detect, inspect)
  -- An empty tank makes turtle.forward() return false exactly as a wall does,
  -- with no error either way. Every move goes through here, so one guard is
  -- what stops a fuel-out reading as "blocked" and the run signing off as
  -- complete with halt unset. calibrate() has the same check for the same reason.
  if fuelLevel() < 1 then
    halt = "out of fuel mid-route -- the tank is empty. Feed me coal and re-run."
    return false
  end
  for _ = 1, 16 do
    if not detect() then return true end
    -- pcall prepends its own success flag, so inspect's two returns land third
    local iok, found, data = pcall(inspect)
    if iok and found and data and protected(data.name) then
      local name, where = tostring(data.name), ("%d,%d,%d"):format(st.x, st.y, st.z)
      local e = left[name] or { n = 0, at = where }
      e.n, left[name] = e.n + 1, e
      obstacle = name
      halt = ("refusing to dig %s beside %s"):format(name, where)
      return false
    end
    if not room() then
      -- the junk tier is the overflow valve: dump a blacklisted stack and carry
      -- on. Only if there is no junk aboard is a full turtle really stuck.
      if not makeRoom(lists) then
        halt = "inventory full -- digging now would destroy the drop"
        return false
      end
    end
    if not dig() then return false end            -- bedrock, or claim protection
    st.dug = (st.dug or 0) + 1
    st.carried = (st.carried or 0) + 1
    if detect() then os.sleep(0.4) end            -- gravel fell in; let the column settle
  end
  return false
end

local function step()
  for _ = 1, 8 do
    if not giveWay() then return false end
    if not clear(turtle.dig, turtle.detect, turtle.inspect) then return false end
    if turtle.forward() then
      local d = DIRS[st.dir]
      st.x, st.z = st.x + d[1], st.z + d[2]
      save()
      return true
    end
    turtle.attack()
  end
  return false
end

local function stepUp()
  for _ = 1, 8 do
    if not giveWay(turtle.detectUp, turtle.inspectUp) then return false end
    if not clear(turtle.digUp, turtle.detectUp, turtle.inspectUp) then return false end
    if turtle.up() then st.y = st.y + 1 save() return true end
    turtle.attackUp()
  end
  return false
end

local function stepDown()
  for _ = 1, 8 do
    if not giveWay(turtle.detectDown, turtle.inspectDown) then return false end
    if not clear(turtle.digDown, turtle.detectDown, turtle.inspectDown) then return false end
    if turtle.down() then st.y = st.y - 1 save() return true end
    turtle.attackDown()
  end
  return false
end

local function turnTo(d)
  d = d % 4
  while st.dir ~= d do
    if (st.dir + 1) % 4 == d then
      turtle.turnRight()
      st.dir = d
    else
      turtle.turnLeft()
      st.dir = (st.dir + 3) % 4
    end
    save()
  end
end

-- Right of way [plan 8]. A turtle in the way cannot be dug, so a 1-wide
-- corridor is a deadlock until one of them leaves it: both blocked, both
-- waiting. The launch index breaks the tie. Nobody can read the other
-- turtle's index -- there is no protocol and the plan wants none -- so the
-- asymmetry has to come from our own, which is exactly what the launch
-- argument is for: index 1 retries soonest and effectively holds the
-- corridor, 2 and 3 wait longer and are the ones that end up moving.
-- Six was not enough: a turtle parked at a trunk stays there for as long as it
-- is stopped, and the one behind it burned its tries in 9 seconds and then
-- routed around into the wrong place [2026-08-29, log 9KJAs]. The waits are
-- scaled by index, so this costs the turtle with right of way the least, and
-- the parking rule above is what makes the wait finite in the first place.
local YIELD_TRIES = 12

local function turtleAt(detect, inspect)
  if not detect() then return false end
  local ok, hit, d = pcall(inspect)
  -- the and-chain used to be compared against nil, so a failed pcall came out
  -- false ~= nil = true and an inspect error read as another turtle
  if not ok or not hit or not d then return false end
  return tostring(d.name):find("turtle", 1, true) ~= nil
end

local function turtleAhead() return turtleAt(turtle.detect, turtle.inspect) end

-- true when the way is ours, false when another turtle held it past every
-- retry. Waits only -- it never moves, because the leg counter and the route
-- both track position and a surprise sidestep would desync them. Moving out
-- of the way is goTo's job, below, where the route is recomputed anyway.
-- Any side, not just the front. All three turtles share one launch block and
-- one depot column, so they meet stacked as often as nose to nose -- and a
-- vertical move had no right of way at all: clear() saw a turtle it may not
-- dig and halted the run outright, which is both of them "stopped" on the
-- depot [user, 2026-08-28, twice].
function giveWay(detect, inspect)
  detect, inspect = detect or turtle.detect, inspect or turtle.inspect
  if not turtleAt(detect, inspect) then return true end
  -- Which side is blocked, so the jam message can name the turtle on it: an
  -- adjacent turtle is a peripheral, and a booted one has labelled itself
  -- quarryN, so its label and its cell turn "another turtle" into "quarry3 at
  -- x,y,z" -- and the three turtles' logs together then say who deadlocked whom
  -- [in-game 2026-08-29, log jGC2X: turtle 2 stopped one block from its own
  -- trunk against an unnamed turtle sitting on its spine].
  local side = (detect == turtle.detectUp and "top")
            or (detect == turtle.detectDown and "bottom") or "front"
  local idx = st.index or 1
  -- Waiting alone cannot resolve a head-on meeting in a 1-wide corridor:
  -- both turtles wait, neither moves, and both give up [in-game 2026-08-29,
  -- logs qhVSH and fPSF1]. Somebody has to reverse, and the retreat is
  -- goTo's job -- so what belongs here is WHEN to stop waiting and let it
  -- happen. Nobody can read the other turtle's index, so the asymmetry has to
  -- come from our own: index 1 waits 9 tries and effectively holds the
  -- corridor, index 3 waits 3 and is the one that ends up moving. That is the
  -- settled "lower wins, higher moves" rule with local knowledge only, and
  -- the index-scaled sleep below still costs the turtle with right of way the
  -- least.
  local tries = math.max(1, YIELD_TRIES - 3 * idx)
  for try = 1, tries do
    sayf("giveway: turtle %d waiting, another one is in the way (%d of %d)",
      idx, try, tries)
    os.sleep(idx * 1.5)
    if not turtleAt(detect, inspect) then return true end
  end
  -- name it now, while the block is still there to be named: "work complete"
  -- was printed for a run that never reached its depot because nothing on the
  -- way up knew what had stopped it.
  local okj, hitj, dj = pcall(inspect)
  local what = (okj and hitj and dj and tostring(dj.name)) or "another turtle"
  -- Read the blocker's own label and work out which cell it is in, so the log
  -- says WHICH turtle and WHERE rather than only that one was there.
  -- Through periph(), not a bare pcall: a neighbour that is not yet visible as
  -- a peripheral is CC:Tweaked #660, which this file already handles elsewhere,
  -- and a bare pcall would put "No peripheral attached to front side" in
  -- `label` and print that as the blocker's name.
  local label = periph(peripheral.call, side, "getLabel")
  local who = (type(label) == "string" and label ~= "") and label or "unlabelled"
  local bx, by, bz = st.x, st.y, st.z
  if side == "top" then by = by + 1
  elseif side == "bottom" then by = by - 1
  else local d = DIRS[st.dir]; bx, bz = st.x + d[1], st.z + d[2] end
  jammed = true
  jamWhy = ("%s (%s) at %d,%d,%d would not move out of the way after %d tries -- it "
    .. "is another turtle, not a block I may dig; I am at %d,%d,%d")
    :format(what, who, bx, by, bz, tries, st.x, st.y, st.z)
  return false
end

-- Pull off the corridor so the other turtle can pass. A branch mouth every 5
-- blocks along the spine is the passing bay [plan 8].
--
-- Stepping back ONE block was not a retreat: it left the turtle in the
-- corridor, so two turtles meeting head-on on the spine both "moved aside"
-- and neither could get past [in-game 2026-08-29, logs qhVSH and fPSF1].
-- Walk backwards along the spine instead, away from the blocker, until a
-- branch mouth is underfoot, then turn into it. Backwards rather than
-- turning round, so we keep facing the blocker and the caller's retry sees
-- the moment it leaves; and the mouth is a row that gets mined anyway, so the
-- retreat costs nothing. A bay is at most 5 blocks away by construction.
local RETREAT_MAX = 5

local function stepAside()
  jammed = false
  local c = claim
  if c and st.y == (st.level or st.y) and st.x == c.spine then
    for back = 0, RETREAT_MAX do
      if isBranch(c, st.y, st.z) then
        turnTo(1)                  -- west into the mouth: a row that gets mined anyway
        if step() then
          -- only worth saying when it really reversed: a turtle already
          -- standing on a branch row is the parking case, which says its own
          -- line
          if back > 0 then
            sayf("giveway: pulled back %d blocks to the branch mouth at %d,%d,%d "
              .. "so the other one can pass", back, st.x, st.y, st.z)
          end
          return true
        end
        break                      -- the mouth will not open either: reverse instead
      end
      local v = DIRS[st.dir]
      if not turtle.back() then break end
      st.x, st.z = st.x - v[1], st.z - v[2]
      save()
    end
  end
  -- off the spine, or no bay would open: one block back is better than nothing
  local d = DIRS[st.dir]
  if turtle.back() then
    st.x, st.z = st.x - d[1], st.z - d[2]
    save()
    return true
  end
  return false
end

-- y first, then x, then z. Descending in place before travelling is what keeps
-- the walk to the trunk below topY, where the user's surface builds are not.
-- A jam on the way is not a failure while there is still somewhere to pull
-- aside to: step out of the corridor and let the loop route around it.
-- A deny-listed block in a travel corridor used to end the whole run: clear()
-- sets halt, goTo hands the false up, and the work loop breaks on it. Lootr
-- chests are common and there are usually several, so a mine could stop on its
-- first one. Step onto the corridor one block over and drive at the target
-- again; the loop re-runs the axis from the new column, which is the go-around.
-- Bounded, because a turtle that keeps sidestepping is not making progress.
local DETOUR_TRIES = 8

-- Never sidestep out of the claim. The claim is the chunk region the
-- player keeps loaded, so a detour past its border digs a neighbour's ground
-- and walks into chunks that may not be ticking.
local function inClaim(x, z)
  local c = claim
  if not c then return true end
  return x >= c.xMin and x <= c.xMax and z >= c.zMin and z <= c.zMax
end

local function goTo(tx, ty, tz)
  local aside = 0
  local function blocked()
    -- stepAside() clears jammed on the way in, so read it before calling it
    local wasJam = jammed
    if jammed and aside < 3 then
      aside = aside + 1
      if stepAside() then return false end
    end
    -- A walk that ran out of retreats did not finish, and nothing above here
    -- knew that: dock() handed the false up, the work loop broke with halt
    -- unset, and report() printed "work complete" for a turtle that never
    -- reached its depot [in-game 2026-08-29, logs qhVSH and fPSF1]. Reaching
    -- the depot and failing is a stop, and it says what stopped it.
    if wasJam and not halt then
      halt = jamWhy or "another turtle held the way and would not move"
    end
    return true
  end

  local detours = 0
  -- Sidestep off the blocked corridor, then one block PAST the obstacle. The
  -- second half is not optional: the loop drives the other axis first, so a
  -- turtle that only stepped aside is walked straight back into the same
  -- block on the next pass and never gets anywhere. Prefer the side the
  -- target is on. Returns false for anything that is not a deny-list block,
  -- so a jam or an empty tank still reaches blocked() as before.
  local function detour(axis)
    if not obstacle or detours >= DETOUR_TRIES then return false end
    detours = detours + 1
    local why, was = halt, obstacle
    halt, obstacle = nil, nil
    sayf("around : %s at %d,%d,%d -- taking the corridor one over (%d of %d)",
      was, st.x, st.y, st.z, detours, DETOUR_TRIES)

    local function go(d)
      local v = DIRS[d]
      if not inClaim(st.x + v[1], st.z + v[2]) then return false end
      turnTo(d)
      if step() then return true end
      -- that way is a deny-list block too: forget it and try the other one
      if obstacle then halt, obstacle = nil, nil end
      return false
    end

    -- goX and goZ only fail while there is still ground to make on their own
    -- axis, so the way past is always the way the loop was already going.
    local past = (axis == "x") and ((tx > st.x) and 3 or 1)
                                or ((tz > st.z) and 0 or 2)
    local a, b
    if axis == "x" then                       -- blocked going along x, so shift z
      a, b = (tz > st.z) and 0 or 2, (tz > st.z) and 2 or 0
    else                                      -- blocked going along z, so shift x
      a, b = (tx > st.x) and 3 or 1, (tx > st.x) and 1 or 3
    end
    for _, side in ipairs({ a, b }) do
      -- one over is progress whether or not the way past opens: the next pass
      -- starts from a different column, and detours are capped either way
      if go(side) then go(past) return true end
    end
    -- boxed in on both sides, or out of fuel mid-detour: hand the reason back
    if not halt then halt, obstacle = why, was end
    return false
  end
  local function goX()
    while st.x ~= tx do
      turnTo(st.x < tx and 3 or 1)
      if not step() then return false end
    end
    return true
  end
  local function goZ()
    while st.z ~= tz do
      turnTo(st.z < tz and 0 or 2)
      if not step() then return false end
    end
    return true
  end
  while st.y > ty do if not stepDown() then return false end end
  while st.y < ty do if not stepUp()   then return false end end
  while st.x ~= tx or st.z ~= tz do
    -- The spine is the corridor and the branches hang off it. Leaving a spine
    -- block sideways walks straight into whatever stands beside it -- which,
    -- at the trunk floor, is the depot chest. Travel z along the spine first
    -- and turn into the branch; anywhere else x is the corridor.
    local first, second, fa, sa = goX, goZ, "x", "z"
    if claim and st.x == claim.spine then first, second, fa, sa = goZ, goX, "z", "x" end
    local axis, ok = fa, first()
    if ok then axis, ok = sa, second() end
    if not ok and not detour(axis) and blocked() then return false end
  end
  return true
end

-- GPS gives position and never facing, so derive the facing once by moving a
-- block and comparing fixes. Two moves, once per boot.
local function calibrate(conf)
  local x0, y0, z0, how = locate(conf)
  if not x0 then return false, "no GPS fix" end

  -- startX/Y/Z pins locate() to a constant, so the second reading below is the
  -- same as the first however far the turtle actually moved, dx and dz are both
  -- nought, and no direction matches. Catch it here rather than after the move:
  -- "calibration moved 0,0" describes the symptom and hides the cause, and it
  -- cost a live run on 2026-08-28. --check warns about this too, but a run
  -- started with `quarry 1` never sees --check.
  -- With the position pinned, the heading has to be told rather than measured.
  -- Everything after this point dead-reckons anyway -- locate() is only called
  -- at boot, resume and deploy -- so a stated heading is enough to mine on.
  -- What it costs is recovery: a turtle that loses its saved state cannot find
  -- itself again, so fixing GPS is still the better answer.
  -- The saved fix comes with a saved heading, which is the whole reason it is
  -- usable where a config pin is not: nothing has to be told, only trusted.
  if how == "quarry.state" then
    sayf("heading: %s from quarry.state -- no GPS fix here, resuming on the saved",
      ({ [0] = "+z", [1] = "-x", [2] = "-z", [3] = "+x" })[st.dir])
    say("         position. If somebody moved me since, this is wrong: delete")
    say("         quarry.state and start me somewhere GPS answers.")
    return true
  end

  if how == "quarry.conf" then
    if not conf.startDir then
      return false, "quarry.conf sets startX/startY/startZ, which pins my position "
        .. "to a constant -- I cannot find my heading by moving if my coordinates "
        .. "never change. Either fix GPS and delete those three lines, or add "
        .. "startDir = 0, 1, 2 or 3 for the way I am facing (+z, -x, -z, +x)."
    end
    st.dir = conf.startDir
    save()
    sayf("heading: %s from quarry.conf startDir, not measured -- GPS is not answering",
      ({ [0] = "+z", [1] = "-x", [2] = "-z", [3] = "+x" })[st.dir])
    return true
  end

  -- turtle.forward() returns false on an empty tank exactly as it does against
  -- a wall, with no error either way. Without this check the loop below reads
  -- an empty tank as "blocked", turns a full circle looking for a way out, then
  -- blames the walls. Say what is actually wrong.
  if fuelLevel() < 1 then
    return false, "out of fuel -- I cannot move one block to find my heading. Feed me coal."
  end

  local moved = false
  for _ = 1, 4 do
    if turtle.forward() then moved = true break end
    turtle.turnRight()
  end
  if not moved then
    if not clear(turtle.dig, turtle.detect, turtle.inspect) then
      return false, halt or "boxed in on all four sides"
    end
    if not turtle.forward() then return false, "cannot move one block to find my heading" end
  end
  local x1, _, z1 = locate(conf)
  if not x1 then return false, "lost the GPS fix mid-calibration" end
  local backOk = turtle.back()
  st.x, st.y, st.z = backOk and x0 or x1, y0, backOk and z0 or z1
  local dx, dz = x1 - x0, z1 - z0
  for d, v in pairs(DIRS) do
    if v[1] == dx and v[2] == dz then st.dir = d save() return true end
  end
  return false, ("calibration moved %d,%d, which is not one block"):format(dx, dz)
end

-- ore ----------------------------------------------------------------------
-- c:ores plus the configured names. No name:find("ore") fallback [plan 6] --
-- that is what makes a turtle chase things you did not mean. Blocks rejected
-- whose name does contain "ore" are logged instead, and printed at the end:
-- that is how the config learns what this pack calls things.

local function isOre(data, l, conf)
  if not data or not data.name then return false end
  if #l.only > 0 then
    for _, n in ipairs(l.only) do if n == data.name then return true end end
    return false
  end
  for _, n in ipairs(l.oreNames) do if n == data.name then return true end end
  if data.tags then
    if data.tags[conf.oreTags] then return true end
  else
    tagless = true
  end
  return false
end

local function noteRejected(data)
  if data and data.name and tostring(data.name):find("ore") then
    rejected[data.name] = (rejected[data.name] or 0) + 1
  end
end

-- Depth-first through a vein, capped by veinMax blocks and veinDepth steps off
-- the branch. Absolute position means there is no unwind to get wrong: after
-- each child the turtle simply walks back to the cell it came from.
local function chase(depth, l, conf)
  if halt or depth <= 0 or st.chased >= conf.veinMax then return end
  local px, py, pz = st.x, st.y, st.z
  local d0 = st.dir

  -- A vein does not stop at the claim rim and chase() used to follow it out:
  -- veinDepth is 12, so a vein off a rim branch walked the turtle twelve blocks
  -- into the neighbouring claim -- ground nobody is keeping loaded, and outside
  -- the claim the player holds open by standing in the centre chunk. Upward it is
  -- worse: past topY is the user's surface builds, which topY exists to protect.
  -- There is no floor to match it: bottomY is where the TRUNK stops, and
  -- bedrock scatters up to -60, so the ore worth having at the bottom of the
  -- mine is under bottomY by definition. A failed dig on bedrock is the floor.
  -- Every other mover is already bounded -- a leg ends at c.west/c.east, the
  -- spine and trunk are interior, the goTo detour asks inClaim -- so this was
  -- the one way out. Look at the ore, do not follow it.
  local function reachable(move)
    local nx, ny, nz = st.x, st.y, st.z
    if move == stepUp then ny = ny + 1
    elseif move == stepDown then ny = ny - 1
    else
      local v = DIRS[st.dir]
      nx, nz = nx + v[1], nz + v[2]
    end
    return inClaim(nx, nz) and ny <= conf.topY
  end

  local function into(move)
    if halt or st.chased >= conf.veinMax then return end
    if not reachable(move) then return end
    if not move() then return end
    st.chased = st.chased + 1
    save()
    chase(depth - 1, l, conf)
    if not halt then goTo(px, py, pz) end
  end

  local function look(inspect, move)
    if halt then return end
    local ok, found, data = pcall(inspect)
    if ok and found and data then
      if isOre(data, l, conf) then into(move) else noteRejected(data) end
    end
  end

  look(turtle.inspectUp, stepUp)
  look(turtle.inspectDown, stepDown)
  -- goTo turns to face the direction it travels, so after a chase into a side
  -- branch st.dir is whatever the walk home needed, not what this cell started
  -- on. A relative turnTo(st.dir + 1) then rotates from the wrong base and the
  -- sweep re-checks one face while never looking at another. Anchor it to d0.
  for i = 0, 3 do
    turnTo(d0 + i)
    look(turtle.inspect, step)
    if halt then return end
  end
end

-- the mine -----------------------------------------------------------------

-- Home is the depot once one has been found, and the launch block until then:
-- the reserve has to cover the walk to wherever the fuel actually is.
local function toHome()
  local h = st.depot or st.home
  return math.abs(st.x - h.x) + math.abs(st.y - h.y) + math.abs(st.z - h.z)
end

-- Stop while there is still fuel to stop safely.
local function reserveOk(conf)
  return fuelLevel() >= toHome() + conf.fuelMargin + 4
end

-- Whose box is this. Change 30 gave every turtle a depot under its own trunk,
-- so the ordinary case is a box no other turtle ever visits, and only
-- findSharedDepot ever writes own = false.
--
-- The test is against false and never against truthiness: every quarry.state
-- in the world was written before this field existed, and every one of those
-- turtles built or probed its own box, so an old file has to fall on the
-- private side. That is the lesson of the deployed/staffed mistake, taken the
-- other way round.
local function ownDepot()
  return not st.depot or st.depot.own ~= false
end

-- Coal in the hold is fuel first and cargo second. Burn the least that reaches
-- the target -- never the stack, or a rich find ends up in one turtle's tank
-- instead of in the chest the other two draw from. Every place that judges the
-- tank low calls this first, so a turtle never stops sitting on its own fuel.
local function burnFrom(l, target)
  local burnt = 0
  for s = 1, 16 do
    if fuelLevel() >= target then break end
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and isCoalish(l, d.name) then
      local n = math.min(d.count, math.ceil((target - fuelLevel()) / 80))
      turtle.select(s)
      local okr, did = pcall(turtle.refuel, n)
      if okr and did then burnt = burnt + n end
    end
  end
  turtle.select(1)
  if burnt > 0 then sayf("fuel   : burnt %d coal from the hold, tank %d", burnt, fuelLevel()) end
  return burnt
end

-- Coal the turtle dug is worth more in the tank than in a box only that same
-- turtle can open. At its own depot there is nobody to save it for, so the
-- tank is topped up to conf.fuelKeep and only the overflow is banked; at a
-- shared box the coal still rides home unburnt, because there the sharing rule
-- is the whole point [RESUME correction, "no burn-it-where-you-find-it"].
--
-- Called at the end of a leg and at a dock, never per dug block: that is a
-- 16-slot getItemDetail scan on every one of a run's few thousand blocks, to
-- catch a seam a leg meets once. A leg is 24 blocks, so coal never rides long.
local function keepFuel(conf, l)
  if not ownDepot() then return 0 end
  local keep = conf.fuelKeep or 0
  if fuelLevel() >= keep then return 0 end
  return burnFrom(l, keep)
end

-- Down the trunk. Above topY there is nothing to mine, so those blocks are
-- travel and not work: no vein chase, no branch, nothing counted as mining.
-- The real floor is a failed dig on bedrock; bottomY is only the safety stop.
local function descend(target)
  while st.y > target do
    if not stepDown() then
      if halt then return false end
      local ok, found, data = pcall(turtle.inspectDown)
      if ok and found and data and tostring(data.name):find("bedrock") then
        st.floor = st.y
        save()
        return true, "bedrock"
      end
      halt = ("cannot descend past y=%d"):format(st.y)
      return false
    end
  end
  return true
end

-- The nearest unmined branch row to the trunk, inside this turtle's third.
-- Phase 4 adds "an air mouth is already taken"; Phase 2 is one turtle alone.
local function pickBranch(c, level, lo, hi, from)
  for d = 0, math.max(from - lo, hi - from) do
    for _, z in ipairs({ from - d, from + d }) do
      if z >= lo and z <= hi and isBranch(c, level, z) then return z end
    end
  end
end

-- "An air mouth is already taken" [plan 4]: the claim protocol, and there is
-- none -- one inspect at the mouth, no rednet, no disk, no hub. Called only
-- on a fresh claim: a turtle resuming its own half-mined branch would read its
-- own work as somebody else's and skip it forever. A natural cave at the mouth
-- costs one skipped branch, which is the same price the plan already accepts
-- for two turtles claiming the same row.
local function mouthTaken()
  for _, d in ipairs({ 1, 3 }) do
    turnTo(d)
    if not turtle.detect() then return true end
  end
  return false
end

-- One leg of a branch, cut outward from the spine to the claim rim or inward
-- from the rim back to the spine, chasing veins on the way. st.along is the
-- resume point either way: blocks from the spine, saved on every block.
-- A block that must not be dug ends this leg, not the whole run. Lootr
-- containers are the common case and there are usually several of them.
-- Where the turtle goes when a leg ends is the work loop's business, not this
-- one's: the next leg of the pair starts at the rim as often as at the spine.
local function endLeg()
  if not obstacle then return false end
  sayf("blocked: %s at %d out -- leaving it and ending this leg", obstacle, st.along)
  halt, obstacle = nil, nil
  return true
end

local function mineLeg(c, conf, l, leg, inward)
  local dir = (leg == "west") and 1 or 3
  if inward then dir = (dir + 2) % 4 end
  local len = (leg == "west") and c.west or c.east
  st.leg, st.task = leg, "branch"
  save()
  while (inward and st.along > 0) or (not inward and st.along < len) do
    if not reserveOk(conf) then burnFrom(l, toHome() + conf.fuelMargin + 4) end
    if not reserveOk(conf) then
      -- The turtle is only up here BECAUSE the depot was dry, so spending the
      -- last of the tank walking 119 blocks back down to it buys nothing but
      -- the walk. Stop, and let the park walk it to the top of its own trunk
      -- where the player can reach it.
      if st.foraging then
        halt = ("out of coal: %d fuel left and the depot was already dry")
          :format(fuelLevel())
        return false
      end
      -- with a depot to walk to, low fuel is a trip home, not a stop; without
      -- one, stopping here is the only safe answer [plan 7, never strand]
      if st.depot then
        st.needDock = true
        save()
        return false
      end
      halt = ("fuel reserve: %d left, %d to walk home"):format(fuelLevel(), toHome())
      return false
    end
    -- Full, carrying a trip's worth, or sitting on a fuel find the other two
    -- turtles could be burning: stop here and let the loop dock. The leg
    -- position is already saved, so the walk back resumes exactly here.
    -- Spare coal only counts when there is a depot to bank it INTO. Without
    -- one it is simply fuel this turtle burns itself, and flagging a dock over
    -- it stopped a run with a full tank and a nearly empty hold dead [in-game
    -- 2026-08-28, log Rpv9m]. The full hold and the tripBlocks trip are real
    -- either way: with nowhere to empty out, mining on only destroys the drops.
    -- Foraging at the top level, a full hold is junk to drop and not a reason
    -- to walk 119 blocks down: the round trip costs more than the branch that
    -- sent the turtle up here. Only ore in a hold with no room left goes home.
    if st.foraging and not room() then makeRoom(l) end
    if not room()
       or (not st.foraging and (st.carried or 0) >= conf.tripBlocks)
       or (st.depot and not ownDepot() and fuelAboard(l) >= conf.fuelShare) then
      st.needDock = true
      save()
      return false
    end
    turnTo(dir)
    if not step() then
      -- a jam is not an obstacle: give this branch up, dock, and re-pick.
      -- A wasted trip beats a stuck turtle [plan 8].
      if jammed then
        jammed = false
        -- The leg is given up, not the row: the rest of the pair routes through
        -- the corridor that is still held, so the plan goes back on the pile,
        -- but the other leg of this row is clear and st.cut remembers which is
        -- which. Writing the whole row off is what the mouth check used to do,
        -- and it cost the far leg every time [in-game 2026-08-28].
        local k = doneKey(st.level, st.branch)
        st.cut = st.cut or {}
        st.cut[k] = st.cut[k] or {}
        st.cut[k][st.leg] = true
        if st.cut[k].west and st.cut[k].east then
          st.done = st.done or {}
          st.done[k], st.cut[k] = true, nil
        end
        st.needDock, st.branch, st.plan, st.step = true, nil, nil, nil
        save()
        sayf("giveway: the way is still held -- giving that leg up and re-picking")
        return false
      end
      if not endLeg() then return false end
      break
    end
    st.along = st.along + (inward and -1 or 1)
    save()
    watchLava(conf, l)
    -- veinMax caps ONE chase. st.chased is the counter chase() tests, so it
    -- resets here; st.veined keeps the run total the report prints.
    st.chased = 0
    chase(conf.veinDepth, l, conf)
    st.veined = (st.veined or 0) + st.chased
    if halt then
      if not endLeg() then return false end
      break
    end
  end
  keepFuel(conf, l)
  return true
end

-- depot --------------------------------------------------------------------
-- Phase 3. The depot is found, never configured. Standing on the trunk floor
-- the turtle looks at all four sides for a container, then takes one item out
-- of each and puts it straight back to learn which one holds fuel. Both
-- coordinates go in the state file, so the probe happens once per claim and a
-- killed turtle picks up where it left off.

-- The shared lava map lives on the floppy, wherever the drive says it is
-- mounted -- "/disk" is only the first drive's name.
local function lavaMap()
  local d = diskPath()
  return d and (d .. "/lava.txt") or nil
end
local LAVA_KEEP = 64             -- sources held in the state file between docks
local function isContainer(name)
  if tostring(name):find("lootr", 1, true) then return false end  -- loot, not storage
  return hasWord(STORAGE, name)
end

-- The depot lives UNDER the trunk floor, so "down" is a direction alongside
-- 0..3 everywhere st.depot is read. A hand-placed container beside the floor
-- still works and still reads as 0..3; only what this program builds goes below.
local function faceDepot(dir)
  if dir ~= "down" then turnTo(dir) end
end
local function depotDrop(dir) return dir == "down" and turtle.dropDown or turtle.drop end
local function depotSuck(dir) return dir == "down" and turtle.suckDown or turtle.suck end

-- Deployment kit never goes into the depot. Turtle 1 carries turtles 2 and 3,
-- their modems, drives, floppies and the depot container itself down with it,
-- and a dump that reads them as spoil posts the other two turtles into a barrel
-- [in-game 2026-08-28: it did exactly that]. Buckets were already kit; this is
-- the same rule with the rest of the kit named.
local KIT_NAMES = { "turtle", "computer", "disk", "modem", "bucket" }
local function isKit(name)
  return hasWord(KIT_NAMES, name) or isContainer(name)
end

local function freeSlot()
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then return s end end
end

local function carrying()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) > 0 then n = n + 1 end end
  return n
end

-- Dump the junk tier to make one slot, so a full turtle mid-vein can finish
-- the block it is standing on instead of walking away from it [plan 6, 8].
-- The junk lands on the tunnel floor; it is junk, and it despawns.
local function isJunk(l, name)
  for _, n in ipairs(l.blacklist) do if n == name then return true end end
  return false
end

function makeRoom(l)
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and isJunk(l, d.name) then
      turtle.select(s)
      local dropped = select(2, pcall(turtle.drop))
      turtle.select(1)
      if dropped then
        st.junked = (st.junked or 0) + d.count
        save()
        return true
      end
    end
  end
  return false
end

-- Which way is the depot: look at all four sides for a container. Called
-- standing on the trunk floor, once, and the answer is saved.
function probeDepot(l)
  local spots = {}
  -- below first: that is where this program builds, and a container there is
  -- the only one the mining pattern can never walk into.
  local okd, hitd, dd = pcall(turtle.inspectDown)
  if okd and hitd and dd and isContainer(dd.name) then spots[#spots + 1] = "down" end
  for d = 0, 3 do
    turnTo(d)
    local ok, hit, data = pcall(turtle.inspect)
    if ok and hit and data and isContainer(data.name) then spots[#spots + 1] = d end
  end
  if #spots == 0 then return false end

  local dump, fuelDir = nil, nil
  for _, d in ipairs(spots) do
    faceDepot(d)
    local slot = freeSlot()
    local role = "dump"
    if slot then
      turtle.select(slot)
      local ok, got = pcall(depotSuck(d), 1)
      if ok and got then
        local oki, item = pcall(turtle.getItemDetail, slot)
        if oki and item and isCoalish(l, item.name) then role = "fuel" end
        pcall(depotDrop(d))         -- straight back where it came from
      else
        role = "empty"              -- nothing in it yet; it can be the dump chest
      end
      turtle.select(1)
    end
    if role == "fuel" then fuelDir = fuelDir or d
    else dump = dump or d end
  end
  -- one chest only: it is both. Two or more: the one with coal in it feeds.
  st.depot = { x = st.x, y = st.y, z = st.z, dump = dump or fuelDir, fuel = fuelDir or dump,
               own = true }
  save()
  return true
end

-- Phase 5, the other half [plan 13]: if the turtle carried the depot down with
-- it, it builds the depot rather than hoping the user placed one. Called once,
-- standing on the trunk floor, before probeDepot -- which then learns the two
-- chests the ordinary way, by taking an item out of each.
function carryingContainer()
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and isContainer(d.name) then return true end
  end
  return false
end

-- A turtle item in the hold means the mine is not staffed yet: turtles 2 and 3
-- ride down with the kit and never work unless somebody deploys them.
local function carryingTurtle()
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and tostring(d.name):find("turtle", 1, true) then return true end
  end
  return false
end

local function buildDepot(l, c, conf)
  -- One container, in the one block beside the trunk that the mining pattern
  -- never enters.
  --
  -- Under the trunk floor is the first choice and the best one: nothing is ever
  -- dug below the bottom level. But bedrock scatters up through y=-60 and the
  -- floor stands at y=-59, so the block below it is usually bedrock and simply
  -- will not open [in-game 2026-08-28, log Rpv9m: "the floor under the trunk
  -- will not open -- no depot built", and then a run with nowhere to bank].
  --
  -- The fallback is beside the trunk one level UP, on an x side. Never beside
  -- the floor itself: all four of ITS neighbours are working rows -- the legs
  -- run east-west through them, the spine north-south -- so a container there
  -- is a block the pattern later walks into and refuses to dig [in-game
  -- 2026-08-28, log 45bPE: turtle 1 lost the branch it was standing on to one
  -- chest and the spine to the other]. One level up, +z/-z is still the spine,
  -- but the east-west legs only cross the trunk's own z on the levels where
  -- isBranch says so, and a row never repeats on the next level -- it shifts 2
  -- in z per level, mod 5 -- so a free level is at most two up.
  local slot
  for sl = 1, 16 do
    local ok, item = pcall(turtle.getItemDetail, sl)
    if ok and item and isContainer(item.name) then slot = sl break end
  end
  if not slot then return 0 end

  -- It goes under THIS turtle's OWN trunk, one box per turtle. It used to be
  -- one box for the whole mine, at the middle trunk -- and that made every
  -- dock from every turtle end at the same block, down a spine that is one
  -- block wide with a passing place only every 5. Turtle 1 walking +z and
  -- turtle 2 walking -z met head-on, giveWay only ever waits, so both waited
  -- and neither moved [in-game 2026-08-29, logs qhVSH and fPSF1: twelve
  -- give-ways each and then "work complete" on a run that had banked nothing].
  -- With a box under its own trunk no turtle has to leave its own third to
  -- bank at all, so the meetings stop rather than being recovered from. The
  -- kit decides: a turtle carrying a container builds one, a turtle with none
  -- falls back to findSharedDepot and the others' boxes, which is exactly the
  -- behaviour that was already there.
  --
  -- It has to be ON the trunk floor, never wherever a walk gave up:
  -- findSharedDepot visits TRUNK FLOORS and nothing else, so a container one
  -- block short of one is a container no other turtle will ever find -- which
  -- is what z=118 was in log 9KJAs.
  local h1 = halt
  local _, _, ownZ = thirdOf(c, st.index or 1, conf.turtles or 1)
  if st.z ~= ownZ then
    sayf("depot  : the depot belongs at a trunk floor -- walking to z=%d", ownZ)
    if not goTo(c.spine, st.y, ownZ) then
      halt = h1
      sayf("depot  : cannot reach z=%d", ownZ)
    end
  end
  if st.z ~= ownZ then
    sayf("depot  : I am at z=%d, which is not a trunk. Building here anyway, but", st.z)
    say("         the other turtles sweep trunk floors, so they will not find it.")
    say("         Move me onto a trunk and delete quarry.state to redo this.")
  end

  local tx, ty, tz = st.x, st.y, st.z
  local spots = { { y = ty, dir = "down" } }
  for off = 1, 3 do
    if not isBranch(c, ty + off, tz) then
      spots[#spots + 1] = { y = ty + off, dir = 1 }   -- -x
      spots[#spots + 1] = { y = ty + off, dir = 3 }   -- +x
      break
    end
  end

  -- clear() sets halt when it meets a deny-list block, and a neighbour it
  -- cannot open is a reason to try the next spot, not to end the run.
  local h0 = halt
  for _, sp in ipairs(spots) do
    if (st.y == sp.y or goTo(tx, sp.y, tz)) then
      local dig, detect, inspect, place
      if sp.dir == "down" then
        dig, detect, inspect, place =
          turtle.digDown, turtle.detectDown, turtle.inspectDown, turtle.placeDown
      else
        turnTo(sp.dir)
        dig, detect, inspect, place =
          turtle.dig, turtle.detect, turtle.inspect, turtle.place
      end
      if clear(dig, detect, inspect) then
        turtle.select(slot)
        local lived, put = pcall(place)
        turtle.select(1)
        if lived and put ~= false then
          if sp.dir == "down" then
            say("depot  : placed a container under the trunk floor")
          else
            sayf("depot  : the floor under the trunk will not open -- placed a "
              .. "container beside the trunk at y=%d instead", sp.y)
          end
          -- probeDepot never sees this one: it looks from the trunk floor and
          -- this may be a level up. One box is both roles, which is the case
          -- restock is already written for.
          st.depot = { x = st.x, y = st.y, z = st.z, dump = sp.dir, fuel = sp.dir, own = true }
          save()
          -- Everything burnable this turtle still carries goes in, and from
          -- here on it rations out of it [plan 7]. With a box each a find by
          -- turtle 1 can no longer be burnt by turtle 3, which is the accepted
          -- cost of the per-turtle depot: the ration still rations from
          -- whatever box this turtle is docked at, and the per-other-turtle
          -- floor is now conservative rather than wrong.
          local banked = 0
          local drop = depotDrop(sp.dir)
          faceDepot(sp.dir)
          for sl = 1, 16 do
            local ok, item = pcall(turtle.getItemDetail, sl)
            if ok and item and isFuelItem(l, item.name) then
              turtle.select(sl)
              if select(2, pcall(drop)) ~= false then banked = banked + item.count end
            end
          end
          turtle.select(1)
          if banked > 0 then sayf("depot  : banked %d fuel into it", banked) end
          halt = h0
          return 1
        end
      end
    end
    halt = h0
  end
  say("depot  : nothing beside the trunk will open -- no depot built")
  return 0
end

local function dumpLoad(l)
  local dp  = st.depot
  local dir = dp and dp.dump
  if not dir then return false, "no container at the trunk floor" end
  faceDepot(dir)
  local drop = depotDrop(dir)
  -- A depot that will not take another stack used to end the run outright, and
  -- what fills it is the junk tier -- stone, deepslate, gravel. So when a drop
  -- comes back false the junk goes on the tunnel floor instead and the run
  -- carries on; only ore, which is the point of the exercise, is worth stopping
  -- over. The player is told, because emptying it is the one thing this turtle
  -- cannot do for itself.
  local floorDrop = (dir == "down") and turtle.drop or turtle.dropDown
  local full = false
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and not isFuelItem(l, d.name) and not isKit(d.name) then
      turtle.select(s)
      local dropped = select(2, pcall(drop))
      if dropped then
        st.hauled = (st.hauled or 0) + d.count
      else
        full = true
        if not (isJunk(l, d.name) and select(2, pcall(floorDrop))) then
          turtle.select(1)
          notify("depot", ("the depot at %d,%d,%d is FULL and I am holding ore -- come and empty it")
            :format(dp.x, dp.y, dp.z))
          return false, "the depot chest is full"
        end
        st.junked = (st.junked or 0) + d.count
      end
    end
  end
  turtle.select(1)
  if full then
    notify("depot", ("the depot at %d,%d,%d is FULL -- junk is going on the tunnel floor, come and empty it")
      :format(dp.x, dp.y, dp.z))
  end
  st.carried = 0
  save()
  return true
end

-- Ration the chest: at most a third per visit and never the last few, so the
-- first turtle to dock cannot starve the other two [plan 7]. A turtle cannot
-- read a chest it is not wired to, so the count is learned by taking: pull the
-- lot, keep the share, put the rest straight back. Burn on pickup, carry none.
local function restock(conf, l, want)
  local dir = st.depot and st.depot.fuel
  if not dir then return 0, 0 end
  faceDepot(dir)
  local suck, drop = depotSuck(dir), depotDrop(dir)
  local before = fuelLevel()
  local aboard = fuelAboard(l)   -- the find; whatever is not burnt is banked

  for _ = 1, 16 do
    local slot = freeSlot()
    if not slot then break end
    turtle.select(slot)
    local ok, got = pcall(suck)
    if not (ok and got) then break end
  end

  local total = 0
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and isCoalish(l, d.name) then total = total + d.count end
  end

  -- Take what this trip actually needs, and at this turtle's own box hold
  -- nothing back at all. There used to be a floor of conf.fuelFloor per OTHER
  -- turtle, written when the mine had one shared depot and the first turtle to
  -- dock could starve the other two. Change 30 gave every turtle a box under
  -- its own trunk, and a reserve in a box nobody else ever opens is coal
  -- nobody can spend: both turtles stopped dead with 16 coal one block away
  -- and 93 fuel in the tank [in-game 2026-08-29, logs E5wWw and hkgWh].
  --
  -- A SHARED box is still rationed, by a per-dock cap rather than a floor. A
  -- cap divides the box across visits without stranding any of it, and it is
  -- in coal, the same unit `want` is in.
  local keep = math.min(total, math.max(want, 0))
  if not ownDepot() then
    keep = math.min(keep, math.max(0, conf.sharePerDock or 0))
  end
  -- Everything that came aboard goes back except the share that gets burnt --
  -- including the load just dumped, because with one chest at the depot the
  -- fuel and the spoil live in the same box and the suck cannot tell them
  -- apart. Kit -- buckets, the spare container, turtles 2 and 3 and their
  -- modems, drives and floppies -- never leaves.
  local burnt = 0
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and not isKit(d.name) then
      turtle.select(s)
      if isCoalish(l, d.name) and burnt < keep then
        local n = math.min(d.count, keep - burnt)
        pcall(turtle.refuel, n)
        burnt = burnt + n
      end
      if turtle.getItemCount(s) > 0 then pcall(drop) end
    end
  end
  turtle.select(1)
  st.shared = (st.shared or 0) + math.max(0, aboard - burnt)
  save()
  return fuelLevel() - before, total
end

-- Change 47, a measurement and not a fix. `turtle.suck` only ever pulls the
-- container's FIRST slot, so restock learns the chest by taking, sixteen
-- stacks at a time -- and the user's depot is bigger than the default 27
-- slots, which buries coal banked behind the spoil. A wrap can READ the whole
-- box, but pushItems/pullItems address peripherals by name and a turtle has no
-- name for itself, so it cannot TAKE from slot 40 either way.
--
-- What this settles is whether the read is available at all: the peripherals
-- dump this pack is written against was taken from a COMPUTER, and a turtle's
-- own sides are its upgrades. Once per run, costing nothing when it fails.
-- ANSWERED in-game 2026-08-29 [logs yiALS and PwHyZ]: a turtle CAN wrap the
-- container it is facing. The user's depot came back as a 132-slot box, and
-- this is the only way a turtle sees past the first sixteen stacks of it.
-- Still read-only -- the take is `turtle.suck`, which only ever pulls the
-- first slot -- but "is the box dry" is a READ, and this is the answer to it.
-- Returns coal, slots used, size; nil when there is no wrap to be had.
local function boxRead(l)
  if type(peripheral) ~= "table" or not peripheral.wrap or not st.depot then return end
  local dir = st.depot.fuel
  faceDepot(dir)
  local ok, inv = pcall(peripheral.wrap, (dir == "down") and "bottom" or "front")
  if not (ok and type(inv) == "table" and inv.list) then return end
  local okl, items = pcall(inv.list)
  if not (okl and type(items) == "table") then return end
  local coal, used = 0, 0
  for _, it in pairs(items) do
    used = used + 1
    if it and isCoalish(l, it.name) then coal = coal + (it.count or 0) end
  end
  local oks, size = pcall(inv.size)
  return coal, used, oks and size or nil
end

local probed = false
local function depotProbe(l)
  if probed or not st.depot then return end
  probed = true
  local coal, used, size = boxRead(l)
  if not coal then
    say("depot  : the box cannot be wrapped from a turtle -- the 16-stack suck is")
    say("         all the turtle can see of it")
    return
  end
  sayf("depot  : wrapped -- %s slots, %d of them used, %d coal in the box",
    size and tostring(size) or "?", used, coal)
end

-- the lava map -------------------------------------------------------------
-- A turtle with a disk drive beside it mounts /disk, so the map needs no
-- protocol: append while docked, read while docked. One source per line,
-- "x,y,z". No drive, no map, and nothing else changes.
--
-- ponytail: the deploy rig leaves the drive at the SURFACE and the depot is at
-- the trunk floor, so /disk is not mounted where dock() calls mapMerge and the
-- map is latent -- it costs a bounded list in the state file and nothing else.
-- To wake it up, stand a second drive beside the depot; the code needs no
-- change, it only ever asks fs.exists("/disk").

local function mapRead()
  local out = {}
  local LAVAMAP = lavaMap()
  if not LAVAMAP or not fs.exists(LAVAMAP) then return out end
  local f = fs.open(LAVAMAP, "r")
  local text = f.readAll()
  f.close()
  for line in tostring(text):gmatch("[^\n]+") do
    local x, y, z = line:match("^(-?%d+),(-?%d+),(-?%d+)")
    if x then out[#out + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
  end
  return out
end

local function mapWrite(list)
  local lines = {}
  for _, p in ipairs(list) do lines[#lines + 1] = ("%d,%d,%d"):format(p.x, p.y, p.z) end
  local LAVAMAP = lavaMap()
  if not LAVAMAP then return end
  local f = fs.open(LAVAMAP, "w")
  f.write(table.concat(lines, "\n") .. "\n")
  f.close()
end

-- Merge what this trip saw into the shared map. Called only while docked.
local function mapMerge()
  if not lavaMap() then return 0 end
  local have, seen, added = mapRead(), {}, 0
  for _, p in ipairs(have) do seen[("%d,%d,%d"):format(p.x, p.y, p.z)] = true end
  for _, p in ipairs(st.lava or {}) do
    local k = ("%d,%d,%d"):format(p.x, p.y, p.z)
    if not seen[k] then
      seen[k] = true
      have[#have + 1] = p
      added = added + 1
    end
  end
  if added > 0 then mapWrite(have) end
  -- the sources are on /disk now, which is what the dedupe was protecting;
  -- lavaSeen used to keep every key it had ever seen and save() serialises the
  -- whole state table on every dug block
  st.lava, st.lavaSeen = {}, {}
  save()
  return added
end

local function mapDrop(x, y, z)
  if not lavaMap() then return end
  local out = {}
  for _, p in ipairs(mapRead()) do
    if not (p.x == x and p.y == y and p.z == z) then out[#out + 1] = p end
  end
  mapWrite(out)
end

-- lava ---------------------------------------------------------------------
-- Sources only: flowing lava cannot be bucketed. A source is level 0 in the
-- block state. Turtles are lavaproof, so none of this is about safety -- it is
-- 1,000 fuel a bucket against coal's 80.

local function isSource(data)
  if not data or not tostring(data.name):find("lava", 1, true) then return false end
  if not data.state then return false end          -- no state table: do not guess
  return data.state.level == 0
end

local function scoop(conf, side)
  if not conf.lava then return false end
  local slot = findItem("minecraft:bucket")
  if not slot then return false end
  turtle.select(slot)
  local place = (side == "down" and turtle.placeDown)
             or (side == "up" and turtle.placeUp)
             or turtle.place
  local ok = select(2, pcall(place))
  local got = findItem("minecraft:lava_bucket")
  if got then
    turtle.select(got)
    pcall(turtle.refuel)
    st.scooped = (st.scooped or 0) + 1
  end
  turtle.select(1)
  save()
  return ok and got ~= nil
end

-- The lava map is shared over rednet, because the floppy cannot do it. The
-- drive and the floppy stay at the SURFACE launch block and every depot is at
-- a trunk floor 119 blocks down, so /disk is not mounted where dock() calls
-- mapMerge -- a source one turtle found never reached the other two [user,
-- 2026-08-29]. A broadcast is the only channel three turtles at y=-59 share.
--
-- It has to be a coroutine blocked on rednet.receive for the whole run. Events
-- that arrive while turtle.forward() is waiting for its turtle_response are
-- pulled and DISCARDED by the turtle API, so draining the queue at dock time
-- finds nothing: by then the message has been thrown away. That is what
-- parallel is for.
local LAVA_PROTO = "quarrylava"

local function lavaSay(kind, x, y, z)
  local side = modemSide()
  if not side or type(rednet) ~= "table" then return end
  pcall(rednet.open, side)
  pcall(rednet.broadcast, ("%s %d,%d,%d"):format(kind, x, y, z), LAVA_PROTO)
end

-- Forget a source everywhere this turtle keeps one: the floppy map if it has
-- one, and the in-memory list the broadcast fills. mapDrop alone left a
-- scooped source in st.lava, and forage would walk to it again.
local function forgetSource(x, y, z)
  mapDrop(x, y, z)
  local k = ("%d,%d,%d"):format(x, y, z)
  local out = {}
  for _, p in ipairs(st.lava or {}) do
    if ("%d,%d,%d"):format(p.x, p.y, p.z) ~= k then out[#out + 1] = p end
  end
  st.lava = out
  if st.lavaSeen then st.lavaSeen[k] = nil end
end

local function lavaAdd(x, y, z, who)
  local k = ("%d,%d,%d"):format(x, y, z)
  st.lava, st.lavaSeen = st.lava or {}, st.lavaSeen or {}
  if st.lavaSeen[k] or #st.lava >= LAVA_KEEP then return false end
  st.lavaSeen[k] = true
  st.lava[#st.lava + 1] = { x = x, y = y, z = z }
  save()
  if who then sayf("lavamap: turtle %s found a source at %d,%d,%d", who, x, y, z) end
  return true
end

local function lavaListen()
  local side = modemSide()
  if not side or type(rednet) ~= "table" or not rednet.receive then
    -- no modem, or no rednet: idle forever so parallel still ends with the mine
    while true do os.sleep(60) end
  end
  pcall(rednet.open, side)
  while true do
    local ok, from, msg = pcall(rednet.receive, LAVA_PROTO)
    if not ok then
      os.sleep(5)                 -- a broken modem must not spin this hot
    elseif type(msg) == "string" then
      local kind, x, y, z = msg:match("^(%a+) (-?%d+),(-?%d+),(-?%d+)$")
      x, y, z = tonumber(x), tonumber(y), tonumber(z)
      if kind == "lava" and x then
        lavaAdd(x, y, z, tostring(from))
      elseif kind == "gone" and x then
        forgetSource(x, y, z)
      end
    end
  end
end

-- Every block of the branch passes this. Record a source's position for the
-- map; scoop it only when the tank is low enough to be worth a bucket trip.
function watchLava(conf, l)
  local probes = {
    { turtle.inspectDown, "down", 0, -1, 0 },
    { turtle.inspect,     "front", DIRS[st.dir or 0][1], 0, DIRS[st.dir or 0][2] },
  }
  for _, p in ipairs(probes) do
    local ok, hit, data = pcall(p[1])
    if ok and hit and isSource(data) then
      local x, y, z = st.x + p[3], st.y + p[4], st.z + p[5]
      local k = ("%d,%d,%d"):format(x, y, z)
      -- take it if the tank wants it; only what is left standing goes on the
      -- map, or the next dock would put a source back that no longer exists
      local took = conf.lava and fuelLevel() < conf.lavaFloor and scoop(conf, p[2])
      if took then
        forgetSource(x, y, z)
        lavaSay("gone", x, y, z)     -- so the others stop walking to it
      else
        -- Capped because save() serialises the whole state table on every dug
        -- block, and mapMerge -- the only thing that empties these -- is a
        -- no-op wherever /disk is not mounted. Unbounded, they turn every
        -- save of a long run into a longer one.
        if not (st.lavaSeen or {})[k] and lavaAdd(x, y, z) then
          lavaSay("lava", x, y, z)
        end
      end
    end
  end
end

-- the work loop ------------------------------------------------------------

local function levelsFrom(conf)
  local ys = {}
  for _, y in ipairs(levels(conf)) do
    if not st.floor or y >= st.floor then ys[#ys + 1] = y end
  end
  return ys
end

function doneKey(y, z) return ("%d:%d"):format(y, z) end

-- The next branch this turtle owns: unfinished rows on the current level
-- first, nearest to the trunk, then the next level in schedule order. Phase 4
-- replaces the state list with "an air mouth is already taken" [plan 4].
function nextBranch(conf, c, lo, hi, trunkZ)
  st.done = st.done or {}
  local ys, from = levelsFrom(conf), nil
  for i, y in ipairs(ys) do if y == st.level then from = i break end end
  for i = from or 1, #ys do
    local y = ys[i]
    for d = 0, math.max(from and (trunkZ - lo) or 0, hi - lo) do
      for _, z in ipairs({ trunkZ - d, trunkZ + d }) do
        if z >= lo and z <= hi and isBranch(c, y, z) and not st.done[doneKey(y, z)] then
          return y, z
        end
      end
    end
  end
end

-- Come home through rock that has to be cut anyway. A leg ends at the rim, 24
-- blocks from the spine, and the walk back down it mines nothing: the rock is
-- already gone. The row 5 over is the next one this third owes, so the turtle
-- jogs to it at the rim -- 5 blocks -- and cuts it inward instead. Two rows
-- come out of four legs and two jogs where they used to cost four legs and
-- four empty walks, and the turtle ends where it started, at the first row's
-- mouth. With no second row to pair with, the row is cut on its own and the
-- walk back to the spine is the price of the last leg.
local function pairPlan(c, y, a, lo, hi)
  st.done, st.cut = st.done or {}, st.cut or {}
  -- A row this turtle has already been down is finished leg by leg, out of the
  -- spine, not paired with anything: the legs it still owes are whatever the
  -- interruption left, and they are not in the order a pair walks.
  local ca = st.cut[doneKey(y, a)]
  if ca and not (ca.west and ca.east) then
    local rest = {}
    if not ca.west then rest[#rest + 1] = { z = a, leg = "west" } end
    if not ca.east then rest[#rest + 1] = { z = a, leg = "east" } end
    return rest
  end
  local b
  for d = 5, math.max(hi - lo, 5), 5 do
    for _, z in ipairs({ a + d, a - d }) do
      if not b and z >= lo and z <= hi and isBranch(c, y, z)
         and not st.done[doneKey(y, z)] and not st.cut[doneKey(y, z)] then b = z end
    end
    if b then break end
  end
  if not b then return { { z = a, leg = "west" }, { z = a, leg = "east" } } end
  return {
    { z = a, leg = "west" },
    { z = b, leg = "west", inward = true },
    { z = b, leg = "east" },
    { z = a, leg = "east", inward = true },
  }
end

-- What one more branch costs from where the turtle stands, plus the walk back
-- to the depot afterwards. This is what the fuel top-up aims at.
function branchCost(c, conf, y, z)
  local dp = st.depot or st.home
  local toMouth = math.abs(st.x - c.spine) + math.abs(st.y - y) + math.abs(st.z - z)
  local legs    = 2 * (c.west + c.east)
  local back    = math.abs(c.spine - dp.x) + math.abs(y - dp.y) + math.abs(z - dp.z)
  return toMouth + legs + back + conf.fuelMargin
end

-- Where to go and mine for coal. It used to be `topY` and nothing else, and
-- once this turtle had cut every row it owns at y=60 the climb became a
-- 238-block round trip to a level with no work left on it: three climbs in
-- log rVv2v and two in lYwey turned round the moment they arrived, and the
-- turtle then ground its tank down to 124 with nowhere left to go.
--
-- Start at the top and work DOWN. Coal gets commoner the higher you go [user,
-- 2026-08-29], so `topY` is the level worth the climb; what changed is what
-- happens when its rows are gone -- the next level DOWN, and the one under
-- that, rather than the same finished level over and over. The climb is paid
-- once and the descent afterwards is free, because the turtle comes down
-- through its own trunk.
--
-- Nothing below y=0 counts as foraging: coal does not generate there in 1.21,
-- which is why the claim floor is somewhere a turtle cannot mine its way out
-- of. A claim whose top is already under y=0 has no coal country in it at all,
-- and there the top level is the best that can be offered.
local function forageLevel(conf, c)
  local lo, hi = thirdOf(c, st.index or 1, conf.turtles or 1)
  st.done = st.done or {}
  local best
  for _, y in ipairs(levels(conf)) do
    if (conf.topY >= 0 and y >= 0) or y == conf.topY then
      local free = false
      for z = lo, hi do
        if isBranch(c, y, z) and not st.done[doneKey(y, z)] then free = true break end
      end
      if free and (not best or y > best) then best = y end
    end
  end
  return best
end

-- Foraging, only when the depot is dry [plan 7]: nearest mapped lava source
-- first, then a coal level, then park.
-- `z` is the trunk column this turtle will work from, and it is what the climb
-- is priced against. It defaults to st.z because dock() calls this standing ON
-- the trunk, where the two are the same thing. runMine's surface call is the
-- one that must pass it: a turtle at the launch block is up to half a claim
-- away from its own trunk in z, and pricing from st.z drops that walk from the
-- estimate twice over -- out and back.
function forage(conf, l, c, z)
  if conf.lava and findItem("minecraft:bucket") then
    local best, bd
    -- both maps: the floppy where there is one, and the list the broadcast
    -- fills, which is the only one a turtle 119 blocks from the drive has
    local pts = mapRead()
    for _, p in ipairs(st.lava or {}) do pts[#pts + 1] = p end
    for _, p in ipairs(pts) do
      local d = math.abs(p.x - st.x) + math.abs(p.y - st.y) + math.abs(p.z - st.z)
      if d * 2 + conf.fuelMargin < fuelLevel() and (not bd or d < bd) then best, bd = p, d end
    end
    if best then
      sayf("forage : mapped lava source at %d,%d,%d, %d blocks off", best.x, best.y, best.z, bd)
      st.task = "forage" save()
      if goTo(best.x, best.y + 1, best.z) then
        local ok, hit, data = pcall(turtle.inspectDown)
        if ok and hit and isSource(data) and scoop(conf, "down") then
          forgetSource(best.x, best.y, best.z)
          lavaSay("gone", best.x, best.y, best.z)
          return true
        end
      end
      forgetSource(best.x, best.y, best.z)   -- gone or unreachable: stop trying
      lavaSay("gone", best.x, best.y, best.z)
    end
  end
  local top = forageLevel(conf, c) or conf.topY
  if not conf.forageCoal then
    halt = ("depot is dry and forageCoal is off: %d fuel, and I am not to climb for coal")
      :format(fuelLevel())
    return false
  end
  if st.level ~= top and not st.foraging then
    -- Price the climb and refuse one it cannot finish. This used to be reached
    -- only from `fuelLevel() < want`, which is to say only once the tank was
    -- already under the cost of one branch -- so the turtle could never afford
    -- the climb it was being sent on, half-committed by setting st.level, and
    -- halted on the pass after. The feature had never once worked in-game
    -- [2026-08-29, logs E5wWw and hkgWh]. dock() now calls this while the tank
    -- can still pay, and what is left is to say so when it cannot.
    --
    -- Cost is priced from the trunk column, which is where a dock leaves the
    -- turtle standing. Short, it stops HERE, at the depot -- somewhere the
    -- player can walk to with a stack of coal. Halfway up a one-wide trunk
    -- shaft is not.
    local cost = branchCost(c, conf, top, z or st.z)
    if fuelLevel() < cost then burnFrom(l, cost) end
    if fuelLevel() < cost then
      halt = ("depot is dry and I cannot afford the climb for coal: %d fuel, %d to work y=%d and come back")
        :format(fuelLevel(), cost, top)
      return false
    end
    sayf("forage : depot is dry -- climbing to y=%d for coal, %d fuel for a %d-block trip",
      top, fuelLevel(), cost)
    notify("fuel", ("the depot at %d,%d,%d is dry -- climbing to y=%d to mine coal")
      :format(st.x, st.y, st.z, top))
    st.foraging = true
    st.level, st.branch, st.leg, st.along = top, nil, nil, 0
    st.plan, st.step = nil, nil
    save()
    return true
  end
  -- Up top and still short. Stopping is the answer; where it stops is the park
  -- block's business, and that is the top of this turtle's own trunk.
  halt = ("out of coal: %d fuel, and the top level had none to give either")
    :format(fuelLevel())
  return false
end

-- One depot visit: dump the load, write what the trip saw into the shared map,
-- take a rationed top-up, and forage if the chest had nothing to give.
function dock(c, conf, l, want)
  local dp = st.depot
  st.task = "depot"
  save()
  sayf("depot  : docking with %d slots used, %d fuel", carrying(), fuelLevel())
  -- Home the way the mine is already cut. goTo always moves y first, so from
  -- 24 blocks out on a branch above the depot it sank a fresh shaft at the leg
  -- end and then bulldozed home through solid rock at the depot's level. The
  -- leg is air, the branch mouth is air, and the trunk is air: walk the leg
  -- back to the spine, take the spine to the trunk column, and only then
  -- change level. Same order recall uses, and the same reason.
  if not goTo(dp.x, st.y, dp.z) then return false end
  if not goTo(dp.x, dp.y, dp.z) then return false end

  local okd, why = dumpLoad(l)
  if not okd then halt = why return false end

  depotProbe(l)
  -- Fuel first, cargo second: the coal this trip dug goes in the tank up to
  -- conf.fuelKeep before the box is asked for any, so a turtle that fed itself
  -- takes nothing and a shared box lasts three times as long.
  keepFuel(conf, l)

  local added = mapMerge()
  if added > 0 then sayf("lavamap: %d new source%s on /disk", added, added == 1 and "" or "s") end

  -- aim at four branches' worth, which the plan's 20,000 tank swallows whole
  local target = want * 4
  local need   = math.max(0, math.ceil((target - fuelLevel()) / 80))
  local got, avail = restock(conf, l, need)
  sayf("depot  : dumped; chest held %d fuel items, took %d fuel, tank %d",
    avail, got, fuelLevel())

  st.needDock = nil
  st.trips = (st.trips or 0) + 1
  save()

  -- Launch the climb while it is still affordable. `fuelLevel() < want` is one
  -- branch's worth, and the climb to the top level costs four -- so waiting
  -- for it means only ever trying the climb once the tank cannot pay for it.
  -- A dock the depot could not feed is the real signal, and it lands several
  -- trips earlier: on log E5wWw at the tank-413 dock rather than at 93.
  -- Dry means the BOX has nothing, never that this trip asked for nothing. A
  -- turtle whose tank is already over four branches takes 0 from a box holding
  -- 38 coal, and reading that as dry sent both turtles up to y=60 on their
  -- second dock with a full depot underneath them [in-game 2026-08-29, logs
  -- yiALS and PwHyZ]. The wrap answers it properly on a box too big for the
  -- suck to read; `avail` is the fallback where there is no wrap.
  local seen  = boxRead(l)
  -- Go for coal while there is plenty left to go on, not at the last moment.
  -- The old gate was twice one climb -- about 790 -- and a turtle that came
  -- back from a climb with less than that, or whose box ran dry with a healthy
  -- tank, spent the rest of the shift mining its reserve down instead. Both
  -- turtles ended a 2,700-block run stranded on 124 fuel with the depot empty
  -- [in-game 2026-08-29, logs rVv2v and lYwey]. conf.fuelKeep is the tank the
  -- turtle wants; below it, with a dry box, going to get coal IS the work.
  local early = (seen or avail or 0) <= 0 and conf.forageCoal and fuelLevel() >= want
                and fuelLevel() < (conf.fuelKeep or 0)
  if fuelLevel() < want or early then
    if not forage(conf, l, c) then
      -- An early climb that could not be started is not a reason to stop: the
      -- tank still covers the next branch, so mine it and ask again at the next
      -- dry dock, by which time the answer may be the halt after all. Only a
      -- turtle that cannot pay for the branch in front of it stops here.
      if fuelLevel() >= want then halt = nil return true end
      if not halt then
        halt = ("depot is dry and there is nothing to forage: %d fuel, %d needed")
          :format(fuelLevel(), want)
      end
      return false
    end
  end
  return true
end

local function report(c, conf)
  sayf("dug    : %d blocks, %d of them chasing veins", st.dug or 0, st.veined or 0)
  sayf("depot  : %d trips, %d items hauled, %d junk dumped in the tunnel",
    st.trips or 0, st.hauled or 0, st.junked or 0)
  if (st.shared or 0) > 0 then
    sayf("fuel   : %d coal banked in the depot chest" ..
      (ownDepot() and " above what the tank would take" or " for the other turtles"),
      st.shared)
  end
  local nb = 0
  for _ in pairs(st.done or {}) do nb = nb + 1 end
  sayf("done   : %d branch%s finished in this third", nb, nb == 1 and "" or "es")
  if (st.scooped or 0) > 0 then sayf("lava   : %d source%s scooped", st.scooped, st.scooped == 1 and "" or "s") end
  sayf("at     : %d,%d,%d facing %s, fuel %d", st.x, st.y, st.z,
    ({ [0] = "+z", [1] = "-x", [2] = "-z", [3] = "+x" })[st.dir or 0], fuelLevel())
  if st.floor then sayf("floor  : bedrock stopped the trunk at y=%d", st.floor) end
  local names = {}
  for name, n in pairs(rejected) do names[#names + 1] = ("%s x%d"):format(name, n) end
  if #names > 0 then
    sayf("passed over: %s", table.concat(names, ", "))
    say("         (those are ore-ish blocks this config does not mine. Add the")
    say("         ones you want under [oreNames] in quarry.conf.)")
  end
  local kept = {}
  for name, e in pairs(left) do kept[#kept + 1] = ("%s x%d (beside %s)"):format(name, e.n, e.at) end
  if #kept > 0 then
    sayf("left alone: %s", table.concat(kept, ", "))
    say("         (Lootr containers cannot be broken or emptied by a turtle at")
    say("          all -- the loot is per-player. Go and open them yourself.)")
  end
  if tagless then
    say("WARNING: inspect returned no tags table, so oreTags is doing nothing here.")
    say("         Only the [oreNames] list is finding ore. Tell me and I will fix it.")
  end
  -- The reason has to outlive the run. "Why are you stopped" gets asked at the
  -- turtle, hours later, by somebody who never saw this screen and cannot
  -- scroll it back -- so it goes in the state file and --check reads it out.
  st.halt = halt
  save()
  if halt then sayf("STOPPED: %s", halt) else say("work complete") end
end

-- Phases 2 and 3: descend, cross to the trunk, sink it, then branch after
-- branch with a depot trip whenever the load or the tank calls for one.
-- Every turtle that carries a container builds its own depot under its own
-- trunk, so this is the FALLBACK: a turtle handed no container, or one whose
-- own floor would not open, still has the others' boxes to bank in. Rather
-- than spend a spine walk on every boot, the sweep waits until a turtle
-- actually needs the depot -- and then happens once, because the answer is
-- saved either way.
-- Bedrock scatters over four blocks so the trunk floors are rarely the same
-- y: probe up the column too, which is cheaper than asking the user to level
-- three floors by hand.
local function findSharedDepot(c, conf, l, index, trunkZ)
  for i = 1, conf.turtles do
    if i ~= index then
      local _, _, tz = thirdOf(c, i, conf.turtles)
      sayf("depot  : looking under turtle %d's trunk at z=%d", i, tz)
      -- bedrock scatters over four blocks in BOTH directions: a turtle whose
      -- own floor stopped higher than its neighbour's is ABOVE the depot, and
      -- an upward-only sweep passes over it and sets noDepot for good.
      local y0 = st.level
      for _, off in ipairs({ 0, 1, 2, 3, -1, -2, -3 }) do
        -- Downwards stops at bottomY. It is one level above bedrock and the
        -- same number for all three turtles, so a neighbour's trunk floor can
        -- never be under it -- the offsets below it buy nothing and cost a dig
        -- into bedrock territory. In-game [log kdxS8, 2026-08-29] this walked
        -- to y=-61 and cut an eight-block corridor around somebody's chests.
        local y = y0 + off
        if y >= conf.bottomY and goTo(c.spine, y, tz) and probeDepot(l) then
          local dp = st.depot
          -- Somebody else's box. This is the one place own = false is written,
          -- and it is what turns the sharing rules back on: the per-dock cap
          -- in restock, the fuelShare trip home, and no burning of a find that
          -- the box's owner is going to want.
          dp.own = false
          save()
          sayf("depot  : shared depot at %d,%d,%d (dump side %s, fuel side %s)",
            dp.x, dp.y, dp.z, tostring(dp.dump), tostring(dp.fuel))
          return true
        end
      end
    end
  end
  st.noDepot = true          -- asked and answered: do not walk the spine again
  save()
  say("depot  : no container under any trunk floor")
  goTo(c.spine, st.level, trunkZ)   -- back to its own trunk to stop tidily
  return false
end

-- startup ------------------------------------------------------------------
-- A turtle in an unloaded chunk stops with the chunk, and comes back by
-- REBOOTING, not by resuming: whatever /startup runs is what decides whether
-- the mine carries on. BOOT writes one as it deploys turtles 2..N, so they
-- come back by themselves; turtle 1 is started by hand and had none, and a
-- chunk reload or a server restart left it parked at a prompt while the other
-- two went back to work. quarry.state holds the branch, so all a reboot needs
-- is somebody to type the command -- which is exactly what this is.

local STARTUP = "/startup"

-- true when /startup is one of ours, false when it is somebody else's, nil
-- when there is none.
local function ourStartup()
  if not fs.exists(STARTUP) then return nil end
  local f = fs.open(STARTUP, "r")
  if not f then return nil end
  local had = f.readAll()
  f.close()
  return tostring(had):find("quarry", 1, true) ~= nil
end

local function installStartup(index)
  local line = ("shell.run('quarry', '%d')"):format(index)
  local mine = ourStartup()
  if mine == false then
    say("startup: /startup is already here and is not mine, so I have left it.")
    say("         This turtle will not restart itself after a chunk reload --")
    say("         add " .. line .. " to it if you want it to.")
    return
  end
  if mine then
    local f = fs.open(STARTUP, "r")
    local had = f.readAll()
    f.close()
    if tostring(had):find(line, 1, true) then return end   -- already right
  end
  local f = fs.open(STARTUP, "w")
  if not f then return end
  f.write(line .. "\n")
  f.close()
  sayf("startup: wrote %s, so a chunk reload or a server restart brings me back", STARTUP)
end

-- Recall is a deliberate stop, so it takes the startup back off with it. Left
-- in place, the next reboot would send a turtle you had just called home
-- straight back down the trunk.
local function clearStartup()
  if ourStartup() then
    fs.delete(STARTUP)
    sayf("recall : removed %s -- a recalled turtle stays put through a reboot", STARTUP)
  end
end

-- Recall [plan 4]. Normal returns are independent -- tying them to the group
-- would idle two turtles every time one filled -- but collecting the mine is
-- collective: you type it on each turtle. It is also the only way to reach a
-- turtle that is already working, so the sequence is Ctrl+T, then
-- "quarry <n> recall". The branch it was on stays in quarry.state, so the
-- same turtle re-run without the argument picks the mine straight back up.
local function runRecall(conf, l, index)
  if not st.home then
    error("nothing to recall from: quarry.state has no claim for this turtle", 0)
  end
  local c = claimOf(st.home.x, st.home.z, conf)
  claim = c
  local _, _, trunkZ = thirdOf(c, index, conf.turtles)
  local h = st.home

  if DRY then
    sayf("DRY recall %d: %d,%d,%d -> the trunk at x=%d z=%d, up to y=%d, then home %d,%d,%d",
      index, st.x or h.x, st.y or h.y, st.z or h.z, c.spine, trunkZ, h.y, h.x, h.y, h.z)
    say("set dry = false in quarry.conf to actually walk it")
    return
  end

  local x, y, z = locateOrAsk(conf)
  if not x then error("no position fix, and none was typed in", 0) end
  st.x, st.y, st.z = x, y, z
  st.task = "recall"
  save()
  local okc, why = calibrate(conf)
  if not okc then error("cannot work out which way I am facing: " .. tostring(why), 0) end

  local trip = math.abs(st.x - c.spine) + math.abs(st.z - trunkZ)
             + math.abs(h.y - st.y) + math.abs(h.x - c.spine) + math.abs(h.z - trunkZ)
  if fuelLevel() < trip + conf.fuelMargin then burnFrom(l, trip + conf.fuelMargin) end
  sayf("recall : %d,%d,%d -> %d,%d,%d, about %d moves, fuel %d",
    st.x, st.y, st.z, h.x, h.y, h.z, trip, fuelLevel())
  if fuelLevel() < trip then
    sayf("recall : SHORT -- %d fuel for a %d-move walk. It will get as far as it can.",
      fuelLevel(), trip)
  end

  -- Along the branch to the trunk column first, and only then up. goTo climbs
  -- before it travels, so going up anywhere else cuts a fresh shaft through
  -- a hundred blocks of rock instead of using the one already there.
  if not goTo(c.spine, st.y, trunkZ) then say("recall : stopped short of the trunk") return end
  if not goTo(c.spine, h.y, trunkZ)  then say("recall : stopped inside the trunk")  return end
  if not goTo(h.x, h.y, h.z)         then say("recall : stopped short of home")     return end
  save()
  clearStartup()
  say("recall : parked. quarry.state still holds the branch -- re-run without")
  say("         the argument and it carries on where it stopped.")
end

-- Phase 5 lives below, but a plain `quarry 1` needs it: declared here,
-- assigned there.
local runDeploy

local function runMine(conf, l, index)
  local x, y, z = locateOrAsk(conf)
  if not x then error("no position fix, and none was typed in", 0) end
  st.halt = nil                 -- this run's reason to stop is not the last one's
  st.index = index
  st.x, st.y, st.z = x, y, z
  st.dug, st.chased, st.veined = st.dug or 0, 0, 0
  -- A saved home from a previous claim would hijack this one, so a turtle that
  -- wakes up outside its old claim has plainly been carried to a new spot:
  -- forget the old anchor and the branch that went with it.
  if st.home then
    local hc = claimOf(st.home.x, st.home.z, conf)
    if x < hc.xMin or x > hc.xMax or z < hc.zMin or z > hc.zMax then
      say("moved: this is not the claim in quarry.state, starting a new one")
      st.home, st.level, st.branch, st.leg, st.along = nil, nil, nil, nil, 0
      st.depot, st.noDepot = nil, nil
    end
  end
  st.home = st.home or { x = x, y = y, z = z }
  save()
  -- Before the walk, not after: the trunk descent alone is over a hundred
  -- blocks, and an unload partway down must not be what costs the mine.
  installStartup(index)

  -- Staff the mine before working it. `quarry 1 deploy` is still the explicit
  -- way to do it, but turtle 1 walking off with turtles 2 and 3 in the hold
  -- just carries them for the whole shift -- in-game 2026-08-28 it posted them
  -- into the depot as spoil, and now that they are kit they ride along instead,
  -- which is no more use. Deploy here, at the surface, on the launch block,
  -- where the drive goes and where every turtle agrees on the claim.
  --
  -- The signal is the hold: turtles aboard means turtles to place. It used to
  -- be a once-per-claim flag written BEFORE the attempt, so a deploy that was
  -- stopped by anything -- a short kit, a blocked spot, a crash -- was never
  -- tried again, and every later `quarry 1` walked off with both turtles still
  -- in the hold and said nothing about it [in-game 2026-08-28]. A deploy that
  -- works empties the hold, so the hold is the flag. The counter is only there
  -- to stop a deploy that fails the same way forever from doing it on every
  -- reboot as well.
  if index == 1 and (conf.turtles or 1) > 1 and carryingTurtle()
     and (st.deployTries or 0) < 3 then
    st.deployTries = (st.deployTries or 0) + 1
    save()
    say("deploy : turtles in the hold -- staffing the mine before I descend")
    local okd, whyd = pcall(runDeploy, conf, l, index)
    if not okd then
      sayf("deploy : the deploy stopped -- %s", tostring(whyd))
      -- clear() sets halt on the way out of a failed deploy, and a halt left
      -- standing is read as this run's reason to stop: the mine descended,
      -- built its depot and then signed off with the deploy's stale message on
      -- its first dock request [log zog32].
      halt, obstacle = nil, nil
      -- Mining alone used to happen here on its own, and a turtle that quietly
      -- carries its crew down the trunk is the one failure nobody notices for
      -- an hour. Ask. Unattended, it does what it always did.
      local a = ask("deploy : r = try the deploy again, a = mine alone, q = stop here.", "a")
      if a:sub(1, 1) == "r" then
        okd, whyd = pcall(runDeploy, conf, l, index)
        if not okd then sayf("deploy : again -- %s", tostring(whyd)) end
        halt, obstacle = nil, nil
      elseif a:sub(1, 1) == "q" then
        halt = "stopped on your say-so after the deploy failed: " .. tostring(whyd)
        report(claimOf(st.home.x, st.home.z, conf), conf)
        return
      end
    end
    st.task = "mine"
    save()
  elseif index == 1 and (conf.turtles or 1) > 1 and carryingTurtle() then
    sayf("deploy : %d turtles still in the hold, but the deploy has failed %d times",
      conf.turtles - 1, st.deployTries or 0)
    say("         already. Fix what it complained about and run `quarry 1 deploy`.")
  end

  -- The claim comes from the block the turtle was LAUNCHED on, never from
  -- where it happens to be standing now. A turtle resuming from 24 blocks
  -- down a branch is often in a different chunk than it started in, and
  -- claimOf() on that position hands it a whole different claim to mine.
  local c = claimOf(st.home.x, st.home.z, conf)
  claim = c
  local lo, hi, trunkZ = thirdOf(c, index, conf.turtles)
  sayf("quarry %d  at %d,%d,%d  claim x %d..%d z %d..%d (anchored at %d,%d)",
    index, x, y, z, c.xMin, c.xMax, c.zMin, c.zMax, st.home.x, st.home.z)
  sayf("third  : z %d..%d, trunk at x=%d z=%d", lo, hi, c.spine, trunkZ)

  topUp(l)
  local okc, why = calibrate(conf)
  if not okc then error("cannot work out which way I am facing: " .. tostring(why), 0) end
  sayf("heading: %d, fuel %d", st.dir, fuelLevel())

  -- "No depot anywhere" is true for one run at most. It is a latch inside a
  -- run, so a turtle that has swept the spine once does not sweep it again on
  -- every dock -- but it was surviving into the NEXT run, and by then turtle 1
  -- has usually built the depot the sweep went looking for. In-game
  -- [2026-08-29, logs H2Ie0 and sCv32] turtles 2 and 3 both stopped with a full
  -- hold and "there is no depot", never sweeping, because their state files
  -- still carried the noDepot written the run before. Clearing it here still
  -- costs no sweep on boot: the sweep only ever runs when a dock is due.
  if st.noDepot then
    st.noDepot = nil
    say("depot  : forgetting last run's \"no depot anywhere\" -- one may have been")
    say("         built since. It is looked for again the first time one is needed.")
    save()
  end

  -- Stop before it strands itself 119 blocks down. But rather than wait at the
  -- surface for a human, gather coal from the top level first: from here the
  -- climb to coal country is a few blocks, not the 119-block round trip the
  -- tank could not pay for. forage() commits to mining coal until the tank
  -- reaches fuelKeep, and the schedule then resumes as usual.
  local travelY = math.min(st.y, conf.topY)
  local target  = st.level or (conf.deepestFirst and conf.bottomY or conf.topY)
  local trip = (st.y - travelY) + math.abs(c.spine - st.x) + math.abs(trunkZ - st.z)
             + math.max(travelY - target, 0)
  local need = 2 * trip + conf.fuelMargin
  if fuelLevel() < need then
    sayf("fuel   : %d in the tank, %d to reach the branch and walk back -- gathering coal first",
      fuelLevel(), need)
    if not forage(conf, l, c, trunkZ) then report(c, conf) return end
    target = st.level or target
  end

  -- 1. straight down to travel height, so the walk to the trunk happens below
  --    topY where the surface builds are not.
  if st.y > travelY then
    sayf("descend: %d blocks to y=%d before crossing (above topY is travel, not mining)",
      st.y - travelY, travelY)
    st.task = "descend" save()
    if not goTo(st.x, travelY, st.z) then report(c, conf) return end
  end

  -- 2. across to the trunk column, 3. down the trunk to the working level.
  -- A turtle resuming at its level is already down here; sending it back to
  -- the trunk first would only walk the branch twice.
  if not (st.level and st.y == st.level) then
    st.task = "spine" save()
    sayf("cross  : to the trunk at %d,%d", c.spine, trunkZ)
    if not goTo(c.spine, st.y, trunkZ) then report(c, conf) return end

    st.task = "descend" save()
    sayf("trunk  : down to y=%d", target)
    local okd, stopped = descend(target)
    if not okd then report(c, conf) return end
    if stopped == "bedrock" then sayf("bedrock: floor is y=%d, working there instead", st.y) end
    st.level = st.y
    save()
  end

  -- 4. the depot. Found, never configured: standing on the trunk floor the
  -- turtle looks around itself once and remembers what it saw.
  if not st.depot then
    -- Carrying chests means deployment is not finished: this turtle is here to
    -- build the depot, not to look for one. Placing first means probeDepot
    -- finds them on the same pass.
    if not probeDepot(l) then
      local built = buildDepot(l, c, conf)
      if built > 0 then
        sayf("depot  : built the depot here, %d container%s", built, built == 1 and "" or "s")
      end
    end
    if st.depot or probeDepot(l) then
      local dp = st.depot
      sayf("depot  : container at %d,%d,%d (dump %s, fuel %s)",
        dp.x, dp.y, dp.z, tostring(dp.dump), tostring(dp.fuel))
    else
      say("depot  : nothing under my own trunk -- it will look under the others")
      say("         the first time it actually needs one [plan 5]")
    end
  end

  -- 5. the work loop. One leg at a time out of a pair of rows: pick the pair,
  -- walk to where that leg starts, cut it, dock when the load or the tank says
  -- so, and carry on until the third is finished or something stops it
  -- [plan 11]. One leg per pass, because a leg of the pair starts at the rim
  -- as often as at the spine and the walk to it is this loop's job.
  while true do
    -- Foraging is over the moment the tank is full enough. The schedule then
    -- picks up at the DEEPEST unfinished level, which clearing st.level makes
    -- nextBranch find on its own -- it scans levelsFrom in schedule order and
    -- only starts partway down when st.level names a level to start at.
    -- Leaving y=60 as the schedule position instead silently reverses
    -- deepestFirst, and with every level below it already marked done the
    -- turtle calls the claim exhausted and stops. That was the second half of
    -- the forage bug, and it has to go with the first.
    if st.foraging and fuelLevel() >= (conf.fuelKeep or 0) then
      st.foraging = nil
      st.level, st.branch, st.leg, st.along = nil, nil, nil, 0
      st.plan, st.step = nil, nil
      save()
      sayf("forage : tank is %d -- back to the schedule at the deepest level left",
        fuelLevel())
    end
    -- A state file written before the pair plan existed carries a half-cut row
    -- as branch/leg/along and nothing else. Rebuild the rest of that row as a
    -- plan of its own rather than throw the leg away: the turtles in the world
    -- are mid-row when the program is updated under them.
    if not st.plan and st.branch and st.leg then
      st.plan, st.step = { { z = st.branch, leg = st.leg } }, 1
      if st.leg == "west" then st.plan[2] = { z = st.branch, leg = "east" } end
    end
    if not st.plan then
      local by, bz = nextBranch(conf, c, lo, hi, trunkZ)
      if not by and st.foraging then
        -- This level is worked out. nextBranch searches from st.level ONWARD,
        -- so a foraging turtle sitting up high reads a claim with unmined
        -- levels under it as finished -- both turtles called the mine complete
        -- after four branches with fuel in the tank [logs yiALS and PwHyZ].
        --
        -- Keep foraging on the next coal level rather than giving up on the
        -- tank: the point of the climb is a full tank, and one level's rows
        -- rarely carry 2,000 fuel of coal. Only when there is no coal country
        -- left with work in it does the schedule get the turtle back.
        local ny = forageLevel(conf, c)
        st.branch, st.leg, st.along, st.plan, st.step = nil, nil, 0, nil, nil
        if ny and ny ~= st.level then
          sayf("forage : y=%d is worked out, still %d short -- on to y=%d",
            st.level, math.max(0, (conf.fuelKeep or 0) - fuelLevel()), ny)
          st.level = ny
        else
          st.foraging = nil
          st.level = nil
          sayf("forage : no coal level left with work on it -- back to the schedule on %d fuel",
            fuelLevel())
        end
        save()
        goto nextpass
      end
      if not by then
        say("claim  : every branch in this third is mined -- stopping and idling [plan 12]")
        break
      end
      if by ~= st.level then sayf("level  : moving to y=%d", by) end
      st.level, st.leg, st.along = by, nil, 0
      st.plan, st.step = pairPlan(c, by, bz, lo, hi), 1
      st.branch = bz
      save()
    end
    st.branch = st.plan[st.step].z

    -- the dock flag is a fact about the load, not durable state: a turtle that
    -- resumes with an empty hold has no trip to make, whatever the file says
    if st.needDock and room() and (st.carried or 0) < conf.tripBlocks
       and (not st.depot or fuelAboard(l) < conf.fuelShare) then
      st.needDock = nil
    end

    local want = branchCost(c, conf, st.level, st.branch)
    if fuelLevel() < want then burnFrom(l, want) end
    -- A foraging turtle is up here BECAUSE the depot was dry, so a tank under
    -- the next branch is not a reason to walk 119 blocks down to it and 119
    -- back: that round trip costs more than the branch that sent it up. Only a
    -- hold with no room left in it is still worth the descent.
    if st.needDock or (fuelLevel() < want and not st.foraging) then
      if not st.depot and not st.noDepot then findSharedDepot(c, conf, l, index, trunkZ) end
      if st.depot then
        if not dock(c, conf, l, want) then break end
        -- foraging can drop the branch it was heading for and pick a level
        -- somewhere else entirely, so start the pass again rather than walk to
        -- a branch that is no longer the plan
        if not st.plan then goto nextpass end
      elseif fuelLevel() < want then
        halt = ("out of fuel: %d in the tank, %d for the next branch, and no depot found")
          :format(fuelLevel(), want)
        break
      else
        -- Three things set st.needDock and only two of them are a reason to
        -- stop. Saying "inventory is full" for all three sent the user to look
        -- at an inventory that had six free slots in it.
        local why
        if not room() then
          why = ("inventory is full: all 16 slots hold something")
        elseif (st.carried or 0) >= conf.tripBlocks then
          why = ("carrying %d blocks and tripBlocks is %d, so it is time to empty out")
            :format(st.carried or 0, conf.tripBlocks)
        else
          -- Spare coal is not on that list: banking it needs a depot to bank
          -- it INTO, and there is none [in-game 2026-08-28, log Rpv9m: a run
          -- with a full tank and a nearly empty hold stopped over 192 coal the
          -- other two turtles were not there to burn]. Anything else that
          -- flagged the dock has passed: burning a stack for the next branch
          -- empties the slot it came out of, so a hold that was full at the end
          -- of the leg has room again by the time the loop looks at it.
          st.needDock = nil
          save()
          goto nextpass
        end
        halt = why .. ", and there is no depot to empty it into"
        break
      end
    end

    -- walk to the work: where this leg begins, or the point in it left off.
    -- st.leg is set before the first block of a leg is cut, so it alone means
    -- this leg is already started. Testing st.along > 0 as well read a leg
    -- that had docked on its own first block as a fresh branch, and mouthTaken()
    -- then saw the air THIS turtle had just mined on the other leg and gave the
    -- whole branch away as somebody else's. Half a branch, every time the hold
    -- filled on a leg boundary.
    local job = st.plan[st.step]
    local len = (job.leg == "west") and c.west or c.east
    if st.leg then
      sayf("resume : %s leg of y=%d z=%d, %d out", st.leg, st.level, st.branch, st.along)
    else
      st.along = job.inward and len or 0
      sayf("branch : y=%d z=%d, %s leg %s", st.level, st.branch, job.leg,
        job.inward and "back to the spine" or ("%d out"):format(len))
    end
    -- Change level in this turtle's OWN TRUNK COLUMN, which is air already:
    -- the first descent cut it from topY to the floor and nothing fills it in.
    -- goTo moves y first, so a level change made anywhere else sinks a fresh
    -- shaft through solid rock -- coming back down from a forage level at
    -- z=724 cut 109 blocks of new tunnel one row over from a trunk that was
    -- standing open [user, 2026-08-29]. Walking to the trunk first costs at
    -- most the width of a third and every block of it is already cut.
    --
    -- It used to be `goTo(c.spine, st.y, st.z)`, the spine column at whatever
    -- z the turtle stopped on. That fixed the older bug -- a turtle that
    -- finished a level at the rim would climb there and bulldoze west along a
    -- z the new level has no row on -- but the spine is only air where it has
    -- been walked, and at a forage level 119 blocks up it has not.
    if st.y ~= st.level then
      local ok1 = goTo(c.spine, st.y, trunkZ)
      if ok1 then ok1 = goTo(c.spine, st.level, trunkZ) end
      if not ok1 then
        -- carrying on to the dock means the run has not stopped, so the reason
        -- goTo left behind is not this run's reason to stop [goTo now names a
        -- jam so a run that gives up on one does not print "work complete"]
        if st.needDock then halt = nil goto nextpass end
        break
      end
    end
    -- The jog between the two rows is this goTo: from the rim of one row to the
    -- rim of the other, 5 blocks of rock instead of a 24-block walk back down a
    -- corridor that is already air.
    local bx = c.spine + ((job.leg == "west") and -st.along or st.along)
    if not goTo(bx, st.level, st.branch) then
      if st.needDock then halt = nil goto nextpass end
      break
    end

    -- Only the first leg starts at an untouched mouth, and only there does an
    -- air mouth mean somebody else's branch. The rest of the pair is entered
    -- from the rim, on rows inside this turtle's own third. A row st.cut knows
    -- about is one this turtle opened itself: reading that air as somebody
    -- else's threw the rest of the row away every time a corridor was held
    -- long enough to give the branch up [in-game 2026-08-28].
    st.cut = st.cut or {}
    if st.step == 1 and not st.leg then
      if st.cut[doneKey(st.level, st.branch)] then
        sayf("resume : y=%d z=%d is my own row, %s leg still to cut",
          st.level, st.branch, job.leg)
      elseif mouthTaken() then
        sayf("taken  : y=%d z=%d is already cut -- another turtle has it", st.level, st.branch)
        st.done = st.done or {}
        st.done[doneKey(st.level, st.branch)] = true
        st.plan, st.step, st.branch, st.leg, st.along = nil, nil, nil, nil, 0
        save()
        goto nextpass
      end
    end

    st.cut[doneKey(st.level, job.z)] = st.cut[doneKey(st.level, job.z)] or {}
    save()

    if not mineLeg(c, conf, l, job.leg, job.inward) then
      -- a dock request goes round the loop again; anything else is a real stop
      if halt then break end
      if not st.needDock then
        halt = "a leg stopped without a reason -- routing failed"
        break
      end
      goto nextpass
    end

    -- A leg that stopped short stopped on something it may not dig, and the
    -- rest of the pair is on the far side of it. Give up the rim route for the
    -- legs that are left and cut them out of the spine instead: the rock still
    -- has to come out, and the way to it is air.
    if (job.inward and st.along > 0) or (not job.inward and st.along < len) then
      for i = st.step + 1, #st.plan do st.plan[i].inward = nil end
    end

    st.step, st.leg = st.step + 1, nil
    -- The leg is cut. An obstacle can end it short, but mineLeg only comes back
    -- true when there is nothing left to do on it either way, and the row is
    -- finished once both its legs say so. Recording it here rather than at the
    -- end of the pair is what lets an interrupted row be picked up leg by leg.
    st.done = st.done or {}
    local key = doneKey(st.level, job.z)
    st.cut[key] = st.cut[key] or {}
    st.cut[key][job.leg] = true
    if st.cut[key].west and st.cut[key].east then
      st.done[key], st.cut[key] = true, nil
    end
    -- the pair is cut and the turtle is back at the first row's mouth
    if st.step > #st.plan then st.plan, st.step, st.branch, st.along = nil, nil, nil, 0 end
    save()
    ::nextpass::
  end

  -- Park OFF the spine. The spine is the one corridor all three share and every
  -- trunk floor sits on it, so a turtle that stops where it stands is a wall
  -- the other two cannot get past for as long as it is there -- and they do not
  -- stop, they burn their give-way tries and then mis-route. In-game
  -- [2026-08-29, log 9KJAs] turtle 2 stopped on the middle trunk and turtle 1
  -- spent 24 give-ways in front of it, gave up, and built the depot in the
  -- wrong place. A branch mouth one block west is out of the way and is a row
  -- that gets mined anyway.
  -- The resume point is st.leg/st.along, not the position, so a block sideways
  -- costs nothing: goTo walks back from wherever it wakes up.
  st.task = "park"
  if not halt then st.leg, st.along = nil, 0 end
  save()
  -- Out of coal parks at the TOP of this turtle's own trunk: not where the
  -- fuel ran out, and not at the depot. Each trunk column is private to its
  -- own third -- the only trunk block on the shared spine is the floor, and a
  -- turtle that can still reach the floor docks rather than parks, so the
  -- settled "park off the spine" rule cannot come into conflict here. y=topY
  -- is also the point nearest the surface, which is where the player can most
  -- easily bring it coal.
  if st.foraging and claim then
    local hp = halt
    local _, _, ptz = thirdOf(claim, index, conf.turtles)
    if st.x ~= claim.spine or st.y ~= conf.topY or st.z ~= ptz then
      goTo(claim.spine, conf.topY, ptz)
    end
    halt = hp
    save()
    sayf("park   : out of coal, parked at %d,%d,%d -- the depot needs filling",
      st.x, st.y, st.z)
    notify("fuel", ("out of coal and parked at %d,%d,%d -- fill the depot%s and reboot me")
      :format(st.x, st.y, st.z,
        st.depot and (" at %d,%d,%d"):format(st.depot.x, st.depot.y, st.depot.z) or ""))
  elseif claim and st.x == claim.spine and stepAside() then
    sayf("park   : stepped off the spine to %d,%d,%d so the others can get past",
      st.x, st.y, st.z)
    save()
  end
  report(c, conf)
end

-- The DRY route: every waypoint and what each costs, and no actuator touched.
local function dryRun(conf, l, index)
  local x, y, z, how = locate(conf)
  if not x then
    say("DRY: no position fix. Run --check first; you are probably missing a modem.")
    return
  end
  -- same anchor rule as the live run: a saved home wins over where it stands
  local c = claimOf(st.home and st.home.x or x, st.home and st.home.z or z, conf)
  local lo, hi, trunkZ = thirdOf(c, index, conf.turtles)
  local travelY = math.min(y, conf.topY)
  local level = conf.deepestFirst and conf.bottomY or conf.topY
  local bz = pickBranch(c, level, lo, hi, trunkZ) or trunkZ
  local drop  = y - travelY
  local cross = math.abs(c.spine - x) + math.abs(trunkZ - z)
  local trunk = travelY - level
  local spine = math.abs(bz - trunkZ)
  local branch = 2 * (c.west + c.east)
  local total = drop + cross + trunk + spine + branch

  sayf("quarry %d  DRY  at %d,%d,%d (%s)", index, x, y, z, how)
  sayf("claim  : x %d..%d, z %d..%d, spine x=%d", c.xMin, c.xMax, c.zMin, c.zMax, c.spine)
  sayf("third  : z %d..%d, trunk at x=%d z=%d", lo, hi, c.spine, trunkZ)
  sayf("route  : down %d to y=%d, across %d to the trunk, down %d to y=%d,",
    drop, travelY, cross, trunk, level)
  sayf("         along the spine %d to z=%d, then %d west and %d east",
    spine, bz, c.west, c.east)
  sayf("moves  : about %d for the first branch, plus vein chases (capped at %d each)",
    total, conf.veinMax)
  sayf("then   : branch after branch until the third is done, docking every %d blocks",
    conf.tripBlocks)
  say("depot  : found on arrival -- a container under the trunk floor, or beside it.")
  say("         No container there means it mines one load and stops.")
  sayf("fuel   : have %d, this branch wants about %d plus a %d reserve",
    fuelLevel(), total, conf.fuelMargin)
  if fuelLevel() < total + conf.fuelMargin then
    say("         SHORT. Put coal in a slot; it is burned on pickup, never carried.")
  end
  sayf("guards : deny list %s; never digs into a full inventory", table.concat(DENY, ", "))
  say("         (a full turtle dumps blacklisted junk to make room before it stops)")
  say("set dry = false in quarry.conf (or DRY = false at the top of this file) to run it")
end

-- deployment [plan 13] -----------------------------------------------------
-- Settled in-game 2026-08-27 by probe.lua, which overturned two assumptions
-- section 13 was written on:
--
--   * A turtle is NOT a peripheral to another turtle. turnOn, isOn and getID
--     are unavailable, so plan 13 step 4 ("call turnOn on turtle 2") cannot be
--     done at all. It does not need to be -- a placed turtle boots on its own
--     and runs /disk/startup.lua unprompted, in about 23 seconds.
--   * Facing does not matter. calibrate() derives a heading by moving one
--     block and diffing GPS, so a deployed turtle orients itself.
--
-- The rig is the one the probe proved: the drive one block up, the new turtle
-- on the ground directly below it, both in front of the deploying turtle.
-- Deployment happens at the SURFACE, on the launch block, not at the claim
-- floor: the drive has to sit directly above the placed turtle, and a trunk
-- floor is a working row in both directions, so nothing is placed beside it.
-- runMine anchors
-- its claim wherever it wakes, and the launch block is in the centre chunk, so
-- all three agree on the same claim anyway.

-- The disk's startup does ONE thing and cannot fail quietly: it writes a line
-- saying it ran, then hands over to boot.lua on the same floppy. Split out on
-- 2026-08-29 because "reboot works, running the actual code doesn't" [user]
-- and one file could not tell those two apart -- an empty floppy log now means
-- the disk startup never ran at all (a CC-side problem: shell.allow_disk_startup,
-- or the drive not being seen), and "startup ran" with nothing after it means
-- boot.lua threw, and the line after that says where.
--
-- No peripheral calls here, and no loops: the path this program was started
-- from is the floppy it is sitting on, so nothing has to be asked for.
local BOOTSTRAP = [==[
-- written by quarry deploy. Runs on a freshly placed turtle and does nothing
-- but leave a trace and hand over, so that a trace always exists.
local N = %d
local D = fs.getDir(shell.getRunningProgram())
if not D or D == "" or D == "." then D = "disk" end
if D:sub(1, 1) ~= "/" then D = "/" .. D end
local h = fs.open(D .. "/deploy" .. N .. ".log", "w")
if h then
  h.writeLine("startup ran off " .. D .. ", handing over to boot.lua")
  h.close()
end
shell.run(D .. "/boot.lua", D)
]==]

local BOOT = [==[
-- written by quarry deploy, and run by the tiny startup on the same floppy.
-- Everything a freshly placed turtle needs doing is here: no label, no fuel,
-- no modem, and an inventory its deployer is still filling.
local N = %d
-- true when quarry.conf pins the position by hand: nothing on this turtle then
-- calls gps.locate, so it needs no modem and must not stop for the want of one.
local MANUAL = %s
os.setComputerLabel("quarry" .. N)

-- The startup that ran us knows the floppy it was running off and hands it
-- over as its one argument -- N is already baked in above, so nothing else is
-- passed and this is it. Run by hand with no argument, ask the drive: "/disk"
-- is only the FIRST drive's mount point, and a second drive anywhere puts this
-- floppy at "/disk2".
local D = ...
if type(D) ~= "string" or D == "" then
  for _, side in ipairs({ "top", "bottom", "front", "back", "left", "right" }) do
    local okt, t = pcall(peripheral.getType, side)
    if okt and t == "drive" then
      local okm, mp = pcall(peripheral.call, side, "getMountPath")
      if okm and type(mp) == "string" and mp ~= "" then
        D = (mp:sub(1, 1) == "/") and mp or ("/" .. mp)
        break
      end
    end
  end
end
if type(D) ~= "string" or D == "" then D = "/disk" end

-- Nobody is watching this screen. Every stage is written to the floppy as well,
-- so the deployer standing behind can read back what actually happened rather
-- than inferring it from a turtle that did not move. Appended, never truncated:
-- the startup wrote the first line of this file and that line is the whole
-- point of the split -- lose it and a disk startup that never ran looks exactly
-- like one that ran and threw.
local LOG = D .. "/deploy" .. N .. ".log"
local function note(msg)
  print("quarry" .. N .. ": " .. msg)
  local h = fs.open(LOG, "a")
  if h then h.writeLine(msg) h.close() end
end

note("boot.lua running, floppy is mounted at " .. D .. ", waiting for my kit")

-- Wrapped, so a fault lands in the floppy log the deployer is already tailing
-- rather than only on a screen nobody is reading. Every `return` below is a
-- deliberate stop that has already said why on its way out; anything that
-- reaches the handler is a real crash, and now it names itself.
local function main()

  -- quarry.lua, not quarry: that is the name turtle 1 runs and the name update
  -- writes, and a turtle carrying both ends up running whichever the shell picks.
  if fs.exists("quarry") then fs.delete("quarry") end
  if fs.exists("quarry.lua") then fs.delete("quarry.lua") end
  fs.copy(D .. "/quarry", "quarry.lua")

  -- The config has to follow the program. Without it this turtle seeds a fresh
  -- quarry.conf off the shipped defaults -- which since 2026-08-27 mine for real
  -- -- so it goes live on settings its deployer never chose: veinMax, tripBlocks,
  -- the ore names and the fuel sections all revert. Same anti-drift rule as the
  -- program itself: take the deployer's file, do not re-derive one.
  -- Only when this turtle has none of its own. It used to overwrite on every
  -- boot, so coordinates typed in by hand were wiped by the next reboot and the
  -- turtle asked for them again -- forever, for as long as it stood beside the
  -- drive [user, 2026-08-28].
  if fs.exists(D .. "/quarry.conf") and not fs.exists("quarry.conf") then
    fs.copy(D .. "/quarry.conf", "quarry.conf")
    note("took the deployer's quarry.conf")
  elseif fs.exists("quarry.conf") then
    note("keeping my own quarry.conf")
  else
    note("WARNING: no quarry.conf on the floppy -- seeding one from the defaults;")
    note("         it MINES, but on default settings, not the deployer's")
  end

  -- The claim is anchored on the block a turtle wakes on, and this turtle wakes
  -- one block in front of its deployer -- which is over a chunk border often
  -- enough to matter. claimOf() would then hand it a different region and it
  -- would sink a trunk in a mine of its own. The deployer's anchor is on the
  -- floppy for exactly that reason; take it, and never overwrite a state file
  -- this turtle has already written for itself.
  if fs.exists(D .. "/quarry.state") and not fs.exists("quarry.state") then
    fs.copy(D .. "/quarry.state", "quarry.state")
    note("took the deployer's claim anchor")
  end

  local function slotLike(pat)
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name:find(pat) then return s, d end
    end
  end

  -- The deployer drops the kit in AFTER placing this turtle, so the boot beats
  -- the coal. Wait for it rather than racing it. 60 x 1s, then give up and say so.
  local modemSlot
  for _ = 1, 60 do
    modemSlot = slotLike("modem")
    if (modemSlot or MANUAL) and slotLike("coal") then break end
    os.sleep(1)
  end
  if not modemSlot then
    if not MANUAL then
      note("no modem arrived in 60s -- cannot GPS, stopping")
      return
    end
    note("no modem, and none needed: quarry.conf pins my position")
  end
  if not slotLike("coal") then
    note("no coal arrived -- carrying on anyway, will stop on fuel 0")
  end

  -- Equip the modem on whichever side is not holding the pickaxe. Guessing wrong
  -- disarms the turtle: equip swaps the SELECTED slot with that side's upgrade,
  -- so equipping off the wrong slot puts the pickaxe in the inventory and this
  -- turtle cannot dig. Two guards. Re-find the slot rather than trusting the one
  -- the wait loop saw, because the deployer was still dropping items in after
  -- that; and read the slot back after selecting it, so nothing is equipped until
  -- the modem is confirmed to be under the hand.
  if modemSlot then
    modemSlot = slotLike("wireless_modem") or slotLike("ender_modem") or modemSlot
    turtle.select(modemSlot)
    local held = turtle.getItemDetail()
    if not held or not held.name:find("modem") then
      note("slot " .. tostring(modemSlot) .. " holds " ..
        tostring(held and held.name or "nothing") .. ", not a modem -- not equipping,")
      note("because that would swap my pickaxe out instead")
      modemSlot = nil
    end
  end
  if modemSlot then
    -- getEquippedLeft/Right name the upgrade, so the free side is known outright.
    -- Without them a pickaxe and an empty side both read as nil under
    -- peripheral.getType, and the only way to find out is to equip and look at
    -- what came off in the hand.
    local function equippedName(side)
      local fn = turtle[side == "left" and "getEquippedLeft" or "getEquippedRight"]
      if not fn then return nil, false end
      local ok, d = pcall(fn)
      if not ok then return nil, false end
      if type(d) == "table" then return d.name, true end
      return (type(d) == "string" and d or nil), true
    end
    local leftName, named = equippedName("left")
    if named then
      local rightName = equippedName("right")
      local side = (leftName == nil and "left") or (rightName == nil and "right")
        or (not tostring(leftName):find("pickaxe") and "left") or "right"
      local ok = side == "left" and turtle.equipLeft() or turtle.equipRight()
      note("left=" .. tostring(leftName or "empty") .. " right=" .. tostring(rightName or "empty")
        .. ", equip" .. side .. " " .. tostring(ok))
    else
      local okR = turtle.equipRight()
      local came = turtle.getItemDetail()
      if came and came.name:find("pickaxe") then
        turtle.equipRight()             -- pickaxe back on the right, modem back in hand
        local okL = turtle.equipLeft()  -- modem goes left instead
        note("equipRight " .. tostring(okR) .. ", pickaxe came off, equipLeft " .. tostring(okL))
      else
        note("equipRight " .. tostring(okR) .. ", nothing came off")
      end
    end

    -- Do not trust the swap. Ask the peripheral API which side actually holds a
    -- modem: on a turtle, left and right report the EQUIPPED upgrade, so this is
    -- a direct answer rather than an inference from what came off in the hand.
    local modemSide
    for _, sd in ipairs({ "left", "right" }) do
      local okp, t = pcall(peripheral.getType, sd)
      if okp and t and tostring(t):find("modem") then modemSide = sd end
    end
    if modemSide then
      note("modem confirmed equipped on " .. modemSide)
    elseif not MANUAL then
      note("STOPPED: no modem on either side after equipping. Without one there is")
      note("no GPS, so I cannot find myself. Equip it by hand and reboot me.")
      for _, sd in ipairs({ "left", "right" }) do
        local okp, t = pcall(peripheral.getType, sd)
        note("  " .. sd .. " holds " .. tostring((okp and t) or "nothing"))
      end
      return
    else
      note("the modem would not equip, but my position is pinned, so I carry on")
    end
  end

  -- Burn everything it was handed. It carries no fuel items to the depot; the
  -- depot is what it rations from after that [plan 7].
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and (d.name:find("coal") or d.name:find("charcoal")) then
      turtle.select(s)
      turtle.refuel()
    end
  end
  turtle.select(1)

  -- Install a local startup so this turtle comes back on its own after a reboot,
  -- a chunk reload, or a server restart. The floppy is one block above the spot
  -- it launches from and it does not carry the drive with it, so the disk cannot
  -- be what restarts it. quarry resumes from its own state file.
  local fuel = turtle.getFuelLevel()
  if fuel ~= "unlimited" and fuel < 1 then
    note("STOPPED: fuel is 0. No coal reached me, and quarry can only spin on an")
    note("empty tank. Put coal in me and reboot.")
    return
  end

  local h = fs.open("/startup", "w")
  if h then
    h.writeLine("shell.run('quarry', '" .. N .. "')")
    h.close()
    note("installed /startup so I come back after a reboot")
  end

  note("fuel " .. tostring(turtle.getFuelLevel()) .. ", starting quarry " .. N)
  shell.run("quarry", tostring(N))
end

local lived, why = pcall(main)
if not lived then
  note("STOPPED: boot.lua crashed -- " .. tostring(why))
end
]==]

-- What block is in front, by peripheral type. A block that has just appeared
-- reads as nothing (CC:Tweaked #660 -- discovery goes stale); a turn refreshes
-- it, and right-then-left is a no-op for the heading tracked in st.dir.
local function frontType()
  local t = select(2, pcall(peripheral.getType, "front"))
  if t then return t end
  pcall(turtle.turnRight)
  pcall(turtle.turnLeft)
  return (select(2, pcall(peripheral.getType, "front")))
end

-- Hand one item to the turtle in front. A turtle is an inventory, so a plain
-- drop lands in its slots -- which is the only channel there is, now that the
-- peripheral route is known to be closed.
local function handOver(pat, count, what)
  -- Walk EVERY matching slot, not just the first. handOver("coal", 64) used to
  -- drop up to 64 out of the first coal slot and call it done -- so a slot
  -- holding 30 handed over 30 and reported success, and with the coal spread
  -- across slots a turtle got a fraction of what it was owed [HARVEST-PLAN C2].
  -- turtle.drop returns only true/false, so the count moved is read as the drop
  -- in the slot's stack before and after.
  local like = (type(pat) == "function") and pat or function(n) return n:find(pat) end
  local want, moved, saw = count, 0, false
  for s = 1, 16 do
    if moved >= want then break end
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and like(d.name) then
      saw = true
      turtle.select(s)
      local before = d.count
      -- pcall prepends its own success flag, so turtle.drop's answer is the
      -- SECOND value. Reading the first as the drop result made every failed
      -- drop look like a success, which is how a turtle got left with no modem.
      local lived, dropped = pcall(turtle.drop, want - moved)
      if not lived then
        sayf("deploy : could not hand over the %s: %s", what, tostring(dropped))
        return false
      end
      local after = select(2, pcall(turtle.getItemCount, s)) or before
      moved = moved + (before - after)
    end
  end
  if not saw then sayf("deploy : no %s to hand over", what) return false end
  if moved == 0 then
    sayf("deploy : the %s would NOT go across -- is the turtle really in front?", what)
    return false
  end
  if moved < want then
    sayf("deploy : handed over %d %s -- that was all that was aboard, not the %d asked for",
      moved, what, want)
  else
    sayf("deploy : handed over the %s", what)
  end
  return true, moved
end

-- One turtle: place it, feed it, wait for it to walk off. Returns false and a
-- reason, never throws, because a half-deployed mine still wants its report.
local function deployOne(conf, l, index, coalShare)
  sayf("deploy : turtle %d", index)

  -- What is in front is usually one of two things. Nothing, which is the happy
  -- case. Or a turtle from an earlier deploy that was placed and never booted
  -- and is still standing there -- both turtles were refused for exactly that
  -- in-game on 2026-08-28 [log 0JCwD], with the stranded turtle 2 of the run
  -- before blocking the spot. That is not an obstruction to route around, it
  -- IS this turtle, already placed: adopt it and go straight to switching it
  -- on. Anything else is the player's build, so ask rather than dig it.
  local standing = false
  while turtle.detect() do
    if frontType() == "turtle" then
      sayf("deploy : a turtle is already standing here -- adopting it as turtle %d", index)
      standing = true
      break
    end
    say("deploy : something is in front of me, and it is not a turtle.")
    local a = ask("deploy : d = dig it out, enter = I have cleared it, s = skip, q = stop.", "", 60)
    if a:sub(1, 1) == "s" then return false, "skipped on your say-so" end
    if a:sub(1, 1) == "q" then return false, "stopped deploying on your say-so", "stop" end
    if a:sub(1, 1) == "d" then pcall(turtle.dig) end
    -- Nobody answered and it is still blocked: the old behaviour, which is the
    -- right one when there is no player to clear it.
    if a == "" and turtle.detect() then
      return false, "something is in front of me; move me somewhere clear"
    end
  end

  local tSlot, tName = slotLike("turtle")
  if not standing then
    if not tSlot then return false, "no turtle item left in the hold" end
    turtle.select(tSlot)
    -- pcall prepends its own success flag, so place's answer is the SECOND
    -- value. Reading the first made a refused placement look placed, and the
    -- modem and coal then went on the floor in front of nothing.
    local lived, placed = pcall(turtle.place)
    if not lived or placed == false then
      return false, "the turtle item would not place: " .. tostring(placed)
    end
    sayf("deploy : placed %s in front", tName)
  end

  -- Turn it on, then ASK whether that worked instead of assuming it did. A
  -- placed turtle is a peripheral on front and it carries isOn, turnOn,
  -- reboot, shutdown and getLabel; those are the only levers there are, and
  -- until now this code pulled two of them blind. isOn turns "it is still
  -- switched off" from a guess into a fact, and the two failures it tells
  -- apart want opposite actions: turnOn for a turtle that is dark, reboot for
  -- one that is running and never ran the disk startup. Harvested from
  -- jnordberg/minecraft-replicator, which has always asked.
  -- CC-Tweaked issue #660: a turtle's peripheral discovery goes stale, and
  -- "causing any kind of update will make turtle see peripheral again --
  -- turning turtle". The block in front was air a moment ago, so a bare
  -- getType honestly reports nothing. Turn to force the refresh; right then
  -- left is a no-op for the heading tracked in st.dir, so nothing else shifts.
  local ptype
  for _ = 1, 6 do
    ptype = periph(peripheral.getType, "front")
    if ptype then break end
    pcall(turtle.turnRight)
    pcall(turtle.turnLeft)
    os.sleep(0.5)
  end

  -- One door to the turtle in front, because pcall prepends its own success
  -- flag and the answer is the SECOND value -- a mistake this file has made
  -- four separate times [RESUME, corrections]. A FAILED pcall puts an error
  -- STRING there, which is not false, so the two are separated here once: nil
  -- back means the peripheral would not answer at all, which is a different
  -- world from an honest `false`.
  local function frontAsk(method)
    local lived, res = pcall(peripheral.call, "front", method)
    if not lived then return nil, tostring(res) end
    return res
  end

  if ptype then
    sayf("deploy : peripheral on front = %s", tostring(ptype))
    local _, err = frontAsk("turnOn")
    if err then
      sayf("deploy : turnOn failed (%s) -- relying on self-boot", err)
    else
      sayf("deploy : turnOn sent to turtle %d", index)
    end
  else
    sayf("deploy : turtle %d is not visible as a peripheral, relying on self-boot", index)
  end

  -- Boot is unprompted and takes about 23s. Feed it while it waits.
  -- The modem is not optional: without one the new turtle cannot reach GPS,
  -- cannot calibrate, and will stand there until someone notices. If it does
  -- not go across, say so here rather than waiting 90s to infer it.
  -- unless the position is pinned by hand, in which case nothing on the new
  -- turtle ever calls gps.locate and a modem is a spare part [item 3].
  if not handOver("modem", 1, "wireless modem") and not manualFix(conf) then
    return false, "the modem did not reach it -- it cannot GPS, so it will never move"
  end
  -- An even share of the coal aboard, not a flat 64 out of the first slot. With
  -- 100 coal and three turtles the old code gave turtle 2 sixty-four, turtle 3
  -- the last thirty-six, and turtle 1 -- the deployer, the one turtle nobody
  -- can hand coal to later -- descended on whatever was left, often nothing
  -- [HARVEST-PLAN C2]. runDeploy divides the starting coal evenly and passes
  -- this turtle's share; a full 64*n kit still works out to 64 each.
  handOver("coal", coalShare or 64, "coal")
  handOver("bucket", 1, "bucket")
  -- A container each, the same way the bucket is one each: with a depot under
  -- its own trunk this turtle never leaves its own third to bank, which is
  -- what stops the head-on meetings on the one-wide spine [in-game 2026-08-29,
  -- logs qhVSH and fPSF1]. Matched with the STORAGE word list, not a pattern
  -- of its own -- there is one answer to "what is storage" [RESUME, settled].
  handOver(isContainer, 1, "container")

  -- It leaves under its own power once quarry N calibrates. An empty block in
  -- front is one signal; the floppy log and the turtle's own label are the
  -- other two, and between them they say whether anything ran at all.
  local logf = ("%s/deploy%d.log"):format(diskPath() or "/disk", index)
  local said, asked = 0, false

  -- The escalation ladder, and ORDER MATTERS because it used to be wrong.
  -- reboot on a computer that is OFF is a no-op -- there is nothing running to
  -- reboot -- and the old code fired one at 6s and again at 16s without ever
  -- confirming the turtle had come on, so on a turtle whose turnOn did not
  -- take, both reboots did nothing at all and the player was then asked to
  -- walk over. Turn on, confirm with isOn, and only then reboot.
  --
  -- `due` is the second the next rung may fire on, so each rung gets its own
  -- settling time rather than a fixed timetable: 2s to come on, 10s to run a
  -- startup. The player prompt below is NOT a rung -- it is what the log says
  -- once every rung has been tried, and the ladder starts again underneath it.
  local due, reboots, blind, cold = 0, 0, 0, false
  local wasOn
  sayf("deploy : waiting for turtle %d to boot and walk off (about 25s)", index)
  for i = 1, 120 do
    if not turtle.detect() then
      sayf("deploy : turtle %d left after %ds, its mine is its own now", index, i)
      return true
    end

    -- Two liveness signals, polled together. The floppy log is the detailed
    -- one and it is often unreadable from here: the drive sits above the
    -- PLACED turtle, so it is diagonal from this one, on no side of it, and
    -- /disk is not mounted here at all. getLabel needs no floppy -- boot.lua
    -- calls os.setComputerLabel("quarry" .. N) in its first seconds, well
    -- before the turtle walks off -- so it answers "did anything run" on its
    -- own, and it answers it fast.
    local on = frontAsk("isOn")
    local label = frontAsk("getLabel")
    local ran = fs.exists(logf) or (type(label) == "string" and label ~= "")
    if i == 1 or on ~= wasOn then
      sayf("deploy : turtle %d isOn=%s, label=%s%s", index, tostring(on),
        tostring(label or "none"), ran and "" or ", still no floppy log")
      -- A turtle that is on may simply not have finished its startup yet: it
      -- labels itself within the first seconds, so give it that window before
      -- rebooting it as one that "has run no startup". Rebooting at 1s throws
      -- away a startup that was about to succeed [HARVEST-PLAN A, test 126].
      if on == true then due = math.max(due, i + 2) end
      wasOn = on
    end

    if not ran and i >= due then
      if on == false then
        -- Placed and dark. turnOn is the only lever there is, and it costs
        -- nothing on a turtle that is already running, so it is repeated
        -- rather than sent once and hoped over.
        frontAsk("turnOn")
        sayf("deploy : %ds -- turtle %d is off, sent turnOn, asking isOn again in 2s",
          i, index)
        due = i + 2
      elseif on == true then
        if reboots < 2 then
          reboots = reboots + 1
          local _, err = frontAsk("reboot")
          sayf("deploy : %ds -- turtle %d is on and has run no startup, so sent reboot "
            .. "to turtle %d (%s)", i, index, index, err or "ok")
          due = i + 10
        elseif not cold then
          -- Colder than a reboot: it stops the computer and starts it again,
          -- which re-mounts the drive on the way up. Two reboots that changed
          -- nothing mean the disk startup is not being seen, not that the
          -- program on it is failing -- boot.lua would have written a line.
          cold = true
          frontAsk("shutdown")
          frontAsk("turnOn")
          sayf("deploy : %ds -- two reboots did nothing, so shut turtle %d down and "
            .. "turned it back on, which re-mounts the drive", i, index)
          due = i + 10
        end
      else
        -- isOn answered nothing at all, so this is not a computer this turtle
        -- can talk to -- a stale peripheral, or a CC old enough not to carry
        -- the method. Fall back to the blind sequence the deploy used before
        -- it could ask: there is no way to tell which lever is wanted, so pull
        -- both.
        blind = blind + 1
        frontAsk("turnOn")
        local _, err = frontAsk("reboot")
        sayf("deploy : %ds -- turtle %d will not answer isOn, so blind: turnOn, then "
          .. "sent reboot to turtle %d (%s)", i, index, index, err or "ok")
        due = i + 10
      end
    end

    if not asked and i >= 24 and not ran then
      asked = true
      -- Not a step in the deploy. Everything automatic above has been tried by
      -- now -- turnOn on a repeat, two reboots, a shutdown and a cold start --
      -- and the ladder starts again underneath this prompt whether anyone
      -- answers it or not [HARVEST-PLAN A2].
      sayf("deploy : turtle %d has not started in %ds, and isOn says %s.",
        index, i, tostring(wasOn))
      say("         RIGHT-CLICK IT. That is the one lever I do not have.")
      -- disk/quarry <n>, NOT disk/startup. In-game 2026-08-29 the user typed
      -- disk/startup on turtle 2 and it was not a file: the floppy had the
      -- program on it and no startup beside it, which is the bug the write
      -- order above fixes. disk/quarry <n> is the line they confirmed works,
      -- it is the one the startup would have run anyway, and it is right even
      -- on a floppy this build did not write.
      sayf("         If its screen is already lit, type this on it:  disk/quarry %d", index)
      local a = ask("deploy : enter = done, s = skip this turtle, q = stop deploying.", "", 60)
      if a:sub(1, 1) == "s" then return false, "skipped on your say-so" end
      if a:sub(1, 1) == "q" then return false, "stopped deploying on your say-so", "stop" end
      due, reboots, blind, cold = i, 0, 0, false
    end

    if fs.exists(logf) then
      local h = fs.open(logf, "r")
      if h then
        local lines = {}
        for line in h.readLine do lines[#lines + 1] = line end
        h.close()
        for n = said + 1, #lines do sayf("  turtle %d: %s", index, lines[n]) end
        if #lines > said then said = #lines end
      end
    elseif i % 10 == 0 then
      sayf("deploy : %ds, turtle %d still standing there (isOn=%s, label=%s)", i, index,
        tostring(on), tostring(label or "none"))
    end
    os.sleep(1)
  end
  -- Every lever this turtle has has now been pulled, more than once. What is
  -- left is a hand: a turtle placed by a turtle is off, turnOn is the only way
  -- to change that from here, and if the server refuses it then nothing in
  -- this program can.
  sayf("deploy : turtle %d did not start in 120s. The last isOn was %s.",
    index, tostring(wasOn))
  say("         I have sent turnOn, two reboots and a shutdown-and-on, and none of")
  say("         them moved it. Right-click it, and if its screen is already lit,")
  sayf("         type this on ITS screen:  disk/quarry %d", index)
  return false, ("turtle %d has not moved after 120s -- right-click it, or run "
    .. "disk/quarry %d on its own screen"):format(index, index)
end

-- Build the boot rig once, then run every remaining turtle through it. The
-- drive stays where it is: it is also the lava map's home [plan 7], and
-- breaking it to carry it down would cost the floppy inside it.
-- A floppy holds 125 kB and this program is past that, so what goes onto the
-- disk is the source with its full-line comments dropped -- 83 kB of the same
-- code. Anything inside a [[ long string ]] is left alone: DEFAULT_CONF is one,
-- and its blank lines and layout are the config file the deployed turtle reads.
-- Line numbers shift, so an error from a deployed turtle points into ITS copy.
local function readAllOf(path)
  local h = fs.open(path, "r")
  if not h then error("cannot read " .. path, 0) end
  local body = h.readAll()
  h.close()
  return body
end

-- A floppy holds 125 kB and this program does not, so what goes on it is the
-- source with every full-line comment dropped, every blank line dropped and
-- every line's indentation trimmed -- whitespace only, which Lua does not care
-- about, and 106 kB rather than 208. That margin is the whole deployment:
-- measured 2026-08-29, comments alone left 117 kB, and 117 plus the boot
-- files, the config and the claim anchor is over the limit -- which is how
-- turtle 2 ended up with `quarry` on its floppy and no `startup` beside it.
-- Anything inside a [[ long string ]] is left exactly as it is: DEFAULT_CONF
-- is one, and its blank lines and layout ARE the config file the deployed
-- turtle reads. Line numbers shift, so an error from a deployed turtle points
-- into ITS copy.
local function strippedBody(src)
  local out, long = {}, false
  for line in (readAllOf(src) .. "\n"):gmatch("([^\n]*)\n") do
    if long then
      out[#out + 1] = line
      if line:find("%]%]") then long = false end
    elseif not line:match("^%s*%-%-") then
      local tight = line:match("^%s*(.-)%s*$")
      if tight ~= "" then out[#out + 1] = tight end
      if line:find("%[%[") and not line:find("%]%]") then long = true end
    end
  end
  return table.concat(out, "\n") .. "\n"
end

-- Write it, then OPEN IT AGAIN AND READ IT BACK.
--
-- fs.open(name, "w") succeeds on a floppy that has no room left: the failure
-- lands on the write, or on the close, or nowhere at all -- the file is simply
-- shorter than what went into it. So counting handles opened is not counting
-- files written, and that is how a deploy came to print "wrote the boot script
-- for turtle 2" onto a floppy that did not have one. In-game 2026-08-29 the
-- user found turtle 2 sitting at a bare `CraftOS 1.9 >` prompt with `quarry`
-- on its floppy and no `startup` beside it: nothing to auto-run, and
-- `disk/startup` was not a file to type either.
--
-- A read-back is two extra file handles and it is the only thing that actually
-- answers "is it there?".
local function writeVerified(path, body)
  local h = fs.open(path, "w")
  if not h then return false, "it would not open for writing" end
  local okw, werr = pcall(h.write, body)
  local okc, cerr = pcall(h.close)
  if not okw then return false, "the write failed: " .. tostring(werr) end
  if not okc then return false, "the close failed: " .. tostring(cerr) end
  local r = fs.open(path, "r")
  if not r then return false, "it is not there after writing" end
  local okr, back = pcall(r.readAll)
  pcall(r.close)
  if not okr or type(back) ~= "string" then return false, "it will not read back" end
  if #back == 0 then return false, ("it read back EMPTY, %d bytes went in"):format(#body) end
  if back ~= body then
    return false, ("it read back %d bytes of the %d written"):format(#back, #body)
  end
  return true, #body
end

-- What the floppy has left, where the mod will say. Older CC has no
-- getFreeSpace and it is pcall'd like every other call out of this program, so
-- nil back means "no idea" rather than "nothing left".
local function freeOn(dir)
  if not (fs and fs.getFreeSpace) then return nil end
  local lived, n = pcall(fs.getFreeSpace, dir)
  if lived and type(n) == "number" then return n end
  return nil
end

-- The three tiny files a placed turtle actually needs, plus the number it is.
-- These go on the floppy BEFORE the 83 kB program, and that ordering is the
-- fix: they are the smallest files on the disk and the only ones that decide
-- whether a turtle boots at all, and written last they are exactly what a
-- floppy short of room drops. Let the program be the thing that does not fit.
local function writeBoot(DISK, n, conf)
  -- The startup goes on under BOTH names. Which one a disk's auto-startup
  -- picks up is the mod's business, not ours, and getting it wrong costs an
  -- in-game trip; writing both costs nothing and cannot pick the wrong one.
  -- What they run is boot.lua, beside them: the startup only records that it
  -- ran, so an empty floppy log is a disk startup that never happened and a
  -- log with one line in it is boot.lua failing [DEADLOCK-PLAN layer 3].
  -- The index is the turtle number, so `cd disk` then `quarry` with no number
  -- is still THIS turtle rather than turtle 1 [HARVEST-PLAN A5].
  local files = {
    { DISK .. "/startup.lua", BOOTSTRAP:format(n) },
    { DISK .. "/startup",     BOOTSTRAP:format(n) },
    { DISK .. "/boot.lua",    BOOT:format(n, tostring(manualFix(conf))) },
    { DISK .. "/index",       tostring(n) },
  }
  local sizes, bad = {}, {}
  for _, f in ipairs(files) do
    local okw, res = writeVerified(f[1], f[2])
    local base = f[1]:match("[^/]+$")
    if okw then
      sizes[#sizes + 1] = ("%s %d"):format(base, res)
    else
      bad[#bad + 1] = ("%s -- %s"):format(base, tostring(res))
    end
  end
  if #bad > 0 then
    sayf("deploy : THE BOOT FILES DID NOT LAND ON THE FLOPPY for turtle %d:", n)
    for _, b in ipairs(bad) do sayf("         %s", b) end
    return false, table.concat(bad, "; ")
  end
  sayf("deploy : wrote the boot script for turtle %d, read back off the floppy: %s",
    n, table.concat(sizes, ", "))
  return true
end

-- The drive does not always answer the moment the floppy goes in. replicator
-- loops on disk.getMountPath up to 20 times, half a second apart, with a move
-- and a move back after the tenth, because "sometimes the disk drive won't
-- show up" -- the same stale-peripheral problem as CC:Tweaked #660, which this
-- program already has to shake off the placed turtle by turning. runDeploy
-- asked once and errored out on nil, which turned half a second of the mod's
-- own bookkeeping into a failed deployment and a player walking over.
local function diskPathRetry()
  for n = 1, 20 do
    -- Ask the DRIVE itself, not diskPath(): the drive was just placed one up
    -- and in front, so this is the "sometimes the disk drive won't show up"
    -- lag we are retrying. diskPath()'s fs.exists("/disk") fallback would
    -- short-circuit the retry the moment that name exists -- and it is the
    -- wrong name anyway if this turtle already has a drive of its own, which
    -- puts this floppy at /disk2.
    local _, p = diskDrive()
    if p then
      if n > 1 then sayf("deploy : the drive answered on try %d, at %s", n, p) end
      return p
    end
    -- the same refresh trick deployOne uses on the placed turtle: a turn is an
    -- update, and right-then-left is a no-op for the heading tracked in st.dir.
    if n == 10 then
      say("deploy : the drive still says nothing -- turning to shake the peripheral")
      pcall(turtle.turnRight)
      pcall(turtle.turnLeft)
    end
    os.sleep(0.5)
  end
  -- twenty tries and the drive never named its mount: the conventional name is
  -- the last resort, exactly as plain diskPath() would fall back to.
  return fs.exists("/disk") and "/disk" or nil
end

-- With startX/Y/Z set there is no GPS to correct a copied file, so handing the
-- deployer's own coordinates on tells every turtle it is standing where turtle
-- 1 stands -- and each one then mines someone else's third. Every turtle is
-- placed in the one block in front, facing back at the deployer, so the fix is
-- known exactly: write that rather than copy the deployer's.
local function confForPlaced(conf, body)
  if not (conf.startX and conf.startY and conf.startZ) then return body end
  -- deploy runs before the mine does, so the heading is whatever the config
  -- said: nothing has turned yet.
  local dir = st.dir or conf.startDir or 0
  local d = DIRS[dir]
  local vals = { startX = st.x + d[1], startY = st.y, startZ = st.z + d[2],
                 startDir = (dir + 2) % 4 }
  body = pinBody(body, vals)
  sayf("deploy : GPS is manual, so the floppy says %d,%d,%d facing %d -- where the",
    vals.startX, vals.startY, vals.startZ, vals.startDir)
  say("         placed turtle actually stands, not where I stand.")
  return body
end

function runDeploy(conf, l, index)
  if index ~= 1 then
    error("deploy is turtle 1's job -- it is the one holding the kit", 0)
  end

  if (conf.turtles or 1) < 2 then
    say("deploy : turtles = 1 in quarry.conf, so there is nobody to deploy.")
    say("         Raise it and re-run, or just run `quarry 1` and mine alone.")
    return
  end

  say("deploy : auditing the kit before anything is placed")
  if not auditKit(conf) then
    say("deploy : nothing has been placed yet.")
    local a = ask("deploy : y = go on with what is aboard, enter = stop and let me fill it.", "n")
    if a:sub(1, 1) ~= "y" then
      say("deploy : STOPPED. Fill the gaps above and re-run.")
      return
    end
    say("deploy : going on short on your say-so.")
  end

  -- The coal split, measured BEFORE topUp so a full 64*n kit divides into an
  -- exact 64 each [HARVEST-PLAN C2]. The rule: coal aboard is divided evenly
  -- between every turtle the mine will run, the deployer included, so with C
  -- coal and k turtles still to place each placed turtle gets
  -- min(64, floor(C / (k+1))) and the deployer keeps the rest -- because the
  -- deployer is the one turtle nobody can hand coal to later. topUp then burns
  -- at most DEPLOY_TANK/80 (~13) coal for its own ride down, out of that rest.
  local staffed = type(st.staffed) == "table" and st.staffed or {}
  local pending = 0
  for n = 2, conf.turtles do if not staffed[n] then pending = pending + 1 end end
  local coalAboard = 0
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and d.name:find("coal") then coalAboard = coalAboard + d.count end
  end
  local coalShare = pending > 0 and math.min(64, math.floor(coalAboard / (pending + 1))) or 0
  if pending > 0 then
    sayf("deploy : %d coal aboard, %d to place -- %d coal each, I keep the other %d",
      coalAboard, pending, coalShare, coalAboard - coalShare * pending)
  end

  -- Fuel before the first move, and after the audit so it still counts a whole
  -- kit. A freshly placed turtle has an empty tank with its coal in the hold,
  -- and the deploy died on "cannot move up to place the drive" with 192 coal
  -- aboard [in-game 2026-08-28, log zog32].
  topUp(l)

  -- Not required yet: the last deploy was told to leave its drive standing
  -- here, so on every run after the first the drive and floppy are already in
  -- place and the hold has neither. Check them where they are used.
  local driveSlot = slotLike("disk_drive")
  local floppySlot = slotLike("disk[^_]") or slotLike("disk$")

  -- stepUp/stepDown keep the position in st, so deploy needs a fix before it
  -- moves -- and turtle 1 needs one to mine anyway. This also anchors the
  -- claim on the launch block, which is where every turtle here agrees.
  local x, y, z = locateOrAsk(conf)
  if not x then error("no position fix, and none was typed in", 0) end
  st.x, st.y, st.z = x, y, z
  st.home = st.home or { x = x, y = y, z = z }
  st.task = "deploy"
  save()

  if DRY then
    sayf("DRY deploy: would place the drive one up and in front, put the floppy in it,")
    sayf("           write /disk/startup.lua and copy this program to /disk/quarry,")
    sayf("           then for turtles 2..%d: place, hand over a modem, 64 coal and a", conf.turtles)
    sayf("           bucket, and wait for it to walk off under quarry <n>.")
    say("           Nothing is placed and no file is written. dry = false to run it.")
    return
  end

  -- 1. the drive, one block up, so it ends up directly above the new turtle.
  if not stepUp() then error("cannot move up to place the drive", 0) end
  -- "the drive and floppy stay here" is what the end of a deploy tells the
  -- player, so a second `quarry 1 deploy` finds its own drive in the spot it
  -- wants. Refusing there would fail every deploy after the first. Reuse it.
  local haveDrive = false
  if turtle.detect() then
    if frontType() == "drive" then
      say("deploy : the drive from the last run is still here -- reusing it")
      haveDrive = true
    else
      pcall(stepDown)
      error("something is in front of me one block up; move me somewhere clear", 0)
    end
  end
  if not haveDrive then
    if not driveSlot then error("no disk drive in the hold", 0) end
    turtle.select(driveSlot)
    local okd = select(2, pcall(turtle.place))
    if okd == false then
      pcall(stepDown)
      error("the disk drive would not place", 0)
    end
    say("deploy : disk drive placed")
  end

  -- A mount only exists when a floppy is in the drive, so it is the test for
  -- whether the last run's floppy is still in there. The name is asked for,
  -- never assumed: "/disk" is the FIRST drive's mount and this turtle may
  -- already have one of its own, which puts this floppy at "/disk2".
  local DISK = diskPath()
  if DISK then
    sayf("deploy : the floppy from the last run is still in the drive, at %s", DISK)
  else
    if not floppySlot then error("no floppy in the hold", 0) end
    turtle.select(floppySlot)
    if select(2, pcall(turtle.drop)) == false then
      error("the floppy would not go into the drive", 0)
    end
    DISK = diskPathRetry()
    sayf("deploy : floppy in the drive, mounted at %s", tostring(DISK))
  end

  if not DISK then
    error("the drive mounted nothing in 20 tries over 10s -- is the floppy really in it?", 0)
  end

  -- 2. the boot files, FIRST. They are about three kilobytes between them and
  --    they are the whole of what makes a placed turtle start itself; the
  --    program below is eighty. Written after it, they are what a floppy with
  --    no room left silently drops, and a turtle whose floppy has `quarry` and
  --    no `startup` boots to a bare CraftOS prompt and waits for a human --
  --    which is exactly what the user found on turtle 2 [2026-08-29].
  --    They are rewritten per turtle in the loop below; this pass reserves the
  --    space for them and proves the floppy will take them at all.
  st.staffed = type(st.staffed) == "table" and st.staffed or {}
  local firstPending
  for n = 2, conf.turtles do
    if not st.staffed[n] then firstPending = n break end
  end
  if firstPending then
    say("deploy : the boot files go on before the program, so the program is what")
    say("         does not fit if anything does not fit.")
  end
  if firstPending and not writeBoot(DISK, firstPending, conf) then
    error("the boot files will not stay on the floppy -- there is nothing to deploy with", 0)
  end

  -- 3. the config and the claim anchor, still ahead of the program. A deployed
  --    turtle that seeds its own config gets dry = true and never moves, which
  --    reads exactly like a hung deployment.
  if fs.exists(CONF) then
    if fs.exists(DISK .. "/quarry.conf") then fs.delete(DISK .. "/quarry.conf") end
    local cbody = confForPlaced(conf, readAllOf(CONF))
    local okc, whyc = writeVerified(DISK .. "/quarry.conf", cbody)
    if not okc then error("cannot write " .. DISK .. "/quarry.conf -- " .. tostring(whyc), 0) end
    sayf("deploy : copied %s to %s/quarry.conf (dry = %s)", CONF, DISK, tostring(conf.dry))

    -- The claim anchor rides with it. A placed turtle wakes one block in front
    -- of me, which is over a chunk border often enough to matter, and claimOf()
    -- would then give it a whole different region to mine -- a second mine,
    -- not a third of this one. Only the home is seeded: no position and no
    -- heading, so locate() still starts it on its own pin, and its own state
    -- overwrites this the moment it saves.
    if fs.exists(DISK .. "/quarry.state") then fs.delete(DISK .. "/quarry.state") end
    if writeVerified(DISK .. "/quarry.state",
        textutils.serialise({ home = { x = st.home.x, y = st.home.y, z = st.home.z } })) then
      sayf("deploy : claim anchor %d,%d on the floppy, so we all mine one claim",
        st.home.x, st.home.z)
    end
    if conf.dry ~= false then
      say("         NOTE: dry is still true, so the turtles will plan and not move.")
    end
  else
    error("no " .. CONF .. " to hand on -- run --check once to seed it", 0)
  end

  -- 4. the payload, LAST, because it is the only thing here that is elastic.
  --    The program copies ITSELF, so a deployed turtle always runs the same
  --    build as the one that placed it -- no second wget, and no way for the
  --    two to drift apart.
  local me = shell and shell.getRunningProgram and shell.getRunningProgram()
  if not me or not fs.exists(me) then
    error("cannot find my own file to copy onto the floppy", 0)
  end
  if fs.exists(DISK .. "/quarry") then fs.delete(DISK .. "/quarry") end
  local body = strippedBody(me)
  local free = freeOn(DISK)
  sayf("deploy : the floppy has %s bytes free and the stripped program is %d",
    tostring(free or "an unknown number of"), #body)
  -- A truncated program is worse than no program: it is a syntax error the
  -- deployed turtle only finds out about after it has been fed and switched
  -- on. Refuse the copy rather than write half of one.
  if free and free < #body then
    error(("the program will not fit: %d bytes free, %d needed. The boot files are "):format(
      free, #body) .. "on the floppy and intact; raise floppy_space_limit in the "
      .. "CC:Tweaked server config, or take a floppy with less on it", 0)
  end
  local wrote, why = writeVerified(DISK .. "/quarry", body)
  if not wrote then
    pcall(fs.delete, DISK .. "/quarry")
    error(("the program did not land on the floppy (%d bytes stripped) -- %s"):format(
      #body, tostring(why)), 0)
  end
  sayf("deploy : copied %s to %s/quarry (%d bytes, comments stripped, read back)",
    me, DISK, #body)


  if not stepDown() then error("cannot move back down after loading the floppy", 0) end

  -- 3. one turtle at a time through the same spot. Each leaves before the next
  --    is placed, which is why one drive serves all of them.
  -- A re-run picks up where the last one stopped. The loop used to start at 2
  -- every time, so every retry re-did the turtles that had already walked off
  -- -- and once turtle 2 was out there, the next turtle ITEM in the hold was
  -- placed and labelled quarry 2 as well: two turtles on one third, and turtle
  -- 3's third never worked at all. Which indices are out is state, so it goes
  -- in quarry.state with everything else. NOT under `deployed`: that name held
  -- the abandoned one-shot boolean [test 72], and a state file written by an
  -- older build still carries it.
  local done, failed = 0, {}
  for n = 2, conf.turtles do
    if st.staffed[n] then
      sayf("deploy : turtle %d is already out at its own trunk -- not placing", n)
      say("         another one for it. Delete quarry.state if that is wrong.")
      done = done + 1
      goto next
    end
    -- Rewritten for this turtle, and read back off the floppy every time. The
    -- space for them was taken above, before the program went on, so this is
    -- an overwrite of files that already exist at almost exactly this size.
    local okb, whyb = writeBoot(DISK, n, conf)
    if not okb then
      failed[#failed + 1] = ("turtle %d: %s"):format(n, tostring(whyb))
      sayf("deploy : turtle %d gets no boot files, so placing it would only strand", n)
      say("         it at a CraftOS prompt. Not placing it.")
      break
    end

    -- And the disk itself says who it is for, harvested from replicator, which
    -- names each floppy after the baby it is for. Best effort: disk.setLabel
    -- addresses the DRIVE, and from where this turtle stands to place turtles
    -- the drive is one up and one forward -- diagonal, on no side of it -- so
    -- there is usually nothing to address. It costs one line and it is free
    -- when the player has put the drive somewhere this turtle can see.
    local dside = diskDrive()
    if dside and disk and disk.setLabel then
      local lived = pcall(disk.setLabel, dside, "quarry" .. n)
      if lived then sayf("deploy : labelled the floppy quarry%d", n) end
    end

    local okn, why, stop = deployOne(conf, l, n, coalShare)
    if okn then
      done = done + 1
      st.staffed[n] = true
      save()
    else
      failed[#failed + 1] = ("turtle %d: %s"):format(n, tostring(why))
      sayf("deploy : turtle %d did not deploy -- %s", n, tostring(why))
      -- It is still standing in the one block a turtle can be placed into, so
      -- the next pass round this loop would adopt it as turtle n+1 -- switch it
      -- on again, hand it a SECOND modem, coal and bucket, and overwrite its
      -- boot script so that when the player finally right-clicks it, it wakes
      -- up as the wrong turtle. That is what "both buckets and modems ended up
      -- on turtle 2" was. Adoption is for a turtle a PREVIOUS run stranded;
      -- one this run just stranded is a spot that has to be cleared first.
      if turtle.detect() and frontType() == "turtle" then
        sayf("deploy : turtle %d is still standing in the only spot I can place", n)
        say("         into, so there is nowhere to put the next one. Get it moving")
        sayf("         first -- right-click it, or on its screen: disk/quarry %d -- then", n)
        say("         `quarry 1 deploy` again to carry on from here.")
        stop = true
      end
    end
    if stop then
      if n < conf.turtles then
        sayf("deploy : turtle %d onwards is still in the hold. `quarry 1 deploy`", n + 1)
        say("         again when you are ready for it.")
      end
      break
    end
    ::next::
  end

  sayf("deploy : %d of %d deployed", done, conf.turtles - 1)
  for _, f in ipairs(failed) do sayf("         %s", f) end
  say("deploy : the drive and floppy stay here; they are the lava map's home.")
  say("         Now run `quarry 1` to start mining. Give me a barrel or a chest")
  say("         and I will put it under the trunk floor myself, or put one there")
  say("         by hand -- UNDER the floor block, never beside it.")
end

-- main ---------------------------------------------------------------------

if not turtle then error("run this on a turtle, not a computer", 0) end

print("quarry starting")          -- liveness: silence after this line is a hang

local args = { ... }

-- Started off the floppy. `cd disk` then `quarry` is what a player reaches for
-- when a deployed turtle did not boot itself, and it half-works: the mine runs,
-- but the PROGRAM is on the floppy, which stays in the drive at the surface.
-- The moment this turtle walks away it cannot be restarted -- /startup runs
-- `quarry <n>` and there is no quarry on the turtle to run. So install first,
-- then hand the run to the installed copy. This is what disk/startup does,
-- minus the label, the modem and the fuel.
-- fs resolves a relative path from the root, so the copies below land on the
-- turtle. shell.run does NOT -- it resolves against the shell's directory,
-- which is the floppy on this route, so the handover has to name /quarry.lua
-- or the shell looks for it on the floppy and finds nothing.
--
-- The mount is asked for, not assumed to be "/disk": a turtle that already has
-- a drive of its own mounts this floppy at "/disk2", and a prefix test against
-- "disk/" then says this run is on the turtle when it is not -- so it installs
-- nothing, writes its state to the floppy, and cannot be restarted once it
-- walks away. That is the turtle you have to go and type commands into.
local me = shell and shell.getRunningProgram and shell.getRunningProgram()
local DISK = diskPath()
local onFloppy = false
if me then
  local full = (me:sub(1, 1) == "/") and me or ("/" .. me)
  if DISK and full:sub(1, #DISK + 1) == (DISK .. "/") then
    onFloppy = true
  elseif full:match("^/disk%d*/") then
    -- The drive answered nothing -- it is not on a side of this turtle, which
    -- is the normal case for a turtle standing away from the launch block --
    -- but the path still says where this program is running from. Asking the
    -- drive is the better answer where there IS one; the name is what is left
    -- when there is not, and without this fallback a `cd disk` + `quarry 2`
    -- run installs nothing at all [user, 2026-08-29].
    onFloppy = true
    DISK = full:match("^(/disk%d*)/")
  end
end
if onFloppy then
  sayf("startup: I am running off the floppy at %s, which stays here when I leave.", DISK)
  say("         Installing to this turtle and starting that copy instead.")
  for _, n in ipairs({ "quarry", "quarry.lua" }) do
    if fs.exists(n) then fs.delete(n) end
  end
  fs.copy(me, "quarry.lua")
  -- Same anti-drift rules as the boot script: take the deployer's config and
  -- claim anchor, and never overwrite one this turtle already has.
  if fs.exists(DISK .. "/quarry.conf") and not fs.exists(CONF) then
    fs.copy(DISK .. "/quarry.conf", CONF)
    say("startup: took the deployer's quarry.conf")
  end
  if fs.exists(DISK .. "/quarry.state") and not fs.exists(STATE) then
    fs.copy(DISK .. "/quarry.state", STATE)
    say("startup: took the deployer's claim anchor")
  end
  -- Which turtle is this? `cd disk` then `quarry`, with no number, is what the
  -- user actually types [2026-08-29], and the parse below reads `index or 1`,
  -- so that run mines turtle 1's third out of turtle 1's trunk and deploys yet
  -- another turtle. The deploy that wrote this floppy knew the answer and left
  -- it beside boot.lua; a number typed on the command line still wins, because
  -- somebody typing one means it.
  local typed = false
  for _, a in ipairs(args) do if tonumber(a) then typed = true end end
  if not typed and fs.exists(DISK .. "/index") then
    local h = fs.open(DISK .. "/index", "r")
    local n = h and tonumber(((h.readAll() or ""):match("%d+")))
    if h then h.close() end
    if n then
      args[#args + 1] = tostring(n)
      sayf("startup: the floppy was written for turtle %d, so that is what I run as", n)
    end
  end
  say("startup: installed as /quarry.lua -- `quarry <n>` from now on")
  return shell.run("/quarry.lua", table.unpack(args))
end
local index, mode = nil, nil
for _, a in ipairs(args) do
  if a == "--check" then mode = "check"
  elseif a == "recall" then mode = "recall"
  elseif a == "deploy" then mode = "deploy"
  elseif a == "stop" then mode = "stop"
  elseif tonumber(a) then index = tonumber(a)
  else error("usage: quarry <1|2|3> [--check|recall|deploy|stop]", 0) end
end

-- `quarry stop` parks the turtle before it is picked up and moved. On first
-- boot the turtle writes its OWN /startup that re-runs `quarry N` on every
-- reboot or chunk reload, independent of the floppy -- so moving it does not
-- stop it, the next reboot resumes from quarry.state. This is the one-word form
-- of `delete startup` + `delete quarry.state`: no config, no position fix, no
-- modem needed, so it runs before any of that is loaded. Ctrl+T first if the
-- mine is still running.
if mode == "stop" then
  local gone = {}
  for _, f in ipairs({ "/startup", STATE }) do
    if fs.exists(f) then fs.delete(f) gone[#gone + 1] = f end
  end
  -- Also drop the pinned coordinates, so a turtle carried somewhere new does not
  -- re-pin to where it used to stand [user, 2026-08-29]. Commented, not deleted.
  local unpinned = false
  if fs.exists(CONF) then
    local h = fs.open(CONF, "r")
    local body = h and h.readAll() or ""
    if h then h.close() end
    local cleaned = unpinBody(body)
    if cleaned ~= body then
      local w = fs.open(CONF, "w")
      if w then w.write(cleaned) w.close() unpinned = true end
    end
  end
  if #gone > 0 or unpinned then
    if #gone > 0 then
      sayf("stopped: deleted %s -- I will not auto-resume.", table.concat(gone, " and "))
    end
    if unpinned then
      say("stopped: commented out startX/Y/Z/startDir in quarry.conf, so my old pin")
      say("         will not follow me if you move me.")
    end
    say("         `quarry <n>` starts a fresh claim wherever I am then.")
  else
    say("stopped: no /startup, quarry.state or pinned coords to clear -- already parked.")
  end
  return
end

local seeded = not fs.exists(CONF)
if seeded then seedConf() end

local conf, l, source = readConf()
if not conf then error(source, 0) end
cfg, lists = conf, l          -- the junk valve inside clear() reads the lists
if seeded then source = "written just now, edit it and re-run" end

index = index or 1
if index < 1 or index > conf.turtles then
  error(("turtle index %d is outside 1..%d"):format(index, conf.turtles), 0)
end
load()
st.index = index

-- DRY ships true and quarry.conf can only lower it. Keeping the switch in the
-- config means it survives re-downloading the program, which the program's own
-- constant does not.
if conf.dry == false then DRY = false end

if mode == "check" then
  check(conf, l, source, index)
  upload()
  return
end

if mode == "deploy" then
  local ok, err = pcall(runDeploy, conf, l, index)
  if not ok then sayf("CRASHED: %s", tostring(err)) end
  upload()
  return
end

if mode == "recall" then
  local ok, err = pcall(runRecall, conf, l, index)
  if not ok then sayf("CRASHED: %s", tostring(err)) end
  upload()
  return
end

if DRY then
  dryRun(conf, l, index)
else
  local function mine()
    local ok, err = pcall(runMine, conf, l, index)
    if not ok then sayf("CRASHED: %s", tostring(err)) end
  end
  -- The lava listener has to be blocked on rednet.receive for the whole run
  -- rather than drained at dock time: a message that arrives while
  -- turtle.forward() waits for its turtle_response is pulled and discarded by
  -- the turtle API, so by dock time it is gone [see lavaListen]. waitForAny
  -- ends when the mine ends; the listener never returns on its own.
  if type(parallel) == "table" and parallel.waitForAny then
    parallel.waitForAny(mine, lavaListen)
  else
    mine()
  end
end
upload()
