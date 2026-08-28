-- quarry : three turtles read a chunk-snapped 3x3 claim with mod-5 branches
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
  veinMax      = 64,    -- hard cap on blocks per vein chase
  veinDepth    = 12,    -- how far a vein chase may wander off the branch
  fuelMargin   = 64,    -- spare fuel kept on top of the walk home
  tripBlocks   = 96,    -- blocks carried before the inventory forces a depot run
  fuelShare    = 128,   -- coal in the hold that sends a turtle home to bank it
  fuelFloor    = 8,     -- coal held back in the depot chest for each OTHER turtle
  lavaFloor    = 4000,  -- scoop a passing lava source when the tank is under this
  saveSamples  = 200,   -- --check writes the state file this many times to time it
}
local STR = {
  oreTags      = "c:ores",
}
local BOOL = {
  deepestFirst = true,
  lava         = true,   -- the scoop was proven in-game 2026-08-27, bucket came back
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
veinMax      = 64      # blocks per vein chase, hard cap
veinDepth    = 12      # how far a chase may wander off the branch
fuelMargin   = 64      # spare fuel kept on top of the walk home
tripBlocks   = 96      # blocks carried before the inventory forces a depot run
fuelShare    = 128     # coal in the hold that sends a turtle home to bank it for the others
fuelFloor    = 8       # coal left in the chest for each OTHER turtle; under that, forage
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
-- centre chunk keeps all nine loaded; the branch pattern anchors to the block
-- the turtle started on.

local function claimOf(x, z)
  local cx, cz = math.floor(x / 16), math.floor(z / 16)
  local c = {
    cx = cx, cz = cz,
    xMin = (cx - 1) * 16, xMax = (cx + 1) * 16 + 15,
    zMin = (cz - 1) * 16, zMax = (cz + 1) * 16 + 15,
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
-- every turtle standing anywhere in the same 3x3 chunk region computes the
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

-- gps.locate's own default is 2s, which is one round trip to four hosts and no
-- slack. A rebuilt constellation at the edge of modem range answers late rather
-- than not at all, and this is called about four times in a whole run, so the
-- extra wait is free and a false NO FIX is not. Raised from 5s to 10s on the
-- user's instruction 2026-08-28: a whole run pays 40s at worst, and a NO FIX
-- underground costs a trip out to the turtle.
local GPS_TIMEOUT = 10

local function locate(conf)
  if conf.startX and conf.startY and conf.startZ then
    -- A pinned position is a starting value, not a sensor. It names the block
    -- the turtle was launched from, and a turtle that has been running is not
    -- standing there any more -- with no GPS to correct it, which is the whole
    -- reason it is pinned, the saved state is the only thing that knows where
    -- it went. So the state wins whenever it has a full fix of its own; a
    -- freshly deployed turtle has none, and starts on the pin.
    if st.x and st.y and st.z and st.dir then
      return st.x, st.y, st.z, "quarry.state"
    end
    return conf.startX, conf.startY, conf.startZ, "quarry.conf"
  end
  if gps then
    local ok, x, y, z = pcall(gps.locate, GPS_TIMEOUT)
    if ok and x then return math.floor(x), math.floor(y), math.floor(z), "gps" end
  end
  -- Underground there may be no constellation to reach: a wireless modem's
  -- range shrinks with depth, and hosts near the surface are a hundred-odd
  -- blocks above the claim floor. GPS being healthy up top says nothing about
  -- y=-59 [in-game 2026-08-28, log td7FE: a turtle parked at the depot, modem
  -- equipped, no host answering]. The state file is written every block and
  -- carries the heading GPS never gives, so a turtle that has been running
  -- already knows where it is. Last resort, and never silent: a turtle someone
  -- picked up and moved cannot tell, so every user of this says where it came
  -- from.
  if st.x and st.y and st.z and st.dir then
    return st.x, st.y, st.z, "quarry.state"
  end
  return nil, nil, nil, "no fix"
end

-- A turtle reaches gps.locate only through an equipped WIRELESS modem, and
-- "wireless" is not the same question as "is there a modem". CC's gps.locate
-- walks the sides looking for one whose isWireless() is true, so a WIRED modem
-- equips happily, reports its type as "modem" exactly as a wireless one does,
-- and still yields no fix ever. Those are two different problems with two
-- different answers, so this tells them apart rather than reporting "modem"
-- for both. The pickaxe is not a peripheral, so it reads as nil here.
local function equippedSides()
  local out = {}
  for _, side in ipairs({ "left", "right" }) do
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
    why = "the depot: one box, for ore and for the coal we share" },
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
local function kitWants(conf)
  local n = conf.turtles or 1
  return { turtle = n - 1, chest = 1, drive = 1, floppy = 1,
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

  local e = equippedSides()
  sayf("equipped: left=%s  right=%s", tostring(e.left or "tool or empty"),
    tostring(e.right or "tool or empty"))

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

  local c = claimOf(x, z)

  sayf("claim  : chunks %d..%d by %d..%d", c.cx - 1, c.cx + 1, c.cz - 1, c.cz + 1)
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
local YIELD_TRIES = 6

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
  local idx = st.index or 1
  for try = 1, YIELD_TRIES do
    sayf("giveway: turtle %d waiting, another one is in the way (%d of %d)",
      idx, try, YIELD_TRIES)
    os.sleep(idx * 1.5)
    if not turtleAt(detect, inspect) then return true end
  end
  jammed = true
  return false
end

-- Pull off the corridor so the other turtle can pass. A branch mouth every 5
-- blocks along the spine is already a passing bay [plan 8]; anywhere else,
-- one block backwards is the best that a 1-wide tunnel offers.
local function stepAside()
  jammed = false
  local c = claim
  if c and st.y == (st.level or st.y) and st.x == c.spine and isBranch(c, st.y, st.z) then
    turnTo(1)                      -- west into the mouth: a row that gets mined anyway
    if step() then return true end
  end
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

-- Never sidestep out of the claim. The claim is the 3x3 chunk region the
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
    if not jammed or aside >= 3 then return true end
    aside = aside + 1
    return not stepAside()
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
  -- the 3x3 the player holds open by standing in the centre chunk. Upward it is
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
    if not room() or (st.carried or 0) >= conf.tripBlocks
       or (st.depot and fuelAboard(l) >= conf.fuelShare) then
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
  return true
end

-- depot --------------------------------------------------------------------
-- Phase 3. The depot is found, never configured. Standing on the trunk floor
-- the turtle looks at all four sides for a container, then takes one item out
-- of each and puts it straight back to learn which one holds fuel. Both
-- coordinates go in the state file, so the probe happens once per claim and a
-- killed turtle picks up where it left off.

local LAVAMAP   = "/disk/lava.txt"
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
  st.depot = { x = st.x, y = st.y, z = st.z, dump = dump or fuelDir, fuel = fuelDir or dump }
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

local function buildDepot(l, c)
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
          st.depot = { x = st.x, y = st.y, z = st.z, dump = sp.dir, fuel = sp.dir }
          save()
          -- Everything burnable this turtle still carries goes in, and from
          -- here on it rations out of it like the other two do [plan 7].
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
          if banked > 0 then sayf("depot  : banked %d fuel into it for all three", banked) end
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

  -- The old rule took a third of whatever the chest happened to hold, which
  -- made the shares unequal: on 300 coal three dockers take 100, then 66, then
  -- 44, because each takes a third of what the last one left, and 90 sit there
  -- for good. Take what this trip actually needs instead, down to a floor held
  -- back for the other turtles. Above the floor every turtle gets the same
  -- `want`; at it nobody takes anything and they forage, which is the designed
  -- dry-depot path. The floor scales with conf.turtles -- the old literal 3
  -- reserved for three turtles however many were actually running.
  local others = math.max(0, math.floor(conf.turtles or 3) - 1)
  local held   = others * math.max(0, conf.fuelFloor or 0)
  local share  = math.max(0, total - held)
  local keep   = math.min(share, math.max(want, 0))
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
  if not fs.exists(LAVAMAP) then return out end
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
  local f = fs.open(LAVAMAP, "w")
  f.write(table.concat(lines, "\n") .. "\n")
  f.close()
end

-- Merge what this trip saw into the shared map. Called only while docked.
local function mapMerge()
  if not fs.exists("/disk") then return 0 end
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
  if not fs.exists("/disk") then return end
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
        mapDrop(x, y, z)
      else
        -- Capped because save() serialises the whole state table on every dug
        -- block, and mapMerge -- the only thing that empties these -- is a
        -- no-op wherever /disk is not mounted. Unbounded, they turn every
        -- save of a long run into a longer one.
        st.lava, st.lavaSeen = st.lava or {}, st.lavaSeen or {}
        if not st.lavaSeen[k] and #st.lava < LAVA_KEEP then
          st.lavaSeen[k] = true
          st.lava[#st.lava + 1] = { x = x, y = y, z = z }
          save()
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

-- Foraging, only when the depot is dry [plan 7]: nearest mapped lava source
-- first, then a top-level branch (coal lives y=0..192 and those levels are on
-- the schedule anyway), then park.
function forage(conf, l, c)
  if conf.lava and findItem("minecraft:bucket") then
    local best, bd
    for _, p in ipairs(mapRead()) do
      local d = math.abs(p.x - st.x) + math.abs(p.y - st.y) + math.abs(p.z - st.z)
      if d * 2 + conf.fuelMargin < fuelLevel() and (not bd or d < bd) then best, bd = p, d end
    end
    if best then
      sayf("forage : mapped lava source at %d,%d,%d, %d blocks off", best.x, best.y, best.z, bd)
      st.task = "forage" save()
      if goTo(best.x, best.y + 1, best.z) then
        local ok, hit, data = pcall(turtle.inspectDown)
        if ok and hit and isSource(data) and scoop(conf, "down") then
          mapDrop(best.x, best.y, best.z)
          return true
        end
      end
      mapDrop(best.x, best.y, best.z)   -- gone or unreachable: stop trying it
    end
  end
  local top = conf.topY
  if st.level ~= top then
    sayf("forage : depot is dry -- taking a branch at y=%d instead, where the coal is", top)
    st.level, st.branch, st.leg, st.along = top, nil, nil, 0
    st.plan, st.step = nil, nil
    save()
    return true
  end
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

  if fuelLevel() < want then
    if not forage(conf, l, c) then
      halt = ("depot is dry and there is nothing to forage: %d fuel, %d needed")
        :format(fuelLevel(), want)
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
    sayf("fuel   : %d coal banked in the depot chest for the other turtles",
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
-- One depot serves all three [plan 5] and it stands at one trunk floor, so
-- two turtles out of three find nothing under their own. Rather than spend a
-- spine walk on every boot, the sweep waits until a turtle actually needs the
-- depot -- and then happens once, because the answer is saved either way.
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
        if goTo(c.spine, y0 + off, tz) and probeDepot(l) then
          local dp = st.depot
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
  local c = claimOf(st.home.x, st.home.z)
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
    local hc = claimOf(st.home.x, st.home.z)
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
        report(claimOf(st.home.x, st.home.z), conf)
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
  local c = claimOf(st.home.x, st.home.z)
  claim = c
  local lo, hi, trunkZ = thirdOf(c, index, conf.turtles)
  sayf("quarry %d  at %d,%d,%d  claim x %d..%d z %d..%d (anchored at %d,%d)",
    index, x, y, z, c.xMin, c.xMax, c.zMin, c.zMax, st.home.x, st.home.z)
  sayf("third  : z %d..%d, trunk at x=%d z=%d", lo, hi, c.spine, trunkZ)

  topUp(l)
  local okc, why = calibrate(conf)
  if not okc then error("cannot work out which way I am facing: " .. tostring(why), 0) end
  sayf("heading: %d, fuel %d", st.dir, fuelLevel())

  -- Refuse the trip it cannot pay for, while still at the surface where the
  -- user can reach it. The reserve inside the branch is what stops it later;
  -- this is what stops it stranding itself 119 blocks down before it starts.
  local travelY = math.min(st.y, conf.topY)
  local target  = st.level or (conf.deepestFirst and conf.bottomY or conf.topY)
  local trip = (st.y - travelY) + math.abs(c.spine - st.x) + math.abs(trunkZ - st.z)
             + math.max(travelY - target, 0)
  local need = 2 * trip + conf.fuelMargin
  if fuelLevel() < need then
    halt = ("not enough fuel: %d in the tank, %d to reach the branch and walk back")
      :format(fuelLevel(), need)
    report(c, conf)
    return
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
      local built = buildDepot(l, c)
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
    if st.needDock or fuelLevel() < want then
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
    -- Change level in the spine column, never out on a leg. goTo moves y first,
    -- so a turtle that finished a level at the rim would climb there and then
    -- bulldoze west along a z the new level has no row on -- the same mistake
    -- the walk home used to make, and now possible because a leg ends at the
    -- rim rather than back at the mouth.
    if st.y ~= st.level and not goTo(c.spine, st.y, st.z) then
      if st.needDock then goto nextpass end
      break
    end
    -- The jog between the two rows is this goTo: from the rim of one row to the
    -- rim of the other, 5 blocks of rock instead of a 24-block walk back down a
    -- corridor that is already air.
    local bx = c.spine + ((job.leg == "west") and -st.along or st.along)
    if not goTo(bx, st.level, st.branch) then
      if st.needDock then goto nextpass end
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

  -- Park, but do NOT clear the leg position on a stop: that is the resume
  -- point, and a stopped turtle is resumed far more often than a finished one.
  st.task = "park"
  if not halt then st.leg, st.along = nil, 0 end
  save()
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
  local c = claimOf(st.home and st.home.x or x, st.home and st.home.z or z)
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

local BOOT = [==[
-- written by quarry deploy. Runs on a freshly placed turtle: no label, no
-- fuel, no modem, and an inventory its deployer is still filling.
local N = %d
-- true when quarry.conf pins the position by hand: nothing on this turtle then
-- calls gps.locate, so it needs no modem and must not stop for the want of one.
local MANUAL = %s
os.setComputerLabel("quarry" .. N)

-- Nobody is watching this screen. Every stage is written to the floppy as well,
-- so the deployer standing behind can read back what actually happened rather
-- than inferring it from a turtle that did not move.
local LOG = "/disk/deploy" .. N .. ".log"
if fs.exists(LOG) then fs.delete(LOG) end
local function note(msg)
  print("quarry" .. N .. ": " .. msg)
  local h = fs.open(LOG, "a")
  if h then h.writeLine(msg) h.close() end
end

note("booted, waiting for my kit")

-- quarry.lua, not quarry: that is the name turtle 1 runs and the name update
-- writes, and a turtle carrying both ends up running whichever the shell picks.
if fs.exists("quarry") then fs.delete("quarry") end
if fs.exists("quarry.lua") then fs.delete("quarry.lua") end
fs.copy("/disk/quarry", "quarry.lua")

-- The config has to follow the program. Without it this turtle seeds a fresh
-- quarry.conf off the shipped defaults -- which since 2026-08-27 mine for real
-- -- so it goes live on settings its deployer never chose: veinMax, tripBlocks,
-- the ore names and the fuel sections all revert. Same anti-drift rule as the
-- program itself: take the deployer's file, do not re-derive one.
-- Only when this turtle has none of its own. It used to overwrite on every
-- boot, so coordinates typed in by hand were wiped by the next reboot and the
-- turtle asked for them again -- forever, for as long as it stood beside the
-- drive [user, 2026-08-28].
if fs.exists("/disk/quarry.conf") and not fs.exists("quarry.conf") then
  fs.copy("/disk/quarry.conf", "quarry.conf")
  note("took the deployer's quarry.conf")
elseif fs.exists("quarry.conf") then
  note("keeping my own quarry.conf")
else
  note("WARNING: no quarry.conf on the floppy -- seeding one from the defaults;")
  note("         it MINES, but on default settings, not the deployer's")
end

-- The claim is anchored on the block a turtle wakes on, and this turtle wakes
-- one block in front of its deployer -- which is over a chunk border often
-- enough to matter. claimOf() would then hand it a different 3x3 region and it
-- would sink a trunk in a mine of its own. The deployer's anchor is on the
-- floppy for exactly that reason; take it, and never overwrite a state file
-- this turtle has already written for itself.
if fs.exists("/disk/quarry.state") and not fs.exists("quarry.state") then
  fs.copy("/disk/quarry.state", "quarry.state")
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
-- disarms the turtle: equip swaps, so the pickaxe would land in the inventory
-- and this turtle could not dig. Do it, look at what came off, and undo it if
-- that was the pickaxe.
if modemSlot then
  turtle.select(modemSlot)
  local okR = turtle.equipRight()
  local came = turtle.getItemDetail()
  if came and came.name:find("pickaxe") then
    turtle.equipRight()             -- pickaxe back on the right, modem back in hand
    local okL = turtle.equipLeft()  -- modem goes left instead
    note("equipRight " .. tostring(okR) .. ", pickaxe came off, equipLeft " .. tostring(okL))
  else
    note("equipRight " .. tostring(okR) .. ", nothing came off")
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
]==]

local function slotLike(pat)
  for s = 1, 16 do
    local ok, d = pcall(turtle.getItemDetail, s)
    if ok and d and d.name:find(pat) then return s, d.name, d.count end
  end
end

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
  local s = slotLike(pat)
  if not s then sayf("deploy : no %s to hand over", what) return false end
  turtle.select(s)
  -- pcall prepends its own success flag, so turtle.drop's answer is the SECOND
  -- value. Reading the first as the drop result made every failed drop look
  -- like a success, which is how a turtle got left standing with no modem.
  local lived, dropped = pcall(turtle.drop, count)
  if not lived then
    sayf("deploy : could not hand over the %s: %s", what, tostring(dropped))
    return false
  end
  if dropped == false then
    sayf("deploy : the %s would NOT go across -- is the turtle really in front?", what)
    return false
  end
  sayf("deploy : handed over the %s", what)
  return true
end

-- One turtle: place it, feed it, wait for it to walk off. Returns false and a
-- reason, never throws, because a half-deployed mine still wants its report.
local function deployOne(conf, l, index)
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

  -- Turn it on. The probe read a nil peripheral.wrap and we took that to mean a
  -- placed turtle self-boots; two live deploys say otherwise -- it sat there
  -- with no label, which is a turtle that never ran anything. Known-good
  -- replicator code calls turnOn on the side it placed into, so try that. It
  -- costs nothing if the turtle was already running.
  -- CC-Tweaked issue #660: a turtle's peripheral discovery goes stale, and
  -- "causing any kind of update will make turtle see peripheral again --
  -- turning turtle". The block in front was air a moment ago, so a bare
  -- getType honestly reports nothing. Turn to force the refresh; right then
  -- left is a no-op for the heading tracked in st.dir, so nothing else shifts.
  local ptype
  for _ = 1, 6 do
    ptype = select(2, pcall(peripheral.getType, "front"))
    if ptype then break end
    pcall(turtle.turnRight)
    pcall(turtle.turnLeft)
    os.sleep(0.5)
  end
  if ptype then
    sayf("deploy : peripheral on front = %s", tostring(ptype))
    local lived, res = pcall(peripheral.call, "front", "turnOn")
    if lived then
      sayf("deploy : turnOn sent to turtle %d", index)
    else
      sayf("deploy : turnOn failed (%s) -- relying on self-boot", tostring(res))
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
  handOver("coal", 64, "coal")
  handOver("bucket", 1, "bucket")

  -- It leaves under its own power once quarry N calibrates. An empty block in
  -- front is the only signal available -- there is no peripheral to ask. The
  -- new turtle also writes its progress to the floppy, so read that back when
  -- it is in reach: it turns a screen nobody is looking at into output here.
  local logf, said, asked = ("/disk/deploy%d.log"):format(index), 0, false
  sayf("deploy : waiting for turtle %d to boot and walk off (about 25s)", index)
  for i = 1, 90 do
    if not turtle.detect() then
      sayf("deploy : turtle %d left after %ds, its mine is its own now", index, i)
      return true
    end
    -- Silence on the floppy after 12s means the boot script never ran, and a
    -- turtle that has not run its boot script is one that is still switched
    -- off. The turnOn above is sent and has worked before, but twice in-game
    -- on 2026-08-28 the new turtle was still dark afterwards -- unlabelled,
    -- with the program still only on /disk. A player fixes that in one click.
    -- Ask for it rather than burning the other 78 seconds and calling it a
    -- failure, and go back to waiting once they say they have.
    if not asked and i >= 12 and not fs.exists(logf) then
      asked = true
      sayf("deploy : nothing from turtle %d yet -- it is still switched off.", index)
      say("         RIGHT-CLICK IT. That turns it on and the disk startup runs.")
      say("         If its screen is already lit, type this on it:  disk/startup")
      local a = ask("deploy : enter = done, s = skip this turtle, q = stop deploying.", "", 60)
      if a:sub(1, 1) == "s" then return false, "skipped on your say-so" end
      if a:sub(1, 1) == "q" then return false, "stopped deploying on your say-so", "stop" end
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
      sayf("deploy : %ds, turtle %d still standing there", i, index)
    end
    os.sleep(1)
  end
  -- It has the drive, the program and the config; what it has not done is run
  -- the disk startup. That is the one step nothing here can force -- a turtle
  -- is not a peripheral to another turtle, so there is no turnOn to call.
  sayf("deploy : turtle %d did not boot into its startup. Right-click it to turn", index)
  say("         it on, and if its screen is already lit, on ITS screen:")
  say("           reboot          -- re-runs the disk startup, usually enough")
  say("           disk/startup    -- runs it by hand if reboot will not")
  sayf("         Either one makes it label itself quarry%d and leave.", index)
  return false, ("turtle %d has not moved after 90s -- reboot it on its own screen"):format(index)
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

local function copyStripped(src, dst)
  local out, long = {}, false
  for line in (readAllOf(src) .. "\n"):gmatch("([^\n]*)\n") do
    if long then
      out[#out + 1] = line
      if line:find("%]%]") then long = false end
    elseif not line:match("^%s*%-%-") then
      out[#out + 1] = line
      if line:find("%[%[") and not line:find("%]%]") then long = true end
    end
  end
  local body = table.concat(out, "\n") .. "\n"
  local h = fs.open(dst, "w")
  if not h then return false, #body end
  local ok = pcall(h.write, body)
  pcall(h.close)
  if not ok then return false, #body end
  return true, #body
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

  -- /disk only exists when a floppy is in the drive, so it is the test for
  -- whether the last run's floppy is still in there.
  if fs.exists("/disk") then
    say("deploy : the floppy from the last run is still in the drive")
  else
    if not floppySlot then error("no floppy in the hold", 0) end
    turtle.select(floppySlot)
    if select(2, pcall(turtle.drop)) == false then
      error("the floppy would not go into the drive", 0)
    end
    say("deploy : floppy in the drive")
  end

  -- 2. the payload. The program copies ITSELF, so a deployed turtle always
  --    runs the same build as the one that placed it -- no second wget, and no
  --    way for the two to drift apart.
  if not fs.exists("/disk") then
    error("the drive did not mount as /disk -- is the floppy in it?", 0)
  end
  local me = shell and shell.getRunningProgram and shell.getRunningProgram()
  if not me or not fs.exists(me) then
    error("cannot find my own file to copy onto the floppy", 0)
  end
  if fs.exists("/disk/quarry") then fs.delete("/disk/quarry") end
  local wrote, size = copyStripped(me, "/disk/quarry")
  if not wrote then
    error(("the program will not fit the floppy even stripped (%d bytes); "):format(size)
      .. "raise floppy_space_limit in the CC:Tweaked server config", 0)
  end
  sayf("deploy : copied %s to /disk/quarry (%d bytes, comments stripped)", me, size)

  -- and the config with it. A deployed turtle that seeds its own gets
  -- dry = true and never moves, which reads exactly like a hung deployment.
  if fs.exists(CONF) then
    if fs.exists("/disk/quarry.conf") then fs.delete("/disk/quarry.conf") end
    local body = readAllOf(CONF)
    body = confForPlaced(conf, body)
    local h = fs.open("/disk/quarry.conf", "w")
    if not h then error("cannot write /disk/quarry.conf", 0) end
    h.write(body)
    h.close()
    sayf("deploy : copied %s to /disk/quarry.conf (dry = %s)", CONF, tostring(conf.dry))

    -- The claim anchor rides with it. A placed turtle wakes one block in front
    -- of me, which is over a chunk border often enough to matter, and claimOf()
    -- would then give it a whole different 3x3 region to mine -- a second mine,
    -- not a third of this one. Only the home is seeded: no position and no
    -- heading, so locate() still starts it on its own pin, and its own state
    -- overwrites this the moment it saves.
    if fs.exists("/disk/quarry.state") then fs.delete("/disk/quarry.state") end
    local sh = fs.open("/disk/quarry.state", "w")
    if sh then
      sh.write(textutils.serialise({ home = { x = st.home.x, y = st.home.y, z = st.home.z } }))
      sh.close()
      sayf("deploy : claim anchor %d,%d on the floppy, so we all mine one claim",
        st.home.x, st.home.z)
    end
    if conf.dry ~= false then
      say("         NOTE: dry is still true, so the turtles will plan and not move.")
    end
  else
    error("no " .. CONF .. " to hand on -- run --check once to seed it", 0)
  end

  if not stepDown() then error("cannot move back down after loading the floppy", 0) end

  -- 3. one turtle at a time through the same spot. Each leaves before the next
  --    is placed, which is why one drive serves all of them.
  local done, failed = 0, {}
  for n = 2, conf.turtles do
    -- Written under BOTH names. Which one a disk's auto-startup picks up is
    -- the mod's business, not ours, and getting it wrong costs an in-game trip;
    -- writing both costs nothing and cannot pick the wrong one.
    local wrote = 0
    for _, name in ipairs({ "/disk/startup.lua", "/disk/startup" }) do
      local h = fs.open(name, "w")
      if h then
        h.write(BOOT:format(n, tostring(manualFix(conf))))
        h.close()
        wrote = wrote + 1
      end
    end
    if wrote == 0 then error("cannot write the boot script to /disk", 0) end
    sayf("deploy : wrote the boot script for turtle %d (%d names)", n, wrote)

    local okn, why, stop = deployOne(conf, l, n)
    if okn then done = done + 1 else
      failed[#failed + 1] = ("turtle %d: %s"):format(n, tostring(why))
      sayf("deploy : turtle %d did not deploy -- %s", n, tostring(why))
    end
    if stop then
      if n < conf.turtles then
        sayf("deploy : turtle %d onwards is still in the hold. `quarry 1 deploy`", n + 1)
        say("         again when you are ready for it.")
      end
      break
    end
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
-- but quarry.conf, quarry.state and /startup are all relative paths, so they
-- are written onto the FLOPPY -- which this turtle walks away from, taking its
-- own memory with it. Install to the turtle and run that copy instead. This is
-- what disk/startup does, minus the label, the modem and the fuel.
local me = shell and shell.getRunningProgram and shell.getRunningProgram()
if me and me:gsub("^/", ""):sub(1, 5) == "disk/" then
  say("startup: I am running off the floppy, where nothing I write survives me.")
  say("         Installing to this turtle and starting that copy instead.")
  for _, n in ipairs({ "quarry", "quarry.lua" }) do
    if fs.exists(n) then fs.delete(n) end
  end
  fs.copy(me, "quarry.lua")
  -- Same anti-drift rules as the boot script: take the deployer's config and
  -- claim anchor, and never overwrite a state file this turtle already has.
  if fs.exists("/disk/quarry.conf") and not fs.exists(CONF) then
    fs.copy("/disk/quarry.conf", CONF)
    say("startup: took the deployer's quarry.conf")
  end
  if fs.exists("/disk/quarry.state") and not fs.exists(STATE) then
    fs.copy("/disk/quarry.state", STATE)
    say("startup: took the deployer's claim anchor")
  end
  say("startup: installed as quarry.lua -- `quarry <n>` from now on")
  return shell.run("quarry.lua", table.unpack(args))
end
local index, mode = nil, nil
for _, a in ipairs(args) do
  if a == "--check" then mode = "check"
  elseif a == "recall" then mode = "recall"
  elseif a == "deploy" then mode = "deploy"
  elseif tonumber(a) then index = tonumber(a)
  else error("usage: quarry <1|2|3> [--check|recall|deploy]", 0) end
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
  local ok, err = pcall(runMine, conf, l, index)
  if not ok then sayf("CRASHED: %s", tostring(err)) end
end
upload()
