# Code Review — quarry.lua

Reviewed: `quarry.lua` (2,396 lines), whole file. No git repository, so there is
no diff; the whole file was read and the checklist applied to it.

Automated checks: `lua5.3 test_quarry.lua` passes — all five phase suites green.
No linter or build command is configured for this project.

## Fixed 2026-08-28 — all nine

CRIT-001, CRIT-002 and WARN-001 were fixed in the first pass, with regression
checks in `test_quarry.lua` (tests 40, 41 and 42). The remaining six —
WARN-002, WARN-003, SUGG-001, SUGG-002, SUGG-003 and SUGG-004 — were fixed in a
second pass on the same day, with tests 43 to 48.

Every one of the six was confirmed non-vacuous: each fix was reverted on its own
in a scratch copy and the suite re-run, and each time the suite failed on that
fix's own test with that test's own message. **Nothing in this review is
outstanding.**

| ID | Test | What the test holds |
| --- | --- | --- |
| CRIT-001 | 40 | Two veins on one leg with `veinMax = 1`: the second still gets chased |
| CRIT-002 | 41 | A refused `turtle.place` reports `would not place` and hands over nothing |
| WARN-001 | 42 | A tank drained mid-route says `out of fuel mid-route`, not `work complete` |
| WARN-002 | 43 | Ore on both z faces of one cell: both get chased, not just the first |
| WARN-003 | 48 | `BOOT` no longer promises a DRY turtle it does not deliver |
| SUGG-001 | 44 | An `inspect` that throws never reads as a turtle in the way |
| SUGG-002 | 45 | `lavaSeen` never holds more keys than `lava` has sources queued |
| SUGG-003 | 46 | A `turtle.place` that throws is not counted as a placed container |
| SUGG-004 | 47 | A depot two blocks BELOW this turtle's floor is still found |

### How the six were fixed

- **WARN-002** — `chase` captures `local d0 = st.dir` with the cell's position,
  and the sweep is `for i = 0, 3 do turnTo(d0 + i) ... end`. Absolute, so it
  survives `goTo` changing the heading on the walk home.
- **WARN-003** — the warning now says a missing floppy config seeds one from the
  defaults, that it **mines**, and that the settings are the defaults rather
  than the deployer's. The comment above it was rewritten to match. No
  behaviour change.
- **SUGG-001** — `turtleAhead` returns `false` explicitly when `pcall` fails,
  before the name test.
- **SUGG-002** — `mapMerge` clears `st.lavaSeen` alongside `st.lava`.
- **SUGG-003** — both call sites read `local lived, put = pcall(...)` and test
  `lived and put ~= false`, the same shape CRIT-002 took.
- **SUGG-004** — `findSharedDepot` probes offsets `{0, 1, 2, 3, -1, -2, -3}`
  from its own level with a `goTo` per offset, so a neighbour's floor below this
  turtle's is reachable. Replaces the one-directional `stepUp` lift.

Two stub switches were added to `test_quarry.lua` to make the `pcall`-failure
paths reachable at all: `V.inspectFails` and `V.placeErrors` make those calls
throw. Every ok-only guard in the file reads that case backwards, so the switches
are worth keeping.

## Review Summary

| ID | Severity | Location | Issue |
| --- | --- | --- | --- |
| CRIT-001 | Critical | quarry.lua:954 | `veinMax` is a whole-run budget, not a per-vein cap, so ore chasing switches itself off partway through a run |
| CRIT-002 | Critical | quarry.lua:2133 | A failed `turtle.place` reads as success during deploy, so the kit is dropped on the ground |
| WARN-001 | Warning | quarry.lua:750 | An empty fuel tank looks identical to a wall, and the run then reports "work complete" |
| WARN-002 | Warning | quarry.lua:979 | The four-way vein sweep loses its bearings after chasing a side branch |
| WARN-003 | Warning | quarry.lua:1996 | The deploy boot script promises a dry turtle and delivers a live one |
| SUGG-001 | Suggestion | quarry.lua:806 | A failed `inspect` is read as "another turtle is in the way" |
| SUGG-002 | Suggestion | quarry.lua:1446 | `st.lavaSeen` never empties, so every save gets slower for the rest of the job |
| SUGG-003 | Suggestion | quarry.lua:1247 | Two more `pcall` results are read one value too shallow |
| SUGG-004 | Suggestion | quarry.lua:1626 | The shared-depot sweep only ever looks upward |

## Critical

### CRIT-001 — `veinMax` stops all vein chasing for the rest of the run

`quarry.lua:954`, `quarry.lua:958`, `quarry.lua:1695` — [Correctness]

**What you would see.** The turtle mines its branches normally for the first
while, then walks straight past ore it is standing next to. Nothing is printed,
nothing halts, and the `dug` count keeps rising, so the run looks healthy while
the thing the mine exists for has quietly stopped.

**What has to be true.** Only that the turtle chases 64 blocks' worth of vein.
`conf.veinMax` defaults to 64 and `st.chased` is reset only at the top of
`runMine` (line 1695), never per vein or per branch, so the counter is
cumulative across the whole run. This will happen on every real run, usually in
the first level or two.

The config comment calls it a "hard cap on blocks per vein chase"
(`quarry.lua:26`), and `report` prints it as "N of them chasing veins", both of
which read as a per-chase limit.

**Fix:** by hand. Reset the counter where a chase begins rather than where a run
begins — `st.chased = 0` at the top of `chase`'s entry from `mineLeg`
(`quarry.lua:1118`), keeping a separate lifetime total for the report if the
`report` line is worth preserving.

```lua
-- in mineLeg, before the chase
st.chased = 0
chase(conf.veinDepth, l, conf)
```

### CRIT-002 — A refused `turtle.place` is read as a successful deploy

`quarry.lua:2133` — [Correctness]

**What you would see.** `deploy` prints "placed <turtle> in front", then hands
over a modem, 64 coal and a bucket, and waits 90 seconds for a turtle that was
never placed. The items go on the ground because the drop has no inventory in
front of it, and the deploy ends with a turtle's worth of kit scattered at the
launch block.

**What has to be true.** Only that `turtle.place` returns `false` — an occupied
block, a protected region, an entity standing in the spot. `pcall` returns its
own success flag first, so `ok` is the flag and `why` is the real result. The
guard `if not ok or ok == false` tests the flag twice and never looks at `why`.
The rest of the file already knows this — `handOver` (`quarry.lua:2097`) has the
comment explaining exactly this mistake, and `runDeploy` uses
`select(2, pcall(...))` correctly at `quarry.lua:2259`.

**Fix:** by hand. Read the second value, the way the neighbouring call sites do.

```lua
local lived, placed = pcall(turtle.place)
if not lived or placed == false then
  return false, "the turtle item would not place: " .. tostring(placed)
end
```

## Warnings

### WARN-001 — An empty tank is invisible to `step`, and the run signs off as complete

`quarry.lua:750`, `quarry.lua:1567` — [Error handling]

**What you would see.** A turtle stops somewhere in the middle of the claim and
prints `work complete`. Nothing says it ran out of fuel, and the summary reads
exactly like a finished third.

**What has to be true.** The tank has to empty while the turtle is travelling
rather than mining. `turtle.forward()` returns `false` on an empty tank with no
error, identically to hitting a wall, so `step` exhausts its eight tries and
returns `false` without setting `halt`. When that happens inside `dock`'s
`goTo`, `dock` returns `false`, `runMine` breaks out of the work loop with
`halt` still nil, and `report` takes the "work complete" branch.

`calibrate` already guards this exact case at `quarry.lua:897` with a message
about it, so the failure mode is known; the guard just is not on the path every
move takes.

**Fix:** by hand. One check in `step`, `stepUp` and `stepDown` — or in `clear`,
which all three call — covers every caller:

```lua
if fuelLevel() < 1 then
  halt = "out of fuel mid-route -- tank is empty"
  return false
end
```

### WARN-002 — FIXED — The vein sweep loses its heading after chasing a side branch

`quarry.lua:979` — [Correctness]

**What you would see.** Veins get partly mined. The turtle takes a branch of the
vein, comes back, and then re-checks a face it has already looked at while never
looking at one or two of the others.

**What has to be true.** The vein has to turn sideways at least once, which is
what a vein does. The sweep is `for _ = 1, 4 do look(...); turnTo(st.dir + 1) end`
— a *relative* turn. But `into` walks the turtle away and calls
`goTo(px, py, pz)` to come back, and `goTo` turns to face the direction of
travel, so `st.dir` on return is whatever the walk home needed. The next
`turnTo(st.dir + 1)` then rotates from the wrong base.

**Fix:** by hand. Anchor the sweep to the heading it started with:

```lua
local d0 = st.dir
for i = 0, 3 do
  turnTo(d0 + i)
  look(turtle.inspect, step)
  if halt then return end
end
```

### WARN-003 — FIXED — The boot script says it will stay dry, and mines instead

`quarry.lua:1996`, `quarry.lua:77` — [Documentation]

**What you would see.** A turtle deployed without `/disk/quarry.conf` prints
`WARNING: no quarry.conf on the floppy -- I will seed a DRY one and not move`,
and then starts mining for real.

**What has to be true.** Only that the floppy copy is missing. `DEFAULT_CONF`
ships `dry = false` (`quarry.lua:77`), so a self-seeded config sets `DRY = false`
at `quarry.lua:2368` and the turtle goes live. The comment above the warning
still describes the older default. The file's header comment at `quarry.lua:9`
and the `seedConf` path now disagree about which way the switch ships.

This is deliberate for the deployer — `BOOL.dry` at `quarry.lua:38` records the
user's 2026-08-27 instruction — so the code is right and the message is stale.

**Fix:** by hand. Say what actually happens: a turtle with no config seeds one
that mines. If a deployed turtle without its deployer's config should instead
stand still, that is a behaviour change, not a comment fix, and it belongs in
`BOOT` rather than in `DEFAULT_CONF`.

## Suggestions

### SUGG-001 — FIXED — A failed `inspect` is treated as a turtle in the way

`quarry.lua:806` — [Correctness]

`turtleAhead` ends with `return (ok and hit and d and ...find("turtle")) ~= nil`.
When `pcall` itself fails the and-chain evaluates to `false`, and `false ~= nil`
is `true` — so an inspect error reads as "another turtle is there". The turtle
then waits through all six `giveWay` retries and marks itself jammed. The
non-error paths are all correct; only the `pcall`-failure path inverts.

**Fix:** by hand. `return ok and hit and d and tostring(d.name):find("turtle", 1, true) ~= nil or false`,
or an explicit `if not ok then return false end`.

### SUGG-002 — FIXED — `st.lavaSeen` grows for the whole job and is serialised on every move

`quarry.lua:1446`, `quarry.lua:1370` — [Performance]

`mapMerge` empties `st.lava` when the turtle docks but leaves `st.lavaSeen`
holding every key it has ever seen. `save()` serialises the whole state table and
runs on every dug block and every move, and `--check` already warns when a save
passes 40 ms, so this table is on the hot path. The cost is small per entry and
never comes back down.

**Fix:** by hand. Clear `st.lavaSeen` alongside `st.lava` in `mapMerge` — the
sources are on `/disk` by then, which is what the dedupe was protecting.

### SUGG-003 — FIXED — Two more `pcall` results read one value too shallow

`quarry.lua:1247`, `quarry.lua:441` — [Correctness]

`buildDepot` tests `select(2, pcall(turtle.place)) ~= false`. When `pcall` fails,
the second value is the error *string*, which is not `false`, so a crashed place
counts as a placed container. `checkLava` at line 441 takes
`local ok = pcall(place)` and prints "scoop ok" from the `pcall` flag alone,
which reports success for a placement that returned `false`.

The second one is diagnostic only, so it misleads a report rather than the mine.

**Fix:** by hand. Same shape as CRIT-002: capture both values and test the
second against `false` explicitly.

### SUGG-004 — FIXED — The shared-depot sweep only looks upward

`quarry.lua:1626` — [Correctness]

`findSharedDepot` walks to each other turtle's trunk at its own `st.level` and
probes up to three blocks up. Bedrock scatters over four blocks, which is the
reason the lift loop exists — but it moves in one direction only. A turtle whose
own bedrock floor stopped it *higher* than its neighbour's is above the depot,
not below it, and the sweep passes over it. It then sets `st.noDepot` and never
looks again.

**Fix:** by hand. Probe symmetrically — a few blocks down as well as up — or
drop to the lowest reachable point in the column before starting the lift.

## What's Good

The failure modes this program has already been through are visible in the code
as guards rather than as comments in a plan: `clear` refuses to dig into a full
inventory and names the issue number, `calibrate` distinguishes an empty tank
from being boxed in, `runMine` explains which of three conditions set
`needDock` instead of blaming the inventory, and `handOver` carries the exact
`pcall` mistake CRIT-002 still has, written down at the call site that got it
right. The `--check` path is a genuine one-run diagnostic: claim maths read back
off the maths rather than asserted, a state-save timing sample, a kit audit that
prints unrecognised item names instead of dropping them.

`test_quarry.lua` covers all five phases against a stubbed world and passes.

## Review Recommendation

**Request changes — since satisfied.** All nine findings are now fixed and
tested; this recommendation stands as the record of why. CRIT-001 disabled the program's main purpose partway through
every run without saying anything, and CRIT-002 turns a refused placement into a
pile of kit on the ground. Both are small, local fixes. WARN-001 is worth taking
in the same pass, because it is the reason a stopped run can report itself as a
finished one — which is what makes the other two hard to notice from a report.
