-- stub CC:Tweaked and run quarry.lua --check against a fake world
-- lua5.3 test_quarry.lua
local PROG = "quarry.lua"

-- CC has printError as a global beside print, and gps.locate uses it for the
-- no-modem verdict. Plain Lua does not, so the harness supplies one.
function printError(...) print(...) end

local W

local function reset(o)
  o = o or {}
  W = {
    files = {}, log = {}, posted = nil, sel = 1,
    fuel = o.fuel or 12000,
    fuelLimit = o.fuelLimit,               -- nil = the stub has no getFuelLimit
    gps  = o.gps ~= false,
    at   = o.at or { 137, 71, -42 },      -- deliberately not on a chunk border
    inv  = o.inv or {},                   -- slot -> {name=...}
    face = o.face or {},                  -- "front"/"down"/"up" -> {name=...}
    placed = {},
    conf = o.conf,
    equip = o.equip or { right = "modem" },
    wired = o.wired or {},                -- side -> true: a modem that is not wireless
    equipItem = o.equipItem or {},        -- side -> item id actually on that side
    getEquipped = o.getEquipped,          -- true: the build has getEquippedLeft/Right
  }
  -- W.equip is the PERIPHERAL view of a side and a pickaxe is not a peripheral,
  -- so it cannot tell a tool from an empty side. W.equipItem is what is really
  -- there, which is what getEquippedLeft/Right report.
  for side, t in pairs(W.equip) do
    if t == "modem" and not W.equipItem[side] then
      W.equipItem[side] = W.wired[side] and "computercraft:wired_modem"
        or "computercraft:wireless_modem_advanced"
    end
  end
  if W.conf then W.files["quarry.conf"] = W.conf end
  if o.state then W.files["quarry.state"] = o.state end
end

local function mkenv()
  local env = setmetatable({}, { __index = _G })

  env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    W.log[#W.log + 1] = table.concat(t, " ")
  end

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
      if W.files[n] == nil then return nil end
      return { readAll = function() return W.files[n] end, close = function() end }
    end,
  }

  -- CC serialises tables to a Lua-ish literal; a round-trip through load() is
  -- close enough for the state file and catches an unserialisable field.
  env.textutils = {
    serialise = function(t)
      local function enc(v)
        if type(v) == "string" then return string.format("%q", v) end
        if type(v) ~= "table" then return tostring(v) end
        local p = {}
        for k, vv in pairs(v) do p[#p + 1] = string.format("[%q]=%s", k, enc(vv)) end
        return "{" .. table.concat(p, ",") .. "}"
      end
      return enc(t)
    end,
    unserialise = function(s) return load("return " .. s)() end,
  }

  env.os = {
    epoch = function() return math.floor(os.clock() * 1000) end,
    clock = os.clock,
    date  = os.date,
    sleep = function() end,
  }

  -- the gps api is always THERE on a real turtle; what a missing modem or a
  -- dead constellation costs is the answer, not the table
  -- The gps api is NOT part of the program under test: it is a rom api with
  -- its own environment, so its debug output goes through the GLOBAL print and
  -- printError, never through the program's env. The stub prints the same way
  -- on purpose -- calling env.print here would let a capture that only shadows
  -- the program's own print look like it worked, which is exactly the bug that
  -- shipped [paste fXOYd, 2026-08-28].
  env.gps = { locate = function(_, debug)
    -- the real api needs a modem whose isWireless() is true, and says so out
    -- loud when asked to; the run captures that print, so the stub makes it
    local wireless = false
    for side, t in pairs(W.equip or {}) do
      if t == "modem" and not W.wired[side] then wireless = true end
    end
    if not wireless then
      -- the real api uses printError for this one
      if debug then printError("No wireless modems attached. GPS requires a wireless modem.") end
      return nil
    end
    if not W.gps then
      if debug then print("Received 0 responses.") print("Could not determine position.") end
      return nil
    end
    return W.at[1], W.at[2], W.at[3]
  end }

  -- an equipped wireless modem is what gives a turtle gps.locate at all
  -- a wired modem reports its type as "modem" exactly as a wireless one does;
  -- isWireless is the only thing that tells them apart, and gps.locate asks it
  env.peripheral = {
    getType = function(side) return W.equip and W.equip[side] or nil end,
    call = function(side, method)
      if method == "isWireless" then return not W.wired[side] end
    end,
  }

  -- equip SWAPS the selected slot with that side's upgrade, which is the whole
  -- hazard: off the wrong slot it takes the pickaxe instead of fitting a modem.
  local function equipSwap(side)
    local held = W.inv[W.sel]
    local was  = W.equipItem[side]
    W.equipItem[side] = held and held.name or nil
    W.inv[W.sel] = was and { name = was, count = 1 } or nil
    W.equip[side] = W.equipItem[side] and W.equipItem[side]:find("modem") and "modem" or nil
    W.wired[side] = W.equipItem[side] and W.equipItem[side]:find("wired") and true or nil
    return true
  end

  env.http = { post = function(_, body)
    W.posted = body
    return { readAll = function() return "https://paste.rs/TEST1" end, close = function() end }
  end }

  local function inspect(where)
    local b = W.face[where]
    if not b then return false, "No block to inspect" end
    return true, b
  end

  env.turtle = {
    getFuelLevel   = function() return W.fuel end,
    getFuelLimit   = W.fuelLimit and function() return W.fuelLimit end or nil,
    select         = function(s) W.sel = s end,
    getItemDetail  = function(s)
      local d = W.inv[s or W.sel]
      if d and not d.count then d.count = 1 end
      return d
    end,
    equipLeft      = function() return equipSwap("left") end,
    equipRight     = function() return equipSwap("right") end,
    getEquippedLeft  = W.getEquipped
      and function() local n = W.equipItem.left  return n and { name = n, count = 1 } or nil end
      or nil,
    getEquippedRight = W.getEquipped
      and function() local n = W.equipItem.right return n and { name = n, count = 1 } or nil end
      or nil,
    getItemCount   = function(s) return W.inv[s] and 1 or 0 end,
    inspect        = function() return inspect("front") end,
    inspectDown    = function() return inspect("down") end,
    inspectUp      = function() return inspect("up") end,
    place          = function() W.placed[#W.placed + 1] = "front" return true end,
    placeDown      = function() W.placed[#W.placed + 1] = "down"  return true end,
    placeUp        = function() W.placed[#W.placed + 1] = "up"    return true end,
    refuel         = function() W.fuel = W.fuel + 1000 return true end,
  }
  return env
end

local function run(...)
  local env = mkenv()
  local chunk = assert(loadfile(PROG, "t", env))
  local ok, err = pcall(chunk, ...)
  return ok, err, table.concat(W.log, "\n")
end

local function grab(text, pat)
  local v = text:match(pat)
  assert(v, "report has no line matching " .. pat .. "\n---\n" .. text)
  return v
end

-- 1. cold start: seeds the config, snaps the claim, reports the pattern ------

reset()
local ok, err, log = run("1", "--check")
assert(ok, "cold --check crashed: " .. tostring(err))
assert(W.files["quarry.conf"], "no quarry.conf was written on first run")

-- 137 -> chunk 8, so the claim spans chunks 7..9 -> x 112..159
-- -42 -> chunk -3, so chunks -4..-2 -> z -64..-17
assert(log:find("corners: x 112..159, z %-64%.%.%-17"),
  "claim is not chunk-snapped:\n" .. log)
assert(log:find("48x48"), "claim is not 48x48:\n" .. log)
assert(log:find("spine  : x=136, branches run 24 west and 23 east"),
  "spine is not at the x-centre:\n" .. log)

-- The pattern is anchored to the turtle's start block, not to the claim rim,
-- so the sequence is 1,3,5,2,4 rotated by wherever the turtle happened to be.
-- What must hold is the shape: a rotation, and a period of exactly 5.
local seq = grab(log, "first branch = ([%d,]+)")
assert(("1,3,5,2,4,1,3,5,2,4,1,3,5,2,4"):find(seq, 1, true),
  "pattern sequence is " .. seq .. ", not a rotation of 1,3,5,2,4")
local part = {}
for n in seq:gmatch("%d+") do part[#part + 1] = tonumber(n) end
assert(#part == 10, "expected 10 levels of sequence, got " .. #part)
for i = 1, 5 do assert(part[i] == part[i + 5], "the sequence does not repeat every 5 levels") end

-- 2. the numbers are the ones the design predicts -------------------------

local branches = tonumber(grab(log, "branches: (%d+) total"))
assert(branches >= 120 * 9 and branches <= 120 * 10,
  "branch count " .. branches .. " is not ~9.6 per level over 120 levels")

local pct = tonumber(grab(log, "%((%d+%.%d)%%%)"))
assert(pct > 19 and pct < 23, "dug fraction is " .. pct .. "%, expected ~20-22%")

local unseen = tonumber(grab(log, "unseen : %d+ of %d+ cross%-section cells %((%d+%.%d+)%%%)"))
local onFace = tonumber(grab(log, "cells %(%d+%.%d+%%%), (%d+) of them on the claim face"))
assert(unseen < 1.5, "unseen is " .. unseen .. "%, the rim effect got worse than expected")
local missed = tonumber(grab(log, "unseen : (%d+) of"))
assert(onFace == missed, "unseen cells exist in the interior -- the stagger is not tiling")
assert(not log:find("INTERIOR"), "the report itself flags interior gaps:\n" .. log)

-- thirds tile the claim with no gap and no overlap
local los, his = {}, {}
for i, lo, hi in log:gmatch("turtle (%d): z (%-?%d+)%.%.(%-?%d+)") do
  los[tonumber(i)], his[tonumber(i)] = tonumber(lo), tonumber(hi)
end
assert(los[1] == -64 and his[3] == -17, "thirds do not span the claim")
assert(his[1] + 1 == los[2] and his[2] + 1 == los[3], "thirds do not tile")

-- 3. the state file round-trips and the timing line is real ----------------

assert(W.files["quarry.state"], "no state file was written")
local st = load("return " .. W.files["quarry.state"])()
assert(st.index == 1 and st.task == "boot", "state did not round-trip: " .. W.files["quarry.state"])
assert(log:find("ms for 200 writes"), "no save timing in the report:\n" .. log)

-- 4. the report is posted, not just printed -------------------------------

assert(W.posted and #W.posted > 200, "report was not uploaded")
assert(W.posted:find("quarry %-%-check"), "uploaded body is not the report")

-- 5. no GPS and no startXYZ: says so and stops, does not guess -------------

reset({ gps = false })
ok, err, log = run("2", "--check")
assert(ok, "no-gps --check crashed: " .. tostring(err))
assert(log:find("NO FIX"), "a fixless turtle did not say so:\n" .. log)
assert(not log:find("corners"), "it invented a claim without a position:\n" .. log)

-- startXYZ in the config replaces GPS
reset({ gps = false, conf = "startX = 0\nstartY = 64\nstartZ = 0\n" })
ok, err, log = run("1", "--check")
assert(ok, "startXYZ --check crashed: " .. tostring(err))
assert(log:find("corners: x %-16%.%.31, z %-16%.%.31"), "startXYZ claim is wrong:\n" .. log)

-- 6. a bad config line names the line, it does not crash the miner ---------

reset({ conf = "topY = 60\nbottomY = banana\n" })
ok, err = run("1", "--check")
assert(not ok, "a non-numeric bottomY was accepted")
assert(tostring(err):find("quarry.conf:2"), "the error does not name line 2: " .. tostring(err))

reset({ conf = "topY = 60\nforgeOres = yes\n" })
ok, err = run("1", "--check")
assert(not ok and tostring(err):find("unknown setting"), "an unknown setting was accepted")

reset({ conf = "[oreNames]\nnot a block name\n" })
ok, err = run("1", "--check")
assert(not ok and tostring(err):find("quarry.conf:2"), "a malformed block name was accepted")

reset({ conf = "[nonsense]\n" })
ok, err = run("1", "--check")
assert(not ok and tostring(err):find("unknown section"), "an unknown section was accepted")

-- a valid config replaces the defaults rather than adding to them
reset({ conf = "topY = 20\nbottomY = 0\n[only]\nminecraft:diamond_ore\n" })
ok, err, log = run("1", "--check")
assert(ok, "custom config crashed: " .. tostring(err))
assert(log:find("y 0%.%.20, 21 levels"), "custom bounds ignored:\n" .. log)
assert(log:find("only these 1 blocks"), "the only-list did not take over:\n" .. log)

-- 7. an out-of-range turtle index is refused -------------------------------

reset()
ok, err = run("4", "--check")
assert(not ok and tostring(err):find("outside 1..3"), "turtle 4 was accepted")

-- 7b. the tank line reports THIS turtle's limit, not the plan's 20,000 -----

-- 49. In-game 2026-08-28 a turtle reported "holds 51183 of 20000", because
-- the limit was a literal. An advanced turtle holds 100,000; ask the turtle.
reset({ fuel = 51183, fuelLimit = 100000 })
ok, err, log = run("1", "--check")
assert(ok, "fuel-limit --check crashed: " .. tostring(err))
assert(log:find("this turtle holds 51183 of 100000"),
  "the tank line did not read the turtle's own limit:\n" .. log)
assert(not log:find("of 20000"), "the 20,000 literal is still being printed:\n" .. log)

-- 50. a turtle whose CC build has no getFuelLimit still gets a sane line
reset({ fuel = 900 })                    -- stub omits getFuelLimit entirely
ok, err, log = run("1", "--check")
assert(ok, "no-getFuelLimit --check crashed: " .. tostring(err))
assert(log:find("this turtle holds 900 of 20000"),
  "the fallback tank line is wrong:\n" .. log)

-- 8. the lava bucket check, in all four states ----------------------------

reset()                                              -- no bucket at all
ok, err, log = run("1", "--check")
assert(log:find("no empty bucket"), "missing-bucket case not reported:\n" .. log)

reset({ inv = { [3] = { name = "minecraft:bucket" } } })   -- bucket, no lava
ok, err, log = run("1", "--check")
assert(log:find("no lava adjacent"), "no-lava case not reported:\n" .. log)

reset({ inv = { [3] = { name = "minecraft:bucket" } },     -- bucket and lava, DRY
        conf = "dry = true\n",                             -- dry is no longer the default
        face = { down = { name = "minecraft:lava" } } })
ok, err, log = run("1", "--check")
assert(ok, "dry-scoop run crashed: " .. tostring(err))
assert(log:find("DRY %-%- would scoop the down source"), "DRY scoop not reported:\n" .. log)
assert(#W.placed == 0, "DRY mode placed the bucket anyway")

reset({ inv = { [3] = { name = "minecraft:lava_bucket" } } })
ok, err, log = run("1", "--check")
assert(log:find("full lava_bucket is in slot 3"), "a full bucket was not caught:\n" .. log)

-- 8b. the kit audit counts what is aboard and names what is not ------------

reset({ inv = {
  [1] = { name = "computercraft:turtle_normal", count = 2 },
  [2] = { name = "minecraft:chest",             count = 3 },
  [3] = { name = "computercraft:disk_drive",    count = 1 },
  [4] = { name = "computercraft:disk",          count = 1 },
  [5] = { name = "minecraft:bucket",            count = 3 },
  [6] = { name = "minecraft:coal",              count = 192 },
  [7] = { name = "computercraft:wireless_modem", count = 2 },
} })
ok, err, log = run("1", "--check")
assert(ok, "full-kit --check crashed: " .. tostring(err))
assert(log:find("nothing missing"), "a complete kit was reported short:\n" .. log)
assert(not log:find("MISSING"), "a complete kit still printed MISSING:\n" .. log)
-- a disk drive must not be counted as a floppy, and vice versa
assert(log:find("disk drive%s+1 of%s+1%s+ok"), "disk drive miscounted:\n" .. log)
assert(log:find("floppy disk%s+1 of%s+1%s+ok"), "floppy miscounted:\n" .. log)

reset({ inv = {
  [1] = { name = "computercraft:turtle_normal", count = 1 },
  [2] = { name = "minecraft:coal",              count = 64 },
  [3] = { name = "minecraft:torch",             count = 64 },
} })
ok, err, log = run("1", "--check")
assert(ok, "short-kit --check crashed: " .. tostring(err))
assert(log:find("MISSING: 1 mining turtle, 3 storage block, 1 disk drive, 1 floppy disk, 2 wireless modem, 3 empty bucket, 128 coal"),
  "the shortfall list is wrong:\n" .. log)
-- an item the audit does not know must be surfaced, never silently dropped
assert(log:find("not recognised: minecraft:torch x64"),
  "an unrecognised item was swallowed:\n" .. log)

-- 8c. the modem is what GPS needs, and the audit must know it ---------------

-- a turtle that already wears a modem needs two spares, not three
reset({ equip = { right = "modem" }, inv = {
  [1] = { name = "computercraft:wireless_modem", count = 2 },
} })
ok, err, log = run("1", "--check")
assert(ok, "modem --check crashed: " .. tostring(err))
assert(log:find("equipped: left=tool or empty  right=wireless modem"), "equipped line wrong:\n" .. log)
assert(log:find("wireless modem%s+3 of%s+3%s+ok"),
  "an equipped modem was not counted toward the kit:\n" .. log)

-- a bare turtle needs all three as items
reset({ equip = {}, inv = {} })
ok, err, log = run("1", "--check")
assert(ok, "bare --check crashed: " .. tostring(err))
assert(log:find("wireless modem%s+0 of%s+3"), "a bare turtle was credited a modem:\n" .. log)

-- no modem and no fix must name the modem as the cause, not shrug
reset({ equip = {}, gps = false })
ok, err, log = run("1", "--check")
assert(ok, "no-modem no-fix crashed: " .. tostring(err))
assert(log:find("CAUSE: no wireless modem"), "NO FIX did not blame the missing modem:\n" .. log)
assert(log:find("run: equip right"), "no remedy was given:\n" .. log)
assert(log:find("kit    :"), "the kit audit was skipped just because there was no fix:\n" .. log)

-- with a modem, a fixless turtle must NOT blame the modem
reset({ equip = { left = "modem" }, gps = false })
ok, err, log = run("1", "--check")
assert(log:find("A wireless modem is equipped"),
  "a modem-equipped turtle was told to fit a modem:\n" .. log)

-- startXYZ works but must be called out as degraded, not endorsed
reset({ equip = {}, gps = false, conf = "startX = 0\nstartY = 64\nstartZ = 0\n" })
ok, err, log = run("1", "--check")
assert(ok, "startXYZ crashed: " .. tostring(err))
assert(log:find("WARNING: that came from quarry.conf"),
  "a hardcoded position was reported as if it were a live fix:\n" .. log)

-- 9. no movement API is touched at all -------------------------------------

reset()
local touched = {}
local env = mkenv()
for _, m in ipairs({ "forward", "back", "up", "down", "turnLeft", "turnRight",
                     "dig", "digUp", "digDown" }) do
  env.turtle[m] = function() touched[#touched + 1] = m return true end
end
assert(pcall(assert(loadfile(PROG, "t", env)), "1", "--check"))
assert(#touched == 0, "phase 1 moved or dug: " .. table.concat(touched, ", "))

-- 9b. the whole point of the corner anchor: three starts, one pattern -------
-- Turtles placed anywhere in the centre chunk must compute the same claim AND
-- the same branch rows, or the air-mouth claiming protocol cannot work.

local function reportFor(at)
  reset({ at = at })
  local o, e, g = run("1", "--check")
  assert(o, "check crashed at " .. table.concat(at, ",") .. ": " .. tostring(e))
  return grab(g, "(corners: [^\n]+)"), grab(g, "first branch = ([%d,]+)")
end

local c1, p1 = reportFor({ 137, 71, -42 })
local c2, p2 = reportFor({ 130, 64, -38 })   -- same chunk, different block
local c3, p3 = reportFor({ 143, 91, -33 })   -- same chunk again, different y
assert(c1 == c2 and c2 == c3, "same chunk gave different claims:\n" .. c1 .. "\n" .. c2 .. "\n" .. c3)
assert(p1 == p2 and p2 == p3, "same claim gave different branch rows: " .. p1 .. " / " .. p2 .. " / " .. p3)

-- and a different bottomY must NOT move the pattern, or config drift between
-- turtles would silently misalign the mine
reset({ conf = "bottomY = -40\n" })
ok, err, log = run("1", "--check")
assert(ok, "custom bottomY crashed: " .. tostring(err))
assert(grab(log, "first branch = ([%d,]+)") == p1,
  "changing bottomY moved the branch pattern -- the anchor is not config-free")

-- 10. dry = true plans the route and touches nothing ---------------------

-- The shipped default is dry = false since 2026-08-27, so a dry run is now
-- something the config asks for rather than something it falls back to.
reset({ conf = "dry = true\n" })
ok, err, log = run("1")
assert(ok, "bare run crashed: " .. tostring(err))
assert(log:find("route  :"), "bare run printed no route:\n" .. log)
assert(log:find("set dry = false"), "the dry run does not say how to go live:\n" .. log)

-- 58. a run that cannot get a fix names WHICH of the three causes it is ----

-- In-game 2026-08-28 the user reported "gps locate works" and the run still
-- died on `no position fix: equip a wireless modem, or set startX/Y/Z`. The
-- message listed every cause at once, so it could not be read as evidence for
-- any of them. Each cause now excludes the others.
reset({ equip = {}, gps = false })
ok, err, log = run("1")
assert(log:find("NO WIRELESS MODEM IS EQUIPPED"),
  "a modem-less run did not say the modem was missing:\n" .. log .. tostring(err))
assert(not log:find("no GPS host answered"),
  "it blamed the constellation for a missing modem:\n" .. log)

reset({ equip = { left = "modem" }, gps = false })
ok, err, log = run("1")
assert(log:find("a wireless modem IS equipped"),
  "a modem-equipped run was told to equip a modem:\n" .. log .. tostring(err))
assert(log:find("no GPS host answered"),
  "it did not name the constellation as the cause:\n" .. log)

-- and whatever the cause, the log carries what gps.locate itself saw. Three
-- sessions went on theories about a NO FIX the api was willing to explain:
-- locate's second argument is a debug flag and its output goes to the terminal,
-- which an uploaded log never sees. The run borrows print for the call.
assert(log:find("gps    : Received 0 responses"),
  "gps.locate's own debug output was thrown away:\n" .. log)

-- 60. a WIRED modem is a third cause, not the second one -------------------

-- peripheral.getType says "modem" for both kinds, and gps.locate takes neither
-- on trust: it checks isWireless() and skips anything that fails. So a wired
-- modem equips cleanly, reads as a modem in every report, and never yields a
-- fix -- which reads exactly like a dead constellation unless something asks.
reset({ equip = { right = "modem" }, wired = { right = true } })
ok, err, log = run("1")
assert(log:find("modem is WIRED"),
  "a wired modem was reported as a constellation problem:\n" .. log .. tostring(err))
assert(not log:find("no GPS host answered"),
  "it blamed the hosts for a modem that cannot talk to them:\n" .. log)
assert(log:find("No wireless modems attached"),
  "gps.locate's own verdict on the wired modem was not captured:\n" .. log)

reset({ equip = { right = "modem" }, wired = { right = true } })
ok, err, log = run("1", "--check")
assert(log:find("equipped: left=tool or empty  right=wired modem"),
  "--check reported a wired modem as if it were wireless:\n" .. log)
assert(log:find("CAUSE: the equipped modem is WIRED"),
  "--check did not name the wired modem:\n" .. log)

-- 59. with no GPS down the hole, the saved state IS the fix -----------------

-- In-game 2026-08-28 (log td7FE) turtle 1 sat at the depot at y=-59 with its
-- modem equipped and got no answer: a wireless modem's range shrinks with
-- depth and the hosts are a hundred-odd blocks up, so GPS being healthy at the
-- surface says nothing at the claim floor. Refusing to start there means a
-- turtle can never resume its own job. quarry.state is written every block and
-- carries the heading GPS never gives, so it is the fallback -- announced, not
-- silent, because a turtle someone carried off cannot tell.
local SAVED = "{x=248,y=-59,z=711,dir=0,index=1,dug=251}"
reset({ gps = false, state = SAVED })
ok, err, log = run("1", "--check")
assert(ok, "the saved-state --check crashed: " .. tostring(err))
assert(log:find("position: 248,%-59,711 %(quarry%.state%)"),
  "it did not fall back to the saved fix:\n" .. log)
assert(log:find("WARNING: gps.locate did not answer HERE"),
  "it passed a saved position off as a live one:\n" .. log)
assert(log:find("delete quarry.state"),
  "it did not say what to do if the turtle was moved by hand:\n" .. log)

-- a live fix still wins over the saved one, or a moved turtle never notices
reset({ state = SAVED, at = { 137, 71, -42 } })
ok, err, log = run("1", "--check")
assert(log:find("position: 137,71,%-42 %(gps%)"),
  "a stale saved position beat a live GPS fix:\n" .. log)

-- and a state file with no heading in it is not a fix: dead-reckoning from an
-- unknown facing walks the claim sideways
reset({ gps = false, state = "{x=248,y=-59,z=711,index=1}" })
ok, err, log = run("1", "--check")
assert(log:find("position: NO FIX"),
  "it ran on a saved position with no saved heading:\n" .. log)

print("all quarry phase 1 checks passed")

-- ==========================================================================
-- Phase 2: a fake world with blocks in it, so movement is actually exercised
-- ==========================================================================
-- The program still opens DRY = true, but quarry.conf now ships dry = false,
-- so a run with no config of its own is live. Tests that want a dry run write
-- "dry = true" into the stub config explicitly.

local V   -- the phase 2 world

-- topY in a test conf is a run bound, not a claim: a full depot no longer stops
-- a run -- the junk goes on the tunnel floor -- so a world that does not cap the
-- levels mines its whole third, which is a minute per test instead of a second.
-- A floppy is 125 kB (CC:Tweaked floppy_space_limit) and the mod throws
-- "Out of space" on the write that goes past it, not on the one after. The
-- program is bigger than that, so the disk has to be a real limit here or a
-- deploy that cannot possibly fit passes the suite [paste WHYa2].
local FLOPPY = 125000
local function writeFile(n, body)
  body = body or ""
  if n:sub(1, 5) == "/disk" then
    local used = 0
    for name, b in pairs(V.files) do
      if name:sub(1, 5) == "/disk" and name ~= n then used = used + #b end
    end
    if used + #body > FLOPPY then error("Out of space", 0) end
  end
  V.files[n] = body
end

local function world(o)
  o = o or {}
  V = {
    blocks  = o.blocks or {},        -- "x,y,z" -> name, or false for air
    surface = o.surface or 70,       -- solid at and below this y
    pos     = o.at or { x = 137, y = 83, z = -42 },
    dir     = o.dir or 0,            -- 0 +z, 1 -x, 2 -z, 3 +x
    fuel    = o.fuel or 20000,
    inv     = o.inv or {},           -- slot -> {name=, count=}
    files   = {}, log = {}, posted = nil, sel = 1,
    lost    = 0, moves = 0, ground = 0,
    equip   = { right = "modem" },
    chests  = o.chests or {},        -- "x,y,z" -> { {name=, count=}, ... }
    disk    = o.disk or false,       -- a disk drive with a floppy at the depot
    sent    = {},                    -- what notify() put on rednet
    sleeps  = 0,                     -- 1s polls burnt waiting for a deployed turtle
    leaveAfter = o.leaveAfter,       -- polls before a deployed turtle walks off
    handed  = {},                    -- what a deployed turtle was given
    -- What a player types at a prompt, in order. Empty means nobody is at the
    -- keyboard, which is the /startup case and must never hang the mine.
    answers = o.answers or {}, asked = {},
    running = o.running,             -- what shell.getRunningProgram() reports
    watchY  = o.watchY,              -- record the z range of moves at this y
  }
  V.files["quarry.conf"] = (o.conf or "") .. "dry = false\n"
  V.files["quarry"] = "-- the program itself, so deploy has something to copy"
end

local function k3(x, y, z) return x .. "," .. y .. "," .. z end

local function blockAt(x, y, z)
  local b = V.blocks[k3(x, y, z)]
  if b ~= nil then return b or nil end
  if y <= -64 then return "minecraft:bedrock" end
  if y > V.surface then return nil end
  return y < 0 and "minecraft:deepslate" or "minecraft:stone"
end

local function setAir(x, y, z) V.blocks[k3(x, y, z)] = false end

-- turtles are lavaproof and detect() is false for liquid, so liquid is not a
-- block as far as movement and digging are concerned
local function liquid(name) return name == "minecraft:lava" or name == "minecraft:water" end
local function solid(x, y, z)
  local b = blockAt(x, y, z)
  if b and liquid(b) then return nil end
  return b
end

local VDIRS = { [0] = { 0, 1 }, [1] = { -1, 0 }, [2] = { 0, -1 }, [3] = { 1, 0 } }

local function ahead()
  local d = VDIRS[V.dir]
  return V.pos.x + d[1], V.pos.y, V.pos.z + d[2]
end

-- a dug block goes into a slot, or is destroyed -- which is the bug the
-- full-inventory guard exists to prevent, so count it
local function give(name)
  for s = 1, 16 do
    local it = V.inv[s]
    if it and it.name == name and it.count < 64 then it.count = it.count + 1 return end
  end
  for s = 1, 16 do
    if not V.inv[s] then V.inv[s] = { name = name, count = 1 } return end
  end
  V.lost = V.lost + 1
end

local function mkworldenv()
  local env = setmetatable({}, { __index = _G })

  env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    V.log[#V.log + 1] = table.concat(t, " ")
  end

  -- CC resolves an fs path from the root, so "disk/quarry" and "/disk/quarry"
  -- are the same file. The stub keys on the string, so make them the same
  -- string.
  local function nn(n) return (n:gsub("^disk", "/disk"):gsub("^//", "/")) end
  env.fs = {
    exists = function(n)
      n = nn(n)
      if n == "/disk" or n == (V.mount or "/disk") then return V.disk end
      return V.files[n] ~= nil
    end,
    delete = function(n) V.files[nn(n)] = nil end,
    move   = function(a, b) a, b = nn(a), nn(b) V.files[b], V.files[a] = V.files[a], nil end,
    copy   = function(a, b) writeFile(nn(b), V.files[nn(a)]) end,
    open   = function(n, m)
      n = nn(n)
      if m == "w" then
        local buf = {}
        return { write = function(s) buf[#buf + 1] = s end,
                 close = function() writeFile(n, table.concat(buf)) end }
      end
      if V.files[n] == nil then return nil end
      return { readAll = function() return V.files[n] end, close = function() end }
    end,
  }

  env.textutils = {
    serialise = function(t)
      local function enc(v)
        if type(v) == "string" then return string.format("%q", v) end
        if type(v) ~= "table" then return tostring(v) end
        local p = {}
        for k, vv in pairs(v) do p[#p + 1] = string.format("[%q]=%s", k, enc(vv)) end
        return "{" .. table.concat(p, ",") .. "}"
      end
      return enc(t)
    end,
    unserialise = function(s) return load("return " .. s)() end,
  }

  env.shell = { getRunningProgram = function() return V.running or "quarry" end,
                run = function(...) V.ran = { ... } return true end }

  -- A deployed turtle leaves under its own power, and the only signal the
  -- deployer has is the block in front going away. Model that as "after this
  -- many 1s polls", so the wait loop is exercised rather than skipped.
  env.os = { epoch = function() return math.floor(os.clock() * 1000) end,
             clock = os.clock, date = os.date,
             sleep = function()
               V.sleeps = V.sleeps + 1
               if V.leaveAfter and V.placedTurtle and V.sleeps >= V.leaveAfter then
                 setAir(V.placedTurtle.x, V.placedTurtle.y, V.placedTurtle.z)
                 V.placedTurtle = nil
               end
             end }
  env.gps = { locate = function()
    if V.noGps then return nil end
    return V.pos.x, V.pos.y, V.pos.z
  end }

  -- read() blocks forever on a turtle nobody is watching, so quarry races it
  -- against a timer inside parallel.waitForAny. Model both arms: the read one
  -- takes the next scripted answer and fails when there is none, and the loser
  -- of that race is the timer, which is exactly what an empty queue means.
  env.read = function()
    local a = table.remove(V.answers, 1)
    if a == nil then error("nobody at the keyboard", 0) end
    V.asked[#V.asked + 1] = a
    return a
  end
  env.parallel = { waitForAny = function(...)
    for _, f in ipairs({ ... }) do
      if pcall(f) then return end
    end
  end }

  -- rednet is the only channel out of the mine. Every world here equips a
  -- wireless modem, so opening it is expected to work.
  env.rednet = {
    open      = function(side) V.rednetOpen = side end,
    broadcast = function(msg, proto) V.sent[#V.sent + 1] = { msg = msg, proto = proto } end,
  }
  -- A placed turtle IS visible as a peripheral to the one that placed it, which
  -- is how the deployer turns it on. Any other side reports the equipped item.
  env.peripheral = {
    getType = function(side)
      if side == "front" and not V.periphStale then
        local fx, fy, fz = ahead()
        local n = blockAt(fx, fy, fz)
        if n and n:find("turtle") then return "turtle" end
        if n and n:find("disk_drive") then return "drive" end
      end
      -- the drive the deploy places ends up directly ABOVE the turtle, which is
      -- the side diskPath finds it on for the rest of the run
      if side == "top" then
        local n = blockAt(V.pos.x, V.pos.y + 1, V.pos.z)
        if n and n:find("disk_drive") then return "drive" end
      end
      return V.equip[side]
    end,
    call = function(side, method)
      if side == "front" and method == "turnOn" then
        V.turnedOn = (V.turnedOn or 0) + 1
        return true
      end
      if side == "front" and method == "reboot" then
        V.rebooted = (V.rebooted or 0) + 1
        return true
      end
      -- the drive answers where it put the floppy; V.mount lets a world put it
      -- somewhere that is not "/disk", which is what a second drive does
      if method == "getMountPath" then return V.disk and (V.mount or "/disk") or nil end
    end,
  }
  env.http = { post = function(_, body)
    V.posted = body
    return { readAll = function() return "https://paste.rs/TEST2" end, close = function() end }
  end }

  local function data(name)
    if not name then return false, "No block to inspect" end
    local tags = name:find("_ore") and { ["c:ores"] = true } or {}
    local d = { name = name, tags = tags }
    if name == "minecraft:lava" then d.state = { level = 0 } end   -- source
    return true, d
  end

  -- chests: a container is a named block with an item list beside it. drop and
  -- suck are the only way a turtle talks to one, which is the whole reason the
  -- fuel ration has to be learned by taking rather than read off the chest.
  local function chestAt(x, y, z)
    return V.chests[k3(x, y, z)]
  end

  -- the target is passed in, because the depot is under the turtle now and
  -- drop/suck have to reach both the block ahead and the block below
  local function dropInto(n, x, y, z)
    -- refuse only drops into a turtle: the drive still takes its floppy, so
    -- the test isolates the handover channel and nothing upstream of it
    if V.dropFails then
      local nm = blockAt(x, y, z)
      if nm and nm:find("turtle") then return false end
    end
    local it = V.inv[V.sel]
    if not it then return false end
    local take = math.min(n or it.count, it.count)
    local c = chestAt(x, y, z)
    local aheadName = blockAt(x, y, z)
    if c then
      if #c >= 27 then return false end                 -- the chest is full
      c[#c + 1] = { name = it.name, count = take }
    elseif aheadName and (aheadName:find("turtle") or aheadName:find("disk_drive")) then
      -- a turtle and a drive are both inventories: this is the deployment channel
      V.handed[#V.handed + 1] = { name = it.name, count = take, into = aheadName }
      -- and a floppy in the drive is what makes /disk appear
      if aheadName:find("disk_drive") and it.name:find("disk")
         and not it.name:find("disk_drive") then V.disk = true end
    else
      V.ground = V.ground + take                        -- junk on the tunnel floor
    end
    it.count = it.count - take
    if it.count == 0 then V.inv[V.sel] = nil end
    return true
  end

  local function suckFrom(n, x, y, z)
    local c = chestAt(x, y, z)
    if not c or #c == 0 then return false end
    local want, first = n or 64, c[1]
    local take = math.min(want, first.count)
    local slot = V.inv[V.sel] and nil or V.sel
    if not slot then
      for i = 1, 16 do if not V.inv[i] then slot = i break end end
    end
    if not slot then return false end
    V.inv[slot] = { name = first.name, count = take }
    first.count = first.count - take
    if first.count == 0 then table.remove(c, 1) end
    return true
  end

  local function scoopAt(x, y, z)
    local it = V.inv[V.sel]
    if not it or it.name ~= "minecraft:bucket" then return false end
    if blockAt(x, y, z) ~= "minecraft:lava" then return false end
    setAir(x, y, z)
    V.inv[V.sel] = { name = "minecraft:lava_bucket", count = 1 }
    return true
  end

  -- a bucket placed against a lava source picks it up; anything else placeable
  -- becomes a block, and a container becomes an empty inventory
  local function placeAt(x, y, z)
    local it = V.inv[V.sel]
    if it and (it.name:find("disk_drive") or it.name:find("turtle")
               or it.name:find("chest") or it.name:find("barrel")) then
      if blockAt(x, y, z) then return false end
      V.blocks[k3(x, y, z)] = it.name
      -- placing the drive does not mount /disk; the floppy going into it does
      if it.name:find("chest") or it.name:find("barrel") then
        V.chests[k3(x, y, z)] = {}         -- a placed chest starts empty
      elseif it.name:find("turtle") then
        V.placedTurtle, V.sleeps = { x = x, y = y, z = z }, 0
        V.periphStale = true      -- issue #660: freshly placed reads as air
      end
      it.count = it.count - 1
      if it.count == 0 then V.inv[V.sel] = nil end
      return true
    end
    return scoopAt(x, y, z)
  end

  local function move(nx, ny, nz)
    if solid(nx, ny, nz) then return false end
    if V.fuel <= 0 then return false end
    V.pos.x, V.pos.y, V.pos.z = nx, ny, nz
    if not V.minY or ny < V.minY then V.minY = ny end
    -- how far along z this turtle ranged at its working level: the spine
    -- between thirds is used once on the way in, and after that a turtle with
    -- its own depot has no reason to leave its third at all
    if V.watchY and ny == V.watchY then
      if not V.zMin or nz < V.zMin then V.zMin = nz end
      if not V.zMax or nz > V.zMax then V.zMax = nz end
    end
    V.fuel = V.fuel - 1
    V.moves = V.moves + 1
    return true
  end

  local function digAt(x, y, z)
    local b = blockAt(x, y, z)
    if not b or b == "minecraft:bedrock" or liquid(b) then return false end
    setAir(x, y, z)
    give(b)
    return true
  end

  env.turtle = {
    getFuelLevel = function() return V.fuel end,
    select       = function(s) V.sel = s end,
    getItemCount = function(s) return V.inv[s] and V.inv[s].count or 0 end,
    getItemDetail= function(s)
      local it = V.inv[s]
      return it and { name = it.name, count = it.count } or nil
    end,
    refuel       = function(n)
      local it = V.inv[V.sel]
      if not it then return false end
      local take = math.min(n or it.count, it.count)
      if take <= 0 then return false end
      it.count = it.count - take
      if it.count == 0 then V.inv[V.sel] = nil end
      V.fuel = V.fuel + (it.name == "minecraft:lava_bucket" and 1000 or 80) * take
      if it.name == "minecraft:lava_bucket" then V.inv[V.sel] = { name = "minecraft:bucket", count = 1 } end
      return true
    end,
    turnLeft     = function() V.dir = (V.dir + 3) % 4 return true end,
    turnRight    = function()
                     V.dir = (V.dir + 1) % 4
                     V.periphStale = false   -- issue #660: a turn refreshes it
                     return true
                   end,
    forward      = function() return move(ahead()) end,
    back         = function()
      local d = VDIRS[V.dir]
      return move(V.pos.x - d[1], V.pos.y, V.pos.z - d[2])
    end,
    up           = function() return move(V.pos.x, V.pos.y + 1, V.pos.z) end,
    down         = function() return move(V.pos.x, V.pos.y - 1, V.pos.z) end,
    detect       = function() return solid(ahead()) ~= nil end,
    detectUp     = function() return solid(V.pos.x, V.pos.y + 1, V.pos.z) ~= nil end,
    detectDown   = function() return solid(V.pos.x, V.pos.y - 1, V.pos.z) ~= nil end,
    inspect      = function()
      if V.inspectFails then error("inspect blew up") end
      return data(blockAt(ahead()))
    end,
    inspectUp    = function() return data(blockAt(V.pos.x, V.pos.y + 1, V.pos.z)) end,
    inspectDown  = function() return data(blockAt(V.pos.x, V.pos.y - 1, V.pos.z)) end,
    dig          = function() return digAt(ahead()) end,
    digUp        = function() return digAt(V.pos.x, V.pos.y + 1, V.pos.z) end,
    digDown      = function() return digAt(V.pos.x, V.pos.y - 1, V.pos.z) end,
    attack       = function() return false end,
    attackUp     = function() return false end,
    attackDown   = function() return false end,
    place        = function()
      if V.placeErrors then error("place blew up") end
      return placeAt(ahead())
    end,
    placeUp      = function() return scoopAt(V.pos.x, V.pos.y + 1, V.pos.z) end,
    placeDown    = function()
      if V.placeErrors then error("place blew up") end
      return placeAt(V.pos.x, V.pos.y - 1, V.pos.z)
    end,
    drop         = function(n) return dropInto(n, ahead()) end,
    suck         = function(n) return suckFrom(n, ahead()) end,
    dropDown     = function(n) return dropInto(n, V.pos.x, V.pos.y - 1, V.pos.z) end,
    suckDown     = function(n) return suckFrom(n, V.pos.x, V.pos.y - 1, V.pos.z) end,
  }
  return env
end

local function runWorld(...)
  local env = mkworldenv()
  local chunk = assert(loadfile(PROG, "t", env))
  local ok, err = pcall(chunk, ...)
  return ok, err, table.concat(V.log, "\n")
end

-- the claim for a turtle at 137,*,-42: x 112..159, spine 136, third 1 is
-- z -64..-49 with its trunk at z=-57, and -57 is itself a branch row at y=-59.
local BX, BY, BZ = 136, -59, -57
-- the MIDDLE turtle's trunk, which is where one shared depot belongs: third 2
-- is z -48..-33, so its trunk -- and the claim's centre -- is z=-41
local MZ = -41

-- 11. a whole branch, start to finish -------------------------------------

-- tripBlocks is lifted so this test is about the branch, not about docking;
-- with no depot in the world the run ends when the tank does.
world({ conf = "tripBlocks = 100000\n" })
ok, err, log = runWorld("1")
assert(ok, "phase 2 crashed: " .. tostring(err))
assert(log:find("STOPPED: inventory is full: all 16 slots hold something, and there is no depot"),
  "the run ended for the wrong reason:\n" .. log)
assert(log:find("done   : %d+ branch"), "the report does not count finished branches:\n" .. log)

-- every block of the branch row is air, both legs, rim to rim
for x = 112, 159 do
  assert(blockAt(x, BY, BZ) == nil, ("branch block %d,%d,%d was left solid"):format(x, BY, BZ))
end
-- and the trunk it came down
for y = BY, 60 do
  assert(blockAt(BX, y, BZ) == nil, ("trunk block at y=%d was left solid"):format(y))
end
assert(V.lost == 0, V.lost .. " drops were destroyed by digging into a full inventory")

local sv = load("return " .. V.files["quarry.state"])()
assert(sv.task == "park", "state task is " .. tostring(sv.task))
assert(sv.done[BY .. ":" .. BZ], "the first branch was not marked done in the state file")
assert(sv.dug > 150, "only " .. tostring(sv.dug) .. " blocks dug for a 48-block branch and a trunk")

-- 12. veins are chased off the branch and capped ---------------------------

world({ conf = "tripBlocks = 100000\n", blocks = {
  [k3(130, BY, BZ - 1)] = "minecraft:diamond_ore",   -- beside the branch
  [k3(130, BY - 1, BZ - 1)] = "minecraft:diamond_ore",
  [k3(130, BY - 2, BZ - 1)] = "minecraft:deepslate_diamond_ore",
  [k3(120, BY + 1, BZ)] = "create:zinc_ore",         -- named in the config, not tagged
} })
ok, err, log = runWorld("1")
assert(ok, "vein run crashed: " .. tostring(err))
for _, p in ipairs({ { 130, BY, BZ - 1 }, { 130, BY - 1, BZ - 1 }, { 130, BY - 2, BZ - 1 },
                     { 120, BY + 1, BZ } }) do
  assert(blockAt(p[1], p[2], p[3]) == nil,
    ("ore at %d,%d,%d was not mined"):format(p[1], p[2], p[3]))
end
local diamonds, zinc = 0, 0
for s = 1, 16 do
  local it = V.inv[s]
  if it and it.name:find("diamond") then diamonds = diamonds + it.count end
  if it and it.name == "create:zinc_ore" then zinc = zinc + it.count end
end
assert(diamonds == 3, "carried " .. diamonds .. " diamond ore, expected 3")
assert(zinc == 1, "the config-named zinc ore was not chased")
assert(log:find("chasing veins"), "the report does not count the vein blocks:\n" .. log)

-- an ore the config does not mine is passed over AND named in the report
world({ conf = "tripBlocks = 100000\n",
        blocks = { [k3(130, BY, BZ - 1)] = "someothermod:oreberry_bush" } })
ok, err, log = runWorld("1")
assert(blockAt(130, BY, BZ - 1) == "someothermod:oreberry_bush",
  "an unlisted ore was mined anyway")
assert(log:find("passed over: someothermod:oreberry_bush"),
  "an unlisted ore-ish block was not reported:\n" .. log)

-- 13. it refuses to dig the deny list -------------------------------------

world({ blocks = { [k3(137, 80, -42)] = "minecraft:chest" } })
ok, err, log = runWorld("1")
assert(ok, "deny-list run crashed: " .. tostring(err))
assert(log:find("STOPPED: refusing to dig minecraft:chest"),
  "it did not refuse the chest:\n" .. log)
assert(blockAt(137, 80, -42) == "minecraft:chest", "the chest was destroyed")

-- 13b. a Lootr chest in the branch ends that leg, it does not end the run ---
-- Lootr containers cannot be broken by a turtle (the break event is cancelled
-- for a non-sneaking player) and expose zero slots to every face, so the only
-- thing to do with one is walk away and tell the user where it is.

world({ conf = "tripBlocks = 100000\n",
        blocks = { [k3(130, BY, BZ)] = "lootr:lootr_chest" } })
ok, err, log = runWorld("1")
assert(ok, "lootr run crashed: " .. tostring(err))
assert(blockAt(130, BY, BZ) == "lootr:lootr_chest", "the Lootr chest was destroyed")
assert(log:find("blocked: lootr:lootr_chest"), "it did not say the leg was blocked:\n" .. log)
assert(log:find("left alone: lootr:lootr_chest x1"),
  "the Lootr chest was not reported for the user to open:\n" .. log)
assert(log:find("done   : %d+ branch"), "one Lootr chest ended the whole run:\n" .. log)
assert(not log:find("STOPPED: refusing"), "it stopped instead of skipping the leg:\n" .. log)
-- the far side of the chest is left alone, the other leg is mined to the rim
assert(blockAt(129, BY, BZ) ~= nil, "it dug past the chest somehow")
for x = 137, 159 do
  assert(blockAt(x, BY, BZ) == nil, ("east leg block %d was left solid"):format(x))
end
local sv13 = load("return " .. V.files["quarry.state"])()
assert(sv13.done[BY .. ":" .. BZ], "the blocked branch was not counted as finished")

-- 14. a full inventory stops it rather than destroying the drop ------------

-- diamonds, not cobble: cobble is the junk tier and the overflow valve would
-- dump it. With nothing dumpable aboard, a full turtle must stop.
local packed = {}
for s = 1, 16 do packed[s] = { name = "minecraft:diamond", count = 64 } end
world({ inv = packed })
ok, err, log = runWorld("1")
assert(ok, "full-inventory run crashed: " .. tostring(err))
assert(log:find("STOPPED: inventory full"), "a full turtle kept digging:\n" .. log)
assert(V.lost == 0, "it destroyed " .. V.lost .. " drops")

-- 15. low fuel stops it while it can still walk home, and it resumes -------

-- too little to get there and back: it refuses at the surface, undug
world({ fuel = 300 })
ok, err, log = runWorld("1")
assert(ok, "no-fuel run crashed: " .. tostring(err))
assert(log:find("STOPPED: not enough fuel"), "it set off on a trip it could not pay for:\n" .. log)
assert(V.pos.y == 83, "it started descending anyway, ending at y=" .. V.pos.y)

-- a trip's worth of blocks, and nowhere to put them: it stops part-way down
-- the leg, which is what makes the resume below a real mid-branch resume.
-- The trunk alone is 142 blocks, so 160 stops it 18 blocks along.
world({ conf = "tripBlocks = 160\n" })
ok, err, log = runWorld("1")
assert(ok, "trip-limit run crashed: " .. tostring(err))
assert(log:find("tripBlocks is 160"),
  "it did not name tripBlocks as what stopped it:\n" .. log)
local mid = load("return " .. V.files["quarry.state"])()
assert(mid.leg and mid.along > 0, "it stopped without recording where it was")

-- second run: same world, same state file, an empty hold
local keep, state = V.blocks, V.files["quarry.state"]
world({ conf = "tripBlocks = 100000\n", blocks = keep,
        at = { x = V.pos.x, y = V.pos.y, z = V.pos.z } })
V.files["quarry.state"] = state
ok, err, log = runWorld("1")
assert(ok, "resume crashed: " .. tostring(err))
assert(log:find("resume : " .. mid.leg), "it did not report resuming the leg:\n" .. log)
local after = load("return " .. V.files["quarry.state"])()
assert(after.done[BY .. ":" .. BZ], "the resumed run did not finish the branch it was on")
-- the claim must come from the launch block, not from where it woke up: at
-- x=118 the turtle stands in a different chunk than it started in
assert(log:find("claim x 112..159"), "the resumed run recomputed a different claim:\n" .. log)
assert(log:find("anchored at 137,%-42"), "the resumed run lost its anchor:\n" .. log)
assert(not log:find("cross  :"), "it walked back to the trunk it was already below:\n" .. log)
for x = 112, 159 do
  assert(blockAt(x, BY, BZ) == nil, ("resume left %d,%d,%d solid"):format(x, BY, BZ))
end

-- 15b. carried to a new claim, it drops the old anchor -------------------

world({ at = { x = 500, y = 83, z = 500 } })
V.files["quarry.state"] =
  '{["index"]=1,["task"]="branch",["along"]=0,["home"]={["x"]=137,["y"]=83,["z"]=-42},' ..
  '["level"]=-59,["branch"]=-57,["dug"]=0,["chased"]=0}'
ok, err, log = runWorld("1")
assert(ok, "moved-claim run crashed: " .. tostring(err))
assert(log:find("moved: this is not the claim"), "it kept a stale anchor:\n" .. log)
assert(log:find("anchored at 500,500"), "it did not re-anchor where it now is:\n" .. log)

-- 16. bedrock, not bottomY, is what really stops the trunk -----------------

world({ conf = "bottomY = -70\n" })
ok, err, log = runWorld("1")
assert(ok, "bedrock run crashed: " .. tostring(err))
assert(log:find("bedrock: floor is y=%-63"), "it did not stop one above bedrock:\n" .. log)
assert(blockAt(BX, -64, BZ) == "minecraft:bedrock", "it dug into bedrock")

-- 17. dry = true touches nothing -----------------------------------------

world()
V.files["quarry.conf"] = "dry = true\n"   -- asked for, not fallen back to
ok, err, log = runWorld("1")
assert(ok, "dry run crashed: " .. tostring(err))
assert(log:find("route  :"), "the dry run printed no route:\n" .. log)
assert(V.moves == 0, "DRY moved " .. V.moves .. " blocks")
assert(V.pos.y == 83, "DRY changed the turtle's position")
assert(next(V.blocks) == nil, "DRY dug something")



print("all quarry phase 2 checks passed")

-- ==========================================================================
-- Phase 3: the depot cycle
-- ==========================================================================
-- The trunk floor is (spine, bottomY, trunkZ) = 136,-59,-57 and a chest goes
-- beside it. Direction 1 is -x, so 135,-59,-57 is the container the turtle
-- finds by looking around itself once.

-- A config file replaces the default lists outright, so a stub config has to
-- name the lists the test depends on. Same rule the user's own file follows.
local SECTIONS = "[fuel]\nminecraft:coal\n[blacklist]\nminecraft:stone\nminecraft:deepslate\n"

local DX, DY, DZ = BX - 1, BY, BZ          -- the depot chest
local function coalChest(n)
  return { [k3(DX, DY, DZ)] = { { name = "minecraft:coal", count = n } } }
end
local function chestItems()
  local c, n = V.chests[k3(DX, DY, DZ)], 0
  for _, it in ipairs(c or {}) do n = n + it.count end
  return c or {}, n
end
local function coalLeft()
  local n = 0
  for _, it in ipairs(select(1, chestItems())) do
    if it.name == "minecraft:coal" then n = n + it.count end
  end
  return n
end

-- 18. dump, ration, restock, resume ---------------------------------------

world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 2000,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest" },
        chests = coalChest(30) })
ok, err, log = runWorld("1")
assert(ok, "depot run crashed: " .. tostring(err))
assert(log:find("depot  : container at %d"),
  "it did not find the chest beside the trunk:\n" .. log)
assert(log:find("depot  : docking"), "it never docked:\n" .. log)
assert(log:find("depot  : dumped; chest held %d+ fuel items, took [1-9]%d* fuel"),
  "it docked but took no fuel:\n" .. log)
assert(log:find("resume :"), "it did not walk back to the leg it left:\n" .. log)
assert(blockAt(DX, DY, DZ) == "minecraft:chest", "it dug the depot chest")

local _, stored = chestItems()
assert(stored > 100, "only " .. stored .. " items reached the chest:\n" .. log)
-- the ration: a third per visit and never the last few, so the chest is never
-- emptied by one turtle however many times it docks
-- the ration is a third per visit and never the last few, so after five trips
-- there is still coal in the chest for the other two turtles
assert(coalLeft() >= 3, "the depot chest was drained to " .. coalLeft() .. " coal")
assert(coalLeft() < 30, "it docked five times and never took any coal")
local sv18 = load("return " .. V.files["quarry.state"])()
assert((sv18.trips or 0) >= 1, "the state file counted no depot trips")
assert((sv18.hauled or 0) > 100, "the state file counted no haul")

-- 18b. the ration is a floor, not a fraction ------------------------------

-- 51. The old rule took floor(total/3) of whatever was in the chest, so three
-- dockers took 100, 66 then 44 of a 300-coal chest and the shares were never
-- equal. Now a turtle takes what the trip needs down to a floor held back for
-- the others: conf.fuelFloor (8) per OTHER turtle, so 16 of 20 with three
-- turtles running. The chest must come to rest on exactly that floor -- the
-- old code walks it down past 16 towards 3.
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 2000,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest" },
        chests = coalChest(20) })
ok, err, log = runWorld("1")
assert(ok, "ration-floor run crashed: " .. tostring(err))
assert(log:find("depot  : docking"), "it never docked:\n" .. log)
assert(coalLeft() == 16,
  "the floor is 8 per other turtle, so 16 should be left, not " .. coalLeft() .. ":\n" .. log)

-- 52. and the floor follows conf.turtles, which the old literal 3 ignored:
-- two turtles reserve for one other, so 8 of the same 20 stay in the chest.
-- Two turtles split the claim in halves, so turtle 1's trunk moves z -57 -> -53.
local HZ = -53
-- 10 coal, not 20: the ceiling almost never binds (a trip wants only 4-6
-- coal), so the floor is the only term that shows, and it only shows once the
-- chest is low enough to reach it. The old rule walks this chest down to 3.
world({ conf = "tripBlocks = 200\nturtles = 2\n" .. SECTIONS, fuel = 2000,
        blocks = { [k3(BX - 1, BY, HZ)] = "minecraft:chest" },
        chests = { [k3(BX - 1, BY, HZ)] = { { name = "minecraft:coal", count = 10 } } } })
ok, err, log = runWorld("1")
assert(ok, "two-turtle ration run crashed: " .. tostring(err))
assert(log:find("depot  : docking"), "the two-turtle run never docked:\n" .. log)
local twoLeft = 0
for _, it in ipairs(V.chests[k3(BX - 1, BY, HZ)] or {}) do
  if it.name == "minecraft:coal" then twoLeft = twoLeft + it.count end
end
assert(twoLeft == 8,
  "with turtles = 2 the floor is 8, not " .. twoLeft .. ":\n" .. log)

-- 18c. startX/Y/Z cannot calibrate, and must say so --------------------------

-- 53. In-game 2026-08-28 turtle 1 crashed with "calibration moved 0,0, which is
-- not one block". The cause was three lines in quarry.conf: startX/Y/Z pin
-- locate() to a constant, so the reading after the calibration move equals the
-- reading before it and no direction matches. The message named the symptom and
-- hid the cause, which cost a live run.
world({ conf = "startX = 10\nstartY = 80\nstartZ = 5\n" .. SECTIONS, fuel = 2000 })
V.noGps = true          -- the pin is only reached when GPS cannot answer [test 94]
ok, err, log = runWorld("1")
assert(ok, "pinned-position run crashed outright: " .. tostring(err))
assert(log:find("pins my position"),
  "it did not name startX/Y/Z as the cause:\n" .. log)
assert(not log:find("calibration moved 0,0"),
  "it still reports the symptom instead of the cause:\n" .. log)

-- 54. with startDir given, a pinned position is enough to run on: the heading
-- is stated instead of measured, and everything past calibration dead-reckons.
world({ conf = "startX = 137\nstartY = 71\nstartZ = -42\nstartDir = 1\ntripBlocks = 200\n"
        .. SECTIONS, fuel = 4000 })
V.noGps = true          -- the pin is only reached when GPS cannot answer [test 94]
ok, err, log = runWorld("1")
assert(ok, "startDir run crashed: " .. tostring(err))
assert(log:find("heading: %-x from quarry.conf startDir"),
  "it did not take the heading from startDir:\n" .. log)
assert(not log:find("pins my position"),
  "it refused even with startDir set:\n" .. log)
assert(V.moves > 0, "it never moved:\n" .. log)

-- 55. startDir is validated, not trusted
world({ conf = "startX = 1\nstartY = 2\nstartZ = 3\nstartDir = 7\n" .. SECTIONS })
ok, err, log = runWorld("1")
assert(not ok and tostring(err):find("startDir wants 0, 1, 2 or 3"),
  "an out-of-range startDir was accepted: " .. tostring(err))

-- 19. the junk tier is the overflow valve ---------------------------------

-- fifteen slots of something undumpable, one free: the free slot fills with
-- stone, and from then on only the junk valve keeps the turtle digging
local nearly = {}
for s = 1, 15 do nearly[s] = { name = "minecraft:diamond", count = 64 } end
world({ conf = "tripBlocks = 100000\n" .. SECTIONS, inv = nearly, fuel = 1200 })
ok, err, log = runWorld("1")
assert(ok, "junk-valve run crashed: " .. tostring(err))
assert(not log:find("STOPPED: inventory full"),
  "the valve did not fire, it stopped instead:\n" .. log)
assert(V.ground > 0, "nothing was dumped on the floor")
assert(V.lost == 0, "it destroyed " .. V.lost .. " drops")
local sv19 = load("return " .. V.files["quarry.state"])()
assert((sv19.junked or 0) > 0, "the state file counted no junk")

-- 20. lava: recorded on the map, and scooped when the tank is low ---------

-- lavaFloor = 0 means never scoop a source the branch passes, so this is purely
-- the map. One level and a stocked depot, because a run that goes dry forages,
-- and foraging takes a mapped source whatever lavaFloor says -- that is what
-- foraging is for. Before the depot-full stop was lifted this world ended
-- itself after a few docks, on a chest the stub caps at 27 stacks; now it runs
-- until the claim or the coal does, so the claim is made small.
world({ conf = "tripBlocks = 60\nlava = true\nlavaFloor = 0\ntopY = -59\n" .. SECTIONS, fuel = 2000,
        disk = true,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest",
                   [k3(145, BY - 1, BZ)] = "minecraft:lava" },
        chests = coalChest(200),
        inv = { [16] = { name = "minecraft:bucket", count = 1 } } })
ok, err, log = runWorld("1")
assert(ok, "lava-map run crashed: " .. tostring(err))
assert(blockAt(145, BY - 1, BZ) == "minecraft:lava", "it scooped with lavaFloor = 0")
assert(V.files["/disk/lava.txt"], "no lava map was written to the disk")
assert(V.files["/disk/lava.txt"]:find("145,%-60,%-57"),
  "the source is not on the map: " .. tostring(V.files["/disk/lava.txt"]))
assert(log:find("lavamap: 1 new source"), "the dock did not report the map write:\n" .. log)

-- same world, a tank far under lavaFloor: now it takes the source
world({ conf = "tripBlocks = 200\nlava = true\nlavaFloor = 20000\n" .. SECTIONS, fuel = 2000,
        disk = true,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest",
                   [k3(145, BY - 1, BZ)] = "minecraft:lava" },
        chests = coalChest(30),
        inv = { [16] = { name = "minecraft:bucket", count = 1 } } })
ok, err, log = runWorld("1")
assert(ok, "lava-scoop run crashed: " .. tostring(err))
assert(blockAt(145, BY - 1, BZ) == nil, "the source is still there:\n" .. log)
local sv20 = load("return " .. V.files["quarry.state"])()
assert((sv20.scooped or 0) == 1, "the state file counted no scoop")
local bucket = false
for sl = 1, 16 do
  local it = V.inv[sl]
  if it and it.name == "minecraft:bucket" then bucket = true end
end
assert(bucket, "the bucket did not come back -- issue #530 behaviour")
assert(not (V.files["/disk/lava.txt"] or ""):find("145,%-60,%-57"),
  "a scooped source was left on the map: " .. tostring(V.files["/disk/lava.txt"]))

-- 21. a dry depot sends it foraging, not to sleep --------------------------

world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 700,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest" },
        chests = { [k3(DX, DY, DZ)] = {} } })          -- a chest with nothing in it
ok, err, log = runWorld("1")
assert(ok, "forage run crashed: " .. tostring(err))
assert(log:find("forage : depot is dry"), "a dry depot did not send it foraging:\n" .. log)
assert(log:find("y=60"), "it did not head for the top level where the coal is:\n" .. log)
assert(log:find("STOPPED: depot is dry and there is nothing to forage"),
  "it did not stop once foraging was exhausted:\n" .. log)

-- 22. coal in the hold is fuel, not cargo ---------------------------------

-- a seam on the west leg, no depot anywhere: a turtle that runs its reserve
-- down while carrying coal burns the coal instead of stopping on top of it
local seam = {}
for x = 135, 126, -1 do seam[k3(x, BY, BZ)] = "minecraft:coal" end
world({ conf = "tripBlocks = 100000\nfuelShare = 100000\n" .. SECTIONS,
        fuel = 560, blocks = seam })
ok, err, log = runWorld("1")
assert(ok, "burn-the-hold run crashed: " .. tostring(err))
assert(log:find("fuel   : burnt %d+ coal from the hold"),
  "it did not burn the coal it was carrying:\n" .. log)

-- 23. a fuel find is banked for the other two ------------------------------

world({ conf = "topY = -55\ntripBlocks = 100000\nfuelShare = 8\n" .. SECTIONS, fuel = 20000,
        blocks = (function()
          local b = { [k3(DX, DY, DZ)] = "minecraft:chest" }
          -- east leg: the chest at 135 blocks the west one at the floor level
          for x = 137, 146 do b[k3(x, BY, BZ)] = "minecraft:coal" end
          return b
        end)(),
        chests = coalChest(30) })
ok, err, log = runWorld("1")
assert(ok, "fuel-share run crashed: " .. tostring(err))
-- a single digit of slots used: the trip was the fuel find, not a full hold
assert(log:find("depot  : docking with %d slots used"),
  "a fuel find did not send it home; only a full hold did:\n" .. log)
local sv23 = load("return " .. V.files["quarry.state"])()
assert((sv23.shared or 0) > 0,
  "nothing was banked for the other turtles:\n" .. log)
assert(coalLeft() > 3, "the chest ended empty: " .. coalLeft())

print("all quarry phase 3 checks passed")

-- ==========================================================================
-- Phase 4: three turtles
-- ==========================================================================
-- One claim, one depot, three launch indexes. Nothing here needs a second
-- process: a turtle block in the world is a turtle in the way, an air mouth is
-- a branch somebody else took, and a chest under another turtle's trunk is the
-- shared depot this one has to go and find.

-- 24. an air mouth is already taken ---------------------------------------

world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest",
                   [k3(BX - 1, BY, BZ)] = false,     -- west mouth already cut
                   [k3(BX + 1, BY, BZ)] = false },   -- east mouth already cut
        chests = coalChest(30) })
ok, err, log = runWorld("1")
assert(ok, "mouth-claim run crashed: " .. tostring(err))
assert(log:find("taken  : y=%-59 z=%-57 is already cut"),
  "it did not read the air mouth as a claim:\n" .. log)
-- and it did not mine the row anyway: the far end of that branch is untouched
assert(blockAt(BX - 20, BY, BZ) ~= nil, "it mined a branch another turtle had")
local sv24 = load("return " .. V.files["quarry.state"])()
assert(sv24.done["-59:-57"], "the taken branch was not written off")

-- 25. right of way: a turtle in the way is waited out, then worked around ---

-- z=-42 is a branch row at y=-59 inside turtle 2's third, so this is another
-- turtle parked six blocks down the leg turtle 2 is about to mine
local T2BZ = -42
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest",
                   [k3(BX - 6, BY, T2BZ)] = "computercraft:turtle_normal" },
        chests = coalChest(30) })
ok, err, log = runWorld("2")
assert(ok, "right-of-way run crashed: " .. tostring(err))
assert(log:find("giveway: turtle 2 waiting"), "it never waited for the turtle:\n" .. log)
assert(log:find("giveway: the way is still held"),
  "it waited forever instead of giving the branch up:\n" .. log)
assert(blockAt(BX - 6, BY, T2BZ) == "computercraft:turtle_normal",
  "it dug the other turtle")
assert(V.lost == 0, "it destroyed " .. V.lost .. " drops")
-- giving one branch up is not giving up: it went back to work afterwards
local sv25 = load("return " .. V.files["quarry.state"])()
local n25 = 0
for _ in pairs(sv25.done or {}) do n25 = n25 + 1 end
assert(n25 > 0, "it stopped for good the first time it met another turtle:\n" .. log)

-- 26. one depot serves all three ------------------------------------------

-- the chest is under turtle 2's trunk (z=-41); turtle 1 has none under its own
-- and has to walk the spine to find it the first time it needs one
local T2Z = -41
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX - 1, BY, T2Z)] = "minecraft:chest" },
        chests = { [k3(BX - 1, BY, T2Z)] = { { name = "minecraft:coal", count = 30 } } } })
ok, err, log = runWorld("1")
assert(ok, "shared-depot run crashed: " .. tostring(err))
assert(log:find("depot  : nothing under my own trunk"),
  "it claimed a depot it does not have:\n" .. log)
assert(log:find("depot  : shared depot at %d+,%-59,%-41"),
  "it never found the depot under the other trunk:\n" .. log)
assert(log:find("depot  : docking"), "it found the depot and never used it:\n" .. log)

-- and a claim with no depot anywhere asks once, not once per branch
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 20000 })
ok, err, log = runWorld("1")
assert(ok, "no-depot run crashed: " .. tostring(err))
local _, asked = log:gsub("depot  : looking under turtle", "")
assert(asked == 2, "it swept the spine " .. asked .. " times, not once per other trunk")
local sv26 = load("return " .. V.files["quarry.state"])()
assert(sv26.noDepot, "the empty answer was not written down")

-- 27. recall brings it back to the block it was launched on ----------------

world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest" },
        chests = coalChest(30) })
ok, err, log = runWorld("1")
assert(ok, "the run before recall crashed: " .. tostring(err))
local mined, state27 = V.blocks, V.files["quarry.state"]
local stopped = { x = V.pos.x, y = V.pos.y, z = V.pos.z }
assert(stopped.y < 0, "it never went underground, so recall proves nothing")

world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = mined, at = stopped })
V.files["quarry.state"] = state27
ok, err, log = runWorld("1", "recall")
assert(ok, "recall crashed: " .. tostring(err))
assert(log:find("recall :"), "recall said nothing:\n" .. log)
assert(V.pos.x == 137 and V.pos.y == 83 and V.pos.z == -42,
  ("recall parked at %d,%d,%d, not on the launch block"):format(V.pos.x, V.pos.y, V.pos.z))
local sv27 = load("return " .. V.files["quarry.state"])()
assert(sv27.done and next(sv27.done), "recall threw away the work done so far")

print("all quarry phase 4 checks passed")

-- ==========================================================================
-- Phase 5: deployment
-- ==========================================================================
-- The probe settled the mechanics in-game on 2026-08-27: a placed turtle is
-- not a peripheral, boots on its own, and auto-runs /disk/startup.lua. These
-- tests hold deploy to that, and to the kit audit gating it.

local KIT5 = {
  [1] = { name = "computercraft:turtle_advanced", count = 2 },
  [2] = { name = "computercraft:disk_drive",      count = 1 },
  [3] = { name = "computercraft:disk",            count = 1 },
  [4] = { name = "computercraft:wireless_modem_advanced", count = 3 },
  [5] = { name = "minecraft:chest",               count = 3 },
  [6] = { name = "minecraft:bucket",              count = 3 },
  [7] = { name = "minecraft:coal",                count = 192 },
}
local function kit(over)
  local out = {}
  for s, it in pairs(KIT5) do out[s] = { name = it.name, count = it.count } end
  -- false removes a slot: a nil value would simply not appear in pairs()
  for s, v in pairs(over or {}) do out[s] = (v ~= false) and v or nil end
  return out
end

-- 28. a complete kit deploys both turtles ----------------------------------

world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "deploy crashed: " .. tostring(err))
assert(log:find("disk drive placed"), "it never placed the drive:\n" .. log)
assert(log:find("floppy in the drive"), "it never loaded the floppy:\n" .. log)
assert(V.files["/disk/quarry"], "it never copied the program onto the floppy")
assert(V.files["/disk/startup.lua"], "it never wrote the disk startup")
assert(V.files["/disk/boot.lua"], "it never wrote boot.lua beside the startup")
assert(log:find("deploy : 2 of 2 deployed"), "it did not deploy both turtles:\n" .. log)

-- both halves are valid Lua and carry the right index for the LAST turtle
assert(load(V.files["/disk/startup.lua"], "startup"), "the disk startup is not valid Lua")
assert(load(V.files["/disk/boot.lua"], "boot"), "boot.lua is not valid Lua")
assert(V.files["/disk/startup.lua"]:find("local N = 3"),
  "the last disk startup was not written for turtle 3")
assert(V.files["/disk/boot.lua"]:find("local N = 3"),
  "the last boot.lua was not written for turtle 3")

-- each deployed turtle got a modem, coal and a bucket, or it cannot work
local got = { modem = 0, coal = 0, bucket = 0 }
for _, h in ipairs(V.handed) do
  if h.into:find("turtle") then
    if h.name:find("modem") then got.modem = got.modem + 1 end
    if h.name:find("coal") then got.coal = got.coal + 1 end
    if h.name:find("bucket") then got.bucket = got.bucket + 1 end
  end
end
assert(got.modem == 2, "handed " .. got.modem .. " modems, not one per turtle")
assert(got.coal == 2, "handed " .. got.coal .. " lots of coal, not one per turtle")
assert(got.bucket == 2, "handed " .. got.bucket .. " buckets, not one per turtle")

-- 29. a short kit places nothing at all ------------------------------------

world({ inv = kit({ [2] = false }), leaveAfter = 3 })   -- no disk drive
ok, err, log = runWorld("1", "deploy")
assert(ok, "the short-kit run crashed: " .. tostring(err))
assert(log:find("MISSING"), "it did not report the missing drive:\n" .. log)
assert(log:find("nothing has been placed yet"),
  "it did not say the kit was short before anything went down:\n" .. log)
assert(log:find("STOPPED. Fill the gaps"),
  "it did not stop on a short kit:\n" .. log)
assert(log:find("nobody answered"),
  "an unattended short kit must take the safe answer and say so:\n" .. log)
assert(not V.files["/disk/startup.lua"], "a short kit still wrote to a floppy")
assert(not V.files["/disk/boot.lua"], "a short kit still wrote boot.lua to a floppy")
assert(not V.disk, "a short kit still placed the drive")

-- 30. only turtle 1 deploys ------------------------------------------------

world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("2", "deploy")
assert(ok, "the wrong-index run crashed outright: " .. tostring(err))
assert(log:find("deploy is turtle 1's job"),
  "turtle 2 was allowed to deploy:\n" .. log)
assert(not V.disk, "turtle 2 placed the drive anyway")

-- 31. a turtle that never leaves is reported, not waited on forever --------

world({ inv = kit(), leaveAfter = nil })   -- nothing ever moves off the spot
ok, err, log = runWorld("1", "deploy")
assert(ok, "the stuck-turtle run crashed: " .. tostring(err))
assert(log:find("has not moved after 90s"), "it never gave up on a stuck turtle:\n" .. log)
assert(log:find("reboot"), "it did not tell the user how to recover a stuck turtle:\n" .. log)
assert(log:find("deploy : 0 of 2 deployed"),
  "it counted a stuck turtle as deployed:\n" .. log)

-- 32. DRY deploy touches nothing -------------------------------------------

world({ inv = kit(), leaveAfter = 3 })
V.files["quarry.conf"] = "dry = true\n"   -- a deployer still planning, not mining
ok, err, log = runWorld("1", "deploy")
assert(ok, "the DRY deploy crashed: " .. tostring(err))
assert(log:find("DRY deploy"), "DRY deploy said nothing:\n" .. log)
assert(not V.disk, "DRY deploy placed the drive")
assert(not V.files["/disk/startup.lua"], "DRY deploy wrote a boot script")

-- 33. a turtle carrying chests builds its own depot ------------------------

-- No container anywhere in the world: the old behaviour was to shrug and mine
-- one load. Carrying chests means deployment is not finished, so it builds one.
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        inv = { [1] = { name = "minecraft:chest", count = 2 },
                [2] = { name = "minecraft:coal",  count = 64 } } })
ok, err, log = runWorld("1")
assert(ok, "the depot-building run crashed: " .. tostring(err))
assert(log:find("depot  : placed a container under the trunk floor"),
  "it never placed a chest it was carrying:\n" .. log)
assert(log:find("depot  : built the depot here"), "it did not report building one:\n" .. log)
assert(log:find("depot  : banked %d+ fuel into it"),
  "it kept the coal instead of banking it for all three:\n" .. log)
assert(log:find("depot  : container at %d"),
  "it built a depot and then did not find it:\n" .. log)

-- and it really is in the world, UNDER the trunk floor, with the coal in it.
-- Under, not beside: the branch legs run east-west through the floor block's
-- sides and the spine runs north-south through them, so a container on any side
-- is a block the pattern later walks into and refuses to dig, which ends that
-- leg and then stops the run. Below the floor is the one neighbour it never
-- touches, so exactly one container goes in, and it goes there.
--
-- And it goes under THIS turtle's OWN trunk, one box per turtle. One box at
-- the middle trunk funnelled every dock from every turtle to a single block
-- down a spine that is one wide, and two turtles walking to it from opposite
-- ends met head-on and both gave up [in-game 2026-08-29, logs qhVSH and
-- fPSF1]. Turtle 1's third is z -64..-49, so its own trunk is z=-57 = BZ; the
-- middle trunk at z=-41 is turtle 2's and this run must not go near it.
assert(not log:find("walking to z=%-41"),
  "it still walks to the middle trunk, which is the funnel:\n" .. log)
local built = 0
for key, name in pairs(V.blocks) do
  if name and (name:find("chest") or name:find("barrel")) then built = built + 1 end
end
assert(built == 1, "it placed " .. built .. " containers, not 1")
assert(V.blocks[k3(BX, BY - 1, BZ)],
  "the container is not under this turtle's OWN trunk floor:\n" .. log)
assert(not V.blocks[k3(BX, BY - 1, MZ)],
  "it built under the middle trunk, in another turtle's third:\n" .. log)
for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
  local n = V.blocks[k3(BX + d[1], BY, BZ + d[2])]
  assert(not (n and (n:find("chest") or n:find("barrel"))),
    "it put a container beside the trunk floor, in the pattern's way:\n" .. log)
end
local banked = 0
for _, c in pairs(V.chests) do
  for _, item in ipairs(c) do
    if item.name:find("coal") then banked = banked + item.count end
  end
end
assert(banked > 0, "the fuel chest is empty, so nothing can ration from it")

-- a turtle carrying no chests still behaves as it did before
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 20000 })
ok, err, log = runWorld("1")
assert(ok, "the no-chest run crashed: " .. tostring(err))
assert(not log:find("built the depot here"), "it built a depot out of nothing:\n" .. log)

-- 34. a drop that comes back false is a failure, not a success ------------

-- pcall prepends its own success flag, so turtle.drop's answer is the SECOND
-- value. Reading the first one instead made every refused drop print
-- "handed over" and leave a modem-less turtle standing on the surface.
world({ inv = kit(), leaveAfter = 3 })
V.dropFails = true
ok, err, log = runWorld("1", "deploy")
assert(ok, "the refused-drop run crashed: " .. tostring(err))
assert(not log:find("handed over the wireless modem"),
  "a refused drop still reported the modem as handed over:\n" .. log)
assert(log:find("would NOT go across"),
  "it did not report the refused drop:\n" .. log)
assert(log:find("it cannot GPS, so it will never move"),
  "it did not abort the turtle whose modem never arrived:\n" .. log)
assert(log:find("deploy : 0 of 2 deployed"),
  "it counted a modem-less turtle as deployed:\n" .. log)

-- 35. the config rides the floppy with the program ------------------------

-- Turtle 2 that seeds its own quarry.conf gets dry = true, plans a route and
-- never walks it -- which on the surface looks exactly like a hung deployment.
-- It cost a real in-game run. The config has to follow the program.
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the deploy run crashed: " .. tostring(err))
assert(V.files["/disk/quarry.conf"],
  "the config was never put on the floppy, so a deployed turtle seeds a DRY one:\n" .. log)
assert(V.files["/disk/quarry.conf"] == V.files["quarry.conf"],
  "the floppy config is not the deployer's own")
assert(log:find("to /disk/quarry.conf"), "it did not report copying the config:\n" .. log)

-- and the boot script it writes actually installs that config
local boot = V.files["/disk/boot.lua"]
assert(boot, "no boot script was written")
assert(V.files["/disk/startup"] == V.files["/disk/startup.lua"],
  "the disk startup was not written under both names, so which one the disk\n" ..
  "auto-runs decides whether deployment works at all")
assert(boot:find('D .. "/quarry.conf"', 1, true),
  "the boot script never reads the config off the floppy")
assert(boot:find("getMountPath", 1, true),
  "the boot script hard-codes /disk instead of asking the drive where the\n" ..
  "floppy is mounted, which is wrong the moment a second drive exists")

-- a deployer still running dry says so rather than placing turtles that stall
world({ inv = kit(), leaveAfter = 3 })
V.files["quarry.conf"] = "dry = true\n"   -- a deployer still planning, not mining
ok, err, log = runWorld("1", "deploy")
assert(ok, "the DRY deploy crashed: " .. tostring(err))
assert(not V.files["/disk/quarry.conf"], "a DRY deploy still wrote the config")

-- 36. the placed turtle is turned on, not trusted to boot itself ----------

-- Two live deploys placed a turtle that never ran anything: no label, its own
-- root empty, and nothing written to the floppy it could plainly read. Known
-- working replicator code calls turnOn on the side it placed into. Do that.
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the deploy run crashed: " .. tostring(err))
assert((V.turnedOn or 0) >= 1,
  "it placed a turtle and never turned it on:\n" .. log)
assert(log:find("turnOn sent to turtle 2"), "it did not report turning it on:\n" .. log)
assert(not log:find("not visible as a peripheral"),
  "it gave up on the stale peripheral instead of turning to refresh it (issue #660):\n" .. log)

-- and the boot script leaves a local startup behind, so a deployed turtle
-- survives a reboot without the floppy it can no longer reach
local boot2 = V.files["/disk/boot.lua"]
assert(boot2:find("fs.open(\"/startup\", \"w\")", 1, true),
  "the boot script does not install a local startup, so a rebooted turtle is dead")

-- and it proves the modem took, rather than inferring it from the hand swap
assert(boot2:find("peripheral.getType", 1, true),
  "the boot script trusts the equip swap instead of checking which side holds the modem")
assert(boot2:find("modem confirmed equipped on", 1, true),
  "the boot script does not report which side the modem ended up on")

-- 37. an empty tank is named, not mistaken for a wall --------------------

-- turtle.forward() returns false on an empty tank exactly as it does against a
-- wall. calibrate used to read that as "blocked", turn a full circle looking
-- for a way out, and then blame the walls -- which in-game looks like a turtle
-- spinning on the spot for no reason.
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 0 })
ok, err, log = runWorld("2")
assert(ok, "the empty-tank run crashed: " .. tostring(err))
assert(log:find("out of fuel"), "it did not say the tank was empty:\n" .. log)
assert(not log:find("boxed in on all four sides"),
  "it blamed the walls for an empty tank:\n" .. log)

-- 38. the shipped defaults are live, and lava is on ----------------------

-- Set at the user's instruction 2026-08-27: the config the program seeds on a
-- fresh turtle mines for real and scoops lava. Deploy copies that same file to
-- every turtle, so a silent revert here would strand all three planning routes
-- they never walk.
local prog = io.open(PROG):read("a")
assert(prog:find("dry%s+= false"), "the seeded config no longer ships dry = false")
assert(prog:find("lava%s+= true"), "the seeded config no longer ships lava = true")

world({ inv = kit(), leaveAfter = 3 })
V.files["quarry.conf"] = nil          -- no config: the turtle seeds its own
ok, err, log = runWorld("1", "deploy")
assert(ok, "the seeded-config deploy crashed: " .. tostring(err))
assert(not log:find("DRY deploy"),
  "a freshly seeded config still came up dry:\n" .. log)
assert(log:find("dry = false"), "it did not report the config as live:\n" .. log)

-- 39. the halt names the trigger that actually fired ---------------------

-- A real run stopped with "inventory is full" while six slots were empty: it
-- had passed tripBlocks, which is a different trigger with the same halt.
world({ conf = "tripBlocks = 8\n", fuel = 20000 })
ok, err, log = runWorld("1")
assert(ok, "the tripBlocks run crashed: " .. tostring(err))
assert(log:find("tripBlocks is 8"),
  "it did not name tripBlocks as the reason it wanted a depot:\n" .. log)
assert(not log:find("inventory is full"),
  "it blamed a full inventory for a tripBlocks dock:\n" .. log)

-- 40. veinMax caps ONE chase, not the whole run --------------------------

-- st.chased used to be reset once per run, so after veinMax blocks of vein
-- the turtle walked past every ore it met for the rest of the shift and said
-- nothing. Two separate veins on one leg, with veinMax = 1: the second one
-- proves the counter resets.
world({ conf = "tripBlocks = 100000\nveinMax = 1\n" .. SECTIONS, blocks = {
  [k3(130, BY, BZ - 1)] = "minecraft:diamond_ore",
  [k3(120, BY, BZ - 1)] = "minecraft:diamond_ore",
} })
ok, err, log = runWorld("1")
assert(ok, "the two-vein run crashed: " .. tostring(err))
assert(blockAt(130, BY, BZ - 1) == nil, "the first vein was not chased:\n" .. log)
assert(blockAt(120, BY, BZ - 1) == nil,
  "the second vein was never chased -- veinMax is capping the whole run:\n" .. log)

-- 41. a placement that comes back false is a failed deploy ----------------

-- pcall prepends its own flag, so place's answer is the SECOND value. Reading
-- the first made a refused placement read as placed, and the modem and coal
-- then went on the floor in front of nothing.
world({ inv = kit(), leaveAfter = 3,
        blocks = { [k3(137, 83, -41)] = "minecraft:lava" } })  -- no detect, no place
ok, err, log = runWorld("1", "deploy")
assert(ok, "the refused-placement deploy crashed: " .. tostring(err))
assert(log:find("would not place"), "a refused placement was not reported:\n" .. log)
assert(log:find("deploy : 0 of 2 deployed"),
  "a turtle that never got placed was counted as deployed:\n" .. log)
local handed = 0
for _, h in ipairs(V.handed) do if h.into:find("turtle") then handed = handed + 1 end end
assert(handed == 0, "it handed " .. handed .. " items to a turtle that was never placed")

-- 42. an empty tank mid-route is named, not signed off as complete --------

-- turtle.forward() returns false on an empty tank exactly as it does against a
-- wall, so a fuel-out inside goTo used to end the run with halt unset -- and
-- report then printed "work complete" over a turtle stranded with 0 fuel.
-- A vein chase is the drain: it has no reserve check of its own, so it can
-- spend what the branch reserved for the walk to the depot.
local drain = { [k3(DX, DY, DZ)] = "minecraft:chest" }
for x = 126, 134 do for y = BY, BY + 3 do for z = BZ - 3, BZ - 1 do
  drain[k3(x, y, z)] = "minecraft:diamond_ore"
end end end
world({ conf = "tripBlocks = 100000\nfuelMargin = 0\nveinMax = 400\nveinDepth = 30\n" .. SECTIONS,
        fuel = 700, blocks = drain, chests = { [k3(DX, DY, DZ)] = {} } })
ok, err, log = runWorld("1")
assert(ok, "the drained-tank run crashed: " .. tostring(err))
assert(V.fuel == 0, "the tank did not actually empty, it holds " .. V.fuel)
assert(log:find("out of fuel mid%-route"), "an empty tank was not named:\n" .. log)
assert(not log:find("work complete"),
  "it stopped with an empty tank and called the third finished:\n" .. log)

-- 43. the vein sweep keeps its bearings after chasing a side branch --------

-- into() walks off and goTo()s home, and goTo faces the direction it travels,
-- so st.dir on return is the walk home's heading. The sweep used to turn
-- relative to that, which cost it one face per chase: with the -z ore taken
-- first the order became -x, -z, -x, -z and +z was never looked at.
local VX = 128
world({ conf = "tripBlocks = 100000\n" .. SECTIONS, blocks = {
  [k3(VX, BY, BZ - 1)] = "minecraft:diamond_ore",
  [k3(VX, BY, BZ + 1)] = "minecraft:diamond_ore",
} })
ok, err, log = runWorld("1")
assert(ok, "the two-sided vein run crashed: " .. tostring(err))
assert(blockAt(VX, BY, BZ - 1) == nil, "the first face was not chased:\n" .. log)
assert(blockAt(VX, BY, BZ + 1) == nil,
  "the sweep lost its heading after the first chase and missed a face:\n" .. log)

-- 44. an inspect that ERRORS is not another turtle in the way --------------

-- turtleAhead ended with (ok and hit and d and ...find) ~= nil. A failed pcall
-- makes that chain false, and false ~= nil is true -- so every inspect error
-- read as a turtle in the corridor and the turtle waited out six retries and
-- gave the branch up.
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest" },
        chests = coalChest(30) })
V.inspectFails = true
ok, err, log = runWorld("1")
assert(ok, "the failing-inspect run crashed: " .. tostring(err))
assert(not log:find("giveway"),
  "a failed inspect was read as another turtle in the way:\n" .. log)
-- rows are written off a pair at a time now, and this run stops on the trip
-- limit before the pair is cut, so the proof it worked is the rock itself
assert(blockAt(BX - 20, BY, BZ) == nil, "it mined nothing with inspect erroring:\n" .. log)

-- 45. the lava dedupe does not outlive the queue it protects ---------------

-- mapMerge emptied st.lava at every dock and left st.lavaSeen holding every
-- key it had ever seen, and save() serialises the whole state table on every
-- dug block. The invariant: seen never holds more than lava does.
world({ conf = "tripBlocks = 200\nlava = true\nlavaFloor = 0\n" .. SECTIONS, fuel = 2000,
        disk = true,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest",
                   [k3(145, BY - 1, BZ)] = "minecraft:lava" },
        chests = coalChest(30),
        inv = { [16] = { name = "minecraft:bucket", count = 1 } } })
ok, err, log = runWorld("1")
assert(ok, "the lava-dedupe run crashed: " .. tostring(err))
assert(V.files["/disk/lava.txt"], "the map was never written, so nothing merged")
local sv45 = load("return " .. V.files["quarry.state"])()
local nSeen, nQueued = 0, 0
for _ in pairs(sv45.lavaSeen or {}) do nSeen = nSeen + 1 end
for _ in pairs(sv45.lava or {}) do nQueued = nQueued + 1 end
assert(nSeen <= nQueued,
  ("lavaSeen holds %d keys with %d sources queued -- it rides every save"):format(nSeen, nQueued))

-- 46. a place that CRASHES is not a placed container -----------------------

-- select(2, pcall(turtle.place)) is the error STRING when pcall fails, and a
-- string is not false, so a crashed place counted as a container and the
-- turtle then docked against a chest that was never there.
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        inv = { [1] = { name = "minecraft:chest", count = 2 },
                [2] = { name = "minecraft:coal",  count = 64 } } })
V.placeErrors = true
ok, err, log = runWorld("1")
assert(ok, "the crashing-place run crashed: " .. tostring(err))
assert(not log:find("placed a container"),
  "a place that threw was counted as a container:\n" .. log)
assert(not log:find("built the depot here"),
  "it reported a depot it never built:\n" .. log)

-- 47. the shared-depot sweep looks down as well as up ----------------------

-- Bedrock scatters both ways. Turtle 1's floor is two blocks HIGHER than
-- turtle 2's here, so the depot is below it and an upward-only lift sailed
-- over it and wrote noDepot down for good.
local T2LOW = -41
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX, BY + 1, BZ)] = "minecraft:bedrock",  -- our floor stops high
                   [k3(BX - 1, BY, T2LOW)] = "minecraft:chest" },
        chests = { [k3(BX - 1, BY, T2LOW)] = { { name = "minecraft:coal", count = 30 } } } })
ok, err, log = runWorld("1")
assert(ok, "the low-depot run crashed: " .. tostring(err))
assert(log:find("depot  : shared depot at %d+,%-59,%-41"),
  "it never looked below its own floor for the depot:\n" .. log)
local sv47 = load("return " .. V.files["quarry.state"])()
assert(not sv47.noDepot, "it wrote off a depot it could have reached")

-- 48. the boot script no longer promises a turtle that will not move -------

-- DEFAULT_CONF ships dry = false, so a self-seeded config mines. The warning
-- still said it would seed a DRY one and stand still.
assert(not prog:find("seed a DRY one and not move"),
  "BOOT still promises a dry turtle it does not deliver")
assert(prog:find("seeding one from the defaults"),
  "BOOT does not say what a missing config actually does")

-- 56. the deployment kit never goes into the depot -------------------------

-- In-game 2026-08-28: turtle 1 ran `quarry 1` carrying turtles 2 and 3, their
-- modems, the drive and the floppy, docked, and dumpLoad posted the lot into
-- the depot as spoil -- it dumps everything that is not fuel, and only the
-- bucket was named as kit. The other two turtles ended up in a chest.
--
-- The kit is short of the drive and the floppy on purpose: with them aboard a
-- plain `quarry 1` now deploys the other two before it descends (test 65), and
-- there would be no turtles left in the hold to dump. Without a drive it
-- cannot deploy, so it carries them down -- which is exactly the run that
-- produced this bug.
world({ conf = "topY = -55\ntripBlocks = 20\n" .. SECTIONS, fuel = 20000,
        inv = kit({ [2] = false, [3] = false }) })
ok, err, log = runWorld("1")
assert(ok, "the kit-carrying run crashed: " .. tostring(err))
assert(log:find("depot  : docking"), "it never docked, so nothing was dumped:\n" .. log)
for _, c in pairs(V.chests) do
  for _, item in ipairs(c) do
    assert(not (item.name:find("turtle") or item.name:find("modem")
                or item.name:find("disk")),
      "it posted " .. item.name .. " into the depot:\n" .. log)
  end
end
local aboard56 = {}
for s = 1, 16 do
  local it = V.inv[s]
  if it then aboard56[it.name] = (aboard56[it.name] or 0) + it.count end
end
assert(aboard56["computercraft:turtle_advanced"] == 2,
  "the two turtles are not in the hold any more:\n" .. log)
assert(aboard56["computercraft:wireless_modem_advanced"] == 3,
  "the spare modems left the hold:\n" .. log)
assert(log:find("staffing the mine"), "it never tried to deploy the turtles it carried:\n" .. log)
assert(not V.disk, "it deployed with no drive in the hold:\n" .. log)

-- 57. a container UNDER the trunk floor is the depot, and a barrel counts ---

-- The user asked for barrels because a chest with a block over it cannot be
-- opened by hand. isContainer already matched "barrel"; what was missing was
-- looking down at all, which probeDepot now does before it looks around.
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 2000,
        blocks = { [k3(BX, BY - 1, BZ)] = "minecraft:barrel" },
        chests = { [k3(BX, BY - 1, BZ)] = { { name = "minecraft:coal", count = 30 } } } })
ok, err, log = runWorld("1")
assert(ok, "the barrel-depot run crashed: " .. tostring(err))
assert(log:find("depot  : container at .-%(dump down, fuel down%)"),
  "it did not find the barrel under the trunk floor:\n" .. log)
assert(log:find("depot  : dumped;"), "it found the barrel and never used it:\n" .. log)
local inBarrel = 0
for _, it in ipairs(V.chests[k3(BX, BY - 1, BZ)] or {}) do inBarrel = inBarrel + it.count end
assert(inBarrel > 30, "nothing was ever dumped into the barrel:\n" .. log)

-- 58. a deny-list block in a travel corridor is walked around --------------

-- A Lootr chest cannot be broken or emptied by a turtle, and a mineshaft has
-- several. On the spine between two branch rows one used to end the whole run.
-- z=-62 is turtle 1's next branch row after its trunk row at z=-57, so the
-- chest at z=-60 sits square in the walk between them.
-- One level only: the chest sits ON the bottom branch row, so higher up it is
-- an obstacle in a row rather than in a corridor, which is a different rule
-- (it ends the leg) and a different test.
world({ conf = "tripBlocks = 200\ntopY = -59\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX, BY - 1, BZ)] = "minecraft:barrel",
                   [k3(BX, BY, -60)] = "lootr:lootr_chest" },
        chests = { [k3(BX, BY - 1, BZ)] = { { name = "minecraft:coal", count = 30 } } } })
ok, err, log = runWorld("1")
assert(ok, "the go-around run crashed: " .. tostring(err))
assert(log:find("around : lootr:lootr_chest"),
  "it did not route around the lootr chest:\n" .. log)
assert(not log:find("STOPPED: refusing to dig lootr"),
  "a corridor obstacle still ended the run:\n" .. log)
assert(blockAt(BX, BY, -60) == "lootr:lootr_chest", "the lootr chest was destroyed")
assert(blockAt(BX - 20, BY, -62) == nil,
  "it never reached the branch on the far side of the chest:\n" .. log)
-- the way round stays inside the claim: x 112..159, z -64..-17. setAir writes
-- false, so a false entry is a block the turtle dug and a named one is world
-- that was seeded and left standing.
for key, v in pairs(V.blocks) do
  if v == false then
    local x, _, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
    x, z = tonumber(x), tonumber(z)
    assert(x >= 112 and x <= 159 and z >= -64 and z <= -17,
      ("it dug %s, which is outside the claim"):format(key))
  end
end

-- 59. a dock on a leg boundary does not give the branch away ---------------

-- st.leg is set before a leg cuts its first block, so leg="east", along=0 is a
-- branch whose west half is already mined. Read as a fresh branch it walked to
-- its own mouth, saw the air it had just cut, and wrote the row off as another
-- turtle's -- losing the whole east leg every time the hold filled on the
-- boundary between the two.
local westCut = { [k3(BX, BY - 1, BZ)] = "minecraft:barrel" }
for x = BX - 24, BX do westCut[k3(x, BY, BZ)] = false end
world({ conf = "topY = -55\ntripBlocks = 100000\n" .. SECTIONS, fuel = 20000,
        at = { x = BX, y = BY, z = BZ }, blocks = westCut,
        chests = { [k3(BX, BY - 1, BZ)] = { { name = "minecraft:coal", count = 30 } } } })
V.files["quarry.state"] = [[{
  ["index"]=1, ["home"]={["x"]=137,["y"]=83,["z"]=-42},
  ["x"]=]] .. BX .. [[, ["y"]=]] .. BY .. [[, ["z"]=]] .. BZ .. [[, ["dir"]=0,
  ["level"]=]] .. BY .. [[, ["branch"]=]] .. BZ .. [[, ["leg"]="east",
  ["along"]=0, ["task"]="branch", ["dug"]=0, ["carried"]=0, ["done"]={}
}]]
ok, err, log = runWorld("1")
assert(ok, "the leg-boundary resume crashed: " .. tostring(err))
assert(not log:find("taken  :"),
  "it read its own west leg as another turtle's claim:\n" .. log)
for x = BX + 1, 159 do
  assert(blockAt(x, BY, BZ) == nil,
    ("the east leg was skipped: %d,%d,%d is still solid"):format(x, BY, BZ))
end

-- 60. a vein chase stops at the claim rim and at bottomY -------------------

-- The west leg ends at x=112, which is the claim rim. A vein carrying on into
-- x=111 is in the neighbouring claim: outside the 3x3 the player keeps loaded,
-- and ground another turtle may own. The same guard caps the chase at topY,
-- so it cannot climb out of the mine into the user's surface builds. There is
-- no matching floor: test 12 chases ore below bottomY on purpose, because
-- bedrock scatters up to -60 and that is where the deep ore is.
world({ conf = "tripBlocks = 100000\n", blocks = {
  [k3(112, BY, BZ)] = "minecraft:diamond_ore",       -- on the rim: fair game
  [k3(111, BY, BZ)] = "minecraft:diamond_ore",       -- one past it: not
  [k3(110, BY, BZ)] = "minecraft:diamond_ore",
} })
ok, err, log = runWorld("1")
assert(ok, "the rim-chase run crashed: " .. tostring(err))
assert(blockAt(112, BY, BZ) == nil, "it did not mine the ore on the rim itself")
assert(blockAt(111, BY, BZ) == "minecraft:diamond_ore",
  "it chased a vein out of the claim:\n" .. log)
assert(blockAt(110, BY, BZ) == "minecraft:diamond_ore", "it chased two blocks out")
for key, v in pairs(V.blocks) do
  if v == false then
    local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    -- the launch column is the one shaft above topY: the drop to travel height
    -- is travel, not mining, and the program says so
    local shaft = (x == 137 and z == -42)
    assert(x >= 112 and x <= 159 and z >= -64 and z <= -17 and (y <= 60 or shaft),
      ("it dug %s, which is outside the claim"):format(key))
  end
end

-- 61. it installs its own /startup, and recall takes it back off -----------

-- A turtle unloaded with its chunk comes back by rebooting, so /startup is
-- what decides whether the mine carries on. Deployed turtles get one from
-- BOOT; turtle 1 is launched by hand and used to get nothing.
world({ conf = "tripBlocks = 100000\n" })
ok, err, log = runWorld("1")
assert(ok, "the startup run crashed: " .. tostring(err))
assert(V.files["/startup"] == "shell.run('quarry', '1')\n",
  "turtle 1 did not install its own startup: " .. tostring(V.files["/startup"]))
assert(log:find("startup: wrote /startup"), "it never said so:\n" .. log)

-- somebody else's startup is not ours to overwrite
world({ conf = "tripBlocks = 100000\n" })
V.files["/startup"] = "shell.run('someone_elses_program')\n"
ok, err, log = runWorld("1")
assert(ok, "the foreign-startup run crashed: " .. tostring(err))
assert(V.files["/startup"] == "shell.run('someone_elses_program')\n",
  "it clobbered a startup that was not its own")
assert(log:find("startup: /startup is already here and is not mine"),
  "it overwrote or ignored a foreign startup silently:\n" .. log)

-- and recall takes ours off again: a turtle called home stays home
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest" },
        chests = coalChest(30) })
ok, err, log = runWorld("1")
assert(ok, "the run before the recall crashed: " .. tostring(err))
assert(V.files["/startup"], "there was no startup for the recall to remove")
local mined61, state61 = V.blocks, V.files["quarry.state"]
local at61 = { x = V.pos.x, y = V.pos.y, z = V.pos.z }
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = mined61, at = at61, chests = coalChest(30) })
V.files["quarry.state"] = state61
V.files["/startup"] = "shell.run('quarry', '1')\n"
ok, err, log = runWorld("1", "recall")
assert(ok, "the recall crashed: " .. tostring(err))
assert(V.files["/startup"] == nil,
  "recall left the startup on, so a reboot would send it back down:\n" .. log)
assert(log:find("recall : removed /startup"), "it never said so:\n" .. log)

-- 62. bedrock under the trunk floor does not cost the run its depot ---------

-- In-game 2026-08-28 (log Rpv9m): the depot goes UNDER the trunk floor, but
-- bedrock scatters up through y=-60 and the floor stands at y=-59, so the block
-- below it would not open. The run built nothing, found nothing under the other
-- two trunks either, and stopped with a load and nowhere to put it. The
-- fallback is beside the trunk one level UP, on an x side: +z/-z is the spine
-- at every level, and the east-west legs only cross the trunk's own z on the
-- levels isBranch names, which the next level up never is.
-- the bedrock goes under this turtle's OWN trunk, because that is where the
-- depot is built now: one box per turtle, under its own trunk [test 33]
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX, BY - 1, BZ)] = "minecraft:bedrock" },
        inv = { [1] = { name = "minecraft:chest", count = 1 },
                [2] = { name = "minecraft:coal",  count = 64 } } })
ok, err, log = runWorld("1")
assert(ok, "the bedrock-under-the-floor run crashed: " .. tostring(err))
assert(log:find("placed a container beside the trunk at y=" .. (BY + 1), 1, true),
  "bedrock under the floor left the run with no depot at all:\n" .. log)
local side62
for _, dx in ipairs({ -1, 1 }) do
  if V.blocks[k3(BX + dx, BY + 1, BZ)] then side62 = k3(BX + dx, BY + 1, BZ) end
end
assert(side62, "no container beside the trunk one level up:\n" .. log)
for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
  local n = V.blocks[k3(BX + d[1], BY, BZ + d[2])]
  assert(not (n and (n:find("chest") or n:find("barrel"))),
    "it put a container beside the trunk FLOOR, in the pattern's way:\n" .. log)
end
assert(blockAt(BX, BY - 1, BZ) == "minecraft:bedrock", "it dug into bedrock")
assert(log:find("depot  : banked %d+ fuel into it"),
  "it placed the chest and never banked its coal for the others:\n" .. log)
assert(log:find("depot  : dumped;"),
  "it built a depot beside the trunk and then never used it:\n" .. log)

-- 63. spare coal is not a reason to stop when there is nowhere to bank it ---

-- In-game 2026-08-28 (log Rpv9m): turtle 1 came down carrying the depot chests
-- and 192 coal it was holding back FOR that depot, could not place a container
-- anywhere, found none under the other two trunks either -- and then stopped on
-- its second branch with "carrying 192 fuel and fuelShare is 128, which the
-- other turtles could burn", on a full tank with a nearly empty hold.
-- fuelShare means "the other two could use some of this", which needs a depot
-- to put it in; with none it is just fuel this turtle burns itself. A full hold
-- still stops the run, because mining on with nowhere to empty out only
-- destroys the drops.
world({ conf = "tripBlocks = 100000\n" .. SECTIONS, fuel = 20000,
        inv = { [1] = { name = "minecraft:chest", count = 1 },
                [2] = { name = "minecraft:coal",  count = 64 },
                [3] = { name = "minecraft:coal",  count = 64 },
                [4] = { name = "minecraft:coal",  count = 64 } } })
V.placeErrors = true            -- every placement throws: no depot, anywhere
ok, err, log = runWorld("1")
assert(ok, "the spare-coal run crashed: " .. tostring(err))
assert(log:find("no container under any trunk floor"),
  "the run found a depot, so this is not the no-depot case:\n" .. log)
assert(not log:find("which the other turtles could burn"),
  "it stopped over coal it could burn itself, with no depot to bank it in:\n" .. log)
assert(log:find("STOPPED: inventory is full"),
  "the run ended for the wrong reason:\n" .. log)
assert((load("return " .. V.files["quarry.state"])()).dug > 150,
  "it barely mined before stopping:\n" .. log)

-- 64. any storage block is a depot, not only a vanilla chest ---------------

-- The word list is what tells this program what storage is, and a modpack
-- renames storage a dozen ways. Sophisticated Storage's barrels and chests
-- already fell out of "barrel" and "chest"; Create's item vault did not, so a
-- vault under the trunk floor read as stone -- diggable, and no depot. One
-- STORAGE list now answers all four questions: what can be a depot, what is
-- never dug, what stays in the hold as kit, and what the kit audit counts.
world({ conf = "tripBlocks = 200\n" .. SECTIONS, fuel = 2000,
        blocks = { [k3(BX, BY - 1, BZ)] = "create:item_vault",
                   [k3(BX, BY, -60)] = "sophisticatedstorage:iron_barrel" },
        chests = { [k3(BX, BY - 1, BZ)] = { { name = "minecraft:coal", count = 30 } } } })
ok, err, log = runWorld("1")
assert(ok, "the modded-storage run crashed: " .. tostring(err))
assert(log:find("depot  : container at .-%(dump down, fuel down%)"),
  "a Create item vault under the trunk floor was not read as a depot:\n" .. log)
assert(log:find("depot  : dumped;"), "it found the vault and never used it:\n" .. log)
assert(blockAt(BX, BY, -60) == "sophisticatedstorage:iron_barrel",
  "a Sophisticated Storage barrel in the way was dug up:\n" .. log)
local inVault = 0
for _, it in ipairs(V.chests[k3(BX, BY - 1, BZ)] or {}) do inVault = inVault + it.count end
assert(inVault > 30, "nothing was ever dumped into the vault:\n" .. log)

-- and a storage block in the hold is kit: it never goes into the depot as spoil
for _, c in pairs(V.chests) do
  for _, item in ipairs(c) do
    assert(not item.name:find("item_vault"),
      "it posted a storage block into the depot as spoil:\n" .. log)
  end
end

-- 65. a plain `quarry 1` staffs the mine before it works it -----------------

-- Deployment was a mode you had to know about: `quarry 1 deploy`. Turtle 1 run
-- without it walked off with turtles 2 and 3 in the hold and mined the claim
-- alone with two thirds of it untouched -- in-game 2026-08-28 it posted them
-- into the depot as spoil, and once they became kit it just carried them.
-- Turtles in the hold are now the signal: deploy at the surface, then descend.
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1")
assert(ok, "the auto-deploy run crashed: " .. tostring(err))
assert(log:find("staffing the mine"), "it never said why it was deploying:\n" .. log)
assert(log:find("deploy : 2 of 2 deployed"),
  "a plain `quarry 1` did not deploy the turtles it was carrying:\n" .. log)
assert(log:find("branch : "), "it deployed and then never mined:\n" .. log)
local sv65 = load("return " .. V.files["quarry.state"])()
assert((sv65.deployTries or 0) > 0, "the state file does not record the attempt")
assert(sv65.dug > 100, "it barely mined after deploying:\n" .. log)

-- and it does not do it twice: the hold is empty of turtles now, so a reboot mines
V.log = {}
ok, err, log = runWorld("1")
assert(ok, "the resumed run crashed: " .. tostring(err))
assert(not log:find("staffing the mine"), "it tried to deploy all over again:\n" .. log)

-- a turtle with no drive cannot deploy, and must mine rather than stop
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        inv = kit({ [2] = false, [3] = false }), leaveAfter = 3 })
ok, err, log = runWorld("1")
assert(ok, "the driveless run crashed: " .. tostring(err))
assert(log:find("staffing the mine"), "it never tried:\n" .. log)
assert(log:find("branch : "), "a failed deploy stopped the mine:\n" .. log)

-- 66. a full depot loses the junk, not the run -------------------------------

-- The depot filling up ended the run outright: "STOPPED: the depot chest is
-- full", with the player nowhere near it and no way to know. What fills it is
-- the junk tier, so that goes on the tunnel floor instead and the run carries
-- on -- and the player is told over rednet, because emptying the box is the one
-- thing the turtle cannot do for itself.
local function fullBarrel()
  local c = { { name = "minecraft:coal", count = 30 } }
  for _ = 2, 27 do c[#c + 1] = { name = "minecraft:stone", count = 64 } end
  return { [k3(BX, BY - 1, BZ)] = c }        -- 27 stacks: the stub's chest cap
end
world({ conf = "topY = -55\ntripBlocks = 20\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX, BY - 1, BZ)] = "minecraft:barrel" },
        chests = fullBarrel() })
ok, err, log = runWorld("1")
assert(ok, "the full-depot run crashed: " .. tostring(err))
assert(log:find("is FULL"), "a full depot said nothing:\n" .. log)
assert(not log:find("STOPPED: the depot chest is full"),
  "a full depot still ended the run:\n" .. log)
assert(V.ground > 0, "the junk was not dropped on the tunnel floor:\n" .. log)
assert(log:find("branch : "), "it never got back to work:\n" .. log)
local sv66 = load("return " .. V.files["quarry.state"])()
assert((sv66.junked or 0) > 0, "the state file counted no junk")

-- and it went out over rednet, once, so a computer in range can print it
assert(V.rednetOpen == "right", "it never opened the modem: " .. tostring(V.rednetOpen))
assert(#V.sent == 1, "it sent " .. #V.sent .. " messages, not one")
assert(V.sent[1].proto == "quarry", "the message is not on the quarry protocol")
assert(V.sent[1].msg:find("FULL") and V.sent[1].msg:find("136,%-59,%-57"),
  "the message does not name the full depot: " .. tostring(V.sent[1].msg))

-- ore is worth stopping for: with the junk gone and the hold full of diamonds
-- there is nowhere to put them, and mining on would only destroy the drops
local held = {}
for sl = 1, 15 do held[sl] = { name = "minecraft:diamond", count = 64 } end
world({ conf = "topY = -55\ntripBlocks = 20\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX, BY - 1, BZ)] = "minecraft:barrel" },
        chests = fullBarrel(), inv = held })
ok, err, log = runWorld("1")
assert(ok, "the full-hold run crashed: " .. tostring(err))
assert(log:find("STOPPED: the depot chest is full"),
  "it mined on with a hold full of ore and nowhere to put it:\n" .. log)
assert(V.sent[1] and V.sent[1].msg:find("I am holding ore"),
  "the message did not say why it stopped: " .. tostring(V.sent[1] and V.sent[1].msg))

-- 67. a fresh turtle fuels itself BEFORE it deploys ---------------------------

-- In-game 2026-08-28, log zog32: turtle 1 was placed with an empty tank and
-- 192 coal in the hold. topUp ran after the deploy, so runDeploy tried to move
-- up to place the drive on no fuel, clear() set halt, and three things went
-- wrong at once: the mine was staffed by nobody, the whole 192 coal went into
-- turtle 1's own tank because bank was computed once against an empty one, and
-- the run signed off with the deploy's stale "out of fuel" halt on its first
-- dock request -- 15,211 in the tank and 0 branches finished.
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 0,
        inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1")
assert(ok, "the empty-tank run crashed: " .. tostring(err))
assert(not log:find("could not deploy"),
  "an empty tank still cost the mine its other two turtles:\n" .. log)
assert(log:find("deploy : 2 of 2 deployed"),
  "it did not deploy on an empty tank:\n" .. log)
assert(not log:find("STOPPED: out of fuel mid%-route"),
  "the deploy's stale halt still ended the run:\n" .. log)
assert(log:find("branch : "), "it never got to work:\n" .. log)
assert(log:find("depot  : banked %d+ fuel"),
  "it burnt the mine's whole coal stock into its own tank:\n" .. log)

-- 68. the walk home uses the mine, not a fresh shaft --------------------------

-- goTo moves y before it travels, so a dock called from 24 blocks out on a
-- branch ABOVE the depot sank a shaft at the leg end and then cut its way home
-- through solid rock at the depot's level -- a level whose branch rows are
-- staggered somewhere else entirely, so none of it was ground the mine wanted.
-- The way home is the way already cut: back down the leg, along the spine to
-- the trunk -- the mouths this level has to open anyway -- and only then change
-- level, in the trunk shaft.
local TOPY = -57
world({ conf = "topY = " .. TOPY .. "\ntripBlocks = 40\n" .. SECTIONS, fuel = 40000,
        blocks = { [k3(BX, BY - 1, BZ)] = "minecraft:barrel" },
        chests = { [k3(BX, BY - 1, BZ)] = { { name = "minecraft:coal", count = 64 } } } })
ok, err, log = runWorld("1")
assert(ok, "the walk-home run crashed: " .. tostring(err))
assert(log:find("depot  : docking"), "it never docked, so nothing was tested:\n" .. log)
assert(log:find("level  : moving to"), "it never left the depot's own level:\n" .. log)

-- Every block cut below the travel level is the spine (the trunk, and the
-- corridor between this level's mouths), a branch row of the level it is on,
-- or the jog along a rim that carries the turtle from one row to the next. A
-- block anywhere else is rock nothing asked for -- which is exactly what the
-- old walk home cut.
local wRim, eRim = log:match("claim x (%-?%d+)%.%.(%-?%d+)")
assert(wRim, "the claim line is gone, so the rims are unknown:\n" .. log)
wRim, eRim = tonumber(wRim), tonumber(eRim)
for key, v in pairs(V.blocks) do
  if v == false then
    local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if y < TOPY and x ~= BX and x ~= wRim and x ~= eRim then
      assert((z - (-64) - 2 * y) % 5 == 0,
        ("it cut %s on the way home: y=%d has no branch row at z=%d"):format(key, y, z))
    end
  end
end

-- 69. the way back to the spine is the next row, not the one just cut --------

-- A leg ends 24 blocks out and the corridor behind it is air, so walking it
-- back mines nothing. The row 5 over has to come out anyway: the turtle jogs
-- to it along the rim and cuts it inward instead, and the pair costs four legs
-- and two jogs where it used to cost four legs and four empty walks.
world({ conf = "topY = -59\ntripBlocks = 100000\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX, BY - 1, BZ)] = "minecraft:barrel" },
        chests = { [k3(BX, BY - 1, BZ)] = { { name = "minecraft:coal", count = 64 } } } })
ok, err, log = runWorld("1")
assert(ok, "the paired-row run crashed: " .. tostring(err))
assert(log:find("leg back to the spine"),
  "no row was cut inward, so nothing was paired:\n" .. log)

local w69, e69 = log:match("claim x (%-?%d+)%.%.(%-?%d+)")
w69, e69 = tonumber(w69), tonumber(e69)
local jog = 0
for key, v in pairs(V.blocks) do
  if v == false then
    local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if (x == w69 or x == e69) and (z - (-64) - 2 * y) % 5 ~= 0 then jog = jog + 1 end
  end
end
assert(jog > 0,
  "it cut nothing along a rim, so it walked back down the corridor it had just cut:\n" .. log)

-- and both rows of the pair are finished, not just the one it started on
local sv69 = load("return " .. V.files["quarry.state"])()
local n69 = 0
for _ in pairs(sv69.done or {}) do n69 = n69 + 1 end
assert(n69 >= 2, "only " .. n69 .. " row(s) were written off:\n" .. log)

-- 70. a corridor held by another turtle costs a leg, not the row --------------

-- The mouth check reads air at a branch mouth as somebody else's claim, and
-- the turtle that had just cut that mouth itself, given the branch up to a
-- turtle standing in the corridor, walked back to it and wrote its own work
-- off. The row went in st.done with 40 of its 48 blocks still solid, and
-- nothing ever came back for it -- rows skipped, in-game 2026-08-28.
world({ conf = "topY = -59\ntripBlocks = 100000\n" .. SECTIONS, fuel = 200000,
        blocks = { [k3(BX, BY - 1, BZ)] = "minecraft:barrel",
                   [k3(BX - 6, BY, BZ)] = "computercraft:turtle_normal" },
        chests = { [k3(BX, BY - 1, BZ)] = { { name = "minecraft:coal", count = 64 } } } })
ok, err, log = runWorld("1")
assert(ok, "the held-corridor run crashed: " .. tostring(err))
assert(log:find("giveway: the way is still held"), "it never gave the leg up:\n" .. log)
assert(not log:find("taken  : y=%-59 z=%-57"),
  "it read its own mouth as another turtle's claim:\n" .. log)
-- the far side of the parked turtle is all it loses: the east leg is cut
for x = BX + 1, 159 do
  assert(blockAt(x, BY, BZ) == nil,
    ("the east leg went with the held one: %d,%d,%d is still solid"):format(x, BY, BZ))
end

-- 71. topY and bottomY are the range, and nothing outside it is mined --------

-- "only from -59 to -40" is two config lines. The trunk still sinks to the
-- floor and the descent shaft still passes through everything above, but the
-- only levels that get branches are the ones inside the range.
world({ conf = "topY = -55\nbottomY = -58\ntripBlocks = 100000\n" .. SECTIONS, fuel = 200000,
        blocks = { [k3(BX, -59, BZ)] = "minecraft:barrel" },
        chests = { [k3(BX, -59, BZ)] = { { name = "minecraft:coal", count = 64 } } } })
ok, err, log = runWorld("1")
assert(ok, "the level-range run crashed: " .. tostring(err))
local perY = {}
for key, v in pairs(V.blocks) do
  if v == false then
    local _, y = key:match("^(-?%d+),(-?%d+),")
    y = tonumber(y)
    perY[y] = (perY[y] or 0) + 1
  end
end
for y, n in pairs(perY) do
  -- a level outside the range is the descent shaft and the trunk: one column,
  -- never a branch row's worth of blocks
  if y > -55 or y < -58 then
    assert(n <= 2, ("y=%d is outside %d..%d and %d blocks came out of it:\n%s")
      :format(y, -58, -55, n, log))
  end
end
for y = -58, -55 do
  assert((perY[y] or 0) > 40, ("y=%d is inside the range and was not mined:\n%s"):format(y, log))
end

-- 72. turtles in the hold are the deploy signal, not a one-shot flag ---------

-- st.deployed was written BEFORE the attempt so a deploy that died half way
-- would not be retried on every reboot. The cost was every other failure: a
-- short kit, a blocked spot, a crash -- the flag was set, and from then on
-- `quarry 1` walked off with both turtles still in the hold and said nothing.
-- A deploy that works empties the hold, so the hold is the flag.
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        inv = kit(), leaveAfter = 3 })
V.files["quarry.state"] = [[{ ["index"]=1, ["deployed"]=true, ["done"]={} }]]
ok, err, log = runWorld("1")
assert(ok, "the retried-deploy run crashed: " .. tostring(err))
assert(log:find("deploy : 2 of 2 deployed"),
  "a state file that says it already deployed kept the turtles in the hold:\n" .. log)

-- but a deploy that keeps failing gives up rather than doing it every reboot
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        inv = kit({ [2] = false, [3] = false }), leaveAfter = 3 })
V.files["quarry.state"] = [[{ ["index"]=1, ["deployTries"]=3, ["done"]={} }]]
ok, err, log = runWorld("1")
assert(ok, "the given-up deploy run crashed: " .. tostring(err))
assert(log:find("deploy : 2 turtles still in the hold"),
  "it said nothing about the turtles it is still carrying:\n" .. log)
assert(log:find("branch : "), "giving the deploy up stopped the mine:\n" .. log)

-- 73. the real program fits the floppy ---------------------------------------

-- In-game the deploy died on `fs.copy(me, "/disk/quarry")` with "Out of space":
-- quarry.lua is 132 kB and a floppy holds 125 kB [paste WHYa2]. The fix strips
-- full-line comments on the way onto the disk, so the check that matters is
-- that the REAL file goes across and still parses.
local src = assert(io.open("quarry.lua", "r"))
local REAL = src:read("a")
src:close()

world({ inv = kit(), leaveAfter = 3 })
V.files["quarry"] = REAL
ok, err, log = runWorld("1", "deploy")
assert(ok, "deploying the real program crashed: " .. tostring(err))
assert(V.files["/disk/quarry"], "the real program never reached the floppy:\n" .. log)
assert(#V.files["/disk/quarry"] < 125000,
  ("what landed on the floppy is %d bytes"):format(#V.files["/disk/quarry"]))
local prog, why = load(V.files["/disk/quarry"], "floppy")
assert(prog, "the stripped copy is not valid Lua: " .. tostring(why))
assert(V.files["/disk/quarry"]:find("DEFAULT_CONF", 1, true),
  "stripping ate the config template")
-- the config template is a long string: its blank lines and # comments survive
assert(V.files["/disk/quarry"]:find("\n# startX = 0", 1, true),
  "stripping reached inside the [[ long string ]] and cut the config help")
assert(log:find("comments stripped"), "it did not say what it wrote:\n" .. log)

-- 74. a manual-GPS deploy hands on the PLACED turtle's fix, not its own -------

-- With startX/Y/Z set there is no GPS to correct a copied config, so copying
-- the deployer's verbatim tells turtles 2 and 3 they are standing where turtle
-- 1 stands. They are placed one block in front of it, facing back at it.
world({ inv = kit(), leaveAfter = 3, at = { x = 137, y = 83, z = -42 }, dir = 0,
        conf = "startX = 137\nstartY = 83\nstartZ = -42\nstartDir = 0\n" })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the manual-GPS deploy crashed: " .. tostring(err))
local handed = V.files["/disk/quarry.conf"]
assert(handed, "no config reached the floppy:\n" .. log)
assert(handed:find("startZ = %-41"),
  "the floppy config still says the deployer's z:\n" .. handed)
assert(handed:find("startX = 137"), "it moved x, and only z changes here:\n" .. handed)
assert(handed:find("startDir = 2"),
  "the placed turtle faces back at the deployer, so startDir must flip:\n" .. handed)

-- and with GPS the config still goes across untouched
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the GPS deploy crashed: " .. tostring(err))
assert(V.files["/disk/quarry.conf"] == V.files["quarry.conf"],
  "a GPS deploy rewrote a config it had no reason to touch")

-- 75. a placed turtle is off, so deploy asks for the one thing only a player --
--     can do, and does what it is told ---------------------------------------

-- In-game twice on 2026-08-28: turtle 2 stood there, unlabelled, with the
-- program still only on /disk. Whatever the turnOn deploy sends did or did not
-- reach, a turtle in that state is switched off, and one right-click is the
-- one thing that always fixes it. Silence on the floppy is the signal: the
-- boot script writes to it before anything else.
world({ inv = kit(), answers = { "q" } })          -- leaveAfter nil: it never moves
ok, err, log = runWorld("1", "deploy")
assert(ok, "the stuck deploy crashed: " .. tostring(err))
assert(log:find("RIGHT%-CLICK IT"), "it never asked for the one thing that works:\n" .. log)
assert(log:find("stopped deploying on your say%-so"), "q did not stop it:\n" .. log)
assert(not log:find("boot script for turtle 3"),
  "q stopped nothing -- it went on to turtle 3:\n" .. log)
assert(log:find("turtle 3 onwards is still in the hold"),
  "it did not say what is left aboard:\n" .. log)

-- s skips this one -- but a skipped turtle is still standing in the only spot
-- the next one can be placed into, so the run stops there rather than adopting
-- it as turtle 3 [test 92]
world({ inv = kit(), answers = { "s" } })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the skipped deploy crashed: " .. tostring(err))
assert(log:find("skipped on your say%-so"), "s did not skip:\n" .. log)
assert(not log:find("boot script for turtle 3"),
  "it went on to turtle 3 with turtle 2 still blocking the spot:\n" .. log)

-- with the way clear it does move on: what is skipped here is a stone block,
-- not a turtle, so nothing has been stranded and turtle 3 is still tried
world({ inv = kit(), leaveAfter = 3, answers = { "s" },
        blocks = { [k3(137, 83, -41)] = "minecraft:stone" } })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the skipped-obstruction deploy crashed: " .. tostring(err))
assert(log:find("skipped on your say%-so"), "s did not skip:\n" .. log)
assert(log:find("boot script for turtle 3"),
  "s stopped the whole run instead of one turtle:\n" .. log)

-- and with nobody at the keyboard it waits it out exactly as it always did
world({ inv = kit() })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the unattended deploy crashed: " .. tostring(err))
assert(log:find("nobody answered"), "an unattended prompt must say so:\n" .. log)
assert(log:find("did not boot into its startup"),
  "unattended, it must still fall through to the old advice:\n" .. log)

-- 76. pinned coordinates need no modem ---------------------------------------

-- With startX/Y/Z and startDir set nothing ever calls gps.locate, so a modem is
-- a spare part. It used to be kit: the audit demanded three, the handover
-- called a missing one fatal, and the boot script stopped dead without one.
local MANUAL = "startX = 137\nstartY = 83\nstartZ = -42\nstartDir = 0\n"
world({ inv = kit({ [4] = false }), leaveAfter = 3, conf = MANUAL,
        at = { x = 137, y = 83, z = -42 }, dir = 0 })
V.equip = {}                                        -- no modem equipped either
ok, err, log = runWorld("1", "deploy")
assert(ok, "a manual-GPS deploy with no modem crashed: " .. tostring(err))
assert(log:find("wireless modem     0 of   0"),
  "the audit still wants modems on a pinned position:\n" .. log)
assert(log:find("deploy : turtle 2"), "it never got as far as placing:\n" .. log)
local boot = V.files["/disk/boot.lua"]
assert(boot, "no boot script reached the floppy")
assert(boot:find("local MANUAL = true"), "the boot script was not told the position is pinned")
assert(not log:find("it cannot GPS, so it will never move"),
  "a missing modem is still fatal on a pinned position:\n" .. log)

-- and on GPS it is kit again
world({ inv = kit({ [4] = false }), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(log:find("wireless modem     1 of   3"),
  "GPS still needs one modem per turtle:\n" .. log)

-- 77. the deployed turtles inherit the deployer's claim anchor ---------------

-- They wake one block in front of the deployer. Over a chunk border that is a
-- different 3x3 region, so each would sink a trunk in a mine of its own --
-- which is what "turtle 2 started a new tunnel" was.
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the anchored deploy crashed: " .. tostring(err))
local anchor = V.files["/disk/quarry.state"]
assert(anchor, "no claim anchor reached the floppy:\n" .. log)
assert(anchor:find("home"), "the seeded state carries no home: " .. anchor)
assert(anchor:find("137") and anchor:find("%-42"), "the anchor is not the deployer's: " .. anchor)
assert(not anchor:find("dir"),
  "the anchor carries a heading, so the placed turtle will skip its own pin: " .. anchor)
local boot2 = V.files["/disk/boot.lua"]
assert(boot2:find('fs.copy(D .. "/quarry.state", "quarry.state")', 1, true),
  "the boot script does not take the anchor")
assert(boot2:find('not fs.exists("quarry.state")', 1, true),
  "it would overwrite a state file the turtle wrote for itself")

-- 78. the program lands in root under the name everything else uses ----------

assert(boot2:find('fs.copy(D .. "/quarry", "quarry.lua")', 1, true),
  "the boot script still writes a second name for the same program")
assert(boot2:find('if fs.exists("quarry") then fs.delete("quarry") end', 1, true),
  "a stale unsuffixed copy is left beside it for the shell to pick")

-- 79. turtles = 1 has nobody to deploy --------------------------------------

world({ inv = kit(), conf = "turtles = 1\n" })
ok, err, log = runWorld("1", "deploy")
assert(ok, "a one-turtle deploy crashed: " .. tostring(err))
assert(log:find("nobody to deploy"), "it tried to staff a one-turtle mine:\n" .. log)
assert(not V.disk, "a one-turtle deploy still placed the drive")

-- and a two-turtle mine is audited as a two-turtle mine
world({ inv = kit(), conf = "turtles = 2\n", leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(log:find("mining turtle      2 of   1"),
  "the audit still wants a hard-coded three turtles:\n" .. log)
assert(log:find("empty bucket       3 of   2"), "the bucket count does not follow turtles:\n" .. log)
assert(log:find("coal or charcoal 192 of 128"), "the coal count does not follow turtles:\n" .. log)

-- 80. mining alone is a question, not a decision -----------------------------

-- A deploy that fails used to descend anyway, carrying the crew for the whole
-- shift, and nobody found out for an hour.
-- a block where the drive has to go: the audit passes, the deploy throws
local SMALL = "topY = -55\nbottomY = -58\ntripBlocks = 100000\n" .. SECTIONS
local BLOCKED = { [k3(137, 84, -41)] = "minecraft:stone" }

world({ inv = kit(), fuel = 200000, conf = SMALL, blocks = BLOCKED })
ok, err, log = runWorld("1")
assert(ok, "the failed-deploy mine crashed: " .. tostring(err))
assert(log:find("in front of me one block up"), "the deploy did not fail as set up:\n" .. log)
assert(log:find("r = try the deploy again"), "it decided to mine alone on its own:\n" .. log)
assert(log:find("nobody answered"), "unattended it must say which answer it took:\n" .. log)

world({ inv = kit(), fuel = 200000, conf = SMALL, blocks = BLOCKED, answers = { "q" } })
ok, err, log = runWorld("1")
assert(ok, "the stopped mine crashed: " .. tostring(err))
assert(log:find("stopped on your say%-so after the deploy failed"),
  "q did not stop the mine:\n" .. log)
assert(not log:find("trunk  : down to"), "q stopped it and it descended anyway:\n" .. log)

-- 81. a stopped run says why, hours later ------------------------------------

world({ inv = kit(), fuel = 10 })
ok, err, log = runWorld("1")
assert(ok, "the out-of-fuel run crashed: " .. tostring(err))
assert(log:find("not enough fuel"), "it did not stop on fuel:\n" .. log)
local saved = V.files["quarry.state"]
assert(saved:find("not enough fuel"), "the reason died with the run: " .. tostring(saved))

reset({ state = "{x=137,y=83,z=-42,dir=0,index=1,halt=\"not enough fuel: 10 in the tank\"}" })
ok, err, log = run("1", "--check")
assert(ok, "--check crashed: " .. tostring(err))
assert(log:find("last   : the last run stopped %-%- not enough fuel"),
  "--check cannot answer \"why are you stopped\":\n" .. log)

-- 82. a pinned position is a starting value, not a sensor --------------------

-- locate() read the pin before the state file, so a manual-GPS turtle that
-- rebooted 100 blocks down its branch believed it was back on the launch block
-- -- and there is no GPS to catch that, which is why it was pinned.
reset({ gps = false, conf = MANUAL,
        state = "{x=137,y=-59,z=-42,dir=1,index=1}" })
ok, err, log = run("1", "--check")
assert(ok, "--check on a pinned position crashed: " .. tostring(err))
assert(log:find("position: 137,%-59,%-42 %(quarry.state%)"),
  "the pin beat the state file, so a rebooted turtle is 142 blocks out:\n" .. log)

-- with no state of its own it starts on the pin, which is what a deployed
-- turtle does on its first boot
reset({ gps = false, conf = MANUAL })
ok, err, log = run("1", "--check")
assert(log:find("position: 137,83,%-42 %(quarry.conf%)"),
  "a turtle with no state must start on its pin:\n" .. log)

-- 83. typed coordinates, when there is no other way ---------------------------

-- The player is standing next to the turtle with the coordinates on their own
-- screen, and the run used to stop rather than listen to them.
world({ inv = kit(), leaveAfter = 3,
        conf = "# startX = 0\n# startY = 64\n# startZ = 0\n# startDir = 0\n",
        answers = { "137", "83", "-42", "0" } })
V.noGps = true
ok, err, log = runWorld("1", "deploy")
assert(ok, "the typed-coordinates deploy crashed: " .. tostring(err))
assert(log:find("no position fix"), "it did not say what was wrong first:\n" .. log)
assert(log:find("written into quarry.conf"), "it never took the typed coordinates:\n" .. log)
local written = V.files["quarry.conf"]
assert(written:find("startX = 137"), "x was not written into quarry.conf:\n" .. written)
assert(written:find("startDir = 0"), "the heading was not written:\n" .. written)
assert(not written:find("# startX"),
  "it wrote the pin and left the comment saying it is unset:\n" .. written)
assert(log:find("deploy : turtle 2"), "it took the coordinates and stopped anyway:\n" .. log)

-- and nobody at the keyboard is still a refusal, not a guess
world({ inv = kit(), leaveAfter = 3 })
V.noGps = true
ok, err, log = runWorld("1", "deploy")
assert(not ok or log:find("no coordinates given"), "it made a position up:\n" .. log)
assert(log:find("no coordinates given"), "it did not say it had nothing to go on:\n" .. log)
assert(not V.disk, "it placed the drive without knowing where it is")


-- 84. a turtle already standing in front is adopted, not refused -----------
-- Both turtles were refused with "something is in front of me" in-game on
-- 2026-08-28 [log 0JCwD]: the stranded turtle 2 of the run before was still
-- standing in the one spot the deploy places into.

world({ inv = kit(), leaveAfter = 3,
        blocks = { [k3(137, 83, -41)] = "computercraft:turtle_advanced" } })
-- it walks off like any other, once something switches it on
V.placedTurtle, V.sleeps = { x = 137, y = 83, z = -41 }, 0
ok, err, log = runWorld("1", "deploy")
assert(ok, "the adopt-a-standing-turtle deploy crashed: " .. tostring(err))
assert(log:find("adopting it as turtle 2"), "it refused its own stranded turtle:\n" .. log)
assert(not log:find("something is in front of me; move me"),
  "it still treated a standing turtle as an obstruction:\n" .. log)
assert(log:find("turnOn sent to turtle 2"), "it never switched the standing turtle on:\n" .. log)
assert(log:find("deploy : 2 of 2 deployed"), "adopting one cost it the other:\n" .. log)

-- 85. the drive the last deploy left standing is reused --------------------
-- The end of a deploy says "the drive and floppy stay here", so the next
-- `quarry 1 deploy` finds them. Refusing there fails every run after the first.

world({ inv = kit(), leaveAfter = 3, disk = true,
        blocks = { [k3(137, 84, -41)] = "computercraft:disk_drive" } })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the second deploy crashed on its own drive: " .. tostring(err))
assert(log:find("still here %-%- reusing it"), "it did not reuse the standing drive:\n" .. log)
assert(log:find("still in the drive"), "it tried to load a second floppy:\n" .. log)
assert(V.files["/disk/quarry"], "nothing reached the floppy on a reused drive")
assert(log:find("deploy : 2 of 2 deployed"), "the reused drive cost it the mine:\n" .. log)

-- 86. anything else in front is asked about, not silently skipped ----------

world({ inv = kit(), leaveAfter = 3, answers = { "d" },
        blocks = { [k3(137, 83, -41)] = "minecraft:stone" } })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the dig-it-out deploy crashed: " .. tostring(err))
assert(log:find("it is not a turtle"), "it never said what was wrong:\n" .. log)
assert(log:find("d = dig it out"), "it did not offer to dig:\n" .. log)
assert(log:find("deploy : 2 of 2 deployed"), "it did not dig and carry on:\n" .. log)

-- q stops the whole deploy, and nobody at the keyboard is still a refusal
world({ inv = kit(), leaveAfter = 3, answers = { "q" },
        blocks = { [k3(137, 83, -41)] = "minecraft:stone" } })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the q deploy crashed: " .. tostring(err))
assert(log:find("stopped deploying on your say%-so"), "q did not stop it:\n" .. log)
assert(not log:find("boot script for turtle 3"), "q still went on to turtle 3:\n" .. log)

world({ inv = kit(), leaveAfter = 3,
        blocks = { [k3(137, 83, -41)] = "minecraft:stone" } })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the unattended blocked deploy crashed: " .. tostring(err))
assert(log:find("move me somewhere clear"), "unattended, it did not fall back to refusing:\n" .. log)
assert(log:find("deploy : 0 of 2 deployed"), "it deployed into a solid block:\n" .. log)


-- 87. a heading read off F3, and one bad answer does not bin the good ones --
-- In-game [log nznpx] the player typed "+z" for the heading and lost all four
-- answers with it: "no coordinates given, so I have taken none of them".

world({ inv = kit(), leaveAfter = 3, answers = { "1594", "78", "22", "+z" } })
V.noGps = true
ok, err, log = runWorld("1", "deploy")
assert(ok, "the +z deploy crashed: " .. tostring(err))
assert(not log:find("no coordinates given"), "it threw away three good answers:\n" .. log)
local w87 = V.files["quarry.conf"]
assert(w87:find("startX = 1594"), "x was lost with the heading:\n" .. w87)
assert(w87:find("startDir = 0"), "+z was not read as a heading:\n" .. w87)

-- south, north, east and west read the same way
world({ inv = kit(), leaveAfter = 3, answers = { "1594", "78", "22", "West" } })
V.noGps = true
ok, err, log = runWorld("1", "deploy")
assert(ok, "the compass-word deploy crashed: " .. tostring(err))
assert(V.files["quarry.conf"]:find("startDir = 1"),
  "west was not read as -x:\n" .. V.files["quarry.conf"])

-- something unreadable is asked again, not fatal
world({ inv = kit(), leaveAfter = 3, answers = { "1594", "78", "22", "sideways", "2" } })
V.noGps = true
ok, err, log = runWorld("1", "deploy")
assert(ok, "the re-ask deploy crashed: " .. tostring(err))
assert(log:find('I cannot read "sideways"'), "it did not say what it could not read:\n" .. log)
assert(V.files["quarry.conf"]:find("startDir = 2"), "it did not take the second answer")

-- and enter on its own still gives up rather than guessing
world({ inv = kit(), leaveAfter = 3, answers = { "1594", "78", "22", "" } })
V.noGps = true
ok, err, log = runWorld("1", "deploy")
assert(log:find("no coordinates given"), "an empty heading did not stop it:\n" .. log)
assert(not V.disk, "it deployed on a position it had guessed")


-- 88. started off the floppy, it installs itself onto the turtle -----------
-- `cd disk` then `quarry` is what a player types when a deployed turtle did
-- not boot itself. Every path quarry writes is relative, so that run puts
-- quarry.conf, quarry.state and /startup on the floppy the turtle walks away
-- from.

world({ running = "disk/quarry", disk = true })
V.files["/disk/quarry"] = "-- the copy on the floppy"
V.files["/disk/quarry.conf"] = "turtles = 3\ndry = false\n"
V.files["/disk/quarry.state"] = '{["home"]={["x"]=1594,["y"]=77,["z"]=22}}'
V.files["quarry.conf"], V.files["quarry.state"] = nil, nil
ok, err, log = runWorld("2")
assert(ok, "the run off the floppy crashed: " .. tostring(err))
assert(V.files["quarry.lua"] == "-- the copy on the floppy",
  "it did not install itself onto the turtle:\n" .. log)
assert(V.files["quarry.conf"], "it left the config on the floppy:\n" .. log)
assert(V.files["quarry.state"], "it left the claim anchor on the floppy:\n" .. log)
-- /quarry.lua, not quarry.lua: shell.run resolves against the shell's
-- directory, which is /disk here, so a bare name is looked for on the floppy.
assert(V.ran and V.ran[1] == "/quarry.lua" and V.ran[2] == "2",
  "it did not hand the run over to the installed copy:\n" .. log)
assert(not log:find("descend"), "it mined from the floppy anyway:\n" .. log)

-- a turtle that already has its own state keeps it
world({ running = "/disk/quarry", disk = true })
V.files["/disk/quarry"] = "-- the copy on the floppy"
V.files["/disk/quarry.state"] = '{["home"]={["x"]=1,["y"]=2,["z"]=3}}'
V.files["quarry.state"] = '{["home"]={["x"]=9,["y"]=9,["z"]=9}}'
ok, err, log = runWorld("2")
assert(ok, "the leading-slash run crashed: " .. tostring(err))
assert(V.files["quarry.state"]:find("9"), "it overwrote the turtle's own state:\n" .. log)


-- 89. a turtle above or below is waited for, not halted on -----------------
-- All three share one launch block and one depot column, so they meet stacked
-- as often as nose to nose. A vertical move had no right of way at all:
-- clear() saw a turtle it may not dig and ended the run, which is both of them
-- reported "stopped" on the depot [user, 2026-08-28, twice].

world({ conf = "tripBlocks = 100000\n",
        blocks = { [k3(137, 82, -42)] = "computercraft:turtle_advanced" } })
V.placedTurtle, V.leaveAfter, V.sleeps = { x = 137, y = 82, z = -42 }, 2, 0
ok, err, log = runWorld("1")
assert(ok, "the stacked-turtle run crashed: " .. tostring(err))
assert(log:find("giveway: turtle 1 waiting"), "it did not wait for the turtle below:\n" .. log)
assert(not log:find("refusing to dig computercraft:turtle_advanced"),
  "a turtle below still ended the run:\n" .. log)
assert(log:find("descend"), "it never got past it:\n" .. log)

-- 90. the deployer's config is a seed, not a master ------------------------
-- It used to be re-copied on every boot, so coordinates typed in by hand were
-- wiped by the next reboot and the turtle asked for them again, forever, for
-- as long as it stood beside the drive.

world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "deploy crashed: " .. tostring(err))
local boot90 = V.files["/disk/boot.lua"]
assert(boot90:find('not fs.exists("quarry.conf")', 1, true),
  "the boot script still overwrites a config the turtle already has:\n" .. boot90)
assert(boot90:find("keeping my own quarry.conf", 1, true),
  "it does not say it kept the turtle's own config:\n" .. boot90)

-- 91. a confirmation waits 10s; something the player must go and do waits 60 --

world({ inv = kit({ [2] = false }), leaveAfter = 3 })   -- a slot short of a kit
ok, err, log = runWorld("1", "deploy")
assert(log:find("go on with what is aboard"), "the kit was not short after all:\n" .. log)
assert(log:find("10s of silence"), "a confirmation still waits a minute:\n" .. log)

world({ inv = kit() })                            -- nothing ever walks off
ok, err, log = runWorld("1", "deploy")
assert(log:find("RIGHT%-CLICK IT"), "it never asked for the right-click:\n" .. log)
assert(log:find("60s of silence"),
  "it gave the player 10s to walk over and click a turtle:\n" .. log)


-- 92. a turtle this run stranded is not adopted as the next one --------------
-- In-game the player found turtle 2 holding both buckets and both modems. The
-- loop placed turtle 2, it never booted, and the next pass saw a turtle in
-- front and adopted it as turtle 3: a second kit into the same turtle, a boot
-- script rewritten to quarry 3, and turtle 3 still in the hold.

world({ inv = kit() })                            -- nothing ever walks off
ok, err, log = runWorld("1", "deploy")
assert(ok, "the stranded-turtle deploy crashed: " .. tostring(err))
assert(log:find("adopting it as turtle 3") == nil,
  "it adopted the turtle it had just stranded and fed it twice:\n" .. log)
assert(log:find("still standing in the only spot"),
  "it did not say why it could not go on:\n" .. log)
assert(log:find("wrote the boot script for turtle 3") == nil,
  "it rewrote the floppy, so turtle 2 would wake up as turtle 3:\n" .. log)
assert(log:find("turtle 3 onwards is still in the hold"),
  "it did not say turtle 3 is still aboard:\n" .. log)

-- 93. a re-run resumes at the turtle that has not gone out yet ---------------
-- The loop started at 2 every time, so every retry re-did the turtles that had
-- already walked off -- and with turtle 2 out there, the next turtle ITEM in
-- the hold was placed and labelled quarry 2 as well: two turtles on one third,
-- and turtle 3's third never worked at all.

world({ inv = kit(), leaveAfter = 3 })
V.files["quarry.state"] = [[{ ["index"]=1, ["staffed"]={ [2]=true } }]]
ok, err, log = runWorld("1", "deploy")
assert(ok, "the resumed deploy crashed: " .. tostring(err))
assert(log:find("turtle 2 is already out at its own trunk"),
  "it placed a second turtle 2 over the one already mining:\n" .. log)
assert(not log:find("boot script for turtle 2"),
  "it rewrote the floppy for a turtle that is already out:\n" .. log)
assert(log:find("boot script for turtle 3"),
  "skipping turtle 2 cost it turtle 3:\n" .. log)
assert(log:find("deploy : 2 of 2 deployed"),
  "the one already out was not counted:\n" .. log)

-- and a turtle that goes out is written down, so the next run skips it
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the first deploy crashed: " .. tostring(err))
local st5 = V.files["quarry.state"]
assert(st5 and st5:find("staffed"), "it did not record who went out:\n" .. tostring(st5))

-- 94. GPS, then the config pin, then the questions ---------------------------
-- On the user's instruction 2026-08-29. locate() used to check the pin FIRST
-- and never call gps.locate at all when one was set, so a turtle somebody had
-- picked up and moved kept insisting it was on its launch block with a live
-- constellation overhead saying otherwise.

-- GPS beats a full pin
reset({ gps = true, conf = MANUAL })
ok, err, log = run("1", "--check")
assert(log:find("position: .* %(gps%)"),
  "the config pin beat a working GPS:\n" .. log)

-- with GPS down the pin is what is left, and it is used rather than asked for
reset({ gps = false, conf = MANUAL })
ok, err, log = run("1", "--check")
assert(log:find("position: 137,83,%-42 %(quarry.conf%)"),
  "with no GPS it did not fall back to the pin:\n" .. log)

-- and the turtle's own record still beats the pin: the pin names the launch
-- block, and a running turtle left it long ago [test 82]
reset({ gps = false, conf = MANUAL,
        state = "{x=137,y=-59,z=-42,dir=1,index=1}" })
ok, err, log = run("1", "--check")
assert(log:find("position: 137,%-59,%-42 %(quarry.state%)"),
  "the pin beat the turtle's own saved fix:\n" .. log)

-- with no modem there is no GPS to try, so a pinned turtle pays nothing for
-- being asked first -- and questions are still the last resort, not the second
world({ inv = kit(), leaveAfter = 3 })
V.noGps = true
ok, err, log = runWorld("1", "deploy")
assert(log:find("no coordinates given"),
  "it asked before it had run out of everything else:\n" .. log)

-- 95. a modem in a slot is fitted to a side, and never off the wrong slot -----
-- On the user's instruction 2026-08-29. A modem in the inventory is not a modem
-- on a side, and only a side answers gps.locate -- so a turtle carrying one was
-- falling through to dead reckoning with everything it needed for a real fix.
-- equip SWAPS the selected slot with that side's upgrade, so the danger in
-- fixing it is equipping off the wrong slot and taking the pickaxe instead.

local MODEM = "computercraft:wireless_modem_advanced"

-- getEquippedLeft/Right available: the empty side is known, so it goes there
reset({ equip = {}, getEquipped = true, equipItem = { right = "minecraft:diamond_pickaxe" },
        inv = { [3] = { name = MODEM, count = 1 } } })
ok, err, log = run("1", "--check")
assert(ok, "--check crashed fitting a modem: " .. tostring(err))
assert(log:find("fitted it on left"),
  "it did not fit the modem on the free side:\n" .. log)
assert(W.equipItem.right == "minecraft:diamond_pickaxe",
  "it equipped over the pickaxe and disarmed the turtle: " .. tostring(W.equipItem.right))
assert(W.equipItem.left == MODEM, "the modem is not on the left: " .. tostring(W.equipItem.left))
assert(log:find("position: .* %(gps%)"),
  "GPS still did not run after the modem went on:\n" .. log)

-- no getEquippedLeft/Right: equip blind, see the pickaxe come off, put it back
reset({ equip = {}, equipItem = { right = "minecraft:diamond_pickaxe" },
        inv = { [3] = { name = MODEM, count = 1 } } })
ok, err, log = run("1", "--check")
assert(ok, "--check crashed on the fallback equip: " .. tostring(err))
assert(W.equipItem.right == "minecraft:diamond_pickaxe",
  "the fallback left the pickaxe off: " .. tostring(W.equipItem.right))
assert(W.equipItem.left == MODEM,
  "the fallback did not end with the modem on the left: " .. tostring(W.equipItem.left))

-- and the selected slot is read back before anything is equipped: a slot that
-- does not hold a modem is not equipped off, whatever the search said
reset({ equip = {}, getEquipped = true, inv = {} })
ok, err, log = run("1", "--check")
assert(ok, "--check crashed with no modem at all: " .. tostring(err))
assert(W.equipItem.left == nil and W.equipItem.right == nil,
  "it equipped something with no modem aboard")
assert(log:find("no wireless modem is equipped"),
  "it did not say the modem is missing:\n" .. log)

-- a modem already on a side is left alone
reset({ equip = { right = "modem" }, getEquipped = true,
        inv = { [3] = { name = MODEM, count = 1 } } })
ok, err, log = run("1", "--check")
assert(not log:find("fitted it on"), "it re-equipped a modem already on a side:\n" .. log)
assert(W.inv[3] and W.inv[3].name == MODEM, "it consumed the spare modem in the hold")

-- the deployed turtle equips its own modem, and it is the one place a wrong
-- slot costs the pickaxe. Its dance has the same two guards, and the boot
-- script is a string, so this is the only way to see them.
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
local bootTxt = V.files["/disk/boot.lua"]
assert(bootTxt, "no boot script to check")
assert(load(bootTxt, "boot"), "the boot script is not valid Lua")
assert(bootTxt:find("not a modem %-%- not equipping"),
  "the boot script equips without reading the slot back")
assert(bootTxt:find("getEquippedLeft"),
  "the boot script never asks which side is free")

-- 96. the floppy is found where the drive says it is, not at "/disk" ---------
-- On the user's instruction 2026-08-29. "/disk" is only the FIRST drive's
-- mount point; a second drive anywhere puts this floppy at "/disk2", and every
-- hard-coded path then silently misses -- the deployer writes a boot script
-- the new turtle cannot see, and a turtle started off the floppy does not
-- recognise it is on one, so it installs nothing, writes its state to a floppy
-- it is about to walk away from, and cannot be restarted. That is the turtle
-- you have to go and type commands into.

world({ inv = kit(), leaveAfter = 3 })
V.mount = "/disk2"
ok, err, log = runWorld("1", "deploy")
assert(ok, "the deploy crashed on a second-drive mount: " .. tostring(err))
assert(log:find("mounted at /disk2") or log:find("still in the drive, at /disk2"),
  "it never asked the drive where the floppy is:\n" .. log)
assert(V.files["/disk2/quarry"], "the program did not reach the real mount point")
assert(V.files["/disk2/startup.lua"], "the disk startup did not reach the real mount point")
assert(V.files["/disk2/boot.lua"], "boot.lua did not reach the real mount point")
assert(not V.files["/disk/quarry"], "it wrote to /disk, which is a different drive")
assert(log:find("deploy : 2 of 2 deployed"),
  "a floppy at /disk2 cost it the deployment:\n" .. log)

-- both halves ask the same question on the turtle they land on. The startup
-- takes it off the path it was itself started from -- it is sitting on the
-- floppy, so nothing has to be asked -- and boot.lua is handed that answer,
-- with getMountPath as the fallback for a run by hand [DEADLOCK-PLAN layer 3].
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
local s96 = V.files["/disk/startup.lua"]
assert(s96:find("getRunningProgram", 1, true),
  "the disk startup does not work out which floppy it is on:\n" .. s96)
assert(not s96:find('"/disk/', 1, true), "the disk startup hard-codes /disk:\n" .. s96)
local b96 = V.files["/disk/boot.lua"]
assert(b96:find("getMountPath", 1, true), "the boot script hard-codes the mount")
assert(b96:find('D .. "/quarry"', 1, true), "the boot script does not use the mount it found")

-- 97. a silent turtle is rebooted before anyone is asked to walk over --------
-- turnOn wakes a turtle that is OFF; it does nothing to one that is on and
-- never ran the disk startup, which is the state two live deploys left them
-- in. reboot re-runs the disk startup -- the very thing the player was being
-- told to do by hand [user, 2026-08-29].

world({ inv = kit() })                            -- nothing ever walks off
ok, err, log = runWorld("1", "deploy")
assert(ok, "the stuck deploy crashed: " .. tostring(err))
assert(log:find("sent reboot to turtle 2"),
  "it asked the player before trying a reboot itself:\n" .. log)
assert((V.rebooted or 0) >= 2, "it only tried the reboot once: " .. tostring(V.rebooted))
local rebootAt = log:find("sent reboot to turtle 2")
local askAt = log:find("RIGHT%-CLICK IT")
assert(rebootAt and askAt and rebootAt < askAt,
  "it asked for the right-click before it tried the reboot:\n" .. log)

-- 98. the shared-depot sweep never goes below the mine's own floor ----------
-- In-game [log kdxS8, 2026-08-29] turtle 2 found nothing under its own trunk,
-- swept the spine for the others' -- and probed DOWNWARD past bottomY to
-- y=-61, where it cut an eight-block corridor around somebody's chests. The
-- downward offsets exist because a neighbour's floor can be below this
-- turtle's when bedrock stopped this one higher, but bottomY is the same
-- number for all three, so nothing is ever under it.

world({ conf = "topY = -55\ntripBlocks = 96\nbottomY = -59\n" .. SECTIONS,
        fuel = 20000, inv = {} })
ok, err, log = runWorld("2")
assert(ok, "the shared-depot sweep crashed: " .. tostring(err))
assert(log:find("looking under turtle"), "it never swept the spine:\n" .. log)
assert(log:find("no container under any trunk floor"),
  "the sweep found something, so this world does not test the clamp:\n" .. log)
assert(V.minY >= -59,
  "it went to y=" .. tostring(V.minY) .. ", below bottomY, digging into bedrock")

-- 99. "no depot anywhere" does not outlive the run that decided it ----------
-- In-game [2026-08-29, logs H2Ie0 and sCv32] turtles 2 and 3 both filled up and
-- stopped with "there is no depot to empty it into", never once sweeping the
-- spine -- because the run BEFORE had swept, found nothing, and latched
-- st.noDepot into the state file. Turtle 1 built the depot in between.

world({ conf = "topY = -55\ntripBlocks = 96\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(DX, DY, DZ)] = "minecraft:chest" },
        chests = coalChest(300) })
V.files["quarry.state"] = [[{ ["index"]=1, ["noDepot"]=true, ["done"]={} }]]
ok, err, log = runWorld("1")
assert(ok, "the stale-noDepot run crashed: " .. tostring(err))
assert(log:find("forgetting last run"),
  "it kept last run's no-depot answer:\n" .. log)
assert(log:find("depot  : docking"),
  "it never docked, so the stale latch is still stopping it:\n" .. log)
assert(not log:find("there is no depot to empty it into"),
  "it still stopped for want of a depot that is right there:\n" .. log)

-- 100. a depot always aims at a trunk floor, and says so when it misses -----
-- Every other turtle looks for a depot by visiting trunk floors and nothing
-- else, so a container one block short of one is a container none of them will
-- ever find. In-game [log 9KJAs] turtle 1 built where it stood and turtles 2
-- and 3 then both stopped with a full hold. The depot is now one box per
-- turtle under its OWN trunk [DEADLOCK-PLAN layer 1], so the own trunk is the
-- only candidate there is -- which makes "I could not get to it" the case that
-- has to be loud rather than quietly built anyway.

-- a resumed turtle already at its working level but 7 blocks short of its own
-- trunk, with another turtle parked between it and that trunk
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        at = { x = BX, y = BY, z = -50 },
        blocks = { [k3(BX, BY, -53)] = "computercraft:turtle_advanced" },
        inv = { [1] = { name = "minecraft:chest", count = 1 },
                [2] = { name = "minecraft:coal",  count = 64 } } })
V.files["quarry.state"] =
  [[{ ["index"]=1, ["level"]=-59, ["home"]={["x"]=137,["y"]=83,["z"]=-42}, ["done"]={} }]]
ok, err, log = runWorld("1")
assert(ok, "the blocked-own-trunk run crashed: " .. tostring(err))
-- it aims at the trunk floor rather than dropping the box where it stands
assert(log:find("the depot belongs at a trunk floor %-%- walking to z=%-57"),
  "it built where it stood instead of walking to its own trunk:\n" .. log)
assert(log:find("cannot reach z=%-57"), "the trunk was not blocked after all:\n" .. log)
-- and when it cannot get there it says so, because a box that is not on a
-- trunk floor is one no other turtle will ever sweep up
assert(log:find("which is not a trunk"),
  "it built off a trunk floor and said nothing:\n" .. log)
assert(log:find("Move me onto a trunk"),
  "it did not tell the player how to put that right:\n" .. log)

-- 101. a stopped turtle parks OFF the spine -------------------------------
-- The spine is the one corridor all three share and every trunk floor is on
-- it, so a turtle that stops where it stands walls the other two in. Turtle 1
-- spent 24 give-ways in front of one [log 9KJAs].

-- no depot anywhere: it sweeps, walks back to its own trunk to stop tidily,
-- and that trunk floor is a spine block
world({ conf = "topY = -55\ntripBlocks = 96\n" .. SECTIONS, fuel = 20000 })
ok, err, log = runWorld("1")
assert(ok, "the parking run crashed: " .. tostring(err))
assert(log:find("no container under any trunk floor"),
  "it did not stop back at its own trunk, so this world tests nothing:\n" .. log)
assert(log:find("stepped off the spine"),
  "it stopped on the shared corridor and left it blocked:\n" .. log)
local parked = tonumber(log:match("stepped off the spine to (%-?%d+),"))
assert(parked and parked ~= BX,
  "it says it stepped off the spine and is still on it: " .. tostring(parked))

-- 102. run off the floppy with no drive in reach, and it still installs -----
-- `cd disk` then `quarry 2` is what a player types on a turtle that did not
-- boot, and that turtle is standing away from the drive -- so getMountPath has
-- nothing to answer with, and the path name is all there is [user, 2026-08-29].
-- disk = false: no drive on any side and no mount to test for, so getMountPath
-- answers nothing and the path name is the only evidence left
world({ running = "disk/quarry", disk = false })
V.files["/disk/quarry"] = "-- the copy on the floppy"
V.files["/disk/quarry.conf"] = "turtles = 3\ndry = false\n"
V.files["quarry.conf"], V.files["quarry.state"] = nil, nil
ok, err, log = runWorld("2")
assert(ok, "the run off the floppy crashed: " .. tostring(err))
assert(log:find("running off the floppy"),
  "with no drive in reach it did not notice it was on a floppy:\n" .. log)
assert(V.files["quarry.lua"] == "-- the copy on the floppy",
  "it never installed itself onto the turtle:\n" .. log)
assert(V.ran and V.ran[1] == "/quarry.lua",
  "it did not hand the run to the installed copy:\n" .. log)

-- and a mount that is not /disk is still recognised by name
world({ running = "/disk2/quarry", disk = false })
V.files["/disk2/quarry"] = "-- the copy on the second drive"
ok, err, log = runWorld("2")
assert(V.files["quarry.lua"] == "-- the copy on the second drive",
  "a floppy at /disk2 was not recognised as a floppy:\n" .. log)

-- 103. a depot each, under each turtle's own trunk ---------------------------
-- The funnel was the bug. One box meant every dock from all three turtles
-- ended at the same block, down a spine that is one wide with a passing place
-- only every 5 -- so turtle 1 walking +z and turtle 2 walking -z met head-on,
-- both waited, and both gave up [in-game 2026-08-29, logs qhVSH and fPSF1].
-- With a container each, no turtle leaves its own third to bank at all.
-- The thirds are z -64..-49, -48..-33 and -32..-17, with trunks at -57, -41
-- and -25.
local THIRDS = { [1] = { -64, -49, -57 }, [2] = { -48, -33, -41 }, [3] = { -32, -17, -25 } }
for idx = 1, 3 do
  local lo, hi, tz = THIRDS[idx][1], THIRDS[idx][2], THIRDS[idx][3]
  world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
          watchY = BY,
          inv = { [1] = { name = "minecraft:chest", count = 1 },
                  [2] = { name = "minecraft:coal",  count = 64 } } })
  ok, err, log = runWorld(tostring(idx))
  assert(ok, "turtle " .. idx .. "'s own-depot run crashed: " .. tostring(err))
  assert(V.blocks[k3(BX, BY - 1, tz)],
    "turtle " .. idx .. " did not build under its own trunk floor:\n" .. log)
  -- and nowhere else: one box, its own
  local built = 0
  for _, name in pairs(V.blocks) do
    if name and (name:find("chest") or name:find("barrel")) then built = built + 1 end
  end
  assert(built == 1, "turtle " .. idx .. " placed " .. built .. " containers, not 1")
  -- it never asked another turtle for a depot, because it has one
  assert(not log:find("looking under turtle"),
    "turtle " .. idx .. " swept the spine for somebody else's box:\n" .. log)
  -- and the whole shift at the working level stayed inside its own third, so
  -- there is nothing left to meet head-on down there
  assert(V.zMin and V.zMin >= lo and V.zMax <= hi,
    ("turtle %d ranged z=%s..%s at y=%d, outside its third %d..%d:\n%s")
      :format(idx, tostring(V.zMin), tostring(V.zMax), BY, lo, hi, log))
end

-- 104. the kit audit asks for one container per turtle, and says why --------
-- It asked for exactly one however many turtles were configured, which is the
-- kit half of the same funnel.
reset({ inv = {
  [1] = { name = "computercraft:turtle_advanced", count = 2 },
  [2] = { name = "minecraft:chest",               count = 1 },
} })
ok, err, log = run("1", "--check")
assert(ok, "the container audit crashed: " .. tostring(err))
assert(log:find("storage block%s+1 of%s+3%s+SHORT 2"),
  "a 3 turtle mine did not ask for 3 containers:\n" .. log)
assert(log:find("one per turtle, under its own trunk"),
  "it did not say what the containers are for:\n" .. log)

-- and it follows conf.turtles, exactly as the buckets do
reset({ conf = "turtles = 2\n", inv = {
  [1] = { name = "minecraft:chest", count = 2 },
} })
ok, err, log = run("1", "--check")
assert(ok, "the two-turtle container audit crashed: " .. tostring(err))
assert(log:find("storage block%s+2 of%s+2%s+ok"),
  "a 2 turtle mine did not ask for 2 containers:\n" .. log)

-- 105. deploy hands a container across, like the bucket --------------------
-- A turtle deployed without one has no depot of its own, falls back to the
-- shared sweep, and is straight back down the shared spine.
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the container-handover deploy crashed: " .. tostring(err))
local boxes = 0
for _, h in ipairs(V.handed) do
  if h.into:find("turtle") and (h.name:find("chest") or h.name:find("barrel")) then
    boxes = boxes + 1
  end
end
assert(boxes == 2, "handed " .. boxes .. " containers, not one per deployed turtle:\n" .. log)
assert(log:find("handed over the container"),
  "it did not report handing the container across:\n" .. log)

-- 106. a blocked turtle retreats to a passing bay, not one block back -------
-- stepAside() used to step back exactly one block, which leaves the turtle
-- still in the corridor: both of two turtles meeting head-on "moved aside"
-- and neither could pass [in-game 2026-08-29, logs qhVSH and fPSF1]. The
-- retreat now walks back along the spine to a branch mouth and turns into it.
--
-- The cross to the trunk runs -z along the spine at y=-55, and a turtle
-- parked at z=-48 stops it at z=-47. Branch rows at y=-55 are z = -49, -44,
-- -39 ... so the nearest bay behind is z=-44, three blocks back.
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX, -55, -48)] = "computercraft:turtle_advanced" } })
ok, err, log = runWorld("1")
assert(ok, "the head-on run crashed: " .. tostring(err))
local back, bx = log:match("pulled back (%d+) blocks to the branch mouth at (%-?%d+),")
assert(back, "it never retreated to a passing bay:\n" .. log)
assert(tonumber(back) > 1,
  "it retreated " .. back .. " block, which leaves it in the corridor:\n" .. log)
assert(tonumber(bx) ~= BX,
  "it says it pulled into a branch mouth and is still on the spine: " .. tostring(bx))

-- 107. the higher index is the one that moves ------------------------------
-- Nobody can read the other turtle's index, so the asymmetry has to come from
-- its own: index 1 waits longest and holds the corridor, index 3 gives up
-- waiting soonest and is the one that retreats. Settled rule, local knowledge.
local waited = {}
for _, idx in ipairs({ 1, 3 }) do
  world({ conf = "tripBlocks = 100000\n",
          blocks = { [k3(137, 82, -42)] = "computercraft:turtle_advanced" } })
  ok, err, log = runWorld(tostring(idx))
  assert(ok, "the give-way run for turtle " .. idx .. " crashed: " .. tostring(err))
  local of = log:match("turtle " .. idx .. " waiting, another one is in the way %(1 of (%d+)%)")
  assert(of, "turtle " .. idx .. " never waited for the turtle below it:\n" .. log)
  waited[idx] = tonumber(of)
end
assert(waited[1] == 9 and waited[3] == 3,
  ("turtle 1 waited %d tries and turtle 3 waited %d; the rule is 12 - 3 * index")
    :format(waited[1], waited[3]))
assert(waited[3] < waited[1],
  "the higher index does not give up waiting sooner, so nobody ever reverses")

-- 108. a run that gives up on a jam is a STOP, not "work complete" ----------
-- In-game [logs qhVSH and fPSF1] both turtles printed twelve give-ways, then
-- "work complete" -- for a run that never reached its depot and banked
-- nothing. goTo handed the false up, the loop broke with no reason set, and
-- report() had nothing to print but success.
world({ conf = "topY = -55\ntripBlocks = 200\n" .. SECTIONS, fuel = 20000,
        blocks = { [k3(BX, -55, -48)] = "computercraft:turtle_advanced" } })
ok, err, log = runWorld("1")
assert(ok, "the jammed run crashed: " .. tostring(err))
assert(not log:find("work complete"),
  "a run that could not get past another turtle called itself finished:\n" .. log)
assert(log:find("STOPPED: "), "it stopped and gave no reason at all:\n" .. log)
-- and the reason names the block, where it was, and that it is another turtle
assert(log:find("STOPPED: computercraft:turtle_advanced would not move"),
  "the stop does not name what was in the way:\n" .. log)
assert(log:find("at %-?%d+,%-?%d+,%-?%d+ after %d+ tries"),
  "the stop does not say where it was or how long it waited:\n" .. log)
assert(log:find("another turtle, not a block I may dig"),
  "the stop does not say it was a turtle rather than rock:\n" .. log)
-- and it outlives the run, because "why are you stopped" is asked hours later
local sv108 = load("return " .. V.files["quarry.state"])()
assert(sv108.halt and sv108.halt:find("would not move"),
  "the jam did not reach the state file: " .. tostring(sv108.halt))

-- 109. the disk startup is a bootstrap that logs before it runs anything ----
-- "reboot works, running the actual code doesn't" [user, 2026-08-29]. With one
-- file on the floppy there was no way to tell a disk startup that never ran
-- from one that ran and threw, and both look like a turtle standing still.
-- Split them: the startup writes one line and hands over, so an empty floppy
-- log is a CC-side problem and a one-line log is boot.lua failing.
world({ inv = kit(), leaveAfter = 3 })
ok, err, log = runWorld("1", "deploy")
assert(ok, "the split-boot deploy crashed: " .. tostring(err))
local boots = V.files["/disk/startup.lua"]
assert(boots, "no disk startup was written")
assert(boots == V.files["/disk/startup"], "the two startup names differ")
assert(load(boots, "startup"), "the disk startup is not valid Lua")
-- tiny, and nothing in it can throw before it has left a trace
assert(#boots < 1000, "the disk startup is " .. #boots .. " bytes, so it is not a bootstrap")
assert(not boots:find("peripheral", 1, true),
  "the bootstrap makes peripheral calls, which can fail before it logs:\n" .. boots)
local logAt, runAt = boots:find("deploy\" .. N .. \".log", 1, true), boots:find("shell.run", 1, true)
assert(logAt and runAt, "the bootstrap does not both log and hand over:\n" .. boots)
assert(logAt < runAt,
  "it hands over BEFORE it records that it ran, so a crash still leaves no trace")
-- the real logic is a separate file beside it, and a crash in it is logged
local bootl = V.files["/disk/boot.lua"]
assert(bootl, "the real boot logic never reached the floppy")
assert(load(bootl, "boot"), "boot.lua is not valid Lua")
assert(boots:find("boot.lua", 1, true), "the bootstrap never runs boot.lua:\n" .. boots)
assert(bootl:find("pcall(main)", 1, true),
  "boot.lua is not wrapped, so a fault only reaches a screen nobody reads")
assert(bootl:find("STOPPED: boot.lua crashed", 1, true),
  "a crash in boot.lua is not written to the floppy log")
-- and boot.lua appends, so the startup's own line survives to be read
assert(bootl:find('fs.open(LOG, "a")', 1, true),
  "boot.lua truncates the log, losing the one line that says the startup ran")
assert(bootl:find("local D = ...", 1, true),
  "boot.lua does not take the mount point the startup hands it")

-- and the handover really works: run the bootstrap itself against a stub and
-- watch what it writes and what it passes on. boot.lua reads its FIRST
-- argument as the mount, so anything passed in front of it -- the turtle index,
-- say -- becomes the path boot.lua writes every one of its files to.
local wroteTo, wroteLine, ranArgs
local benv = setmetatable({
  fs = {
    getDir = function(n) return (n:gsub("/?[^/]+$", "")) end,
    open = function(n)
      wroteTo = n
      return { writeLine = function(txt) wroteLine = txt end, close = function() end }
    end,
  },
  shell = {
    getRunningProgram = function() return "disk2/startup" end,
    run = function(...) ranArgs = { ... } return true end,
  },
}, { __index = _G })
local bs = assert(load(boots, "bootstrap", "t", benv))
bs()
-- the floppy carries the LAST turtle's startup, which is turtle 3
assert(wroteTo == "/disk2/deploy3.log",
  "the bootstrap logged to " .. tostring(wroteTo) .. ", not the floppy it started from")
assert(wroteLine and wroteLine:find("startup ran"),
  "it did not record that it ran: " .. tostring(wroteLine))
assert(ranArgs and ranArgs[1] == "/disk2/boot.lua",
  "it ran " .. tostring(ranArgs and ranArgs[1]) .. ", not boot.lua on its own floppy")
assert(ranArgs[2] == "/disk2",
  "boot.lua is handed " .. tostring(ranArgs[2]) .. " as its mount point, so every\n" ..
  "file it writes -- the log, the program, the config -- lands somewhere else")
assert(ranArgs[3] == nil,
  "a third argument shifts what boot.lua reads as its mount: " .. tostring(ranArgs[3]))

print("all quarry phase 5 checks passed")
