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
