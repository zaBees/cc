-- fletcher32 of a file, arithmetic only: CC:Tweaked is Lua 5.2, no bitwise ops.
local name = ... or "quarry"
local h = fs.open(name, "r")
if not h then error("no such file: " .. name, 0) end
local s = h.readAll()
h.close()
local n = #s
if n % 2 == 1 then s = s .. "\0" end
local s1, s2 = 0, 0
for i = 1, #s, 2 do
  local a, b = string.byte(s, i, i + 1)
  s1 = (s1 + a + b * 256) % 65535
  s2 = (s2 + s1) % 65535
  if i % 16385 == 0 then os.sleep(0) end
end
print(("%s: %d bytes, fletcher32 %d"):format(name, n, s2 * 65536 + s1))
