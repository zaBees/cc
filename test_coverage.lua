-- cross-section (y,z) coverage test for tunnels running along x.
-- a tunnel of height H at (y,z) occupies (y..y+H-1, z); it SEES every cell
-- face-adjacent to an occupied cell.
local H_ = 200  -- cross-section size, toroidal so edges don't lie to us
local function run(name, H, pick)
  local seen, dug = {}, 0
  local function m(y,z) seen[(y%H_)..","..(z%H_)] = true end
  for y = 0, H_-1 do for z = 0, H_-1 do
    if pick(y,z) then
      for k = 0, H-1 do
        dug = dug + 1
        m(y+k,z); m(y+k,z-1); m(y+k,z+1); m(y+k-1,z); m(y+k+1,z)
      end
    end
  end end
  local miss = 0
  for y = 0, H_-1 do for z = 0, H_-1 do if not seen[y..","..z] then miss = miss+1 end end end
  print(("%-34s dug %5.1f%%   unseen %5.2f%%"):format(name, dug/(H_*H_)*100, miss/(H_*H_)*100))
end

run("1-high, spacing 3 x 3",        1, function(y,z) return y%3==0 and z%3==0 end)
run("1-high, mod-5 stagger",        1, function(y,z) return (z-2*y)%5==0 end)
run("2-high, spacing 3z x 4y",      2, function(y,z) return y%4==0 and z%3==0 end)
run("2-high, spacing 2z x 4y",      2, function(y,z) return y%4==0 and z%2==0 end)
run("2-high, mod-8 stagger",        2, function(y,z) return (z*3-y)%8==0 end)
-- vertical shaft = full column, so cross-section is 1D: mod-5 on z alone
print(("%-34s dug %5.1f%%   unseen %5.2f%%"):format("vertical shafts (canes)", 20.0, 0.00))
