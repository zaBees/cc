-- pgps.lua - private GPS constellation.
--
-- Public GPS lives on channel 65534, so every host anyone builds answers your
-- pings, and one host with wrong coordinates poisons everybody's fix. This runs
-- the same protocol on a channel of your own: only your hosts ever reply.
--
-- usage:  pgps channel 6500     set the channel, once per computer
--         pgps host [x y z]     coordinates are saved, later runs can omit them.
--                               Giving them also writes a startup file, so the
--                               host comes back up on its own after a reboot
--         pgps locate [timeout]
--
-- The channel must match on all four hosts, on every client, and in
-- quarry.conf's gpsChannel. No DRY flag: this drives no actuator, it only
-- talks on a modem.
--
-- ponytail: privacy is the channel number alone. Anyone who scans channels can
-- still spoof a host. Sign the fix with a shared-secret hash if that ever matters.

local CFG = "pgps.cfg"
local DEFAULT_CHANNEL = 6500

local args = { ... }

local function load_cfg()
  if not fs.exists(CFG) then return {} end
  local f = fs.open(CFG, "r")
  local t = textutils.unserialise(f.readAll() or "")
  f.close()
  return type(t) == "table" and t or {}
end

local function save_cfg(cfg)
  local f = fs.open(CFG, "w")
  f.write(textutils.serialise(cfg))
  f.close()
end

local function findModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local ok, wireless = pcall(peripheral.call, name, "isWireless")
      if ok and wireless then return peripheral.wrap(name), name end
    end
  end
end

-- Reuse the rom implementation, trilateration and all, on our channel.
local function privateLocate(channel, timeout)
  local f = assert(fs.open("rom/apis/gps.lua", "r"), "cannot read rom/apis/gps.lua")
  local src = f.readAll()
  f.close()
  local env = setmetatable({}, { __index = _G })
  assert(load(src:gsub("65534", tostring(channel)), "@pgps", nil, env))()
  if type(env.locate) ~= "function" then
    error("rom/apis/gps.lua no longer defines locate; patch pgps", 0)
  end
  return env.locate(timeout or 2)
end

-- A host is only useful running, and a chunk reload or a server restart stops
-- it. Written on the setup run, when coordinates are typed. An existing startup
-- is somebody's, so it is reported and left alone rather than replaced.
local BOOT = 'shell.run("pgps", "host")\n'
local function installStartup()
  for _, name in ipairs({ "startup", "startup.lua" }) do
    if fs.exists(name) then
      local f = fs.open(name, "r")
      local body = f and f.readAll() or ""
      if f then f.close() end
      if body:find("pgps", 1, true) then return name .. " already starts pgps" end
      return name .. " exists and does not start pgps -- left alone. Add this line to it: "
        .. BOOT:gsub("\n", "")
    end
  end
  local f = fs.open("startup", "w")
  if not f then return "cannot write startup -- this host will not come back after a reboot" end
  f.write(BOOT)
  f.close()
  return "wrote startup: this computer hosts on boot"
end

local function host(channel, x, y, z, modem, name)
  pcall(modem.open, channel)
  print(("pgps host %d %d %d, channel %d, %s"):format(x, y, z, channel, name))
  while true do
    local _, _, ch, reply, msg, dist = os.pullEvent("modem_message")
    if ch == channel and msg == "PING" and type(dist) == "number" then
      pcall(modem.transmit, reply, channel, { x, y, z })
    end
  end
end

local cfg = load_cfg()
local mode = args[1]

if mode == "channel" then
  local n = tonumber(args[2])
  if not n or n < 0 or n > 65535 or n % 1 ~= 0 then
    error("channel wants a whole number 0-65535, got " .. tostring(args[2]), 0)
  end
  if n == 65534 then error("65534 is the public GPS channel -- pick another", 0) end
  cfg.channel = n
  save_cfg(cfg)
  print(("channel %d, saved to %s"):format(n, CFG))
  return
end

if mode ~= "host" and mode ~= "locate" then
  print("usage: pgps channel <n> | pgps host [x y z] | pgps locate [timeout]")
  print(("channel is %d%s"):format(cfg.channel or DEFAULT_CHANNEL,
    cfg.channel and "" or " (default -- not set here yet)"))
  return
end

local channel = cfg.channel or DEFAULT_CHANNEL
local modem, name = findModem()
if not modem then error("no wireless modem attached", 0) end

if mode == "locate" then
  print(("pgps locate, channel %d, %s"):format(channel, name))
  local ok, x, y, z = pcall(privateLocate, channel, tonumber(args[2]))
  if not ok then error(x, 0) end
  if x then
    print(("%d %d %d"):format(x, y, z))
  else
    print("no fix: need 4 private hosts in range, not all in one plane")
  end
  return
end

local x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
if x and y and z then
  cfg.x, cfg.y, cfg.z = x, y, z
  save_cfg(cfg)
  print(installStartup())
else
  x, y, z = cfg.x, cfg.y, cfg.z
  if not x then error("no saved position: run  pgps host <x> <y> <z>  once", 0) end
end
host(channel, x, y, z, modem, name)
