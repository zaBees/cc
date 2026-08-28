-- alert : print what the quarry turtles send home
-- wget https://raw.githubusercontent.com/zaBees/cc/main/alert.lua alert
--
-- Run this on a computer with a modem. `quarry` broadcasts on the "quarry"
-- protocol whenever something happens that only a person can fix -- a full
-- depot, so far -- and this is the screen it lands on.
--
-- Range is the catch, and it is physics rather than a bug: a wireless modem's
-- reach shrinks with depth, and the mine floor is a hundred-odd blocks down.
-- The same thing keeps GPS off the claim floor. An ender modem hears the whole
-- world; a plain wireless one wants to be near the mine.

local side
for _, s in ipairs(peripheral.getNames()) do
  if peripheral.getType(s) == "modem" then
    -- a wired modem cannot hear a turtle in a tunnel; take a wireless one if
    -- there is one, and settle for whatever is there if not
    local ok, wireless = pcall(peripheral.call, s, "isWireless")
    if ok and wireless then side = s break end
    side = side or s
  end
end
if not side then error("no modem attached -- put one on any side of me", 0) end

rednet.open(side)
print("alert: listening on " .. side .. " for protocol \"quarry\". Ctrl+T to stop.")

while true do
  local id, msg = rednet.receive("quarry")
  print(("[%s] computer %d: %s"):format(textutils.formatTime(os.time(), true),
    tonumber(id) or 0, tostring(msg)))
end
