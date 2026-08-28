-- check the canes shaft set actually sees every column, exactly once
-- lua5.3 test_pattern.lua
local function isShaft(u, v) return (u - 2*v) % 5 == 0 end

local N = 48                     -- 3x3 chunks
local seen, shafts = {}, 0
local function bump(u, v)
  local k = u .. "," .. v
  seen[k] = (seen[k] or 0) + 1
end

-- shafts anchored on the start block, extended one row/col past the rim so the
-- boundary columns get their neighbour
for v = -1, N do
  for u = -1, N do
    if isShaft(u, v) then
      shafts = shafts + 1
      bump(u, v); bump(u-1, v); bump(u+1, v); bump(u, v-1); bump(u, v+1)
    end
  end
end

local missed, doubled = 0, 0
for v = 0, N-1 do
  for u = 0, N-1 do
    local n = seen[u .. "," .. v] or 0
    if n == 0 then missed = missed + 1 elseif n > 1 then doubled = doubled + 1 end
  end
end

-- the sequence the user gave: first shaft per row, 1-indexed
local seq = {}
for v = 0, 9 do
  for u = 0, 4 do
    if isShaft(u, v) then seq[#seq+1] = u + 1 break end
  end
end
local got = table.concat(seq, ",")
local want = "1,3,5,2,4,1,3,5,2,4"

assert(got == want, "row sequence is " .. got .. ", expected " .. want)
assert(missed == 0, missed .. " columns never inspected")
assert(doubled == 0, doubled .. " columns inspected twice (pattern not minimal)")

print(("sequence  %s"):format(got))
print(("claim     %dx%d = %d columns"):format(N, N, N*N))
print(("shafts    %d  (%.1f%% of columns)"):format(shafts, shafts/(N*N)*100))
print("coverage  100%, no column covered twice")

-- how much does the rim ring actually buy?
local inner = 0
for v = 0, N-1 do for u = 0, N-1 do if isShaft(u,v) then inner = inner + 1 end end end
local seen2 = {}
for v = 0, N-1 do for u = 0, N-1 do if isShaft(u,v) then
  for _,d in ipairs{{0,0},{-1,0},{1,0},{0,-1},{0,1}} do
    seen2[(u+d[1])..","..(v+d[2])] = true end end end end
local m2 = 0
for v = 0, N-1 do for u = 0, N-1 do if not seen2[u..","..v] then m2 = m2 + 1 end end end
print(("rim ring  %d extra shafts, closes %d otherwise-unseen columns"):format(shafts-inner, m2))
print(("in-claim  %d shafts, %d columns unseen without the ring"):format(inner, m2))
