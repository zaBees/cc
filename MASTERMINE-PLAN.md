# quarry.lua — settled design

> Session handoff is `RESUME.md`. Read it first.
>
> This document was rewritten on 2026-08-24 after a full design interview. The
> geometry it describes — horizontal branches off per-turtle spines — replaces
> the vertical-shaft design in earlier revisions. Every decision below was put
> to the user and answered; nothing here is assumed.

Target: three turtles working a **3×3 chunk claim** (48×48) with no chunk
loader, reading every block in it, hauling ore to an underground depot,
restocking their own coal, and surviving being killed at any instruction.

---

## 1. Harvest Mastermine, do not port it

`merlinlikethewizard/Mastermine` is 3,510 lines. About 300 are worth having.

**Taken:**

| Idea | Upstream location |
| --- | --- |
| Ore-vein flood fill with a hard cap | `turtle_files/actions.lua:726` `mine_vein` |
| Six-face inspection, memoised so a block is checked once | `turtle_files/actions.lua:640` `scan` |
| Gravity-block handling as an explicit pass | `turtle_files/actions.lua:767` |
| Dump-with-omit-list, so fuel is never dumped | `turtle_files/actions.lua:460` `dump_items` |
| Fuel budgeting before departure | `hub_files/whosmineisitanyway.lua:189` |

**Left behind:** the GPS-dependent hub, the monitor UI (937 lines), the pocket
computer, the floppy-disk `require` tree, and chunky-turtle pairing — the pack
has no Advanced Peripherals. **The linked-list queue past the drop and fuel
chests** (`hub_files/config.lua` `main_loop_route`) was on the list to take and
then was not built: it is for a hub with a monitor and any number of turtles,
and three turtles at one box just wait. See section 5.

**Broken on NeoForge 1.21.1:** `blocktags` keys `forge:ores`, which is now
**`c:ores`**; `orenames` is a 1.12/1.16 mod list; `mine_levels` and the level
geometry predate 1.18 world heights.

`tunnel.lua` in this directory already implements DRY mode, a resume-safe state
file, fuel top-up, ore detection, vein following and go-home — in one file,
under the pack conventions. It is the base to build on.

---

## 2. The claim, and why it needs no chunk loader

CC:Tweaked does not chunk-load, and no mod in this pack gives a turtle one.

A player standing in the centre chunk keeps all nine loaded. So the claim is
**snapped to chunk borders** — `cx = floor(x/16)`, spanning `(cx-1)*16` through
`(cx+1)*16+15` on each axis, 48 blocks per side — and every turtle stays inside
it for its entire trip. Nothing ever walks out of the loaded region.

The claim is snapped to chunks, and **the pattern is anchored to the claim's
own corner** — `zMin`, and absolute `y`. Neither term comes from `quarry.conf`.

*Amended 2026-08-24.* This section previously anchored the pattern to the
turtle's start block, calling the two-anchor split "fine, and costs nothing".
It costs a great deal once there is more than one turtle: three turtles
starting on three different blocks compute three different patterns, their
branch mouths never line up, and the air-mouth claiming protocol of section 4
cannot work. Keying the anchor to a config value fails the same way the moment
one turtle's `quarry.conf` drifts from another's. Deriving it from the claim
corner makes every turtle in the same 3×3 chunk region agree with no
coordination at all — **and it means placement no longer matters: put all three
turtles anywhere inside the centre chunk.**

`--check` prints the pattern sampled at a fixed `y=0..9` rather than at
`bottomY`, so the line is a stable fingerprint: two turtles printing the same
claim corners and the same fingerprint are provably mining the same grid.

When you walk away the turtles freeze mid-instruction. The state file makes
that harmless: they resume from the last saved step.

---

## 3. Geometry — horizontal branches on a mod-5 cross-section

Branches run along **x**. Spines run along **z**. The cross-section
perpendicular to a branch is therefore the `(y, z)` plane, and that is where
the pattern lives.

A branch is sunk wherever

```
z ≡ 2y  (mod 5)
```

Reading the first branch position on each level going up gives
`1, 3, 5, 2, 4, 1, 3, 5, 2, 4` — the sequence the user specified, with each
level shifted two along z from the one below.

### Why this is optimal, measured not assumed

A 1-high branch at `(y, z)` digs one cross-section cell and *sees* five: its
own, `y±1` in its own column, and `z±1` at its own level. Five cells covered
per cell dug is the ceiling, so **20% is the hard floor for any full-coverage
scheme with 1-wide passages.** The mod-5 stagger tiles those plus-shapes
perfectly and sits exactly on the floor.

`test_coverage.lua` measures the alternatives:

| Scheme | Dug | Unseen |
| --- | --- | --- |
| 1-high, spacing 3×3 | 11.2% | **44.22%** |
| **1-high, mod-5 stagger** | **20.0%** | **0.00%** |
| 2-high, spacing 3z × 4y | 16.8% | **33.25%** |
| 2-high, spacing 2z × 4y | 25.0% | **25.00%** |
| 2-high, mod-8 stagger | 25.0% | 0.00% |
| vertical shafts, mod-5 | 20.0% | 0.00% |

Two earlier revisions of this plan were wrong here and the corrections matter:

1. It claimed 1-high tunnels at 3×3 spacing read 100% for 11%. They leave
   **44% unseen**. The error was assuming a tunnel sees its side neighbours at
   every level it covers — it does not. It sees `z±1` only at its own `y`.
2. It treated "stack layers 4 apart" as a saving. With 2-high tunnels that
   leaves **33% unseen**. Layer spacing cannot be chosen independently of the
   horizontal stagger; the mod-5 tiling fixes both at once.

### Layout

- **Branches**: 1-high, 1-wide, running along x. The spine sits at the claim's
  x-centre, so each branch runs **24 blocks each way**, 48 total. Halving the
  branch length halves the worst-case walk back when a turtle fills up
  mid-branch.
- **Spine**: runs along z at the claim's x-centre, one per level. Branch mouths
  open off it every 5 blocks.
- **Trunks**: **one per turtle**, vertical, sited at the centre of that
  turtle's third of the claim. Three trunks cost 360 blocks — 0.6% of the
  claim — and in exchange no two turtles ever occupy the same corridor.
- **Levels**: every `y` from one above bedrock up to the cap. Both bounds are
  configurable.

### Bounds

- **Top: y = 60**, so surface builds survive. Configurable.
- **Bottom: one level above bedrock.** Bedrock is solid at y=-64 and scattered
  through -63..-60, so a fixed floor either wastes depth or drives the turtle
  into a block it cannot dig. Descend until `digDown()` fails on a block
  `inspectDown` names `minecraft:bedrock`, and stop. `bottomY` is a
  configurable safety floor, not the primary rule.
- **Order: deepest first, working up.** Diamond and redstone peak at y=-59,
  gold at -16, lapis at 0, iron at 15, copper at 48. Monotonic, nothing to get
  wrong, and stopping early loses only the cheapest levels. Direction and
  height range are both configurable.

### Cost

| | |
| --- | --- |
| Volume | 48 × 48 × 120 = 276,480 |
| Branches | ~1,152 (about 10 per level, 120 levels) |
| Blocks dug — branches | ~55,300 |
| Blocks dug — spines | ~4,560 |
| Blocks dug — trunks | 360 |
| **Total dug** | **~60,200 (21.8%)** |
| Coverage | **100%** |
| Estimated fuel, whole claim | **~350,000 (~4,400 coal)** |

The fuel figure is large and largely self-funding: coal ore is abundant through
the upper two thirds of the claim, and lava scooped at depth is worth 1,000
each. `--check` reports the real figure for your claim rather than this
estimate.

---

## 4. Three turtles

All three work **the same level**, splitting the claim's z-range into three
contiguous 16-block thirds. Each has its own trunk at the centre of its third,
so the only shared space is the depot corridor.

**Claiming a branch needs no protocol: a branch mouth that is already air is
already taken.** A turtle prefers its own third; when that is clear it walks to
the nearest unmined mouth anywhere on the level and takes it. Checking costs one
`inspect` per mouth, every 5 blocks of spine. The level advances when no unmined
mouths remain.

Two turtles can in principle claim one branch simultaneously. The cost is one
duplicated branch, not a failure. No rednet, no disk, no hub, no barrier.

Turtle index is a launch argument — `quarry 1`, `quarry 2`, `quarry 3`.

**Returns are independent; recall is collective.** A turtle that fills up goes
to the depot alone and rejoins the queue. `recall` is a command you type: it
brings all three to the surface station and parks them, for logging off or
moving the claim. Tying normal returns to the group would idle two turtles every
time one filled.

---

## 5. The depot

**At the claim floor, UNDER a trunk.** Turtles never surface during normal
operation.

A surface depot would cost roughly **240,000 fuel — about 3,000 coal — in
commuting alone** across ~1,200 branch trips, and deepest-first ordering puts
most of the work at the far end of that climb. The bottom depot roughly halves
it. `recall` is how you collect and restock.

**One box, not two, and under the floor rather than beside it.** Every side of
a trunk floor block is a working row — the branch legs run east–west through
them, the spine north–south — so a container on a side is a block the pattern
later walks into and refuses to dig, which ends that leg and then the run.
Underneath is the one neighbour nothing ever mines. Bedrock scatters up through
y=-60 and the floor stands at y=-59, so the block below usually will not open;
the fallback is a niche beside the trunk one level UP. Spoil goes in and fuel
comes out of the same box, which is what the ration is written for.

**Found by looking, never configured.** One depot serves all three turtles: a
turtle with none under its own trunk walks the spine to the others, once, and
remembers the answer either way. It is never swept for on boot — that costs ~70
dug blocks on a claim that has no container — only when a depot is actually
needed.

**A full depot does not stop the run.** What fills one is the junk tier, so a
drop the depot refuses goes on the tunnel floor instead and the run carries on;
a hold that still cannot be emptied of ore does stop it, because mining on
would only destroy the drops. Either way the turtle broadcasts it on the rednet
protocol `quarry`, which `alert.lua` prints on a computer — best effort, since
a modem's range shrinks with depth.

Mastermine's linked-list queue is **not** built: it was for a hub with a
monitor and any number of turtles. Three turtles at one box wait, and waiting is
the whole queue.

---

## 6. Items

**Haul everything. No routine voiding.** A branch yields ~48 blocks, and slot
pressure comes from block *type*, not count — stone, deepslate, tuff, granite,
diorite, andesite, dirt, gravel each claim a slot. That is one to two branches
per trip, which is workable without throwing anything away.

**Blacklisted blocks are a junk tier**, not a skip list — a turtle cannot
decline to pick up what it digs. They are dug, carried, never trigger a vein
chase, and are **the first thing dumped when a slot is needed**. Cobblestone
lives in the blacklist rather than being special-cased in code.

**Ore is `c:ores` plus whatever the config names.** Mastermine's
`name:find("ore")` fuzzy fallback is dropped — it is what makes a turtle chase
things you did not mean. Three knobs: `oreTags` (default `c:ores`), `oreNames`
(additive), and `only` (when set, overrides both and mines exactly that list).

Ancient debris is **not** in the config: it is nether-only and this is an
overworld claim.

**Finding what this pack calls things, without a scan run.** A dedicated `--scan`
mode was proposed and rejected — a turtle in a fresh shaft sees four stone faces
and learns nothing. Instead the turtle logs any block it *rejected* whose name
or tags contain "ore", and posts that list to paste.rs with its status report.
Costs nothing, and after one session you have a real list to add to the config.

---

## 7. Fuel

Accepted: **coal, coal blocks, charcoal, lava buckets.** Nothing else.

### The tank changes the shape of this

A normal turtle's fuel tank holds **20,000**, and a branch trip costs roughly
232 moves. A turtle topped up at the depot therefore carries about **80
branches** of fuel, and it already docks every one or two branches because the
*inventory* fills first.

So fuel never runs low in the normal loop, and foraging is a **fallback for
when the depot runs dry**, not the primary supply. This is why the fuel system
is forty lines rather than a scheduler.

### Normal loop

Top the tank on each depot visit to `(reserve + next branch estimate) × 4`,
rounded up to whole items and capped at the tank. **Burn on pickup; carry no
fuel items** — a coal in a slot is a slot not holding ore, and the tank is
never the constraint. Coal beyond the target stays in the chest.

**Ration the depot by a FLOOR, not a fraction**: a turtle takes what the trip
needs, down to `fuelFloor` coal per OTHER turtle (default 8, so 16 with three
running), and takes nothing at all below that — which drops it into the
designed forage path. A turtle cannot read a chest it is not wired to, so the
count is learned by taking: pull the lot, keep the share, put the rest straight
back. The original `available ÷ 3` made the shares unequal — on 300 coal three
dockers took 100, then 66, then 44, each taking a third of what the last one
left, and 90 sat there for good.

Coal and the lava bucket are exempt from dumping and from the blacklist
overflow valve, or the turtle throws away its own fuel supply.

### Sharing a find

Coal mined on a branch is nobody's private supply. It rides in the hold to the
depot, where the ration puts back everything the turtle does not burn, so a
strike on one branch ends up in the chest the other two draw from. Two rules
make that reliable:

- **`fuelShare` (128 coal) is a third dock trigger**, beside a full hold and
  `tripBlocks`. A turtle sitting on a seam's worth of coal walks it home rather
  than carrying it around for another eighty branches.
- **A low tank burns the hold before it burns a trip.** Every place that judges
  the tank low — the reserve check in a leg, the branch-cost gate in the work
  loop — burns the least coal aboard that clears the bar first. Before this, a
  turtle could stop with "out of fuel" while carrying three stacks of it.

The two do not fight: the burn takes the minimum, and the surplus is what goes
in the chest. A rich turtle banks its find; a poor one eats it, which is also
the right answer.

### Foraging, when the depot is dry

Priority order:

1. **Nearest recorded lava source**, if reachable within current fuel plus
   margin. About 1,000 fuel per source, against coal's 80.
2. **A top-level branch.** Coal generates y=0–192, peaking at 96, so within
   this claim it exists only from y=0 up and there is essentially none below.
   Deepest-first ordering means those upper levels are *still unmined and on
   the schedule anyway* — so the turtle goes and mines a real branch up there,
   keeps the coal, and that branch is permanently done. Foraging is productive
   work, not a detour.
3. **Park at the depot**, status posted, idle.

The turtle saves its assigned branch position before leaving and resumes it
afterwards. That is the existing resume machinery; foraging adds no new state.

### Never strand

The **return reserve** is recomputed before every step deeper as
`(distance to depot + margin)`, and the turtle refuses to start new work while
below it. That is what makes case 3 a park rather than a strand: it stops while
it still has the fuel to stop safely. A turtle stranded at the claim floor is a
manual rescue, and it only has to happen once for you to stop trusting the
program.

### Lava

Turtles are **lavaproof and submersible**, and `detect()` returns false for
liquid, so movement into it is never blocked. **Liquid needs no handling at
all** — the sealing logic from earlier revisions is deleted.

A turtle with an empty bucket collects a lava **source** with `place`. Flowing
lava cannot be bucketed, so only sources are worth recording. One bucket, one
permanent slot.

This was gated behind a `--check` that scoops one source and confirms the fuel
rose and the bucket came back, because
[issue #530](https://github.com/cc-tweaked/CC-Tweaked/issues/530) had lava
buckets deleted on `placeDown()` in 1.16.1. **The check was run on this server
on 2026-08-27 and passed**, so the gate is lifted: `quarry.conf` ships
`lava = true`.

### The lava map

**Shared, on a disk drive at the depot** — one block you place. Written and read
only while docked, so there is no mid-branch coordination and no protocol: a
turtle appends what it found when it dumps, and reads the map when it leaves.

One line per source, `x,y,z`, marked consumed when scooped. A scooped source
becomes air, so entries go stale — but lakes cluster, so a turtle arriving at a
consumed position checks the four neighbours before pruning the entry. Plain
text, readable in-game with `edit`.

---

## 8. Safety rules

These are not optimisations and they are not configurable.

**Never dig into a full inventory.** `turtle.dig` on a full inventory succeeds,
returns `true`, and **destroys the drop**. This is expected behaviour, not a
bug — [issue #1046](https://github.com/cc-tweaked/CC-Tweaked/issues/1046)
reporting it was closed `invalid` — and it is why Mastermine caps `vein_max`,
its config noting that turtles "continue on a vein even when their inventory
fills up". Check for a free slot before *every* dig; if there is none, dump
blacklist junk to make room; if there is still none, stop digging and return.

**Never dig a turtle, computer, disk drive or chest.** `inspect()` before every
dig and match the name against a hard deny list. A destroyed turtle drops its
entire inventory on the floor. Mastermine's `dig_disallow` lists `computer` for
exactly this reason. The guard costs nothing even if turtles turn out not to be
diggable.

**Lootr containers are an obstruction, not loot, and they end a leg rather than
the run.** The pack ships Lootr, which replaces every generated loot container
with its own block — `lootr:lootr_chest`, `lootr:lootr_trapped_chest`,
`lootr:lootr_barrel`, `lootr:lootr_shulker`, `lootr:lootr_inventory`,
`lootr:decorated_pot`, `lootr:suspicious_sand`, `lootr:suspicious_gravel` — and
with `convert_mineshafts = true` it turns mineshaft chest minecarts into
`lootr:lootr_chest` blocks, so branches at mining depth will meet them. Two
facts, both read out of `lootr-neoforge-1.21.1` itself rather than assumed:

- **A turtle cannot break one.** `HandleBreak.onBlockBreak` cancels the break
  event for any player in the `lootr:containers` tag who is not sneaking, and a
  turtle's fake player never sneaks. `enable_break` and
  `enable_fake_player_break` are both `false` by default, which is what
  `canDestroyOrBreak` needs to return true. `turtle.dig` simply fails.
- **A turtle cannot take from one.** Every Lootr block entity implements
  `ILootrWorldlyContainer`, whose `getSlotsForFace` returns an empty array and
  whose `canTakeItemThroughFace` returns `false` for every face, and the mod
  registers no item-handler capability. `turtle.suck`, hoppers and pipes all
  get nothing. The loot is per-player and is generated when a player opens it.

So the deny list carries `lootr` as a namespace match, and hitting one **ends
that leg and returns to the spine** instead of halting the run — several per
branch is normal. The report prints a `left alone:` line with the block name
and coordinates, which is how the user learns where to go and open them by
hand. `should_drop_player_loot = false` is the default, so a break that did
succeed would destroy the loot outright; refusing is the only correct answer.

**Right of way is by launch index.** Two turtles meeting in a 1-wide corridor
is a deadlock, not a death, once the guard above is in place — both blocked,
both waiting. The **lower index wins; the higher backs off to the nearest
branch mouth** and waits. Deterministic, terminates, needs no shared state, and
the branch mouths every 5 blocks along the spine are already natural passing
bays. Random backoff can livelock; level reservation cannot work when turtles
only write to the map at the depot. Cap the retries — on repeated failure the
turtle returns to the depot and re-picks a branch, because a wasted trip beats
a stuck turtle.

This matters because **foraging and cross-third helping both break the
one-turtle-per-corridor invariant** that section 4 otherwise relies on. Under
normal operation turtles never share a corridor; those two cases are the
exceptions, and this is what covers them.

---

## 9. Configuration

A **data file, not a code module.** `quarry.lua` writes `quarry.conf` itself on
first run if absent, then reads it at every start. Delivery stays a single
`wget`; you edit it in-game with `edit quarry.conf`; it survives program
updates. Format is plain `name = value` plus bare block names under section
headers — deliberately not Lua, so a typo prints a line number instead of
crashing the miner.

Holds: ore tags, ore names, the `only` restrict list, the blacklist, height
bounds and direction, turtle count, vein cap, fuel reserve margin, and the
accepted-fuel list.

*Amended 2026-08-25.* It also holds **`dry`**. The program still opens
`local DRY = true` and the config can only lower it, never raise it — so a
fresh `wget` can never arm an actuator. The reason it lives here at all is that
delivery replaces the program file on every update, which would otherwise make
the user re-edit the same line after every single delivery, in an in-game text
editor. The config is seeded once and never overwritten, so the operator's
decision survives. `dry` does not touch the branch pattern, so the rule that
nothing in this file may move the grid still holds.

*Amended 2026-08-27 at the user's instruction.* The seeded config now ships
`dry = false` and `lava = true`. `local DRY = true` still opens the program and
the config still only lowers it — what changed is what a fresh config says.
`deploy` copies that same file to every turtle, which is why the old
`dry = true` default stranded turtle 2 on the first live deployment.

---

## 10. State and resume

**Save every block.** A turtle move is throttled to 0.4s; a ~50-byte `fs` write
is sub-millisecond and does not yield. Movement is 100% of the bottleneck, so
per-block saving is free. The file is overwritten, never appended, so it does
not grow against the disk quota.

GPS is available on this server, which changes what the file must carry: the
*task* — which level, which branch, which direction along it, and whether it
was mining, chasing a vein, or heading to the depot. On boot the turtle calls
`gps.locate` and cross-checks against the saved task; on disagreement it walks
back to the branch it owns rather than guessing.

*Amended 2026-08-25, from building Phase 2.* The file must also carry the
**absolute position and heading**, and the **launch block the claim was derived
from**. Position, because dead reckoning between GPS fixes is what makes a
mid-branch kill recoverable without re-locating on every step. The launch
block, because the claim is a chunk-snapped function of a position, and a
turtle resuming 18 blocks along a branch is frequently standing in a
neighbouring chunk: re-deriving the claim there produces a different, entirely
self-consistent claim and the turtle mines the wrong 48×48. A turtle that boots
outside the claim its saved anchor implies has been carried somewhere new, and
drops the old anchor deliberately.

---

## 11. Phases

All five are built and all five have run in-game. Phase 6 is not started.

| Phase | Scope |
| --- | --- |
| 1 | Claim maths, the branch and spine iterators, `--check`, the kit audit |
| 2 | One turtle, one branch: trunk descent, spine travel, vein chase, resume |
| 3 | The depot cycle and fuel: dump, ration, restock, lava, foraging, the work loop |
| 4 | Three turtles: air-mouth claiming, right of way, the shared depot, `recall` |
| 5 | Deployment: the probe run, `buildDepot`, and turtles 2..N placed at the launch block — by `quarry 1 deploy`, or by a plain `quarry 1` that finds turtles in its hold |
| 6 | Deferred: monitor display, and a full-clear `quarry` mode |

Each phase forced design rules that writing it revealed — the depot is found
rather than configured, the ration can only be taken and not read, the dock flag
is recomputed rather than trusted, `goTo` must leave a spine block along z, the
shared-depot sweep waits until the depot is needed, and giving way may never
move a turtle mid-leg. **All of them now live in `RESUME.md` under "Settled" and
"Corrections already made"**, which is the list to read and the list to obey.
The phase-by-phase account of how each was discovered is in
`reports/history-2026-08.md`. This file's own pre-2026-08-28 text, with the
original phase schedule, is in git history and nowhere else — it was dropped on
2026-08-28 because nothing read it.

---

## 12. Deferred and closed

- **Monitor / hub display.** Deferred by decision. None of it makes the mine
  work; revisit after Phase 4.
- **Claim exhaustion: stop, report, idle.** No auto-shift to the next 3×3 block
  — the new claim is chunks your body is not standing in, so the turtles would
  freeze the moment they entered it. Moving the mine is you moving and
  re-running.
- **`--scan` mode.** Rejected — a turtle in a fresh shaft sees four stone faces
  and learns nothing. Passive rejected-block logging instead, see section 6.
- **Liquid sealing.** Deleted — turtles are lavaproof, see section 7.
- **Fuel scheduler.** Not built. A tank of 20,000 or more — an advanced turtle
  holds far more, and the program asks it rather than assuming — means fuel is
  never the reason for a trip; foraging is a dry-depot fallback, see section 7.
- **Vertical-shaft `canes` pattern.** Superseded by horizontal branches. It
  measures identically (20%, 0% unseen) and remains a valid fallback if branch
  routing proves troublesome.

---

## 13. Deployment — the turtle sets its own mine up

*Added 2026-08-24 at the user's request.* The user drops the kit into turtle 1
and runs one command; turtle 1 audits what it has, says what is missing, and
then builds the mine.

### What the dump permits, and what it forbids

A turtle **seen from another computer** exposes exactly six methods, confirmed
in the live peripheral dump:

```
reboot  getLabel  turnOn  isOn  getID  shutdown
```

That is the whole remote surface. Turtle 1 therefore **cannot** push a file to
turtle 2, cannot read its inventory, and cannot run a program on it. It can
only switch it on. Every deployment design has to route around that.

The route that works is the floppy bootstrap, which needs no new mechanism.
As built and run in-game:

1. Turtle 1 writes `startup.lua` onto the floppy and copies **both**
   `quarry.lua` and its own `quarry.conf` beside it. The config has to follow
   the program: without it the new turtle seeds its own from the defaults and
   inherits none of the deployer's settings.
2. It places the disk drive one block up and in front, then places turtle 2 on
   the ground **directly below the drive**, so the drive mounts as `/disk`.
3. It hands that turtle its modem, 64 coal and a bucket with a plain
   `turtle.drop` — a turtle is an inventory to the turtle in front of it.
4. Turtle 2 boots on its own, runs the disk's startup, copies the program and
   config to its own filesystem, labels itself, equips the modem on whichever
   side is not the pickaxe, burns the coal and launches `quarry 2`. `turnOn` is
   only a backstop.

One drive serves all of them, because each turtle leaves before the next is
placed.

### The kit manifest

Built into `--check` as of Phase 1, because knowing you are a floppy short is
worth having *before* you ride a shaft 130 blocks down.

| Item | Count | What for |
| --- | --- | --- |
| Mining turtle | 2 | turtles 2 and 3 — turtle 1 is the one running |
| Chest or barrel | 1 | the depot: one box, ore in and coal out |
| Disk drive | 1 | the lava map, and the only way to hand code to a turtle |
| Floppy disk | 1 | goes in the drive |
| Empty bucket | 3 | one per turtle; lava scooping is confirmed working here |
| Coal or charcoal | 192 | a stack per turtle to start |

Item ids are matched **by pattern, not by exact name**, and anything
unrecognised is printed verbatim rather than ignored. This pack's real ids came
back from the probe and all four already match the patterns, so nothing is
hard-coded and nothing needs to be. Do not hard-code an id that has not come
back from a real run — and note that both turtles report
`computercraft:turtle_advanced`, so no audit can tell a mining turtle from a
plain one.

### The three mechanics, settled in-game 2026-08-27

Deployment was made a phase of its own because three things the peripheral dump
could not answer had to be answered by a real run. The probe answered all three:

1. **`turtle.place()` with a turtle item produces a working turtle, and facing
   does not matter.** `calibrate()` derives a heading by moving one block and
   diffing GPS, so a deployed turtle orients itself.
2. **A freshly placed turtle boots on its own** and runs `/disk/startup.lua`
   unprompted, about 23 seconds from placement.
3. **A turtle adjacent to a disk drive does auto-run `disk/startup.lua`** —
   standard CraftOS behaviour, now confirmed here.

One thing the probe got wrong and four deploy runs paid for: it reported that a
turtle is not visible as a peripheral to another turtle. It is — on `front` —
but discovery goes stale (CC:Tweaked #660) and the probe looked from a position
it had already left. `deploy` forces a refresh with a `turnRight`+`turnLeft`
pair, which is the spinning the user sees.

---

## Open questions

None. The design interview is complete and every mechanic section 13 was
waiting on is settled in-game. What is left is verification, not design — see
`RESUME.md`.
