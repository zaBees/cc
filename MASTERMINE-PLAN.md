# quarry.lua — settled design

> Session handoff is `RESUME.md`; read it first. This is the terse design
> reference — the rules and numbers the code obeys. The reasoning behind any of
> them, the rejected alternatives, and the phase-by-phase discovery are in
> `reports/history-2026-08.md` (do not read unless chasing a regression).

Three turtles work a chunk-snapped claim, read every block, haul ore to an
underground depot, restock their own coal, and survive being killed at any step.

## 1. Source

Harvested from `merlinlikethewizard/Mastermine`, not ported. Taken: ore-vein
flood fill with a hard cap, memoised six-face scan, gravity-block pass,
dump-with-omit-list, pre-departure fuel budgeting. Left: the GPS hub, monitor
UI, pocket computer, `require` tree, chunky-turtle pairing, the linked-list
depot queue. `forge:ores` → **`c:ores`** on 1.21.1.

## 2. The claim

- Chunk-snapped: `chunksX`×`chunksZ` chunks centred on the start chunk, **3×3
  (48×48) default**. No chunk loader — the player in the centre chunk holds the
  claim's chunks open; a bigger claim needs a real loader and every chunk loaded.
- **Anchored to the claim corner and absolute y, never to a turtle's start
  block or a config value.** Derived from `st.home`, the launch block, and
  persisted. Every turtle in the same region agrees with no coordination.
- `chunksX`/`chunksZ` are **fleet-wide** — every turtle must carry the same two
  or branch mouths will not line up. `deploy` copies the deployer's config to all.
- Placement does not matter: put all three turtles anywhere in the centre chunk.

## 3. Geometry

Branches run along **x**; spines run along **z**; the pattern lives in the
`(y,z)` cross-section. A branch is sunk wherever:

```
z ≡ 2y  (mod 5)      measured from the claim corner
```

First branch per level going up: `1,3,5,2,4` (the user's sequence). A 1-high
branch digs 1 cell and sees 5 (own, `y±1`, `z±1` at its level) — 20% is the hard
floor for full coverage with 1-wide passages, and the mod-5 stagger sits on it.

| Scheme | Dug | Unseen |
| --- | --- | --- |
| 1-high, spacing 3×3 | 11.2% | 44.22% |
| **1-high, mod-5 stagger** | **20.0%** | **0.00%** |
| 2-high, spacing 2z×4y | 25.0% | 25.00% |
| vertical shafts, mod-5 | 20.0% | 0.00% |

(0% unseen is toroidal; on the real claim ~1.16%, all on the claim face — do not
"fix" it. `test_coverage.lua` measures these.)

**Layout:** branches 1-high 1-wide along x, running **24 west, 23 east** of the
spine. Spine along z at the claim's x-centre, branch mouths every 5 blocks. One
vertical trunk per turtle at the centre of its third, sitting on the spine — so
trunks cost **no extra blocks**. **Top y=60, bottom one level above bedrock**
(descend until `digDown` fails on `minecraft:bedrock`; `bottomY=-59` is the
safety floor). **Deepest first, working up.** All bounds configurable.

Whole-claim estimate: ~60,200 dug (21.8%), ~350,000 fuel (~4,400 coal),
largely self-funding from coal ore and lava. `--check` reports the real figure.

## 4. Three turtles

All three work the same level, splitting the z-range into three contiguous
thirds, each with its own trunk. **A branch mouth that is already air is already
taken** — no protocol; a turtle prefers its own third, else takes the nearest
unmined mouth. Index is a launch arg (`quarry 1/2/3`). Returns are independent;
`recall` is a typed command that brings all three to the surface station.

## 5. The depot

**One box per turtle, at the claim floor UNDER its own trunk.** A surface depot
would cost ~240,000 fuel in commuting; the bottom depot roughly halves it.
Under the floor because every side of a trunk floor block is a working row a
container would block; bedrock usually blocks the block below, so the fallback
is a niche beside the trunk one level up. Spoil in and fuel out of the same box.
Never configured — found by looking, and only when a depot is actually needed
(sweeping on boot costs ~70 dug blocks on a claim with no chest). **A full depot
does not stop the run:** the junk tier goes on the tunnel floor and the run
carries on; only an un-emptiable hold of ore stops it. Broadcast on rednet
`quarry`; `alert.lua` prints it.

## 6. Items

Haul everything, no routine voiding — slot pressure is block *type*, ~1–2
branches per trip. **Blacklisted blocks are a junk tier**: dug, carried, **never
chased**, first dumped when a slot is needed, and **not ore even if the pack
tags them into `c:ores`** [2026-08-31]. Ore is `oreTags` (`c:ores`) plus
`oreNames`; `only`, when set, overrides both (and outranks the blacklist).
Mastermine's `name:find("ore")` fuzzy fallback is dropped. A rejected block
whose name/tags contain "ore" is logged and posted with the report — that is how
the config learns the pack's names, without a `--scan` run.

## 7. Fuel

Accepted: coal, coal blocks, charcoal, lava buckets. Tank holds ≥20,000 (asked,
not assumed); a branch trip is ~232 moves, so a topped turtle carries ~80
branches and docks on the *inventory* filling first. **Fuel is never the reason
for a trip in the normal loop; foraging is the dry-depot fallback.**

- **Burn on pickup, carry no fuel items — at a turtle's OWN box only.** `keepFuel`
  burns the hold up to `fuelKeep` (2000) at every leg end and dock. At a shared
  box coal rides home unburnt (do not burn-where-found there — that is the
  hoarding the sharing rule stops).
- **Shared box:** `sharePerDock` (16) caps one dock's take; `fuelShare` (128 in
  hold) is a dock trigger so a coal strike is banked, not carried around. A low
  tank burns the least coal aboard that clears the bar before it burns a trip.
- **Forage (`forageCoal`), when the depot is dry:** nearest recorded lava source
  if reachable (~1000 fuel each), else climb to the top level and mine a real
  branch for coal (coal is y=0–192, none below, and those upper levels are
  unmined on the schedule anyway — foraging is productive), else park. Foraging
  starts at `topY` and works down; nothing below y=0 counts. A level change
  happens in the turtle's own trunk column (air already), never mid-branch.
- **Never strand:** a return reserve `(distance to depot + margin)` is recomputed
  before every step deeper; the turtle refuses new work below it and parks safely.
- **Lava:** turtles are lavaproof and submersible, `detect()` is false for
  liquid — no sealing logic. An empty bucket scoops a lava **source** with
  `place` (flowing cannot be bucketed). Confirmed 2026-08-27; ships `lava=true`.
- **Lava map** is shared over rednet (`quarrylava`): a find is broadcast, a scoop
  broadcast as `gone`; a listener coroutine under `parallel.waitForAny` drains
  it (the drive/floppy stay at the surface, unreachable at the floor). A turtle
  arriving at a consumed source checks the four neighbours before pruning.

## 8. Safety rules — not optional, not configurable

- **Never dig into a full inventory** — `turtle.dig` destroys the drop (#1046,
  closed invalid). Check a free slot before every dig; dump junk; else stop.
- **Never dig a turtle, computer, drive or chest** — `inspect()` against a hard
  deny list. A destroyed turtle drops its whole inventory.
- **Lootr containers are an obstruction, not loot** — a turtle can neither break
  one (break event cancelled server-side) nor take from one (`getSlotsForFace`
  empty, no item-handler capability). `lootr` is a namespace match on the deny
  list; hitting one ends that leg and returns to the spine, printing a
  `left alone:` line with coordinates. Several per branch is normal.
- **Right of way is by launch index** — lower wins and holds the corridor, higher
  reverses along the spine to a branch mouth (`stepAside`, `RETREAT_MAX`) and
  waits, index-scaled retries. On repeated failure it re-picks a branch. This
  covers the two cases that break one-turtle-per-corridor: foraging and cross-
  third helping. A jam that exhausts retries sets `halt` and names the blocker.

## 9. Configuration

A data file (`quarry.conf`), not code — plain `name = value` plus block names
under section headers, deliberately not Lua so a typo prints a line, not a crash.
Written on first run if absent, seeded once, never overwritten, survives updates.
Holds ore tags/names/`only`/blacklist, height bounds and direction, turtle count,
`chunksX`/`chunksZ`, vein cap, the fuel keys, `gpsChannel`, and `dry`. **The
program opens `local DRY = true`; the config may only lower it, never raise it**
— a fresh `wget` can never arm an actuator. Ships `dry=false`, `lava=true`,
`forageCoal=true`. `gpsChannel=0` (off) selects the private GPS constellation
(`pgps.lua`) when set — asked before public GPS on 65534.

## 10. State and resume

**Save every block** — movement is throttled to 0.4s, an `fs` write is sub-ms
and does not yield, so per-block saving is free. Overwritten, never appended.
Carries the **task** (level, branch, direction, mode), the **absolute position
and heading** (dead reckoning between GPS fixes makes a mid-branch kill
recoverable), and the **launch block the claim was derived from** — a turtle
resuming 18 blocks along a branch often stands in a neighbouring chunk, and
re-deriving the claim there would mine the wrong 48×48. A turtle that boots
outside its saved anchor's claim has been carried, and drops the old anchor.
GPS does not reach the claim floor (range shrinks with depth) — every fix is
taken at the surface launch block; below that the turtle dead-reckons.

## 11. Phases

Phases 1–5 built and run in-game; boot, placing and mining confirmed working.
Phase 6 (off-turtle monitor + pocket client, plus a small turtle-side heartbeat
and gated remote recall/locate) deferred, unstarted; full-clear cut. See RESUME.

| Phase | Scope |
| --- | --- |
| 1 | Claim maths, branch/spine iterators, `--check`, kit audit |
| 2 | One turtle, one branch: trunk descent, spine travel, vein chase, resume |
| 3 | Depot cycle and fuel: dump, ration, restock, lava, foraging, work loop |
| 4 | Three turtles: air-mouth claiming, right of way, shared depot, `recall` |
| 5 | Deployment: probe, `buildDepot`, turtles placed at the launch block |
| 6 | Deferred: off-turtle monitor + pocket client, turtle-side heartbeat + gated remote recall/locate (full-clear cut) |

## 12. Deployment (built, settled in-game)

The user drops the kit into turtle 1 and runs `quarry 1`; it audits, then builds
the mine at the **surface launch block** (drive one up and in front, turtle
placed directly below it so the drive mounts as `/disk`). A turtle exposes only
`reboot/getLabel/turnOn/isOn/getID/shutdown` to another — so code is handed over
by the **floppy bootstrap**: write the boot files + program + config to the
floppy, place the turtle under the drive, `turtle.drop` its modem/coal/bucket,
and it boots itself, installs, labels, equips and launches `quarry N`. A placed
turtle IS a peripheral on `front` but discovery goes stale (#660) — `deploy`
forces a refresh with a turn (the cosmetic spinning). Kit: 2 turtles, 1 box per
turtle, 1 drive, 1 floppy, 3 buckets, coal split evenly across all turtles. Ids
matched by pattern, not hard-coded. `quarry stop` parks a turtle for relocation.
