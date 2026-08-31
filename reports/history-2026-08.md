# Archive — RESUME.md as it stood on 2026-08-28, before the trim

This is the full working history of the build up to 2026-08-28: the
phase-by-phase narratives, the code-review findings in full, the four failed
deploy runs, the probe results and the in-game logs' conclusions.

It was split out because `RESUME.md` is read at the start of every session and
had grown to 646 lines, most of it settled history that no longer changes a
decision. Nothing here was deleted — it was moved. `RESUME.md` now carries the
state, the rules and the next action, and points here for the why.

Read this when you need the reasoning behind a decision `RESUME.md` states
flatly, or when something that was settled starts misbehaving again.

---

# Resume here

Handoff for the turtle mining build in this directory. If a session ends
mid-task — budget exhausted, crash, context lost — a fresh session reads this
file, then `MASTERMINE-PLAN.md`, and continues without re-deriving anything.

**Rule: this file is rewritten whole at the end of every phase, before anything
else.** Nothing important lives only in chat. Never patch it with a blind
search-and-replace — a patch whose search string does not match fails silently,
which has already happened once and left this file describing an abandoned
design. An asserted replace is fine; a hopeful one is not.

---

## Where the work stands

Last updated **2026-08-28**, after clearing every finding from the code review
of `quarry.lua` — nine in all — and uploading the fixed build as `3PcMy`.

**Phases 1 to 5 have all now run in-game (2026-08-27).** Turtle 2 mined 177
blocks under its own power after being deployed by turtle 1. What has NOT been
proven is the depot cycle: no container has ever been placed, so docking,
rationing, restocking and the three-turtle interplay are still stub-tested
only.

| Phase | State |
| --- | --- |
| 1 — claim maths, iterators, `--check`, kit audit | **Done. Run in-game 2026-08-24.** |
| 2 — one turtle, one branch | **Done. Run in-game 2026-08-27** (turtle 2, 177 blocks). |
| 3 — depot cycle, fuel, the work loop | **Partly run.** Travel, fuel and the work loop ran in-game; the depot cycle has never had a container to use. |
| 4 — three turtles | **Partly run.** Turtle 2 worked its own third correctly. Two turtles have never run at once. |
| 5 — deployment (`quarry 1 deploy`) | **Done. Run in-game 2026-08-27** after four failed attempts; turtle 2 deployed, booted and mined. |
| 6 — deferred (monitor, full-clear mode) | Not started |

### Delivered 2026-08-25 — the sandbox reached paste.rs this time

| Program | URL | What it is |
| --- | --- | --- |
| `quarry.lua` | `https://paste.rs/3PcMy` | **CURRENT — uploaded 2026-08-28, all nine review findings fixed.** Verified by fetching it back and diffing against disk: identical. |
| `probe.lua` | `https://paste.rs/4uJB7` | The Phase 5 deployment probe. |

`3PcMy` is digit three, capital P, small c, capital M, small y — ids are
case-sensitive and a 404 is usually a case slip.

**Every download is TWO lines.** CC's `wget` refuses to overwrite an existing
file: it prints `File already exists`, downloads nothing, and reads like
success. No force flag, and the CC shell has no `&&` or `;`.

```
delete quarry
wget https://paste.rs/3PcMy quarry

delete probe
wget https://paste.rs/4uJB7 probe
```

The earlier note that the sandbox cannot reach paste.rs no longer holds — the
upload went straight through on 2026-08-25. Try it before asking the user to run
`curl -sS --data-binary @quarry.lua https://paste.rs/` in their own shell.

paste.rs pastes are immutable, so **every edit to either file needs a fresh
upload and the new id written into this file, `SETUP.md` and the setup artifact
at https://claude.ai/code/artifact/6989784d-6bae-4da6-8158-0dc6464885c5** (update
that same page — a fresh publish makes a second one). **The artifact was
regenerated from `SETUP.md` on 2026-08-28** and now covers phases 1 to 5 and
hands out `3PcMy`. All three surfaces agree.

Superseded ids, which must not be run: `swzlE` (the pre-review build: stops
chasing ore after 64 blocks, says `work complete` on an empty tank), `uKUTW`,
`3A9h2`, `lQszb`, `bO7bo`,
`cpeuw` and `llZlk` (deployed turtles
seeded their own DRY config and never moved), `4zMLm` (start-block anchor), `kgXRL`
(no modem in kit), `4b9IM` (Phase 1, `--check` only), `KRY8F` (probe, crashed on
an unlabelled turtle).

## Code review, 2026-08-28 — all nine fixed, no design change

`reports/code-review-quarry.md` is the full review of `quarry.lua` (9 findings).
**All nine are now fixed** — three in the first pass, the remaining six in a
second pass the same day. Each fix has a regression test (tests 40 to 48) that
was confirmed to FAIL against the unfixed code: every one of the six was
reverted on its own in a scratch copy and the suite re-run, and each time it
failed on that fix's own test with that test's own message.

**None of this touches the design.** They were slips in code that was already
right in principle, and several are mistakes the file had already made and
corrected somewhere else.

- **`veinMax` was capping the whole run, not one chase.** `st.chased` is the
  counter `chase()` tests against `conf.veinMax`, and it was reset only at the
  top of `runMine`. After 64 chased blocks the turtle walked past every ore it
  met for the rest of the shift, printed nothing, and kept mining branches — so
  a run that had stopped doing the one thing the mine exists for still looked
  healthy. Now reset per chase in `mineLeg`; `st.veined` carries the run total
  the report prints. Test 40.
- **A refused `turtle.place` read as a successful deploy.** `deployOne` had
  `local ok, why = pcall(turtle.place)` and then tested `ok` twice, so the real
  result was never read. A turtle that never got placed was handed a modem, 64
  coal and a bucket — onto the ground, in front of nothing. This is the same
  `pcall` mistake `handOver` has a comment about 30 lines above. Test 41.
- **An empty tank mid-route was reported as `work complete`.** `turtle.forward()`
  returns false on 0 fuel exactly as it does against a wall, so a fuel-out inside
  `goTo` (the walk to the depot, most often) left `halt` unset, broke the work
  loop, and `report` took the "work complete" branch over a stranded turtle. One
  guard at the top of `clear()`, which `step`/`stepUp`/`stepDown` all route
  through, so every caller is covered by the one check. `calibrate()` has had the
  same guard since Phase 2 for the same reason. Test 42.

The six fixed in the second pass, in the review's own numbering:

- **WARN-002** — the four-way vein sweep turned relative to `st.dir`, which
  `goTo` had already changed on the walk home, so it re-checked one face and
  missed another. `chase` now captures `d0 = st.dir` with the cell's position
  and sweeps `turnTo(d0 + i)` for `i = 0..3`. Test 43.
- **WARN-003** — the `BOOT` script warned it would seed a DRY config and not
  move, which stopped being true when the defaults went live. It now says a
  missing floppy config seeds one from the defaults, that it **mines**, and that
  the settings are the defaults rather than the deployer's. Text only. Test 48.
- **SUGG-001** — `turtleAhead` compared its and-chain against `nil`, so a failed
  `pcall` came out `false ~= nil` = true and an inspect error read as another
  turtle in the corridor. Explicit `if not ok ... return false` now. Test 44.
- **SUGG-002** — `st.lavaSeen` never emptied and rode every save. `mapMerge`
  clears it alongside `st.lava`. Test 45 holds the invariant: the dedupe never
  holds more keys than the queue it protects. Test 45.
- **SUGG-003** — two more `pcall` results read one value too shallow, in
  `buildDepot` and `checkLava`. A `pcall` that fails puts an error STRING
  second, which is not `false`, so a crashed place counted as a placed
  container. Both now read `lived, put` and test `lived and put ~= false`.
  Test 46.
- **SUGG-004** — `findSharedDepot` probed only upward, so a turtle whose own
  bedrock floor is higher than its neighbour's sailed over the depot and wrote
  `noDepot` down for good. It now probes offsets `{0, 1, 2, 3, -1, -2, -3}` from
  its own level, a `goTo` per offset. Test 47.

`test_quarry.lua` gained two stub switches to make the `pcall`-failure paths
reachable at all: `V.inspectFails` and `V.placeErrors` make those calls throw.
Every ok-only guard in the file reads that case backwards, so they are worth
keeping for the next such finding.

## Files

| File | What it is |
| --- | --- |
| `MASTERMINE-PLAN.md` | The design, every decision and its reasoning. Read second. §11 carries the per-phase notes. |
| `quarry.lua` | **The deliverable.** ~2,400 lines, Phases 1–5. Ships `DRY = true`. |
| `test_quarry.lua` | Five suites against stubbed CC worlds: phase 1 maths, phase 2 movement, phase 3 depot cycle, phase 4 three turtles, phase 5 deployment. Tests 40–42 are the 2026-08-28 review regressions. `lua5.3 test_quarry.lua` |
| `probe.lua` | **The Phase 5 probe.** Answers plan §13's three mechanics in one in-game run, plus the item ids and the `tags` question. `probe` is a dry run, `probe go` is the real one. |
| `test_probe.lua` | Stubbed CC world for `probe.lua`, live path and DRY path. `lua5.3 test_probe.lua` |
| `SETUP.md` | What the user does in-game. §5b is the Phase 2 run, §5c the depot, §5d all three turtles. |
| `reports/check-1-2026-08-24.txt` | The first real `--check` output, verbatim. |
| `reports/code-review-quarry.md` | The 2026-08-28 review. Three findings fixed, six still open. |
| `test_pattern.lua` | Asserts the mod-5 stagger yields `1,3,5,2,4` and covers everything. |
| `test_coverage.lua` | Measures dug% and unseen% for every pattern considered. |
| `tunnel.lua` | The earlier working program. Phase 2 copied its `clear`/`step` shape. |
| `HANDOFF-PROMPT.md` | The prompt to paste into a fresh session. |

## The design in one paragraph

Three turtles work a chunk-snapped 3×3 chunk claim (48×48) with no chunk
loader — the player standing in the centre chunk is what keeps it loaded.
Branches are 1-high, 1-wide, run along x, and are sunk wherever
`z ≡ 2y (mod 5)` **measured from the claim's own corner**; that is the user's
`1,3,5,2,4` sequence and it reads the claim interior exactly for ~22% dug,
which is the proven floor. A spine runs along z at the claim's x-centre with
branch mouths every 5 blocks; branches run 24 west and 23 east. Each turtle has
its own vertical trunk at the centre of its own third. Levels run deepest
first, from one above bedrock up to y=60. The depot is at the claim floor;
turtles never surface except on `recall`.

---

## What Phase 3 added

- **The work loop.** Phase 2 mined one branch and parked. Now: pick the nearest
  unfinished branch in this third, mine both legs, mark it done in the state
  file, take the next one, and move up a level when the current one is
  finished. Stops on `claim  : every branch in this third is mined`.
- **The depot is found, never configured.** On reaching the trunk floor the
  turtle looks at all four sides for a container and takes one item out of each
  to learn which holds fuel. `st.depot = { x, y, z, dump, fuel }` is saved, so
  the probe happens once per claim.
- **Dump, ration, restock.** Everything that is not fuel or a bucket goes into
  the dump chest. Then the fuel chest is sucked out whole, a third is kept
  (never the last three items), it is burnt on the spot, and **everything else
  goes straight back** — including the spoil just dumped, which is what lets a
  single chest do both jobs.
- **The junk tier is the overflow valve.** A full turtle mid-vein drops a
  blacklisted stack on the tunnel floor and keeps digging. Only a hold with no
  junk in it is really stuck.
- **Two dock triggers**: no free slot, or `tripBlocks` blocks carried. Low fuel
  is a third — with a depot known, the reserve check sends it home instead of
  stopping where it stands. `fuelShare` is a fourth; see fuel sharing below.
- **Lava.** Sources the branch passes are recorded and, when the tank is under
  `lavaFloor`, scooped on the spot. `lava = false` shipped off until `--check`
  proved the bucket comes back on this server (issue #530). **It was proved
  in-game 2026-08-27 — the scoop works and the bucket returns — so `lava = true`
  in `quarry.conf` is now correct.**
- **The lava map** at `/disk/lava.txt` on a depot disk drive: merged in while
  docked, pruned when a source is taken. No drive, no map, nothing else
  changes.
- **Foraging** when the depot is dry: nearest mapped lava source in reach,
  otherwise a branch at `topY` where the coal generates — which is work that
  was on the schedule anyway — otherwise stop and say so.

### Fuel sharing, added 2026-08-25 after Phase 3

A coal find belongs to all three turtles, not to whoever dug it.

- **`fuelShare = 128` is a dock trigger.** Coal in the hold above that sends
  the turtle home to bank it, beside the existing full-hold and `tripBlocks`
  triggers. The dock flag is recomputed from the load, so the fuel count is
  part of that recompute too.
- **`burnFrom(l, target)` burns the hold before the tank counts as low.** Both
  places that judge fuel — the reserve check inside a leg and the branch-cost
  gate in the work loop — call it first. A turtle used to stop with "out of
  fuel" while carrying stacks of coal; now it eats the minimum and works on.
- **`restock` already did the sharing half**: it puts back everything it did
  not burn, so the find lands in the chest the others ration from. It now
  counts what it left, and `report` prints `fuel   : N coal banked ...`.
- `isFuelItem`/`isCoalish` moved above the mine so the reserve check can see
  them; `topUp` reuses `isFuelItem` instead of its own loop.

### Four bugs the stubbed world caught before the user did

1. **`BOOL[k]` is false for a false default.** `lava = false` in the config was
   rejected as an unknown setting. The test is `BOOL[k] ~= nil`. Any future
   boolean defaulting to false would have hit the same wall.
2. **Park wiped the resume point.** The end of the run cleared `st.leg` and
   `st.along` unconditionally, including after a stop — exactly the case where
   they are needed. They are now cleared only on a clean finish.
3. **`needDock` was treated as durable state.** A turtle resuming with an empty
   hold went straight back to the depot. It is now recomputed from the hold.
4. **Foraging left the loop mid-pass.** It changes the level and clears the
   branch, and the rest of the pass then walked to a branch that no longer
   existed. The pass restarts (`goto nextpass`).

Also fixed in the harness, not the program: `getItemDetail` returned the live
slot table, so every count read after a drop came back zero. It returns a copy
now, like CC does.

## What Phase 4 added

- **Air-mouth claiming.** On arriving at a fresh branch mouth the turtle looks
  west and east; air either side means the row is somebody's, and it is written
  off in `st.done` and skipped. `mouthTaken()` runs **only on a fresh claim** —
  a turtle resuming its own half-mined branch would otherwise read its own work
  as another turtle's and skip it forever.
- **Right of way by launch index.** `giveWay()` runs before every dig in
  `step()`. A turtle in the way is waited out in `index × 1.5s` bursts, six
  tries: index 1 retries soonest and effectively holds the corridor, 2 and 3
  are the ones that end up moving. Nobody can read another turtle's index —
  there is no protocol and the plan wants none — so the asymmetry comes from
  the launch argument, which is what it is for.
- **Giving way never moves a turtle mid-leg.** `giveWay` only waits. Moving
  aside is `goTo`'s job (`stepAside`), because the route there is recomputed
  from actual coordinates; a sidestep inside `mineLeg` would desync `st.along`.
  A jam inside a leg gives that *branch* up — `st.needDock, st.branch = true,
  nil` — docks, and re-picks. A wasted trip beats a stuck turtle [plan 8].
- **`goTo` travels the spine first.** From a spine block it now moves z before
  x. Moving x first walks a turtle leaving the trunk floor straight into the
  depot chest beside it. This was invisible with one turtle whose depot chest
  happened to sit on its own branch row.
- **One shared depot, found lazily.** Two turtles of three have no chest under
  their own trunk. `findSharedDepot` walks the spine to the other trunks and
  probes up to four blocks up each column (bedrock scatters over four, so the
  trunk floors are rarely the same y). It runs **only when a turtle actually
  needs the depot**, once, and writes down `st.noDepot` when the answer is no —
  sweeping on boot cost ~70 dug blocks every boot on a claim with no chest.
- **`recall`.** `quarry <n> recall` walks the branch back to the trunk, climbs
  the shaft, crosses to the launch block and parks, leaving `st.done` and the
  branch position intact so a plain `quarry <n>` resumes. In DRY it prints the
  route and moves nothing. Ctrl+T first — it is also the only way to reach a
  turtle that is already working.

### What the phase 4 suite covers

Tests 24–27, none of which need a second process: an air mouth pre-cut in the
world, a `computercraft:turtle_normal` block parked in a leg, a chest under
another turtle's trunk, and a recall from a mid-branch state file.

**Two test-world traps worth not rediscovering:** the depot chest at
`spine-1, floor, trunkZ` blocks the west leg at the floor level, so a seam or a
blocker placed on the west leg tests nothing — use the east leg, or another
turtle's row. And a blocker only blocks the turtle whose *third* it is in:
`z = -42` is turtle 2's, `z = -57` is turtle 1's.

## Settled — do not reopen these

Plan section numbers in brackets.

- **Harvest Mastermine, do not port it** [1]. `forge:ores` must become `c:ores`.
- **Claim is chunk-snapped** 3×3; **the pattern anchors to the claim corner and
  absolute y**, never to a turtle's start block and never to a config value [2].
  **The claim itself anchors to `st.home`, the launch block, and is persisted.**
- **Geometry: horizontal 1-high branches along x**, `z ≡ 2y (mod 5)` [3].
- **Spine along z at the x-centre**, branches 24 west and 23 east [3].
- **One trunk per turtle** at the centre of its third [3, 4]. Trunks sit on the
  spine, so they cost **no extra blocks**.
- **Bottom is one level above bedrock**, found by failed dig [3]. `bottomY=-59`
  is the safety stop. **Top is y=60.** Both configurable.
- **Deepest first, working up** [3]. Direction and range configurable.
- **Three turtles on the same level**, z split into thirds [4].
- **Branch claiming: an air mouth is already taken** [4]. Built in Phase 4.
  `st.done` stays as the per-turtle exact record; the mouth test is what stops
  two turtles taking the same row.
- **Depot at the claim floor** [5], **found by looking, not configured**. One
  chest serves all three; a turtle with none under its own trunk walks the
  spine to the others, once.
- **The depot queue is the waiting, not a queue** [5]. Mastermine's linked-list
  route was for a hub with a monitor and any number of turtles. Do not build it.
- **Right of way by launch index** — lower wins, higher moves [8]. Built.
- **`recall` is per-turtle and typed; normal returns are independent** [4].
- **Haul everything; the blacklist is a junk tier**, dumped first on overflow
  [6]. A turtle cannot decline to pick up what it digs.
- **Ore = `c:ores` + config names**; `only` restricts to an exact list [6]. No
  fuzzy `find("ore")` fallback. Ancient debris excluded — nether-only.
- **No `--scan` mode** [6]. The `passed over:` line does that job.
- **Fuel: coal, coal blocks, charcoal, lava buckets only** [7].
- **Depot-first, forage only when dry** [7]. Inventory is the trip trigger.
- **A find is shared, not hoarded** [7]: `fuelShare` coal in the hold is a dock
  trigger, and a low tank burns the hold before it costs a trip.
- **Depot fuel rationed**: at most `available ÷ 3` per visit, never the last
  few [7]. **Learned by taking, because a turtle cannot read a chest it is not
  wired to.** Burn on pickup, carry no fuel items, one bucket.
- **Lava scooping is opt-in** [7]: `lava = false` until `--check` proves it.
  **Proved in-game 2026-08-27. Turn it on in `quarry.conf`.**
- **Lava map shared on a depot disk drive** [7], read and written while docked.
- **Never dig into a full inventory** [8]. `dig` succeeds and destroys the drop.
- **Never dig a turtle, computer, disk drive, chest, or anything `lootr`** [8].
  In a branch leg that ends the leg; anywhere else it stops the run.
- **Config is a self-seeding data file**, `quarry.conf`, plain format, not Lua
  [9]. Nothing in it may affect the branch pattern. **A config file replaces
  the default lists outright** — a file with no `[blacklist]` section has no
  blacklist. That is deliberate; tests must spell out the lists they need.
- **Save state every block** [10]. Measured at 1.35 ms against a 400 ms move.
- **GPS exists on this server**, through an equipped wireless modem.
- **Claim exhaustion: stop, report, idle** [12].
- **Deployment is Phase 5** [13]. The monitor is Phase 6.

## Corrections already made — do not reintroduce

- 1-high tunnels at 3×3 spacing leave **44% unseen**; 2-high layered 4 apart
  leave **33%**. A tunnel sees `z±1` only at its own `y`.
- The vertical-shaft (`canes`) design is superseded but measures identically.
- `turtle.dig` on a full inventory destroys the drop. Issue #1046, closed
  `invalid`.
- Ancient debris is nether-only.
- Turtles are lavaproof and submersible; `detect()` is false for liquid. All
  liquid-sealing logic was deleted.
- **The stagger's 0% unseen is a toroidal figure.** On the real claim it is
  1.16%, all on the claim face. Do not "fix" it.
- **Trunks cost no blocks.** Do not re-add the 360-block line to a cost table.
- **`pcall` prepends its own success flag.** Two locals binds `data` to a
  boolean.
- **A turtle needs a wireless modem for GPS.**
- **CC:Tweaked is Lua 5.2 (Cobalt).** No `//`, no bitwise operators. `goto` is
  fine — 5.2 has it, and the work loop uses several.
- **Never derive the claim from the turtle's current position after boot.**
- **`DRY` is not edited in the program.** `dry = false` in `quarry.conf` is what
  goes live, because the config survives a re-download.
- **Lootr loot is unreachable to a turtle, by both routes.** Do not add a
  `turtle.suck` at a Lootr container, and do not add a config switch to dig
  them: the break is cancelled server-side, and `should_drop_player_loot` is
  false by default, so a break that did land would destroy the loot.
- **"Burn on pickup, carry no fuel items" is about depot coal, not mined coal.**
  Coal dug on a branch rides home to the chest. Do not add a burn-it-where-you-
  find-it rule; that is the hoarding the sharing rule exists to stop.
- **The depot chest stands on a branch row.** The trunk is on the spine, so its
  four neighbours are spine or branch. One leg of one branch is lost at the
  floor level. Do not redesign the geometry for it — but do remember `goTo`
  must leave a spine block along z, or it walks into that chest.
- **`os.getComputerLabel()` returns NO values on an unlabelled computer**, not
  nil. `tostring(os.getComputerLabel())` throws `bad argument #1 to 'tostring'
  (value expected)`. A local or a function parameter collapses a zero-return to
  nil; an argument list does not. `probe.lua` crashed on this at line 142, and
  the copy of it inside the floppy's `startup.lua` would have crashed on the
  placed turtle, which is always unlabelled.
- **A turtle is not a peripheral to another turtle.** Do not write `turnOn`,
  `isOn` or `getID` against a placed turtle. Settled in-game 2026-08-27.
- **Do not sweep the spine for the shared depot on boot.** It costs ~70 dug
  blocks every boot on a claim that has no chest at all. It waits until the
  depot is needed, and `st.noDepot` records a negative answer.
- **`st.chased` is a per-chase counter, not a run total.** Reset it where a
  chase begins, never where a run begins, or `veinMax` silently switches off all
  vein chasing for the rest of the shift. `st.veined` is the run total. Test 40.
- **`pcall` prepends its own flag — including around `turtle.place`.** This one
  has now been got wrong twice, in `checkLava` and in `deployOne`. Capture both
  values and test the second against `false` explicitly. Test 41.
- **An empty tank is not a wall.** `turtle.forward()` returns false either way,
  so any move path with no fuel check reports the wrong thing — and with `halt`
  unset, `report` calls a stranded turtle finished. The guard lives at the top
  of `clear()`, which every stepper routes through; do not move it into one
  caller. Test 42.

## What Phase 5 added, 2026-08-27

**`quarry 1 deploy`.** Turtle 1 audits the kit, and if nothing is missing it
builds the boot rig the probe proved: the disk drive one block up and in front,
each new turtle placed on the ground directly below it. It copies **itself** to
`/disk/quarry`, writes a `/disk/startup.lua` carrying that turtle's index, places
the turtle, hands it a modem, 64 coal and a bucket through a plain
`turtle.drop`, and waits up to 90s for it to walk off before doing the next one.
One drive serves all of them because each leaves before the next is placed.

**Deployment happens at the surface launch block, not at the claim floor** — a
deliberate deviation from plan §13, which assumed turtles would be carried to
their own trunks. The drive has to sit directly above the placed turtle and a
trunk floor has no spare side once two depot chests are down. It costs nothing:
`runMine` anchors its claim wherever it wakes, the launch block is in the centre
chunk, so all three agree on the same claim and each digs its own trunk.

**The boot script waits for its kit rather than racing it.** The placed turtle
boots in about a second and the deployer is still dropping coal into it, so
`startup.lua` polls its own inventory for up to 60s for a modem and coal before
doing anything.

**It equips the modem on whichever side is not the pickaxe.** `equipRight`
swaps, so guessing wrong disarms the turtle. It equips right, looks at what came
off, and if that was a pickaxe it puts it back and uses the left side instead.

**`buildDepot`, the other half of §13.** A turtle that reaches its trunk floor
carrying containers cuts an alcove on up to two sides, places them, and banks
every fuel item it still carries into the first one. That is the fuel chest;
an empty second chest reads as the dump. It runs only when `probeDepot` finds
nothing, so a hand-placed depot still wins.

**`topUp` holds coal back while the depot is still in the hold.** It used to
burn every coal on the way down, which left turtles 2 and 3 at an empty fuel
chest. Coal is now kept for the depot whenever a container is aboard and the
tank is already over 1000.

### What the phase 5 suite covers

Tests 28–33: a complete kit deploys both turtles and hands each one a modem,
coal and a bucket; a short kit places nothing at all; only turtle 1 may deploy;
a turtle that never leaves the spot is reported rather than waited on forever;
DRY deploy touches nothing; and a turtle carrying chests builds and stocks its
own depot while one carrying none behaves exactly as before.
## Phase 2-4 RAN IN-GAME, 2026-08-27 — turtle 2 mined

`reports/mine-live-1-turtle2-2026-08-27.txt` (paste `rpP96`). **This is the
first time any of the mining code has run on the server.** Turtle 2 booted,
equipped its modem, took a GPS fix, calibrated a heading, descended 20 blocks
to `topY`, crossed to its trunk at `x=8 z=7`, sank to `y=-59`, cut a branch and
dug 177 blocks before stopping cleanly.

So the deployment chain works end to end. **The modem equip works** — GPS is
impossible without it and the turtle located itself. Everything under "the
deployed turtle does not boot" is resolved.

It stopped here, correctly:

```
depot  : no container under any trunk floor
STOPPED: inventory is full and there is no depot to empty it into
```

**That message was wrong and the user caught it: six slots were still empty.**
Three things set `st.needDock` — no free slot, `tripBlocks` carried, and
`fuelShare` — and the halt printed the full-hold wording for all three. It had
dug 177 blocks against a `tripBlocks` of 96, so the block count was the real
trigger. Fixed: the halt now names which one fired, with the numbers. Tests at
`test_quarry.lua` lines ~699 and ~811 were asserting the wrong wording and now
assert the right one; test 39 covers the tripBlocks case directly.

**The remaining blocker is a depot.** There is no container under any trunk
floor. Either place a chest against the bottom block of a trunk with coal in
it, or run `quarry 1` — turtle 1 carries the chests and builds the depot
itself when it reaches its own trunk floor.

## Next action

**Give it a depot.** That is the one thing standing between here and a working
mine. Two ways:

1. **Run `quarry 1`.** Turtle 1 carries the two chests and builds the depot
   itself when it reaches its own trunk floor, banking its coal into the first.
   This is the intended path and it exercises Phase 5's depot-building.
2. **Place a chest by hand** against the bottom block of a trunk, with coal in
   it. A second container on another side becomes the dump chest.

Then re-run turtle 2 and watch it dock: that is the depot cycle — dump, ration,
restock — which has never had a container to run against.

After that, the untested ground is **two turtles working at once** (the
right-of-way rules in `giveWay`/`stepAside`), and the **`passed over:` line**
from a run that finds ore, which is how the config learns this pack's ore ids.

## Settled in-game, 2026-08-27

### From the probe (two runs, `KjiTU` and `nztF6`)

- **A placed turtle boots on its own** and runs `/disk/startup.lua` unprompted,
  about 23s from placement. **This is now doubtful** — see the deploy runs
  below, where four placements produced a turtle with no label. Its
  `result.txt` is still on the floppy, so it did happen once.
- **Facing does not matter.** `calibrate()` derives a heading by moving one
  block and diffing GPS, so a deployed turtle orients itself.
- **`inspect` returns a `tags` table on this server** (`tags=yes`), so
  `c:ores` works and quarry prints no `WARNING:`.
- **This pack's real ids**: `computercraft:turtle_advanced`,
  `computercraft:disk_drive`, `computercraft:disk`,
  `computercraft:wireless_modem_advanced`. All four already match the kit
  audit's patterns; nothing is hard-coded and nothing needs to be.
- **The turtles are advanced *and* mining.** Both share the id
  `computercraft:turtle_advanced`, so no audit can tell them apart. Do not add
  a check for it.
- **A placed turtle inherits nothing**: fuel 0, no label, no modem, empty
  inventory. Everything is handed over after placement.
- **A turtle is NOT a peripheral to another turtle** — `peripheral.wrap`
  returned nil. **This was wrong, and it cost three runs.** See the #660 entry
  below. The probe looked from a position it had already moved away from.

### Lava works

The user ran the `--check` scoop test with an empty bucket and confirmed the
bucket comes back. **Issue #530 does not apply on this server.** `lava = true`
is now the shipped default.

### The four live deploy runs

Logs are in `reports/deploy-live-1..4-2026-08-27.txt`. Each fixed something
real and none of them got a turtle to leave:

1. **`4ED14`** — kit complete, rig built, all handovers reported, turtle 2 never
   moved. **Cause: the deployed turtle seeded its own `quarry.conf`**, which
   shipped `dry = true`, so it planned a route and stood still. The floppy
   carried the program but not the config. Fixed: `deploy` copies `quarry.conf`
   to `/disk/quarry.conf` and `BOOT` installs it.
2. **`17N9H`** — config now on the floppy and confirmed `dry = false`. Still no
   movement, and turtle 2 had **no label and an empty root**, so `BOOT` never
   ran at all. `/disk/deploy2.log` never appeared either.
3. **`4AwFr`** — printed `turtle 2 is not visible as a peripheral`.
   `peripheral.getType("front")` returned nil with a turtle standing in front.
4. **`inrHz`** — **the #660 fix worked**: `peripheral on front = turtle`,
   `turnOn sent to turtle 2`. Still did not leave in 90s.

### CC-Tweaked issue #660: peripheral discovery goes stale

From the issue: *"Causing any kind of update will make turtle see peripheral
again. Turning turtle / removing or adding disk to disk drive ect."* The block
in front was air a moment before `turtle.place`, so `getType` honestly reported
nothing. `deploy` now retries up to six times with a `turnRight`+`turnLeft`
between attempts — a no-op for the heading in `st.dir`. **That pair is what the
user saw as "spins left or right sometimes"; it is turtle 1, and it is
cosmetic.**

Two wiki facts that came out of this, both worth keeping:

- **On a turtle, `left` and `right` report the EQUIPPED upgrade, not the
  adjacent block** (tweaked.cc/module/turtle.html). A turtle checks the
  equipped upgrade on a side first and falls back to the adjacent block, so
  `front` is a valid way to see a placed turtle.
- **The `### left [turtle]` entries in the peripheral dump are physical
  sides**, and that dump's header says `turtle=false` — it was taken from a
  computer, so it never described what a turtle sees. `peripherals.md` gives
  that caveat. It was misread once in this session.

### The spin: an empty tank read as a wall

`calibrate` finds its heading by moving one block. **`turtle.forward()` returns
false on an empty tank exactly as it does against a wall**, with no error
either way, so a fuelless turtle turned a full circle and then reported
`boxed in on all four sides`. Fixed: `calibrate` checks `fuelLevel()` first and
says `out of fuel` by name, and `BOOT` refuses to hand a fuel-0 turtle to
quarry at all.

### Still unexplained

The user reports the modem is not equipped. `BOOT` no longer trusts the equip
swap — it asks `peripheral.getType` which side actually holds a modem, reports
it, and stops with both sides listed if neither does. **`/disk/deploy2.log` is
where that answer will be.**

## The defaults changed, 2026-08-27 — at the user's instruction

`quarry.conf` now ships **`dry = false`** and **`lava = true`**.

This overrides the long-standing convention that the program is never handed
over ready to mine. `local DRY = true` still opens the file, and the config
lowers it as it always did — the change is only to what the seeded config says.
It matters more than it looks: **`deploy` copies that same file to every
turtle**, so the old `dry = true` default is what stranded turtle 2 on the first
live run. Test 38 asserts both values so a later edit cannot revert them
quietly.

Tests that wanted a dry run now write `dry = true` into the stub config
explicitly rather than falling back to it.

## Before the next deploy run

- **Download the current build: `3PcMy`.** Uploaded 2026-08-28 with all nine
  review findings fixed, fetched back and diffed against disk. `delete quarry`
  first, then `wget https://paste.rs/3PcMy quarry` — two lines, because `wget`
  will not overwrite. This file and `SETUP.md` carry the new id; **the setup
  artifact does not** and still hands out `4b9IM`.
- **Break turtle 2 and pick it up.** It is standing in the deployment spot with
  a seeded DRY config, and `deploy` needs that block clear.
- **Check the modem count afterwards.** A broken turtle may come back with the
  modem still attached as an upgrade rather than as a loose item, in which case
  the kit audit will read 2 modems and say `SHORT 1`. Believe the audit.
- **Confirm `dry = false` is in turtle 1's `quarry.conf`**, not only that it was
  set for the last run. That one file is now what all three turtles inherit.

## Waiting on the user, whenever they want to run it

- **The `passed over:` line from a real run** — this pack's real ore ids.
- **192 coal or charcoal**, a stack per turtle. The only thing `deploy` is
  short of.
- **A real `deploy` run.** Everything under it is tested only against the stub.

## Blocks the user must place before a run

- **A chest or barrel against the bottom block of a trunk.** That is the depot;
  the turtles find it, and one chest serves all three. Coal in it. A second
  container on another side becomes the dump chest and keeps the spoil out of
  the fuel. **Since Phase 5 this is optional**: a turtle that reaches its trunk
  floor still carrying chests cuts the alcoves, places them, and banks its own
  coal into the first. A hand-placed depot still takes priority.
- **Optional: a disk drive with a floppy** beside the trunk floor — the shared
  lava map, and the only channel by which one turtle can hand code to another.
- **Do not hand-dig down.** Each turtle cuts its own trunk and that shaft is
  the way in.
- **Launch all three within a few blocks of each other**, ideally the same
  chunk. The claim comes from the launch block, so turtles launched far apart
  get different claims and mine different regions.

## Conventions that govern the code

One self-contained file, no `require`, delivered as a single `wget` from
paste.rs. Opens `local DRY = true` and is never handed over with it false;
`quarry.conf` may lower it and may never raise it. Persist state every
meaningful step. `pcall` every peripheral call — and remember it prepends its
own success flag. Test under `lua5.3` before delivering; `test_quarry.lua` is
the stubbed world to extend, not replace. Diagnostics go *in* the program so
one in-game run answers the question instead of three. Print a liveness line
before any long work. CC:Tweaked is Lua 5.2. The peripheral dump in
`~/.claude/skills/cc-tweaked-pack/references/` outranks the wiki; if a method
is not in it, ask for a re-survey rather than guessing. **Mod behaviour is read
out of the mod's own jar and config when they are on disk** (`unzip`, `javap
-c`, `config/*.toml`) — that is how the Lootr answer was settled.

## Open questions

None on the design, and none blocking. Every mechanic Phase 5 was waiting on is
settled. What is left is verification: Phases 2 to 5 have never run in-game.

---

# Moved out of RESUME.md on 2026-08-28, last

RESUME.md carried four dated "what shipped" logs for a single day, plus the
narrative of a GPS outage that was over and a `--check` audit that had been
acted on. They are kept here whole and unedited; RESUME.md now carries one
summary of the day and the state that came out of it.

## What shipped 2026-08-28 evening

All tested under `lua5.3`, every regression confirmed to fail against its own
unfixed code. `test_quarry.lua` was 55 checks at that point and is 57 now.

- **The fuel ration is a floor, not a fraction.** See the Settled list. New
  `fuelFloor` setting, default 8, seeded into `quarry.conf`. Tests 51, 52.
- **The `--check` tank line asks the turtle for its limit.** It printed
  `this turtle holds 51183 of 20000` in-game, because 20,000 was a literal in
  two places; an advanced turtle holds far more. Falls back to 20,000 if
  `getFuelLimit` is absent. Tests 49, 50.
- **`calibrate` refuses a pinned position instead of crashing on it.** Turtle 1
  died with `calibration moved 0,0, which is not one block` because
  `startX/Y/Z` in `quarry.conf` make `locate()` return a constant, so the
  reading after the calibration move equals the reading before it. The message
  named the symptom and hid the cause. Test 53.
- **`startDir` lets a turtle run with GPS down.** 0, 1, 2, 3 = facing +z, -x,
  -z, +x, validated on read. Only the initial heading actually needed GPS --
  `locate()` is called at boot, resume and deploy and nowhere else, and
  everything between dead-reckons -- so a stated heading is enough to mine on.
  What it costs is recovery: a turtle that loses `quarry.state` cannot find
  itself again. Tests 54, 55.

## What shipped 2026-08-28 night

Both from run `45bPE`, both confirmed to fail against the build that produced
that log.

- **The depot goes under the trunk floor.** `probeDepot` looks down before it
  looks around, `buildDepot` digs out the block below and places one container
  there, and `"down"` is a direction everywhere `st.depot` is read —
  `faceDepot`, `depotDrop`, `depotSuck`. A container beside the floor is still
  found and used, because someone may have placed one; it is just never built
  there any more. Test 33 rewritten, test 57 new.
- **The deployment kit stays in the hold.** `isKit` covers turtle, computer,
  disk, modem, chest, barrel, shulker and bucket; `dumpLoad` and `restock` both
  skip it. Test 56.
- The report line is now `depot  : container at the trunk floor x,y,z
  (dump down, fuel down)` — `%s`, not `%d`, because the side can be `"down"`.
- **A NO FIX crash names its own cause.** `noFix()` reports the equipped sides
  and picks one answer: no modem equipped, or a modem with no host answering.
  The old line listed both at once, which is why `URkmo` could not be read.
  `gps.locate`'s timeout went 2s → 5s. Test 58.
- **`quarry.state` is a position source when GPS is silent.** Log `td7FE`:
  turtle 1 at the depot, `left=modem`, no host answering in 5s. A wireless
  modem's range shrinks with depth and the constellation is a hundred-odd
  blocks above the claim floor, so **GPS answering at the surface says nothing
  at y=-59** — and a turtle that cannot get a fix at the floor can never resume
  its own job. `locate` now falls back to the saved position, which comes with
  the saved heading, so `calibrate` has nothing to measure and nothing to be
  told. It is announced every time, in `--check` and in the run, because a
  turtle someone picked up and moved cannot know it. A state file with no
  `dir` in it is not a fix. Test 59, three cases.
- **A wired modem is a third cause of NO FIX, and it looked like the second.**
  `peripheral.getType` answers `"modem"` for wired and wireless alike;
  `gps.locate` does not take that on trust — it walks the sides asking
  `isWireless()` and skips anything that fails. So a wired modem equips
  cleanly, reads as a modem in every report the program printed, and never
  yields a fix, which is indistinguishable from a dead constellation unless
  something asks. `equippedSides` now reports `wireless modem` / `wired modem`,
  and `hasModem` means wireless. Test 60.
- **The run captures `gps.locate`'s own debug output.** Its second argument is a
  debug flag; with it on the api prints which sides it tried, how many hosts
  answered and whether they agreed — to the terminal, which an uploaded log
  never sees. `gpsDebug()` borrows `print` for the call, so a NO FIX now uploads
  `gps    : Received 0 responses.` instead of one bare `CRASHED` line. Three
  sessions were spent theorising about a fix the api was willing to explain.

## What shipped 2026-08-28 late night

Both from run `Rpv9m`, both confirmed to fail against the build that produced
that log. `test_quarry.lua` is 62 checks now, tests 62 and 63.

- **Bedrock under the trunk floor no longer costs the run its depot.** The
  depot still goes under the floor first — that is the one neighbour nothing
  ever mines — but bedrock scatters up through y=-60 and the floor stands at
  y=-59, so on most trunks the block below simply will not open. `Rpv9m` said
  `the floor under the trunk will not open — no depot built` and then had
  nowhere to put anything for the rest of the run. `buildDepot` now falls back
  to a niche **beside the trunk, one level up**, on an x side: ±z is the spine
  at every level, and the east-west legs only cross the trunk's own z on the
  levels `isBranch` names — and a row never repeats on the next level up, since
  it shifts 2 in z per level mod 5, so a free level is at most two up. It sets
  `st.depot` itself, because `probeDepot` looks from the floor and would never
  see it. Test 62.
- **Spare coal is not a reason to stop when there is nowhere to bank it.**
  `Rpv9m` ended `STOPPED: carrying 192 fuel and fuelShare is 128, which the
  other turtles could burn` — on a full tank, with a nearly empty hold, 4520
  fuel left and no depot in the claim. `fuelShare` means *the other two could
  use some of this*, which needs a depot to put it in; without one it is just
  fuel this turtle burns itself. `mineLeg` now flags the dock on spare coal only
  when `st.depot` is set, the resume guard matches, and the halt reason is gone.
  A full hold and a `tripBlocks` load still stop the run: with nowhere to empty
  out, mining on only destroys the drops. Test 63.
- **A dock flag whose reason has passed is cleared, not halted on.** Burning a
  stack for the next branch empties the slot it came from, so a hold that was
  full when the leg ended has room again by the time the loop looks. That used
  to fall through to `STOPPED: a depot run was queued`, which named nothing.
- `findSharedDepot` reported the depot sides with `%d`, which throws on the
  `"down"` side the previous night's change introduced. Now `%s`.
- The found-depot line is `depot  : container at x,y,z`, not `at the trunk
  floor`: it may now be a level above it.

## What shipped 2026-08-28, last

Both at the user's instruction. `test_quarry.lua` is 66 tests now; 65 and 66
were both confirmed to fail against the build before them.

- **`quarry 1` deploys the rest of the turtles by itself.** A turtle item in
  turtle 1's hold means the mine is not staffed, so `runMine` runs the whole of
  `runDeploy` at the launch block before it descends — the drive, the floppy,
  the boot script and turtles 2..N, one at a time through the same spot.
  Deployment used to be a mode you had to know about, and turtle 1 run without
  it mined a third of the claim with the other two turtles in its inventory.
  Recorded in `quarry.state` as `deployed` **before** it runs, so a deploy that
  dies half way is not retried on every reboot; `quarry 1 deploy` still forces
  one. A deploy that cannot happen — no drive aboard, a short kit — says so and
  the turtle mines alone rather than stopping. Test 65.
- **A full depot loses the junk, not the run.** `dumpLoad` used to hand back
  `the depot chest is full`, which `dock` turned into a halt. What fills a depot
  is the junk tier, so a drop the depot refuses now puts that stack on the
  tunnel floor instead and the run carries on. Ore is still worth stopping for:
  with the junk gone and the hold still full, mining on would only destroy the
  drops. Test 66.
- **The turtle tells someone.** `notify()` puts the line in the log — so the
  uploaded paste carries it — and broadcasts it over rednet on the `quarry`
  protocol through the equipped wireless modem, once per kind per run. A full
  depot is the only thing that sends one so far.
- **`alert.lua` is the other end of that**, a new program for a computer:
  it finds a modem, prefers a wireless one, and prints what arrives.
  `update` now carries three files — `quarry`, `update`, `alert`.
  **Range is the catch**, and it is the same physics that keeps GPS off the
  claim floor: a wireless modem's reach shrinks with depth. Put the computer
  near the mine, or use an ender modem.
- **Test worlds now cap `topY`.** A run that no longer stops on a full depot
  mines its whole third, which took the suite from 10s to 68s. Ten of the
  worlds cap the levels instead; the ones that assert the trunk shape or the
  forage target still use the real ceiling.

## Storage is one word list now, not four

Added 2026-08-28 late night at the user's request, for Sophisticated Storage.

`STORAGE = { "chest", "barrel", "shulker", "crate", "item_vault" }`, matched as
a **substring of the block id**, and it answers four questions that used to
carry four copies of the words: what can be a depot (`isContainer`), what is
never dug (`protected`), what stays in the hold rather than being dumped as
spoil (`isKit`), and what the kit audit counts.

- **Sophisticated Storage already worked** — `sophisticatedstorage:barrel`,
  `:iron_barrel`, `:limited_barrel_1`, `:chest` and the rest all contain
  `barrel` or `chest`. So do Iron Chests, Expanded Storage and Quark. What was
  genuinely missing was Create's `item_vault`, and `crate`.
- **Drawers and bins are deliberately NOT on the list.** A Storage Drawer, a
  Functional Storage drawer and a Mekanism bin each lock to one item type, so a
  mixed dump into one fails on the second stack and the run halts with `the
  depot chest is full`. They are storage; they are not depots.
- **The kit audit wants ONE storage block, not two.** `buildDepot` has placed
  exactly one since the depot moved under the floor — fuel and spoil share it,
  which is the case the ration was already written for — but the audit still
  asked for two and reported a shortfall for a correctly equipped turtle.
  Label is now `storage block`.
- Test 64, confirmed to fail against the three-word list.

**Prefer a Sophisticated Storage barrel for the depot.** A full depot halts the
run with `the depot chest is full`, and one box now serves all three turtles.

## GPS was down on 2026-08-28 evening and is up again

The user fixed the constellation that night. Run `45bPE` opened with
`quarry 1  at 243,73,734` and mined a claim anchored there, so `gps.locate` is
answering and `startX/Y/Z` are out of `quarry.conf`. What follows is kept
because the constellation has now failed once and may again.


`gps.locate` returns nil on turtle 1 with a modem equipped, so **no GPS host is
answering**. It answered that morning, so something changed: hosts stopped,
their chunks unloaded, the server restarted, or they are out of range. A GPS
constellation wants four or more computers with wireless modems running
`gps host <x> <y> <z>` at their true coordinates, in loaded chunks, in range.

Two ways forward, and they are not equivalent:

1. **Fix the constellation, delete `startX/Y/Z` from `quarry.conf`.** The right
   answer. Position stays self-correcting, and a turtle that loses its state
   file can still find itself.
2. **Keep the pinned position and add `startDir`.** Mines fine -- everything
   past the first fix dead-reckons -- but recovery is gone: a turtle that loses
   `quarry.state` has no way back, and every missed move is a permanent offset.
   Treat it as the way to get mining tonight, not the way to leave it.

The live `quarry.conf` on turtle 1 as of 2026-08-28 evening sets
`startX = 10`, `startY = 80`, `startZ = 5` and **no `startDir`**, so a run
refuses to start until one of the two above is done.

## Still outstanding from the 2026-08-28 `--check` (`u8p0M`)

- `wireless modem 2 of 3 SHORT 1` — the known case: turtle 2's modem came back
  as an attached upgrade, not a loose item. Believe the audit; a turtle with no
  modem cannot GPS, so it cannot resume.
- `empty bucket 2 of 3 SHORT 1`, `coal or charcoal 128 of 192 SHORT 64`.
- `disk drive 57 of 1` is the user carrying a stack, not an audit bug.
- **Whatever position the turtle ends up using must match real F3
  coordinates**, whether it comes from a hand-configured GPS constellation or
  from `startX/Y/Z`. The pattern anchors to absolute y and levels run
  y -59..60, so a wrong origin mines a correct claim in the wrong place.
  Bedrock still stops the trunk safely; the mine would just be somewhere else.
  Nobody has checked this yet.

After that the untested ground is **two turtles working at once** (the
right-of-way rules in `giveWay`/`stepAside`), and the **`passed over:` line**
from a run that finds ore, which is how the config learns this pack's ore ids.

---

# Also moved out of RESUME.md on 2026-08-28

At the user's instruction: RESUME.md keeps only what a session needs in order
to write code. What the player places before a run, and what the mine is
waiting on them for, are `SETUP.md`'s job and are kept here.

## Blocks the user must place before a run

- **A barrel UNDER the bottom block of a trunk.** That is the depot; the
  turtles find it by looking down, and one container serves all three. Coal in
  it. **Not beside the floor** — every side of it is a working row, and a
  container there stops the run. A barrel rather than a chest because the
  turtle stands on this one and a chest with a block above it will not open by
  hand. **Since Phase 5 this is optional**: a turtle that reaches its trunk
  floor still carrying a container digs the block out from under itself, places
  it and banks its own coal into it. A hand-placed depot still takes priority.
- **Optional: a disk drive with a floppy** beside the trunk floor — the shared
  lava map, and the only channel by which one turtle can hand code to another.
  A drive on a side does eventually get mined out, which costs the map and
  nothing else.
- **Do not hand-dig down.** Each turtle cuts its own trunk and that shaft is
  the way in.
- **Launch all three within a few blocks of each other**, ideally the same
  chunk. The claim comes from the launch block, so turtles launched far apart
  get different claims and mine different regions.

## Waiting on the user

- **The `passed over:` line from a real run** — this pack's real ore ids, which
  is how `[oreNames]` in `quarry.conf` learns what Create and Mekanism call
  things here.
- **192 coal or charcoal**, a stack per turtle. The only thing the kit audit
  was ever short of, along with a third wireless modem.
- **Turtle 2 out of the deployment spot.** It was left standing there with a
  seeded DRY config, and `deploy` needs that block clear. A broken turtle can
  come back with its modem attached as an upgrade rather than as a loose item,
  in which case the audit reads two modems and says `SHORT 1`. Believe the
  audit: a turtle with no modem cannot GPS, so it cannot resume.
- The two chests turtle 1 built at 248,-59,711 have been broken and their
  contents recovered — that blocker is cleared.

---

# Superseded paste.rs build ids, removed from RESUME.md on 2026-08-28

Delivery is GitHub now, so these are of historical interest only. They must not
be run if anyone digs one out: `swzlE` (pre-review: stops chasing ore after 64
blocks, says `work complete` on an empty tank), `4b9IM` (Phase 1, `--check`
only), `4zMLm`, `kgXRL`, `uKUTW`, `3A9h2`, `lQszb`, `bO7bo`, `cpeuw`, `llZlk`,
and `KRY8F` for the probe. `3PcMy` is the last paste.rs quarry and `4uJB7` the
last probe; old pastes stay fetchable, so those builds can still be read.


---

# ARCHIVED RESUME snapshot (moved out 2026-08-31)

The deploy/boot/fuel/harvest/claim-size saga, items 1-60 and the dated
"What shipped" narratives, lived in RESUME.md until 2026-08-31, when boot,
placing and mining were all confirmed working in-game and RESUME was cut down
to what writes code. Kept here whole and unedited.

# Resume here

Handoff for the turtle mining build in this directory. If a session ends
mid-task — budget exhausted, crash, context lost — a fresh session reads this
file, then `MASTERMINE-PLAN.md`, and continues without re-deriving anything.

**Rule: this file is rewritten whole at the end of every phase, before anything
else.** Nothing important lives only in chat. Never patch it with a blind
search-and-replace — a patch whose search string does not match fails silently,
which has already happened once and left this file describing an abandoned
design. An asserted replace is fine; a hopeful one is not.

**Everything this file has ever dropped is in `reports/history-2026-08.md`,**
whole and unedited: the phase narratives, the code review, the four failed
deploy runs, the probe results, and — moved there on 2026-08-28 — the four
dated shipping logs of that day, the GPS outage that is over, and the `--check`
audit that has been acted on. **This file carries only what a session needs in order to write code**: the
state, the settled design, the corrections, the conventions and the next run to
ask for. What the player places, presses and downloads is `SETUP.md`'s job. Go
to the history for the reasoning behind anything stated flatly here, or when
something settled starts misbehaving again.

---

## Where the work stands

Last rewritten **2026-08-29**, after the claim-size build (changes 56–58) was
merged down from the `deepseek` branch. The mine is not blocked on anything:
`update`, then `quarry 1` from the surface.

**Branches: `main` is the original and the only one that ships.** `deepseek`
was a side branch and is merged; `update.lua` pulls from `/main/` and nothing
else ever should.

| Phase | State |
| --- | --- |
| 1 — claim maths, iterators, `--check`, kit audit | **Done. Ran in-game 2026-08-24.** |
| 2 — one turtle, one branch | **Done. Ran in-game 2026-08-27** (turtle 2, 177 blocks). |
| 3 — depot cycle, fuel, the work loop | **Partly run.** Travel, fuel, the work loop, building the depot, docking and dumping all ran in-game 2026-08-28. Rationing handed out coal for the first time on 2026-08-29 (logs `E5wWw`, `hkgWh`) and then stopped both turtles for fuel; changes 35–47 are the fix and have not run in-game. |
| 4 — three turtles | **Partly run.** Turtle 2 worked its own third correctly. Two turtles have never run at once. |
| 5 — deployment | **Done. Ran in-game 2026-08-27** after four failed attempts; turtle 2 deployed, booted and mined. A plain `quarry 1` now deploys the others itself; that part has not run in-game. |
| 6 — deferred (monitor, full-clear mode) | Not started. |

**What is unproven in-game: changes 35–58, two turtles at once, and the two
changes from the build before those** — the automatic deployment and the
full-depot behaviour. That is the fuel build, the harvest build and the
claim-size build, none of which has run.

The last log out of the game is `Rpv9m`. It got a fix, crossed to its trunk,
descended to y=-59, and could not build a depot at all: **the block under the
trunk floor was bedrock.** With no depot anywhere it mined 39 blocks and
stopped, over coal it could have burnt itself. Both are fixed. The run before
it, `45bPE`, mined 251 blocks and stopped on its own depot — two chests it had
placed beside the trunk floor, which the pattern later walked into and refused
to dig. That is why the depot goes under the floor, and why the fallback niche
is a level up rather than beside it.

## What shipped on 2026-08-28, after the deploy that left turtle 2 standing

Nine changes, written as `DEPLOY-PLAN.md` first and then built. The user's
report: turtle 2 never moved, the program was only on `/disk`, no modem got
equipped, turtle 2 later dug a tunnel of its own, both turtles ended up on the
depot saying "stopped". Every one of the nine has a regression test confirmed
to fail against its own unfixed code (tests 75-83, plus 29).

1. **Deploy asks for the right-click.** Twelve seconds of silence on the floppy
   means the boot script never ran, which means the turtle is still off.
   `enter` = done, `s` = skip this one, `q` = stop deploying.
2. **Every question answers itself after 60s** through `ask()`, racing `read()`
   against a timer in `parallel.waitForAny`, and says nobody answered. A turtle
   rebooted by `/startup` with nobody watching must not hang on a prompt.
3. **A no-fix run asks for the four numbers** and writes them into
   `quarry.conf`. Empty answer or nobody there = the old refusal.
4. **A pinned position needs no modem.** `manualFix(conf)` is all four of
   `startX/Y/Z` and `startDir`; under it the kit audit wants none, the handover
   is best-effort, and the boot script neither waits for one nor stops without
   one.
5. **`locate()` prefers `quarry.state` to the pin.** The pin is the launch
   block; a running turtle is not standing on it, and with GPS unavailable
   nothing else would ever catch that. Superseded in part by item 20: GPS is
   now tried above both.
6. **The deployed turtles inherit the deployer's claim anchor**, seeded as a
   `home`-only `quarry.state` on the floppy. They wake one block in front of
   turtle 1, which is over a chunk border often enough to matter -- that is
   what "turtle 2 started a new tunnel" was.
7. **`st.halt` outlives the run** and `--check` prints it as `last   :`.
8. **The kit audit follows `conf.turtles`** rather than a hard-coded three, and
   `turtles = 1` refuses to deploy instead of failing its own audit.
9. **A failed deploy asks** rather than mining alone on its own, and the boot
   script writes `quarry.lua`, the name `update` and turtle 1 both use.

Unproven in-game: all of it.

## What shipped next, from logs 0JCwD and nznpx (2026-08-28)

The run above got as far as the audit and then refused both turtles with
`something is in front of me; move me somewhere clear`, deploying neither. The
block in front was the stranded turtle 2 of the run before, still standing in
the one spot a deploy places into. Four more changes, tests 84-87, each
confirmed to fail against its own unfixed code:

10. **A turtle already standing in front is adopted, not refused.** It is not
    an obstruction, it *is* that turtle, already placed: skip the placing and
    go straight to switching it on and feeding it. Without this a deploy that
    strands a turtle can never be re-run at all.
11. **Anything else in front is a question**, not a silent failure: `d` digs it
    out, enter says the player has cleared it, `s` skips, `q` stops. Nobody at
    the keyboard is still the old refusal.
12. **The drive and floppy the last deploy left standing are reused.** The end
    of a deploy tells the player they stay put, so every deploy after the first
    used to die on `something is in front of me one block up`.
13. **A heading typed as `+z` is read as a heading** — `+z`/`south`, `-x`/
    `west`, `-z`/`north`, `+x`/`east`, or the raw `0..3`. And an answer that
    cannot be read costs only that answer: it asks the same question again
    instead of discarding the three good coordinates with it. In-game [nznpx]
    the player typed `+z` and got `no coordinates given, so I have taken none
    of them`.

14. **Started off the floppy, it installs itself onto the turtle and re-runs
    from there.** `cd disk` then `quarry` is what a player types on a deployed
    turtle that did not boot [user, 2026-08-28], and every path quarry writes
    is relative -- so that run puts `quarry.conf`, `quarry.state` and
    `/startup` on the floppy the turtle then walks away from -- and the
    program itself stays on the floppy, so nothing can restart it. Test 88.
    Corrected the same day: `fs` resolves a relative path from the root, so the
    copies were always landing on the turtle. `shell.run` does not -- it
    resolves against the shell's directory, `/disk` on this route -- so the
    handover has to name `/quarry.lua`, which is why turtle 2 printed the
    install line and then did nothing.

15. **A turtle above or below is waited for, not halted on.** `giveWay` was
    only wired into horizontal moves; a vertical one went straight to `clear()`,
    which saw a block on the deny list and ended the run. All three turtles
    share one launch block and one depot column, so that is what "turtles
    stacked on the depot and both say stopped" was, both times. Test 89.
16. **The deployer's `quarry.conf` is a seed, not a master.** The boot script
    re-copied it on every boot, so coordinates typed in by hand were wiped by
    the next reboot and asked for again -- forever, while the turtle stood
    beside the drive. Test 90.
17. **A confirmation waits 10s, not 60.** The two prompts that need the player
    to go and do something -- right-click a turtle, clear a blocked spot --
    pass their own 60s. Test 91.

18. **A turtle this run stranded is not adopted as the next one.** `deployOne`
    adopts a turtle standing in front, which is right for one a PREVIOUS run
    left there -- and wrong inside the deploy loop. Turtle 2 was placed, never
    booted, and the next pass round the loop saw a turtle in front and adopted
    it as turtle 3: a second modem, a second bucket and a second 64 coal into
    the same turtle, the floppy's boot script rewritten to `quarry 3` so the
    player's eventual right-click would wake it as the wrong turtle, and turtle
    3 still sitting in the hold. In-game the player found both buckets and both
    modems on turtle 2 [2026-08-29]. A failed `deployOne` that leaves a turtle
    standing in the placement spot now stops the loop and says the spot has to
    be cleared first. `s = skip this turtle` stops there too -- skipping does
    not move the turtle out of the way. A non-turtle obstruction that is
    skipped still moves on, because nothing was stranded. Test 92, and test
    76's skip case rewritten; both confirmed to fail against the unfixed code.

19. **A re-run of the deploy resumes; it does not start over at turtle 2.**
    `runDeploy` looped `for n = 2, conf.turtles` every time, with no record of
    who was already out. So every retry re-did turtle 2 -- and once turtle 2
    had walked off, the next turtle ITEM in the hold was placed and labelled
    `quarry 2` as well: two turtles on one third, and turtle 3's third never
    worked at all. That is the "restarting every time" the user reported
    [2026-08-29]. Each index that goes out is now written to `quarry.state` as
    `st.staffed[n]` and skipped on a later run, counted in the `N of M` line so
    the total stays honest. **The field is `staffed`, not `deployed`** --
    `deployed` was the abandoned one-shot boolean and older state files still
    carry it as `true`, which an index into would throw on. Test 93, confirmed
    to fail against the unfixed code.

20. **Position fix order is GPS, then `quarry.state`, then the config pin,
    then the questions** -- on the user's instruction 2026-08-29. `locate()`
    used to check the pin FIRST and never call `gps.locate` at all when one was
    set, so a turtle somebody had picked up and moved kept insisting it was on
    its launch block with a live constellation overhead saying otherwise. GPS
    goes first because it is the only thing here that actually LOOKS; the pin
    and the state file are both records of where the turtle was put. GPS is
    skipped only where it cannot work -- `hasModem()` is false, so no fix is
    possible -- which is why a pinned turtle with no modem pays nothing for the
    new order. `st.x/y/z/dir` still beats the pin [item 5, unchanged]. Test 94,
    confirmed to fail against the unfixed code; tests 53 and 54 now turn GPS
    off explicitly, because that is the only way the pin is reached.

21. **The equipped upgrades are read by name, and a modem in a slot is fitted
    to a side.** On the user's instruction 2026-08-29. Three parts:
    - **`turtle.getEquippedLeft/Right` name the upgrade**, which
      `peripheral.getType` cannot: a pickaxe is not a peripheral, so under
      `getType` an armed side and an EMPTY side both read as nil. That is why
      the boot script had to equip blind and undo it when the pickaxe fell out.
      **The method is not in `references/peripherals.md` -- that dump was taken
      from a COMPUTER, which has no turtle API at all** -- so it is called
      through `pcall` and the `getType` route stays as the fallback, which is
      also what an older CC:Tweaked gets. Both return shapes are read, a table
      with `.name` and a bare string.
    - **`ensureModem()` equips a modem that is aboard but not on a side.** A
      modem in a slot is not a modem on a side and only a side answers
      `gps.locate`, so a turtle carrying one was falling through to dead
      reckoning with everything it needed for a real fix. `locate()` now asks
      `hasModem() or ensureModem()`, so the question is whether a fix is
      POSSIBLE, not whether somebody remembered to equip it.
    - **The selected slot is read back before anything is equipped.** `equip`
      SWAPS the selected slot with that side's upgrade, so equipping off the
      wrong slot puts the pickaxe in the inventory and the turtle cannot dig.
      The boot script also re-finds the slot rather than trusting the one its
      wait loop saw, because the deployer is still dropping items in after that.
    Test 95, confirmed to fail against the unfixed code.

## What shipped on 2026-08-29, from log kdxS8

Turtle 2 ran the current build: `equipped: a modem was in a slot and not on a
side -- fitted it on left` is item 21 working in-game. It crossed to its trunk,
sank to y=-59, found nothing under its own trunk, swept the spine for the
others' -- and stopped at 145 blocks with nowhere to bank them. Four changes.

22. **One depot, at the MIDDLE trunk.** On the user's instruction. `buildDepot`
    placed it wherever the carrier happened to be standing, which is turtle 1's
    trunk -- one end of the claim -- so turtle 3 walked the whole spine on every
    trip and turtle 2 found nothing under its own. It now walks to the middle
    turtle's trunk first (`math.ceil(turtles / 2)`, whose trunk is the claim's
    own z-centre) and builds there; a middle trunk it cannot reach falls back to
    building where it stands. Tests 33 and 62 rewritten around it.
23. **The shared-depot sweep stops at `bottomY`.** It probed `{0,1,2,3,-1,-2,-3}`
    off `st.level`, so from a floor at y=-59 it walked to **y=-61** and cut an
    eight-block corridor round somebody's chests. The downward offsets exist for
    a real case -- bedrock can stop THIS turtle higher than its neighbour -- but
    `bottomY` is the same number for all three, so nothing is ever under it.
    Test 98.
24. **The floppy is found where the drive says it is.** `getMountPath` on the
    drive, everywhere `/disk` was hard-coded: the deployer's writes, the boot
    script's reads, the lava map, and the "am I running off the floppy?" test in
    `main`. **`/disk` is only the FIRST drive's mount** -- a second drive
    anywhere puts this floppy at `/disk2`, and then the prefix test says a run
    off the floppy is a run on the turtle, so it installs nothing, writes its
    state to a floppy it walks away from, and cannot be restarted. That is a
    turtle you have to go and type commands into. Test 96.
25. **A silent turtle is rebooted before anyone is asked to walk over.**
    `turnOn` wakes a turtle that is OFF and does nothing to one that is on but
    never ran the disk startup -- which is the state two live deploys left them
    in. `reboot` re-runs the disk startup, which is exactly what the player was
    being told to do by hand. Sent at 6s and again at 16s; the right-click
    question moved back to 24s. Test 97.

## What shipped on 2026-08-29, from logs 9KJAs, H2Ie0 and sCv32

Three turtles ran at once for the first time. The chain: turtle 2 parked on the
middle trunk, turtle 1 waited out 24 give-ways one block short of it, gave up
and built the depot at z=118 -- not a trunk floor -- and turtles 2 and 3, whose
state files still carried last run's `noDepot`, never swept for it and both
stopped with a full hold. Four changes.

26. **`st.noDepot` does not outlive the run that set it.** It is a within-run
    latch so a turtle does not re-sweep the spine on every dock; it was
    surviving into the next run, by which time turtle 1 has usually built the
    depot the sweep was looking for. Cleared at the top of a run, which still
    costs no sweep on boot -- the sweep only ever runs when a dock is due.
    Test 99.
27. **A depot that cannot go at the middle trunk goes at THIS turtle's trunk**,
    never wherever the walk gave up. `findSharedDepot` only knows how to visit
    trunk floors, so a container one block short of one is a container no other
    turtle will ever find -- which is exactly what z=118 was. Falls back
    mid-trunk, then own trunk, and says loudly if it ends up on neither.
    Test 100.
28. **A stopped turtle parks OFF the spine.** The spine is the one corridor all
    three share and every trunk floor sits on it, so a turtle that stops where
    it stands is a wall the other two cannot pass -- and they do not stop, they
    burn their give-way tries and mis-route. It now steps into a branch mouth,
    a row that gets mined anyway. The resume point is `st.leg`/`st.along`, not
    the position, so a block sideways costs nothing. Test 101.
    `YIELD_TRIES` also went 6 to 12; the waits are index-scaled, so this costs
    the turtle with right of way the least.
29. **A floppy run with no drive in reach is still a floppy run.** `diskPath()`
    answers nothing when the drive is not on a side of this turtle, which is
    the normal case for one standing away from the launch block -- and item 24
    made that the only test, so `cd disk` then `quarry 2` installed nothing at
    all. The path name is the fallback. Test 102.

## What shipped on 2026-08-29, from logs qhVSH and fPSF1

Both turtles worked properly for the first time: 635 and 639 blocks, 11 and 12
branches, five depot trips each, lava scooped. Both then ended the same way --
twelve give-ways in front of each other and `work complete` on a run that had
just failed to reach its depot. The design note is `DEADLOCK-PLAN.md`.

**The cause was structural, not a bug in the waiting.** One depot meant every
dock from all three turtles ended at the same block, down a spine one block wide
with a passing place only every 5. Turtle 1 walking +z and turtle 2 walking -z
met head-on; `giveWay` only ever waits, so both waited and neither moved.
**Waiting cannot resolve a head-on meeting in a 1-wide corridor -- somebody has
to reverse.**

30. **One depot per turtle, under its own trunk. This REPLACES the settled "the
    depot is ONE box".** With a box each, no turtle leaves its own third to bank
    at all, so the meetings stop rather than being recovered from. `kitWants`
    asks for `turtles` containers; `deployOne` hands one over beside the modem,
    coal and bucket; `buildDepot` builds under this turtle's own trunk and the
    middle-trunk walk is gone. `findSharedDepot` stays as the fallback for a
    turtle that has no container -- the kit decides, and no config key was
    added. **Accepted cost: coal sharing degrades**, because a find by turtle 1
    can no longer be burnt by turtle 3. Tests 103-105, and 33/62/100 rewritten.
    **The ration was left unchanged here, and that was the bug**: a floor held
    back for the other turtles in a box none of them visits is coal nobody can
    spend. Changes 37-39 (2026-08-29) finish this one.
31. **The retreat actually clears the corridor.** `stepAside` walked back one
    block, which leaves a turtle still in a 1-wide tunnel. It now reverses along
    the spine up to `RETREAT_MAX = 5` until it is on a branch row and pulls into
    the mouth -- a row that gets mined anyway. Test 106.
32. **The tie is broken by index, with no messaging.** `tries = max(1,
    YIELD_TRIES - 3 * idx)`: turtle 1 waits 9 and holds the corridor, turtle 3
    waits 3 and is the one that moves. That is the settled "lower wins, higher
    moves" rule using only what a turtle knows about itself. Test 107.
33. **A run that gives up on a jam says so.** `goTo` records what would not move,
    where, and that it is another turtle, and sets `halt` when the retreats run
    out -- `dock` handed the false up, the loop broke with `halt` unset and
    `report` printed `work complete`. The two loop sites that deliberately carry
    on to a dock after a failed walk now clear `halt` first. Test 108.
34. **The boot is split so one run says which half failed.** `<disk>/startup`
    (both names) is now a bootstrap that derives the floppy from
    `fs.getDir(shell.getRunningProgram())` -- no peripheral calls, no loops --
    writes one line to the floppy log, and runs `<disk>/boot.lua`. The real
    logic is `boot.lua`, wrapped in `pcall` with its crash written to that log.
    **So an empty floppy log means the disk startup never ran at all** (a
    CC-side problem: `shell.allow_disk_startup`, or the drive not seen), and a
    log with one line in it means `boot.lua` failed and the next line says
    where. Test 109.

## What shipped on 2026-08-29, from logs E5wWw and hkgWh

Both turtles ran well and both stopped the same way, with coal in their own
depot: 2,751 and 1,621 blocks, 44 and 25 branches, neither crashed, both under
160 fuel one block from a container of coal. `FUEL-PLAN.md` is the design note
and carries the log evidence, the rejected alternatives, and the reasoning.

**Three independent causes**, each of which alone produces "coal in the box,
turtle stopped": the ration floor reserved 16 coal in a box no other turtle
visits; `restock` cannot read past the first 16 stacks of a container bigger
than 27 slots; and the climb to `topY` was only ever attempted once the tank
held less than the climb costs, so it had never once worked.

35. **Coal is burnt on pickup, up to `fuelKeep` (2000), at a PRIVATE depot
    only.** `keepFuel` calls the existing `burnFrom` at the end of every leg and
    at every dock — never per dug block, which is a 16-slot scan on every one of
    a run's thousands of blocks. At a shared box coal still rides home unburnt.
36. **A depot is this turtle's own unless explicitly shared.** `probeDepot` and
    `buildDepot` write `own = true`; `findSharedDepot` writes `own = false`;
    everything reads it as `st.depot.own ~= false`, never truthiness, so a
    `quarry.state` written before the field existed falls on the private side —
    which is where every turtle in the world belongs. Test 111.
37. **`fuelFloor` is deleted**, from `NUM` and from the seeded config.
38. **`sharePerDock = 16` caps one dock's take at a SHARED box.** A cap, not a
    reserve: it divides the box across visits without stranding any of it.
39. **`fuelShare`'s dock trigger fires only at a shared depot.** Its stated
    purpose is banking a find "for the others"; at a private box the trip only
    moves coal into a container the same turtle draws it back out of. Test 114.
40. **`forageCoal = true` in `BOOL`**, beside `lava`, which already gates the
    lava-scoop arm of the same `forage()`. Test 38 pins the default; test 118
    covers the off path, which stops at the depot naming the switch.
41. **The climb is launched while it can still be paid for.** A dock the depot
    could not feed, with the tank under twice the top-branch cost, rather than
    `fuelLevel() < want` — one branch's worth, when the climb costs four. On
    log `E5wWw` that fires at the tank-413 dock instead of at 93. Test 115.
42. **A climb it cannot afford halts AT the depot**, naming the shortfall, and
    the cost is priced from the trunk column. Halting halfway up a one-wide
    trunk shaft leaves the turtle somewhere the player cannot reach with coal.
    An early climb it cannot start is not a reason to stop while the tank still
    covers the next branch — it mines on and asks again at the next dry dock.
    Test 116.
43. **Up top it mines until the tank reaches `fuelKeep`**, not one branch and
    back. A full hold drops junk through `makeRoom` and descends only holding
    ore; a foraging turtle never walks home for fuel, because the box it would
    walk to is the dry one that sent it up.
44. **Then it re-enters the schedule at the deepest unfinished level**, by
    clearing `st.level` and letting `nextBranch` find it. Leaving `topY` as the
    schedule position silently reverses `deepestFirst`, and with every level
    below already done the turtle calls the claim exhausted. Test 117.
45. **A turtle that cannot reach `fuelKeep` parks at the top of its own trunk,
    y=`topY`** — private to its own third, and the point nearest the surface.
46. **`notify()` on both events**, the ascent and the park.
47. **The depot's true size and coal total are printed once per run**, through a
    `pcall`-wrapped `peripheral.wrap`. **Read-only, and a measurement rather
    than a fix**: `pushItems`/`pullItems` address peripherals by name and a
    turtle has no name for itself, so a wrap can read slot 40 and still not take
    from it. **It also settles whether a turtle can wrap an adjacent inventory
    at all** — the peripherals dump in the skill's references was taken from a
    computer, and a turtle's own sides are its upgrades. If it comes back
    showing a deep box full of buried coal, splitting the depot into two
    containers (dump and fuel, which `probeDepot` already supports) is the next
    change.

**Deliberately not done: the 16-stack read cap stays**, at the user's decision.
Change 35 keeps the tank topped from what the turtle digs, so it rarely needs to
go looking; change 47 is the instrument that says whether the residual costs
anything.

## What shipped on 2026-08-29, from logs yiALS and PwHyZ

The first live run of the fuel build. Deployment, the depot, the burn on pickup
and the notify all worked. **Change 47 answered its question: a turtle CAN wrap
the container it is facing, and the user's depot came back as a 132-slot box**
holding 38 and 64 coal. The 16-stack read cap is therefore no longer a wall for
*reading*; the take is still `turtle.suck`, which only ever pulls the first
slot.

Both turtles then climbed to y=60 on their second dock with a full depot under
them, worked out the top level, and called the mine complete after four
branches with fuel still in the tank. Two bugs, both in the new code:

48. **`dry` means the BOX has nothing, not that this trip asked for nothing.**
    It was read off what the dock TOOK, and a turtle whose tank already covers
    four branches takes 0 from a box holding 38 coal. It is now read off the
    wrap where there is one, and off `restock`'s count where there is not.
    Test 119.
49. **A worked-out top level is not a finished claim.** `nextBranch` searches
    from `st.level` onward, so a foraging turtle sitting at `topY` reads a claim
    with unmined levels UNDER it as finished. When the top level runs out and
    the tank never reached `fuelKeep`, the turtle now drops `st.foraging`,
    clears `st.level` and goes back to the schedule. Test 120.

`boxRead` is the wrap, `pcall`-wrapped and read-only; `depotProbe` is the
once-per-run printout on top of it. **A world with no wrap is still the
fallback everywhere** — every test but 119 leaves `chestSize` nil.

## What shipped on 2026-08-29, from logs rVv2v and lYwey

Two long, healthy runs -- 2,753 blocks and 45 branches on `rVv2v` -- and both
ended stranded at the depot on 124 and 131 fuel. The first climb worked
(`lYwey`: `tank is 2028 -- back to the schedule`). Every climb after it turned
round on arrival, because the turtle had already cut every row it owns at
y=60: three bounces in `rVv2v`, two in `lYwey`, and then a slow grind down to
nothing.

50. **The lava map is shared over rednet, not over the floppy.** The drive and
    the floppy stay at the SURFACE launch block and every depot is at a trunk
    floor 119 blocks down, so `/disk` is never mounted where `dock` calls
    `mapMerge` -- a source one turtle found never reached the other two [user,
    2026-08-29]. A find is broadcast on the `quarrylava` protocol, a scoop is
    broadcast as `gone`, and `forage` reads the in-memory list as well as the
    floppy. **The listener is a coroutine under `parallel.waitForAny`**, not a
    drain at dock time: an event that arrives while `turtle.forward()` waits
    for its `turtle_response` is pulled and DISCARDED by the turtle API, so by
    dock time there is nothing left in the queue. Test 122.
51. **Foraging starts at `topY` and works DOWN.** Coal gets commoner the higher
    you go [user, 2026-08-29], so the top of the claim is the level worth the
    climb; what changed is where the turtle goes when that level's rows are
    gone -- the next level down, and the one under that, instead of the same
    finished level over and over. Nothing below y=0 counts as foraging: coal
    does not generate there in 1.21, which is why the claim floor is somewhere
    a turtle cannot mine its way out of. A claim whose top is already under y=0
    has only its top level to offer. Tests 21 and 120.

    *(Shipped for an hour as "the nearest level from y=0 up", on the reasoning
    that y=0 is 118 blocks of climb cheaper. The user corrected the density
    assumption; the climb is paid once and the descent afterwards is free.)*
52. **The gate is `conf.fuelKeep`, not twice one climb.** Twice a climb is about
    790; a turtle that came back from a climb with less than that, or whose box
    ran dry on a healthy tank, spent the rest of the shift mining its reserve
    down instead of going to get coal. `fuelKeep` is the tank the turtle wants,
    and below it, with a dry box, going to get coal IS the work. Test 120.
53. **A worked-out forage level moves to the next one.** One level's rows rarely
    carry 2,000 fuel of coal, and giving up after one is what made the climbs
    bounce. Only when coal country has no work left in it does the schedule get
    the turtle back. Test 120.

55. **A level change happens in this turtle's own TRUNK COLUMN.** `goTo` moves
    y first, so a level change made anywhere else sinks a fresh shaft through
    solid rock: coming down from a forage level the turtle cut 53 blocks of new
    tunnel at the claim rim with its trunk standing open [user, 2026-08-29].
    The trunk is air from `topY` to the floor from the first descent, and
    walking to it costs at most the width of a third, every block of it already
    cut. This replaces `goTo(c.spine, st.y, st.z)` -- the spine column at
    whatever z the turtle stopped on, which is only air where it has been
    walked, and at a forage level 119 blocks up it has not. Test 123.

## What shipped on 2026-08-29, the harvest build (A, stop, C) and the B finding

`HARVEST-PLAN.md` is the design note, written from the user's three complaints
and the `jnordberg/minecraft-replicator` reference. Package A (boot) was already
built by the session before this one but left five red tests; this session
finished it, added a `quarry stop` command the user asked for, built package C
(fuel), and investigated package B (routing) to a no-change conclusion. All
three suites pass. **Unproven in-game: all of it.**

**A — the boot, fully automatic (tests 124–129).** The floppy write order is the
fix: the three tiny boot files (`startup`, `startup.lua`, `boot.lua`) and the
`index` file go on BEFORE the 83 kB program, so the program is the only thing
that can be squeezed off a full floppy — not the boot script, which is what left
turtle 2 at a bare `CraftOS 1.9 >` prompt with `quarry` on its floppy and no
`startup`. Every write is read back and compared (`writeVerified`); a write that
lands nothing is reported by name. `fs.getFreeSpace` is printed and the payload
is **refused** rather than written truncated if it will not fit beside the boot
files. The drive mount is retried 20 times (`diskPathRetry`, harvested from
replicator) probing the drive directly rather than through `diskPath()`, whose
`fs.exists("/disk")` fallback short-circuited the retry. The floppy carries its
own `index`, so a bare `disk/quarry` runs as the right turtle; `disk.setLabel`
names it `quarryN`. The isOn/reboot ladder stays as a cheap backstop, demoted —
and now waits ~2s for a freshly-on turtle to label itself before rebooting it.

**`quarry stop` — park a turtle for relocation (test 131).** On the user's
instruction. On first boot a turtle writes its own `/startup` that re-runs
`quarry N` on every reboot, independent of the floppy — so moving it does not
stop it, the next reboot resumes from `quarry.state`, and a pinned `startX/Y/Z`
sends it to the OLD spot. `quarry stop` deletes `/startup` and `quarry.state`
and comments out `startX/Y/Z/startDir` in `quarry.conf` (kept as `#` comments,
still readable). Ctrl+T first if it is still running.

**C — the fuel split (tests 132–134).** `kitWants` for `turtles = 1` no longer
demands a drive or a floppy: a solo mine deploys nobody and shares its map with
nobody, so the audit stopped refusing a complete solo kit. `handOver` now walks
EVERY matching slot and counts what actually moved (via `getItemCount`), rather
than dropping up to N out of the first slot and calling a 30-coal slot a success.
And the coal aboard at deploy start is split evenly across every turtle the mine
will run, the deployer included: with C coal and k still to place, each placed
turtle gets `min(64, floor(C / (k+1)))` and the deployer keeps the rest —
measured before `topUp` so a full 64×n kit is exactly 64 each. The worked case,
128 coal / 3 turtles, is now 42 / 42 / 44 (deployer keeps 44) instead of the old
64 / 64 / nothing that sent turtle 1 down 119 blocks on an empty tank. C3 (solo
needs no ration) was already correct and is unchanged.

**B — routing: no change needed, and here is why (test 135).** `HARVEST-PLAN.md`
claimed a dock throws the pair away, so most pairs never get past their second
leg. **That does not happen in the current code**, proven by test 135: a run with
`tripBlocks = 8` docks three times per leg and still finishes its pairs through
the rim jog. A normal dock preserves `st.plan`, `st.step` and `st.leg`, so the
leg resumes exactly where it stopped; `forage` clears the plan only when it
actually climbs to another level, which is correct. The one path that discards a
pair is a mid-leg **jam** (another turtle in the corridor) — and that is
deliberate and geometrically necessary: a leg that jams before reaching its rim
never reaches the rim, so the rim-jog to the partner row is impossible, and
re-picking from the spine is the only recovery. B1/B2/B3 as written are either
already-handled or unsound; test 135 is the regression guard. Complaint #2's
"sometimes returns to the spine" is that jam case, and it cannot be given the
rim jog. **If the marginal jam-case efficiency (pair the leftover row with a
neighbour after the interrupted leg reaches the rim, B2) is wanted, it is a
careful change to `pairPlan` — flagged, not done.**

**SETUP.md moved to `attic/SETUP.md`** on the user's instruction. No code reads
it; only docs referenced it. The setup artifact was generated from it.

## What shipped on 2026-08-29, the claim-size build (changes 56–58)

Three changes, built on the `deepseek` branch and merged into `main` the same
day. All five suites pass. **Unproven in-game: all of it.**

56. **The claim is no longer fixed at 3×3 chunks.** `chunksX` and `chunksZ` are
    config keys, defaulting to `3` and `3`, and `claimOf` takes the config and
    spans that many chunks centred on the start chunk. An odd count centres
    exactly; an even one leans one chunk toward `-c` so the start chunk is still
    inside the claim. `--check` prints the real span it computed rather than the
    hard-coded `cx-1..cx+1`. Every call site passes `conf` — the live run, the
    recall, the dry run, the moved-turtle test and the deploy. The spans use
    `math.floor`, not `/`: CC is Lua 5.2 and all-doubles, but the test harness
    is 5.3, where a bare `/` makes `1.0` print as `1.0` and breaks the report.

    **Both values must match on every turtle**, exactly like `topY` — the branch
    pattern is keyed to the world, so turtles that disagree about the claim
    compute mouths that do not line up. And the player must keep every chunk in
    the claim loaded: 3×3 is what standing in the centre chunk holds open, and
    anything larger needs a real loader or a branch strands.

57. **A short tank gathers coal instead of refusing the trip.** `runMine`'s
    surface fuel gate used to halt with `not enough fuel` and wait for a human.
    It now calls `forage`, which is a few blocks' climb to coal country from the
    surface rather than the 119-block round trip the tank could not pay for;
    `forage` commits to mining coal until the tank reaches `fuelKeep` and the
    schedule resumes from there. A turtle that cannot even pay for the climb
    still stops, and stops **at the surface** where the player can reach it —
    `depot is dry and I cannot afford the climb for coal`.

58. **A jam names the turtle that caused it, and where it was.** An adjacent
    turtle is a peripheral and a booted one has labelled itself `quarryN`, so
    `giveWay` now reads the blocker's label off the side it is blocking and
    works out the blocker's own cell. `computercraft:turtle_advanced (quarry3)
    at x,y,z would not move out of the way after N tries ... I am at x,y,z`.
    Read against the other two turtles' logs, that says who deadlocked whom —
    which log `jGC2X` could not, having stopped turtle 2 one block from its own
    trunk against an unnamed turtle sitting on its spine.

59. **The boot files go on the floppy stripped, and that is the 5 kB the
    deploy was short of.** In-game 2026-08-29 the deploy stopped one file from
    done: `the program will not fit: 109401 bytes free, 110442 needed` — 1041
    short — with a 10064-byte `boot.lua` on the disk that was half comments.
    `strippedBody` is now `stripText(body)` and `writeBoot` runs `BOOT` and
    `BOOTSTRAP` through it: `boot.lua` 10065 to 5113, each `startup` 483 to
    333, so 5252 bytes come back and the same floppy now takes the program with
    about 4 kB to spare. Not the config — that one IS a file the deployed
    turtle reads back, and its layout is the file. Test 138 sizes a floppy at
    the program plus 6800 bytes: the stripped boot files, config and anchor
    come to 5833 and the unstripped ones to 11085, so the fixed build fits with
    1 kB to spare and the unfixed build prints the in-game refusal. Confirmed
    to fail against the unstripped writeBoot.

60. **Every turtle's boot files reach the FLOPPY now, not the deployer's own
    hard drive.** In-game 2026-08-29 [paste Ql3Nv] turtles 2 and 3 both came up
    `quarry2`. The loop rewrites the boot files per turtle from the PLACING
    spot, where the drive is one up and one forward -- diagonal, on no side of
    the turtle -- so `/disk` is not a mount there and `writeVerified` created a
    plain `/disk` folder on the deployer's own hard drive, wrote into it and
    read it back perfectly. The floppy kept whatever the last write from up
    beside the drive left on it, which was `local N = 2`. The loop now steps up
    beside the drive, re-asks `diskPath()`, writes, labels the floppy (from up
    there the drive is the block in front, so `disk.setLabel` finally has
    something to address) and steps back down before placing. A failed `stepUp`
    records the turtle as failed rather than placing one with no boot files.
    **The test harness had modelled `/disk` as writable from anywhere, which is
    why this shipped**; it now mounts the floppy only while the drive is on a
    side (`onDrive()`, `V.driveAt`), and an off-drive `/disk` write lands under
    an `(off the drive)` key. Test 139, plus three older deploy tests that had
    been passing on the harness's fiction and now fail against the unfixed code.

**Three loose ends this build left, all closed the same day:**

- **`span()` now has a test (5b).** Three `--check` runs from a turtle pinned at
  `0,64,0`: `chunksX = 5` spans chunks −2..2 for an 80×48 claim, `chunksX = 4`
  leans to −1..2 for 64×64 — the half that keeps the START chunk inside rather
  than on its own rim — and the shipped default is still −1..1 and 48×48. Both
  branches were confirmed to fail against a mutated `span`.
- **`giveWay` read a label without its `ok` flag, and that is fixed.** It was
  the fifth time this file has taken the second value out of a `pcall` without
  the first; see the corrections list. The fix is a shared `periph(fn, ...)`
  beside `equippedItem` that returns nil when the call did not live, now used by
  `giveWay` and by `runDeploy`'s `getType` probe. Test 136 covers it: a blocker
  that answers `quarry3` is named, and a blocker that will not answer at all
  (CC:Tweaked #660) reads as `(unlabelled)` rather than
  `(No peripheral attached to front side)`. Confirmed to fail against the
  unfixed line.
- **The surface climb is priced from the trunk column now (test 137).**
  `forage` prices with `branchCost`, which measures from a trunk column, and
  passed `st.z` for every caller. That is right for `dock`, which calls it
  standing on the trunk, and wrong for `runMine`'s surface call: a turtle at the
  launch block is up to half a claim away from its own trunk in z, and the walk
  was dropped from both halves of the estimate. **`chunksZ` is what turned this
  from harmless into a bug** — the worst gap is 48 at the shipped 3×3, which
  `fuelMargin` (64) swallows, but 70 at `chunksZ = 5` and 112 at `chunksZ = 9`,
  and a turtle that commits to a climb it is 70 short of strands in its trunk.
  `forage` now takes the column as an argument, defaulting to `st.z` so `dock`
  is unchanged. The worked case in the test: turtle 3 starting 27 blocks off its
  own trunk priced its climb at 206, and prices it at 260.

## Next action

**Ask for `update`, then `quarry 1`** from the launch block. The harvest build
(A, `quarry stop`, C) is in; B needed no change. The claim-size build (56–58)
is in on top of it. The five suites pass.

**What to read in the log for the claim-size build:**

- **`claim  : chunks A..B by C..D`** on `quarry 1 --check`. With the shipped
  `chunksX = 3, chunksZ = 3` that is the same nine chunks as before — the point
  is that it is now computed, not written down. Change one value in
  `quarry.conf` on **every** turtle to widen the claim, and keep every chunk
  loaded.
- **`fuel   : N in the tank, M to reach the branch and walk back -- gathering
  coal first`** instead of `STOPPED: not enough fuel`. A turtle that starts
  short should now climb for coal rather than stand there. If it stops anyway,
  the line to find is `cannot afford the climb for coal`, and it stops at the
  surface.
- **A jam, if one happens**: `... (quarry3) at x,y,z would not move out of the
  way after N tries ... I am at x,y,z`. `(unlabelled)` means the blocker had no
  label to give, or would not answer at all. Read it against the other turtles'
  logs: between them they say who deadlocked whom, which is what log `jGC2X`
  could not.

**What to read in the log this time** — the harvest build is unproven in-game:

- **The floppy write-back**: `deploy : wrote the boot script for turtle 2, read
  back off the floppy: startup.lua N, startup N, boot.lua N, index N`, then
  `the floppy has N bytes free and the stripped program is N`, then
  `copied ... to /disk/quarry (N bytes, comments stripped, read back)`. If the
  floppy is too small, `the program will not fit` and the boot files survive.
  The point: turtle 2 should NOT end up at a bare `CraftOS >` prompt this time.
- **The coal split**: `deploy : N coal aboard, K to place -- M coal each, I keep
  the other R`. With a full kit that is 64 each; with less, the deployer keeps a
  fair share instead of descending on an empty tank.
- **`quarry stop`**: run it on a turtle, reboot it, confirm it stays at `>` and
  does not resume. Move it, `quarry N`, confirm a fresh claim.

**What to read in the log** (unchanged from the fuel build): `climbing to y=60`
at a much healthier tank than
before, then `forage : y=60 is worked out, still N short -- on to y=59` if one
level is not enough; `forage : tank is N -- back to the schedule` when the tank
is full; and `lavamap: turtle N found a source at ...` on a turtle that did not
find it itself, which is the first time the three of them have shared anything.

The code is ready. The run to ask for: **`update`, then `quarry 1`** from the
launch block, carrying a barrel, turtles 2 and 3, the drive and the floppy.
`quarry 1` deploys by itself while turtles are in the hold, then mines;
`quarry 1 deploy` is only for retrying the staffing alone. **Stay at the
turtle**: it asks to have each new turtle right-clicked, and waits 60s for that
one. The turtle already standing at the depot does not need moving and needs
nothing typed on it — the deploy adopts it as turtle 2 and rewrites its floppy
with the current build. `SETUP.md` is the player-facing version of all of this.

What to read in the log that comes back:

- **`a turtle is already standing here -- adopting it as turtle 2`**, or
  `placed computercraft:turtle_advanced in front`. Either is the deploy getting
  past the block that stopped log 0JCwD.
- **`deploy : nothing from turtle 2 yet -- it is still switched off`** or its
  absence. That answers whether the `turnOn` on `front` reaches a freshly
  placed turtle at all, which two logs now disagree about.
- **`deploy : claim anchor x,z on the floppy`**, then on turtle 2's own screen
  `took the deployer's claim anchor`. That is the fix for the second tunnel.
- **A depot.** Log 0JCwD went short one storage block on the player's say-so
  and the mine stopped at 194 blocks with nowhere to put them. The kit needs a
  box.

- **`position:` against F3.** Nobody has ever confirmed the turtle's fix
  matches the real world, and the pattern anchors to absolute coordinates — a
  wrong origin mines a correct claim in the wrong place.
- **`deploy : turtles in the hold -- staffing the mine before I descend`**, then
  `deploy : 2 of 2 deployed`. That path has never run in-game.
- **`depot  : the floor under the trunk will not open -- placed a container
  beside the trunk at y=-58 instead`.** That is the bedrock fallback working,
  not a fault. `nothing beside the trunk will open` means all three candidate
  spots refused to be dug; read the lines above it.
- **A dock**: dump, ration, restock. Rationing has never handed out coal.
- **`taken  : y=-59 z=711 is already cut`** and the same for z=706 is expected
  on this claim: `Rpv9m`'s own work, read back as another turtle's once
  `quarry.state` was deleted. `mouthTaken()` cannot tell the difference and by
  design does not try. Restarting over an old mine costs those rows.

## What shipped on 2026-08-28

Four builds in a day, each one from an in-game log. The full write-up of each
is in `reports/history-2026-08.md`; this is the list. Every fix has a
regression test confirmed to fail against its own unfixed code.

**Morning, from the code review** (`reports/code-review-quarry.md`): all nine
findings fixed, tests 40–48. The vein-chase counter, the empty-tank guard, the
absolute vein sweep, three `pcall` result bugs, and the lava dedupe.

**Evening**, tests 49–55: the fuel ration became a floor rather than a fraction
(`fuelFloor`, default 8 — **deleted again on 2026-08-29, change 37**); `--check`
asks the turtle for its own tank limit
instead of assuming 20,000; `calibrate` refuses a config-pinned position rather
than crashing on it; `startDir` lets a turtle mine with GPS down, at the cost
of ever recovering from a lost state file.

**Night**, from log `45bPE`, tests 56–60 and a rewritten 33: the depot moved
**under** the trunk floor, the one neighbour the pattern never enters; the
deployment kit stays in the hold instead of being dumped as spoil; a NO FIX
crash names which of its three causes it is, uploads `gps.locate`'s own debug
output, and tells a wired modem from a wireless one; `quarry.state` stands in
as a position source where GPS cannot reach.

**Late night**, from log `Rpv9m`, tests 62–64: bedrock under the trunk floor
falls back to an x-side niche a level up; spare coal is no longer a reason to
stop when there is no depot to bank it in; **one `STORAGE` word list** — chest,
barrel, shulker, crate, item_vault, matched as a substring — answers all four
questions the program asks about storage. Drawers and bins stay off it: they
lock to one item type, so a mixed dump fails on the second stack.

**Last**, at the user's instruction, tests 65–66:

- **`quarry 1` staffs the mine itself.** A turtle item in the hold means
  deployment never happened, so the run does the whole of `runDeploy` at the
  launch block before it descends. Recorded in `quarry.state` *before* it runs,
  so a deploy that dies half way is not retried on every reboot; a deploy that
  cannot happen at all says so and the turtle mines alone.
- **A full depot loses the junk, not the run.** A drop the depot refuses puts
  that stack on the tunnel floor when it is the junk tier. Ore still stops the
  run — mining on would only destroy the drops.
- **`notify()` calls home.** The line goes in the log, so the uploaded paste
  carries it, and out over rednet on the `quarry` protocol through the equipped
  wireless modem, once per kind per run. A full depot is the only thing that
  sends one so far.
- **`alert.lua` is the other end**, a new program for a computer. Range is the
  catch and it is physics, not a bug: a modem's reach shrinks with depth, the
  same thing that keeps GPS off the claim floor.
- **The test suite caps `topY` in eleven worlds.** A run that no longer stops
  on a full depot mines its whole third, which took the suite from 10s to 68s;
  it is about 9s now. The worlds that assert the trunk shape or the forage
  target still use the real ceiling.

## Delivered

| Program | URL | What it is |
| --- | --- | --- |
| `quarry.lua` | `raw.githubusercontent.com/zaBees/cc/main/quarry.lua` | **CURRENT — 2026-08-29.** Auto-deploy from a plain `quarry 1`, a full depot that drops junk and calls home instead of stopping, a deploy that resumes at the turtle still in the hold instead of restarting at turtle 2, GPS asked before the config pin, a modem in a slot fitted to a side, the floppy found through getMountPath, a stopped turtle that parks off the shared spine, one depot per turtle so they stop funnelling into one block, and the fuel build: coal burnt on pickup to `fuelKeep`, no ration at a turtle's own box, `sharePerDock` at a shared one, and a climb into coal country launched while it can still be paid for, with the depot read through a peripheral wrap rather than sixteen sucks and the lava map shared over rednet. **The harvest build (2026-08-29):** the floppy writes its boot files first and reads every write back, refuses a program that will not fit, retries the mount, and carries its own turtle index; `quarry stop` parks a turtle for relocation; a solo kit needs no drive or floppy; and the coal aboard is split evenly across every turtle, the deployer included. **The claim-size build (2026-08-29):** `chunksX`/`chunksZ` size the claim, a short tank climbs for coal instead of refusing the trip, and a jam names the turtle that caused it, through a shared `periph()` that is the one door to a peripheral read, and the surface climb is priced from the trunk column it will actually walk to. **The floppy-space fix (2026-08-29):** the boot files go on the floppy stripped, which is the 5 kB the deploy was 1041 bytes short of. **The label fix (2026-08-29):** every turtle's boot files are written from up beside the drive, so they reach the floppy instead of the deployer's own hard drive. Comments cut to short descriptions in the same build. **Pushed 2026-08-29** as `a8c2f3e` and verified byte-for-byte against both the commit-pinned URL and `/main/`. 207,385 bytes, fletcher32 `184118494`. |
| `probe.lua` | `raw.githubusercontent.com/zaBees/cc/main/probe.lua` | The Phase 5 deployment probe. |
| `update.lua` | `raw.githubusercontent.com/zaBees/cc/main/update.lua` | The in-game updater. Downloaded once by hand; after that `update` replaces `quarry`, `alert` and itself. Briefly renamed `deep.lua` on the `deepseek` branch on 2026-08-29; the rename was reverted before the merge, because the turtles already have `update` installed and a renamed file would have left them asking GitHub for a name it no longer serves. 3,357 bytes, fletcher32 `4171412274`. |
| `alert.lua` | `raw.githubusercontent.com/zaBees/cc/main/alert.lua` | **NEW.** For a computer, not a turtle: prints what the mine broadcasts on the `quarry` protocol. 1,379 bytes, fletcher32 `142400053`. |

`SETUP.md` carries the download lines for the user. The setup artifact at
https://claude.ai/code/artifact/6989784d-6bae-4da6-8158-0dc6464885c5 predates
GitHub delivery and is **out of date** — update that same URL when it is
regenerated, because a fresh publish makes a second page.

## Delivery goes through GitHub

The repo is **https://github.com/zaBees/cc**, public, and this directory is its
working tree. **Ship a fix by pushing**, then telling the user to run `update`.

**Verify every push against the commit-pinned URL, never the branch one:**

```
curl -sS https://raw.githubusercontent.com/zaBees/cc/$(git rev-parse HEAD)/quarry.lua
```

The `/main/` URL is CDN-cached and served the previous build for more than two
minutes after a push on 2026-08-28, which looks exactly like a failed push. The
same cache can hand the user a stale file if they re-download immediately.

`update` replaces `quarry`, `alert` and itself: it writes `<name>.new` and moves
it into place, so a failed download leaves the working copy alone; it refuses an
empty body and an HTML 404 page; it appends `?t=<epoch>` to defeat that cache;
and it prints `quarry: N bytes, fletcher32 N` to check a delivery against the
local file. Configs are never touched. `test_update.lua` covers all of it.

**A hand-typed download is always TWO lines**, `delete <name>` then the `wget`.
CC's `wget` refuses to overwrite an existing file — it prints `File already
exists`, downloads nothing, and reads like success. No force flag, and the CC
shell has no `&&` or `;`. `SETUP.md` carries the lines for the user.

**Delivery is GitHub, and only GitHub.** The one other place a paste.rs id
still comes from is the program's own crash report, which it POSTs there and
the user pastes back — that is a log channel, not a delivery route.

**cloudcat is archived in `attic/`. Do not use it unless the user asks for it
by name.** It is the fallback if GitHub is ever unreachable in-game: it pushes
a file into the game over cloud-catcher, split across packets and stitched
back. It needs `websockets` (not installable system-wide here under PEP 668)
and the in-game computer running `cloud <token>`.

## Files

| File | What it is |
| --- | --- |
| `MASTERMINE-PLAN.md` | The design, every decision and its reasoning. Read second. Trimmed 2026-08-28: §11 is now a status table, and the rules it used to carry are in this file's Settled and Corrections lists. |
| `quarry.lua` | **The deliverable.** ~2,430 lines, Phases 1–5. Opens `local DRY = true`; the config lowers it. |
| `test_quarry.lua` | Five suites against stubbed CC worlds, 135 tests. Tests 40–48 are the 2026-08-28 review regressions; 49–55 the evening fixes; 56–60 the night ones; 62–64 the late-night ones; 65–66 the auto-deploy and the full depot; 75–91 the deploy build of that night; 92 the double-fed turtle; 93 the deploy that restarted at turtle 2; 94 the position-fix order; 95 the equipped-upgrade check and the modem fit; 96-98 the mount point, the auto-reboot and the depot-sweep floor; 99-102 the three-turtle run; 103-109 the depot-funnel deadlock and the boot split; 124-129 the harvest boot build (floppy write order, read-back, space refusal, mount retry, floppy index); 131 `quarry stop`; 132-134 the fuel split (solo kit, multi-slot hand-over, even coal split); 135 the guard that a mid-pair dock keeps the pair. The claim-size build changed
two existing tests rather than adding numbered ones: the low-fuel test now
asserts the turtle forages instead of refusing, and the jam test asserts the
blocker is named and placed. 5b is the chunk span, odd and even; 136 is the
jam that names its blocker, including the blocker that will not answer; 137 the
climb priced from the trunk column. `lua5.3 test_quarry.lua` |
| `alert.lua` | For a computer: prints what the turtles broadcast on the `quarry` protocol. |
| `update.lua` | The in-game updater: `update` replaces `quarry` and itself from GitHub. Downloaded once by hand. |
| `test_update.lua` | Stubbed `http`/`fs` around the updater: the failed download, the HTML 404, the cache-buster, the checksum. `lua5.3 test_update.lua` |
| `probe.lua` | The Phase 5 probe. `probe` is a dry run, `probe go` is the real one. |
| `test_probe.lua` | Stubbed world for the probe, live and DRY paths. `lua5.3 test_probe.lua` |
| `attic/SETUP.md` | What the user does in-game. **Archived 2026-08-29** on the user's instruction — no code reads it; the setup artifact was generated from it. Needs the `quarry stop` command and the harvest-build log lines adding if it is ever revived. |
| `reports/history-2026-08.md` | **Everything this file used to say.** The phase narratives, the deploy-run post-mortems, the probe findings. |
| `reports/code-review-quarry.md` | The 2026-08-28 review. All nine findings, all fixed, each with its test. |
| `reports/check-1-2026-08-24.txt` | The first real `--check` output, verbatim. |
| `reports/mine-live-1-turtle2-2026-08-27.txt` | The 177-block in-game run. |
| `reports/deploy-live-1..4-2026-08-27.txt` | The four failed deploy runs. |
| `test_pattern.lua`, `test_coverage.lua` | The pattern proofs: `1,3,5,2,4`, and dug%/unseen% per candidate. |
| `FUEL-PLAN.md` | The design note for changes 35–47, written 2026-08-29 from logs `E5wWw` and `hkgWh` and settled with the user. **Built and shipped the same day** — it survives as the reasoning behind those changes, including the rejected alternatives and the one thing deliberately left undone (the 16-stack read cap). |
| `HANDOFF-PROMPT.md` | The pointer to paste into a fresh session. It says to read this file; it deliberately repeats nothing. |
| `ROCKET-PLAN.md`, `spacex.lua`, `icmb.lua` | **An unrelated second thread**: a Create Aeronautics flight controller. Nine fixes planned, none implemented. Leave it alone unless the user raises it. |
| `attic/` | Superseded and reserve work. `tunnel.lua` and its test, and the cloudcat delivery client. |
| `attic/cloudcat.py` | **Archived 2026-08-28. Do not use unless the user asks.** Pushes files into the game over cloud-catcher, split and stitched. The fallback if GitHub is ever unreachable in-game. |
| `attic/test_cloudcat.py` | fletcher32 vectors, plus a real split of `quarry.lua` whose generated joiner is run under `lua5.3` and diffed byte-for-byte. Run from inside `attic/`. |
| `attic/sumfile.lua` | cloudcat's verifier: prints a file's fletcher32 in-game. Arithmetic-only, because CC is Lua 5.2. |

## The design in one paragraph

Three turtles work a chunk-snapped claim, `chunksX` × `chunksZ` chunks centred
on the start chunk and 3×3 (48×48) by default, with no chunk loader — the player
standing in the centre chunk is what keeps those nine loaded, and a bigger claim
needs a real loader.
Branches are 1-high, 1-wide, run along x, and are sunk wherever
`z ≡ 2y (mod 5)` **measured from the claim's own corner**; that is the user's
`1,3,5,2,4` sequence and it reads the claim interior exactly for ~22% dug,
which is the proven floor. A spine runs along z at the claim's x-centre with
branch mouths every 5 blocks; branches run 24 west and 23 east. Each turtle has
its own vertical trunk at the centre of its own third. Levels run deepest
first, from one above bedrock up to y=60. The depot is at the claim floor;
turtles never surface except on `recall`.

## Settled — do not reopen these

Plan section numbers in brackets.

- **Harvest Mastermine, do not port it** [1]. `forge:ores` must become `c:ores`.
- **Claim is chunk-snapped** 3×3; **the pattern anchors to the claim corner and
  absolute y**, never to a turtle's start block and never to a config value [2].
  **The claim itself anchors to `st.home`, the launch block, and is persisted.**
- **Geometry: horizontal 1-high branches along x**, `z ≡ 2y (mod 5)` [3].
- **Spine along z at the x-centre**, branches 24 west and 23 east [3].
- **One trunk per turtle** at the centre of its third [3, 4]. Trunks sit on the
  spine, so they cost **no extra blocks**.
- **Bottom is one level above bedrock**, found by failed dig [3]. `bottomY=-59`
  is the safety stop. **Top is y=60.** Both configurable.
- **Deepest first, working up** [3]. Direction and range configurable.
- **Three turtles on the same level**, z split into thirds [4].
- **Branch claiming: an air mouth is already taken** [4]. `st.done` is the
  per-turtle exact record; the mouth test is what stops two turtles taking the
  same row. `mouthTaken()` runs **only on a fresh claim**, or a turtle resuming
  its own half-mined branch reads its own work as somebody else's.
- **Depot at the claim floor** [5], **found by looking, not configured**. One
  container serves all three; a turtle with none under its own trunk walks the
  spine to the others, once, and writes `st.noDepot` if the answer is no.
- **The depot goes UNDER the trunk floor, and beside the trunk one level UP
  when bedrock is in the way.** The block under the floor is the one neighbour
  nothing ever mines, so it is always tried first — but bedrock scatters up
  through y=-60 and the floor stands at y=-59, so it usually will not open
  (in-game 2026-08-28, `Rpv9m`). The fallback is an x-side niche one or two
  levels up, never a side of the floor itself. Changed
  2026-08-28 night on in-game evidence (`45bPE`). All four sides of the floor
  block are working rows -- the branch legs run east-west through them, the
  spine runs north-south through them -- so a container on a side is a block
  the pattern later walks into and refuses to dig, which ends that leg and then
  stops the run. Turtle 1 built chests on sides 0 and 1 and lost the branch it
  was standing on to one and the spine to the other. Below the floor is the one
  neighbour nothing ever mines. `probeDepot` looks down first and `"down"` is a
  direction alongside 0..3; a hand-placed container on a side is still honoured,
  and is still in the way. `buildDepot` places exactly one, which is the
  single-box case the ration was already written for.
- **One STORAGE word list decides what storage is**, matched as a substring of
  the block id: `chest`, `barrel`, `shulker`, `crate`, `item_vault`. Enumerating
  every tier of every storage mod is a losing game; matching the word is not.
  Drawers and bins stay off it on purpose — they lock to one item type, so a
  mixed dump fails on the second stack. Do not re-split this into per-question
  copies; there were four.
- **`st.noDepot` is a within-RUN latch, not a permanent one.** Cleared at the
  top of every run. It exists only so a turtle does not re-sweep the spine on
  every dock of the same run; kept across runs it makes a turtle stop over a
  depot that was built in the meantime.
- **A turtle parks OFF the spine when it stops.** Every trunk floor is a spine
  block and the spine is the only corridor, so a parked turtle is a wall. The
  resume point is `st.leg`/`st.along`, never the position.
- **A retreat has to clear the corridor.** `stepAside` reverses along the spine
  up to 5 blocks to a branch mouth; one block back leaves the turtle still in a
  1-wide tunnel. Waiting alone can never resolve a head-on meeting.
- **The give-way threshold falls with index** (`YIELD_TRIES - 3 * idx`), which
  is how "lower wins, higher moves" is enforced without either turtle being able
  to read the other's index.
- **Nothing hard-codes `/disk`.** `diskPath()` asks the drive through
  `getMountPath`; `/disk` is only the first drive's mount and a second one puts
  the floppy at `/disk2`. The boot script resolves it the same way into `D`.
- **The shared-depot sweep never probes below `bottomY`.** It is the same
  number for all three turtles, so no neighbour's floor is under it, and going
  there digs into bedrock.
- **There is one depot PER TURTLE, under its own trunk.** Changed 2026-08-29
  from "the depot is ONE box", which is what caused the deadlock: one box means
  every dock from every turtle ends at the same block down a one-wide spine.
  The kit audit asks for `turtles` containers and the deploy hands one to each.
  A turtle with no container still falls back to `findSharedDepot`. Coal sharing
  across turtles is the accepted cost; do not "fix" it by going back to one box.
- **The deployment kit never goes into the depot.** `dumpLoad` and `restock`
  skip anything matching turtle, computer, disk, modem, chest, barrel, shulker
  or bucket. Before this, `quarry 1` carrying turtles 2 and 3 posted them into
  the dump chest as spoil, which is what happened in `45bPE`.
- **The depot queue is the waiting, not a queue** [5]. Mastermine's linked-list
  route was for a hub with a monitor and any number of turtles. Do not build it.
- **Right of way by launch index** — lower wins, higher moves [8]. `giveWay`
  only ever waits; moving aside is `goTo`'s job, because a sidestep inside
  `mineLeg` would desync `st.along`.
- **Position fixes come in one order: GPS, `quarry.state`, the `quarry.conf`
  pin, then coordinates typed in by hand.** GPS is skipped only when no
  wireless modem is equipped, because then no fix is possible. Do not move the
  pin back above GPS: a pinned turtle somebody has picked up and moved has no
  other way to notice. Set 2026-08-29 at the user's instruction.
- **`recall` is per-turtle and typed; normal returns are independent** [4].
- **Haul everything; the blacklist is a junk tier**, dumped first on overflow
  [6]. A turtle cannot decline to pick up what it digs.
- **Ore = `c:ores` + config names**; `only` restricts to an exact list [6]. No
  fuzzy `find("ore")` fallback. Ancient debris excluded — nether-only.
- **No `--scan` mode** [6]. The `passed over:` line does that job.
- **Fuel: coal, coal blocks, charcoal, lava buckets only** [7].
- **Depot-first, forage only when dry** [7]. Inventory is the trip trigger.
- **A find is shared, not hoarded** [7]: `fuelShare` coal in the hold is a dock
  trigger, and a low tank burns the hold before it costs a trip.
- **A turtle's OWN box is not rationed; a SHARED box is capped per dock**
  [changed 2026-08-29, change 37/38]. **Learned by taking, because a turtle
  cannot read a chest it is not wired to.** At its own depot a turtle takes
  what the trip needs (`want`) and holds nothing back. `fuelFloor` is deleted:
  it reserved `(turtles-1) * 8` coal in a box no other turtle ever opens, and
  that is what stopped both turtles in logs `E5wWw` and `hkgWh` with 16 coal
  one block away. At a shared box the take is capped at `sharePerDock` (16)
  coal in one dock -- a cap divides the box across visits without stranding
  any of it, which is what the floor did. Ownership is `st.depot.own`, tested
  as `~= false`. Tests 110-112. The rule this replaces, and the fraction
  before it, are in the history. Tests 51
  and 52, both confirmed to fail against the old line.
- **Lava map shared on a depot disk drive** [7], read and written while docked.
- **Never dig into a full inventory** [8]. `dig` succeeds and destroys the drop.
- **Never dig a turtle, computer, disk drive, chest, or anything `lootr`** [8].
  In a branch leg that ends the leg; anywhere else it stops the run.
- **Config is a self-seeding data file**, `quarry.conf`, plain format, not Lua
  [9]. Nothing in it may affect the branch pattern. **A config file replaces
  the default lists outright** — a file with no `[blacklist]` section has no
  blacklist. That is deliberate; tests must spell out the lists they need.
- **Save state every block** [10]. Measured at 1.35 ms against a 400 ms move.
- **A modem in a slot is fitted to a side, not reported as missing.**
  `ensureModem()` does it, `locate()` calls it, and `--check` leaves the turtle
  with the modem on. Read the SELECTED slot back before equipping: `equip`
  swaps, so the wrong slot costs the pickaxe.
- **Ask `getEquippedLeft`/`getEquippedRight` for what is on a side, through
  `pcall`, with `peripheral.getType` as the fallback.** `getType` cannot tell a
  tool from an empty side -- a pickaxe is not a peripheral, so both read nil.
  The method is NOT in the peripherals dump: that dump was taken from a
  computer, which has no turtle API, so its absence there is not evidence.
- **"A modem is equipped" was never the right question.** `getType` says
  `"modem"` for a wired one too, and `gps.locate` only ever answers through a
  modem whose `isWireless()` is true. Ask `isWireless`, not `getType`, anywhere
  the answer decides whether GPS can work.
- **GPS does not reach the claim floor, and that is physics, not a fault.**
  A wireless modem's range shrinks with depth; the hosts sit near the surface
  and the mine floor is y=-59, a hundred-odd blocks down. `gps.locate` answering
  where the user is standing says nothing about where the turtle is. Every fix
  a run gets is taken at the launch block before it descends; from there it
  dead-reckons, and `quarry.state` is what a turtle at the floor resumes on.
  Confirmed in-game 2026-08-28 (`td7FE`).
- **GPS is NOT reliable on this server.** It worked on 2026-08-28 morning
  (`--check` reported `position: 8,79,4 (gps)`), was dead that evening --
  `gps.locate` returned nil from turtle 1 with `left=modem` equipped, so no
  host answered -- and was up again that night after the user rebuilt the
  constellation (`45bPE`, `at 243,73,734`). A turtle still reaches GPS only
  through an equipped wireless modem, and the constellation itself cannot be
  assumed up. See `startDir`.
- **Claim exhaustion: stop, report, idle** [12].
- **Deployment happens at the surface launch block, not at the claim floor** —
  a deliberate deviation from plan §13. The drive must sit directly above the
  placed turtle, and the trunk floor is a working row in every direction.
  It costs nothing: every turtle anchors its claim where it wakes, and they all
  wake in the centre chunk.
- **Turtles in turtle 1's hold mean the mine is not staffed**, so a plain
  `quarry 1` deploys them before it descends. `quarry 1 deploy` is kept as the
  explicit form; the run-mode deploy is the same code, once per claim, recorded
  in `quarry.state` before it runs.
- **A full depot is not a reason to stop.** The junk tier goes on the tunnel
  floor and the run carries on; only a hold that still cannot be emptied of ore
  stops it. The player is told over rednet, because emptying the box is the one
  thing the turtle cannot do for itself.
- **Notifications are best effort and always logged.** A wireless modem's range
  shrinks with depth, so a broadcast from y=-59 may reach nobody. `notify()`
  writes the line into the report either way; do not build anything that
  depends on the message arriving.
- **The monitor is Phase 6.**

## The defaults, changed 2026-08-27 at the user's instruction

`quarry.conf` ships **`dry = false`**, **`lava = true`** and **`forageCoal =
true`** (a dry depot climbs to `topY` and mines for coal rather than stopping).
The fuel keys are `fuelKeep = 2000` (a tank LEVEL, what the hold is burnt up to
at a private box), `sharePerDock = 16` (a COAL COUNT, the cap on one dock's
take at a shared box) and `fuelShare = 128` (a coal count in the hold that
sends a turtle home — at a shared box only).

The claim keys are `chunksX = 3` and `chunksZ = 3`, the claim's width and length
in chunks. They are a **fleet-wide** setting like `topY`: every turtle in one
mine must carry the same two values or their branch mouths will not line up.
`deploy` copies the deployer's config to every turtle, which is what makes that
hold by default — an edit made on one turtle by hand does not.

This overrides the old convention that the program is never handed over ready
to mine. `local DRY = true` still opens the file and the config lowers it as it
always did — the change is only to what the seeded config says. It matters more
than it looks: **`deploy` copies that same file to every turtle**, so the old
`dry = true` default is what stranded turtle 2 on the first live run. Test 38
asserts all three so a later edit cannot revert them quietly. Tests that want
a dry run write `dry = true` into the stub config explicitly.

## Corrections already made — do not reintroduce

- 1-high tunnels at 3×3 spacing leave **44% unseen**; 2-high layered 4 apart
  leave **33%**. A tunnel sees `z±1` only at its own `y`.
- The vertical-shaft (`canes`) design is superseded but measures identically.
- **The stagger's 0% unseen is a toroidal figure.** On the real claim it is
  1.16%, all on the claim face. Do not "fix" it.
- **Trunks cost no blocks.** Do not re-add the 360-block line to a cost table.
- `turtle.dig` on a full inventory destroys the drop. Issue #1046, closed
  `invalid`.
- Ancient debris is nether-only.
- Turtles are lavaproof and submersible; `detect()` is false for liquid. All
  liquid-sealing logic was deleted.
- **CC:Tweaked is Lua 5.2 (Cobalt).** No `//`, no bitwise operators. `goto` is
  fine — 5.2 has it, and the work loop uses several.
- **A turtle needs a wireless modem for GPS.**
- **Never derive the claim from the turtle's current position after boot.**
- **`DRY` is not edited in the program.** `dry` in `quarry.conf` is what goes
  live, because the config survives a re-download.
- **Lootr loot is unreachable to a turtle, by both routes.** Do not add a
  `turtle.suck` at a Lootr container, and do not add a config switch to dig
  them: the break is cancelled server-side, and `should_drop_player_loot` is
  false by default, so a break that did land would destroy the loot.
- **"Burn on pickup, carry no fuel items" is about depot coal, not mined coal
  — but only where the depot is SHARED.** At a shared box, coal dug on a branch
  rides home unburnt; do not add a burn-it-where-you-find-it rule there, that
  is the hoarding the sharing rule exists to stop. **At a turtle's own box the
  rule is reversed** [change 35, 2026-08-29, confirmed with the user]: with one
  depot per turtle there is nobody to hoard from, and coal banked in a box only
  that turtle opens is what stranded two turtles. `keepFuel` burns the hold up
  to `fuelKeep` at every leg end and dock, at a private depot only.
- **A depot chest beside the trunk floor stands on a branch row.** The trunk is
  on the spine, so all four of the floor's neighbours are spine or branch, and
  a container on any of them costs a leg or the spine. This program no longer
  builds there — under the floor first, an x-side niche a level up when bedrock
  blocks that — but a hand-placed one is still honoured and still in the way.
  Do not redesign the geometry for it; do remember `goTo` must leave a spine
  block along z, or it walks into that chest.
- **Do not sweep the spine for the shared depot on boot.** It costs ~70 dug
  blocks every boot on a claim that has no chest. It waits until the depot is
  needed.
- **`os.getComputerLabel()` returns NO values on an unlabelled computer**, not
  nil. `tostring(os.getComputerLabel())` throws `bad argument #1 to 'tostring'
  (value expected)`. A local or a parameter collapses a zero-return to nil; an
  argument list does not. A placed turtle is always unlabelled.
- **A placed turtle IS visible as a peripheral on `front`** — but discovery
  goes stale (CC:Tweaked #660), so it reads as air right after `turtle.place`.
  `deploy` retries six times with a `turnRight`+`turnLeft` between attempts to
  force a refresh. **That pair is the spinning the user sees; it is cosmetic.**
  An earlier note here said a turtle is not a peripheral to another turtle —
  that was the probe looking from a position it had already left, and it cost
  three deploy runs.
- **On a turtle, `left` and `right` report the EQUIPPED upgrade, not the
  adjacent block.** So `front` is the valid way to see a placed turtle. The
  peripheral dump in the skill's references was taken from a COMPUTER
  (`turtle=false`) and never described what a turtle sees.
- **`pcall` prepends its own success flag.** Two locals binds `data` to a
  boolean. This has now been got wrong **five** times, in `checkLava`,
  `deployOne`, `buildDepot`, `turtleAhead` and `giveWay`. Capture both values
  and test the second against `false` explicitly — and remember a *failed*
  `pcall` puts an error STRING second, which is not `false`, and is not empty,
  so every guard of the form `type(x) == "string"` waves it through and the
  error text gets printed as if it were the answer. **There is now one door:
  `periph(fn, ...)`, beside `equippedItem`, which returns nil when the call did
  not live.** Use it for every `peripheral.*` read; `frontAsk` inside
  `runDeploy` is the same idea kept local because it wants the error text for
  its log. Tests 41, 44, 46, 136.
- **`st.chased` is a per-chase counter, not a run total.** Reset it where a
  chase begins, never where a run begins, or `veinMax` silently switches off
  all vein chasing for the rest of the shift. `st.veined` is the run total.
  Test 40.
- **An empty tank is not a wall.** `turtle.forward()` returns false either way,
  so any move path with no fuel check reports the wrong thing — and with `halt`
  unset, `report` calls a stranded turtle finished. The guard lives at the top
  of `clear()`, which every stepper routes through; do not move it into one
  caller. Test 42.
- **The vein sweep must be absolute.** `goTo` faces the direction it travels,
  so `st.dir` after a chase is the walk home's heading, not the cell's. Anchor
  the four-way sweep to a `d0` captured on entry. Test 43.
- **A deploy is resumable, and `st.staffed` is the record.** Do not go back to
  looping from 2 unconditionally: with turtle 2 already out, that places the
  next turtle item as a SECOND quarry 2. `deployed` is a dead name from the
  abandoned one-shot flag; do not reuse it.
- **Adoption is for a turtle a PREVIOUS run stranded, never one this run just
  stranded.** `deployOne` treats a turtle standing in the placement spot as
  itself, already placed. Inside the loop that means a turtle that failed to
  boot gets adopted as the next index and fed a second kit, and the boot script
  on the floppy is rewritten under the wrong number. The loop now stops when a
  failed `deployOne` leaves a turtle standing there. Test 92.
- **Probe for the shared depot in both directions.** Bedrock scatters over four
  blocks either way, so a neighbour's floor can be below this turtle's, not
  only above. Test 47.

## This pack's real ids, settled in-game

`computercraft:turtle_advanced`, `computercraft:disk_drive`,
`computercraft:disk`, `computercraft:wireless_modem_advanced`. All four already
match the kit audit's patterns; nothing is hard-coded and nothing needs to be.

**The turtles are advanced *and* mining** — both share
`computercraft:turtle_advanced`, so no audit can tell them apart. Do not add a
check for it.

**`inspect` returns a `tags` table on this server**, so `c:ores` works and
quarry prints no `WARNING:`. **A placed turtle inherits nothing**: fuel 0, no
label, no modem, empty inventory. **Facing does not matter** — `calibrate()`
derives a heading by moving one block and diffing GPS.

## Conventions that govern the code

One self-contained file, no `require`, delivered as a single `wget` from the
GitHub repo. Opens `local DRY = true`; `quarry.conf` may lower it and may never
raise it. Persist state every meaningful step. `pcall` every peripheral call —
and remember it prepends its own success flag. Test under `lua5.3` before
delivering; `test_quarry.lua` is the stubbed world to extend, not replace.
**When you fix a bug, add a test and verify it FAILS against the unfixed
code.** A test that passes against the bug asserts nothing — usually its world
never reaches the path, or the string it greps for appears anyway. Eighteen
tests here have been confirmed non-vacuous that way; it costs a minute. Diagnostics go *in* the program so one in-game run answers
the question instead of three. Print a liveness line before any long work.
CC:Tweaked is Lua 5.2. The peripheral dump in
`~/.claude/skills/cc-tweaked-pack/references/` outranks the wiki, but read its
headers — it was taken from a computer; if a method is not in it, ask for a
re-survey rather than guessing. **Mod behaviour is read out of the mod's own
jar and config when they are on disk** (`unzip`, `javap -c`, `config/*.toml`) —
that is how the Lootr answer was settled. No CC:Tweaked jar is in this sandbox,
so CC mod-side behaviour comes from tweaked.cc or from the user.

## Standing rules from the user

- **Work must survive their budget running out.** Write deliverables and
  handoff updates to disk as you go, never only in chat. Rewrite this file
  whole at the end of every phase.
- **Test under lua5.3 here before anything reaches their server.** They run the
  code and you never see the game, so a bug that ships costs a round trip.
- **Ask before reverting or deleting anything.** This directory became a git
  repository on 2026-08-28, so there is an undo now — but the rule stands. Ask,
  then revert deliberately with git rather than by hand.
- **How the sessions actually go:** the user pastes the id of an in-game log —
  the program POSTs its own report to paste.rs and prints the id — and little
  else. Fetch it, read it as the primary evidence, and put the
  diagnostic INTO the program so the next single run answers the question. Five
  deploy runs were spent on a chain of separate bugs, each hidden behind the
  last. Do not theorise past the evidence — when a log cannot distinguish two
  causes, add the line that will, and say so.

## Open questions

None on the design, and none blocking. What is left is verification: the depot
cycle, two turtles at once, and the two changes in the last build.
