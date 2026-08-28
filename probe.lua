-- probe.lua -- Phase 5 deployment probe.
--
-- Answers, in one in-game run, the three mechanics MASTERMINE-PLAN.md section 13
-- says cannot be answered off-line:
--
--   1. Does turtle.place() with a turtle item yield a working turtle, and which
--      way does it face relative to the turtle that placed it?
--   2. Does a freshly placed turtle boot on its own, or does it need turnOn()
--      from a neighbour?
--   3. Does a turtle adjacent to a disk drive auto-run /disk/startup.lua?
--
-- It also prints every inventory item id verbatim, which is what teaches the
-- quarry kit audit this pack's real ids for Mining Turtle, floppy disk and
-- wireless modem, and it reports whether inspect() returns a tags table.
--
-- Run:  probe        -- dry run, places nothing, prints the plan
--       probe go     -- the real run
--
-- Geometry it builds, starting from wherever it stands, facing F:
--
--        [drive]        <- placed from one block up
--   [me] [turtle2]      <- turtle2 placed from the ground block
--
-- turtle2 is adjacent to the drive (below it), so the drive mounts as /disk on
-- turtle2 and on the probe turtle when it stands one block up. The two share
-- that disk, which is how turtle2's report gets back here without a radio.
--
-- Afterwards: break the drive and turtle2 to get the kit back. The floppy is
-- inside the drive.

local args = { ... }
local DRY = true
if args[1] == "go" then DRY = false end

local LOGFILE = "/probe.log"
local PASTE = "https://paste.rs/"

local log = {}

local function say(fmt, ...)
  local line = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  log[#log + 1] = line
  print(line)
  local ok, h = pcall(fs.open, LOGFILE, "w")
  if ok and h then
    h.write(table.concat(log, "\n"))
    h.close()
  end
end

-- Some CC calls return NO values rather than nil (os.getComputerLabel on an
-- unlabelled computer, peripheral.getType on an empty side). tostring() with an
-- empty argument list throws "value expected"; a parameter collapses it to nil.
local function str(v) return tostring(v) end

-- pcall prepends its own flag, and every turtle action returns ok, reason.
-- Returns the callee's first value, or false plus the error on a throw.
local function call(fn, ...)
  local r = { pcall(fn, ...) }
  if not r[1] then return false, tostring(r[2]) end
  return r[2], r[3]
end

-- turtle.inspect returns found, data. nil means air or a throw.
local function look(fn)
  local r = { pcall(fn) }
  if not r[1] or not r[2] then return nil end
  return r[3]
end

local function describe(d)
  if not d then return "air/none" end
  local tags = "tags=NONE"
  if type(d.tags) == "table" then
    tags = "tags=" .. (next(d.tags) ~= nil and "yes" or "empty")
  end
  return d.name .. " " .. tags
end

local function act(desc, fn, ...)
  if DRY then
    say("DRY    %s", desc)
    return true
  end
  local ok, why = call(fn, ...)
  say("%-6s %s", ok and "did" or "FAILED", desc .. (ok and "" or (" -- " .. tostring(why))))
  return ok
end

-- The program turtle2 boots into, if question 3 is answered yes. It writes its
-- findings to the shared disk; this turtle reads them back off the same disk.
local STARTUP = [==[
local PLACER = %d
if os.getComputerID() == PLACER then return end
local out = {}
local function add(f, ...) out[#out + 1] = string.format(f, ...) end
local function look(f)
  local r = { pcall(f) }
  if not r[1] or not r[2] then return "air/none" end
  local d = r[3]
  local tags = "tags=NONE"
  if type(d.tags) == "table" then
    tags = "tags=" .. (next(d.tags) ~= nil and "yes" or "empty")
  end
  return d.name .. " " .. tags
end
add("startup ran on id %%d", os.getComputerID())
local lbl = os.getComputerLabel()   -- unlabelled returns NO values, not nil
add("label      : %%s", tostring(lbl))
add("turtle api : %%s", tostring(turtle ~= nil))
add("fuel       : %%s", turtle and tostring(turtle.getFuelLevel()) or "n/a")
if turtle then
  local names = { "front", "right", "back ", "left " }
  for i = 1, 4 do
    add("%%s      : %%s", names[i], look(turtle.inspect))
    pcall(turtle.turnRight)
  end
  add("up         : %%s", look(turtle.inspectUp))
  add("down       : %%s", look(turtle.inspectDown))
end
local h = fs.open("/disk/result.txt", "w")
h.write(table.concat(out, "\n"))
h.close()
print("probe: wrote /disk/result.txt")
]==]

local function post()
  local body = table.concat(log, "\n")
  local r = { pcall(http.post, PASTE, body) }
  if not r[1] or not r[2] then
    print("post failed; the whole log is at " .. LOGFILE)
    return
  end
  local res = r[2]
  local ok, txt = pcall(res.readAll)
  pcall(res.close)
  print("log: " .. (ok and tostring(txt) or "posted, no body"))
end

local function finish()
  post()
  return
end

-- Liveness first: a remote terminal only pushes a frame when the screen changes.
say("probe  : phase 5 deployment probe, %s", DRY and "DRY (run `probe go` for real)" or "LIVE")
-- os.getComputerLabel() returns NO values when unlabelled, so tostring() would
-- get zero arguments and throw. A local collapses that to nil; an argument does not.
local myLabel = os.getComputerLabel()
say("id     : %d  label: %s  fuel: %s",
  os.getComputerID(), tostring(myLabel), tostring(turtle and turtle.getFuelLevel()))

if not turtle then
  say("stop   : this is not a turtle")
  return finish()
end

-- 1. Inventory, verbatim. This is the answer to "what are this pack's real ids".
say("")
say("-- inventory, verbatim --")
local slots = {}
for i = 1, 16 do
  local d = call(turtle.getItemDetail, i)
  if type(d) == "table" then
    slots[i] = d.name
    say("slot %2d: %s x%d", i, d.name, d.count or 0)
  end
end

local function slotMatching(want, reject)
  for i = 1, 16 do
    local n = slots[i]
    if n and n:find(want, 1, true) and not (reject and n:find(reject, 1, true)) then
      return i, n
    end
  end
end

local driveSlot, driveName = slotMatching("disk_drive")
local floppySlot, floppyName = slotMatching("disk", "disk_drive")
local turtleSlot, turtleName = slotMatching("turtle")
local fuelSlot = slotMatching("coal")

say("")
say("drive  : %s", driveName or "MISSING")
say("floppy : %s", floppyName or "MISSING")
say("turtle : %s", turtleName or "MISSING")

if not (driveSlot and floppySlot and turtleSlot) then
  say("stop   : need one disk drive, one floppy and one mining turtle in the hold")
  say("         (ids above are verbatim -- if an item is present but not matched,")
  say("          this pack names it something the patterns miss; report the line)")
  return finish()
end

-- Fuel: turning is free but this turtle has to move up and down twice.
if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 8 then
  if fuelSlot then
    act("refuel from slot " .. fuelSlot, function()
      turtle.select(fuelSlot)
      return turtle.refuel(1)
    end)
  else
    say("stop   : fuel %d and no coal in the hold", turtle.getFuelLevel())
    return finish()
  end
end

-- 2. Build the rig.
say("")
say("-- building the rig --")
say("front  : %s", describe(look(turtle.inspect)))
say("up     : %s", describe(look(turtle.inspectUp)))

if look(turtle.inspectUp) then act("dig up", turtle.digUp) end
if not act("move up", turtle.up) then
  say("stop   : cannot get above the ground block")
  return finish()
end

if look(turtle.inspect) then act("dig forward (drive space)", turtle.dig) end
act("select drive slot " .. driveSlot, turtle.select, driveSlot)
if not act("place disk drive in front", turtle.place) then
  say("stop   : drive would not place")
  return finish()
end

act("select floppy slot " .. floppySlot, turtle.select, floppySlot)
act("drop floppy into the drive", turtle.drop, 1)

local mounted = DRY and "(dry)" or str(fs.exists("/disk"))
say("mount  : /disk exists on the placer = %s", mounted)
if not DRY then
  local drv = peripheral.wrap("front")
  if drv then
    say("drive  : type=%s diskPresent=%s diskID=%s mountPath=%s",
      str(peripheral.getType("front")),
      str(call(drv.isDiskPresent)),
      str(call(drv.getDiskID)),
      str(call(drv.getMountPath)))
  end
end

if DRY then
  say("DRY    write /disk/startup.lua")
else
  local ok, h = pcall(fs.open, "/disk/startup.lua", "w")
  if not (ok and h) then
    say("stop   : cannot write /disk/startup.lua -- the floppy did not go in")
    return finish()
  end
  h.write(string.format(STARTUP, os.getComputerID()))
  h.close()
  say("did    write /disk/startup.lua (placer id %d)", os.getComputerID())
end

if not act("move down", turtle.down) then
  say("stop   : stuck above the ground block")
  return finish()
end

if look(turtle.inspect) then act("dig forward (turtle space)", turtle.dig) end
act("select turtle slot " .. turtleSlot, turtle.select, turtleSlot)
if not act("place turtle in front", turtle.place) then
  say("stop   : the turtle item would not place")
  return finish()
end

-- 3. Question 2: does it boot on its own?
say("")
say("-- question 2: does a placed turtle self-boot? --")
if DRY then
  say("DRY    would wrap the block in front and poll isOn() for 10s")
else
  say("type   : peripheral.getType(front) = %s", str(peripheral.getType("front")))
  local t2 = peripheral.wrap("front")
  if not t2 then
    -- Settled in-game 2026-08-27: a turtle is NOT a peripheral to another
    -- turtle, so a nil wrap says nothing about whether the placed turtle
    -- booted. Do not read it as a failed placement -- the place already
    -- succeeded above. Question 3 below is what actually answers the boot.
    say("ANSWER : no peripheral wrap. A turtle cannot see another turtle as a")
    say("         peripheral, so turnOn/isOn/getID are all unavailable here.")
    say("         The disk report below is the only proof of a boot.")
  else
    local methods = {}
    for _, m in ipairs(peripheral.getMethods and peripheral.getMethods("front") or {}) do
      methods[#methods + 1] = m
    end
    if #methods > 0 then say("methods: %s", table.concat(methods, " ")) end
    say("id     : %s  label: %s", str(call(t2.getID)), str(call(t2.getLabel)))
    local selfOn = false
    for i = 1, 10 do
      if call(t2.isOn) == true then
        selfOn = true
        say("ANSWER : self-booted, isOn() true after %ds -- no turnOn needed", i - 1)
        break
      end
      os.sleep(1)
    end
    if not selfOn then
      say("ANSWER : still off after 10s -- a placed turtle does NOT self-boot")
      act("turnOn the placed turtle", t2.turnOn)
      os.sleep(3)
      say("after  : isOn() = %s", str(call(t2.isOn)))
    end
  end
end

-- 4. Question 3: did it run /disk/startup.lua? And question 1, its facing.
say("")
say("-- question 3: does it auto-run /disk/startup.lua? --")
if DRY then
  say("DRY    would go back up and poll /disk/result.txt for 30s")
  say("DRY    that file also carries question 1: which relative side holds the placer")
  return finish()
end

act("move up", turtle.up)
local got = false
for i = 1, 30 do
  if fs.exists("/disk/result.txt") then
    got = true
    say("ANSWER : yes -- /disk/startup.lua ran on the placed turtle (%ds)", i - 1)
    local ok, h = pcall(fs.open, "/disk/result.txt", "r")
    if ok and h then
      say("")
      say("-- what the placed turtle reported --")
      for line in h.readLine do say("%s", line) end
      h.close()
    end
    break
  end
  os.sleep(1)
end

if not got then
  say("ANSWER : no result after 30s. Either the disk startup did not auto-run, or")
  say("         the placed turtle never booted. Check its screen in-game.")
end

say("")
say("-- question 1: facing --")
say("The placer stood behind the placed turtle, one block back at ground level,")
say("and the drive sits directly above it. In the report above, the side that")
say("names a turtle is where the placer is: `back` means the placed turtle faces")
say("away from its placer, `front` means it faces the placer.")
say("")
say("Recover the kit by breaking the drive (floppy inside) and the placed turtle.")
finish()
