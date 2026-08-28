# Resume here

Handoff for the turtle mining build in this directory. If a session ends
mid-task — budget exhausted, crash, context lost — a fresh session reads this
file, then `MASTERMINE-PLAN.md`, and continues without re-deriving anything.

**Rule: this file is rewritten whole at the end of every phase, before anything
else.** Nothing important lives only in chat. Never patch it with a blind
search-and-replace — a patch whose search string does not match fails silently,
which has already happened once and left this file describing an abandoned
design. An asserted replace is fine; a hopeful one is not.

**This file was trimmed on 2026-08-28** from 646 lines to roughly a third of
that. Everything removed is in `reports/history-2026-08.md`, complete and
unedited: the phase-by-phase narratives, the code review in full, the four
failed deploy runs, the probe results. This file carries the state, the rules
and the next action. Go there for the reasoning behind anything stated flatly
here, or when something settled starts misbehaving again.

---

## Where the work stands

Last updated **2026-08-28 late night**, after log `Rpv9m` — the first run with
the depot-under-the-floor build. It got a fix, crossed to its trunk, descended
to y=-59, and then could not build a depot at all: **the block under the trunk
floor is bedrock.** With no depot anywhere it mined 39 blocks and stopped, over
coal it was perfectly able to burn itself. Both are fixed here: the depot falls
back to a niche beside the trunk one level up, and spare coal is no longer a
reason to stop when there is nowhere to bank it.

The run before that (`45bPE`) mined 251 blocks, docked once, and stopped on its
own depot: the two chests it had placed beside the trunk floor were blocks the
pattern later walked into and refused to dig. That is why the depot goes under
the floor, and why the fallback niche is a level UP rather than beside it.

| Phase | State |
| --- | --- |
| 1 — claim maths, iterators, `--check`, kit audit | **Done. Ran in-game 2026-08-24.** |
| 2 — one turtle, one branch | **Done. Ran in-game 2026-08-27** (turtle 2, 177 blocks). |
| 3 — depot cycle, fuel, the work loop | **Partly run.** Travel, fuel, the work loop, building the depot, docking and dumping all ran in-game 2026-08-28. Rationing has still never handed out coal — the tank was full every time it docked. |
| 4 — three turtles | **Partly run.** Turtle 2 worked its own third correctly. Two turtles have never run at once. |
| 5 — deployment (`quarry 1 deploy`) | **Done. Ran in-game 2026-08-27** after four failed attempts; turtle 2 deployed, booted and mined. |
| 6 — deferred (monitor, full-clear mode) | Not started |

**What is still unproven in-game is rationing and the three-turtle interplay.**
The turtle docked and dumped, but every dock found the tank already full, so no
coal has ever been handed out, and two turtles have never run at once.

## Next action

**Run it from the surface again**, from the same launch block as `Rpv9m`,
carrying a barrel.

1. **`update`** on the turtle, for the bedrock-fallback build.
2. **`quarry 1 --check`** and read the `position:` line against F3. Nobody has
   ever confirmed the turtle's fix matches the real world, and the pattern
   anchors to absolute coordinates — a wrong origin mines a correct claim in
   the wrong place.
3. **Launch from the same block** to reuse the trunk already cut at
   248,-59,711. The claim anchors to the launch block: `Rpv9m` anchored at
   243,73,734, claim x 224..271, z 704..751. Launched from somewhere else it
   cuts a fresh trunk somewhere else, which is correct behaviour and probably
   not what is wanted.
4. **A barrel in the hold**, then `quarry 1`.

**Expect `depot  : the floor under the trunk will not open — placed a container
beside the trunk at y=-58 instead`** (with a plain `--` in the real line). That
is the fallback working, not a fault. If it says `nothing beside the trunk will
open` instead, read the lines above it: all three candidate spots refused to be
dug.

**Two rows of the old trunk level are gone for good.** `Rpv9m` reported
`taken  : y=-59 z=711 is already cut` and the same for z=706 — that was the
run's own earlier work, read back as another turtle's once `quarry.state` was
deleted. `mouthTaken()` cannot tell the difference and by design does not try.
Restarting over an old mine costs those rows; it is not a bug.

Then run turtle 2 and watch it dock: dump, ration, restock.

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

## Delivered

| Program | URL | What it is |
| --- | --- | --- |
| `quarry.lua` | `raw.githubusercontent.com/zaBees/cc/main/quarry.lua` | **CURRENT — 2026-08-28 late night.** The bedrock depot fallback and the spare-coal stop, on top of the depot-under-the-floor build. 119,158 bytes, fletcher32 `3223320507`. |
| `probe.lua` | `raw.githubusercontent.com/zaBees/cc/main/probe.lua` | The Phase 5 deployment probe. |
| `update.lua` | `raw.githubusercontent.com/zaBees/cc/main/update.lua` | The in-game updater. Downloaded once by hand; after that `update` replaces `quarry` and itself. |

See "Delivery goes through GitHub" below for the two `wget` lines. The setup
artifact at
https://claude.ai/code/artifact/6989784d-6bae-4da6-8158-0dc6464885c5 still
describes the paste route and is **out of date** — update that same URL when it
is regenerated, because a fresh publish makes a second page.

**Superseded ids, which must not be run:** `swzlE` (pre-review: stops chasing
ore after 64 blocks, says `work complete` on an empty tank), `4b9IM` (Phase 1,
`--check` only), `4zMLm`, `kgXRL`, `uKUTW`, `3A9h2`, `lQszb`, `bO7bo`, `cpeuw`,
`llZlk`, and `KRY8F` for the probe.

## Delivery goes through GitHub

Changed 2026-08-28 at the user's instruction. The repo is
**https://github.com/zaBees/cc**, public, and this directory is now that repo's
working tree -- it had no version control before, which is why the standing
rule says there is no undo. There is one from here.

```
delete quarry
wget https://raw.githubusercontent.com/zaBees/cc/main/quarry.lua quarry

delete probe
wget https://raw.githubusercontent.com/zaBees/cc/main/probe.lua probe
```

**Get `update` onto each turtle once and the two-line ritual is over.** From
then on a redelivery is `git push` here and `update` in-game:

```
delete update
wget https://raw.githubusercontent.com/zaBees/cc/main/update.lua update
```

```
update            -- every program: quarry and update itself
update quarry     -- just that one
```

It writes to `<name>.new` and moves it into place, so a download that fails
leaves the working copy alone; it refuses an empty body and an HTML 404 page;
it appends `?t=<epoch>` to defeat the CDN cache described below; and it prints
`quarry: N bytes, fletcher32 N`, the same number `attic/sumfile.lua` prints, so
a delivery can be checked against the local file without transcribing anything.
Configs are never touched. `test_update.lua` covers all of that under
`lua5.3`.

**The URL never changes.** That is the whole point of the switch: paste.rs ids
were immutable, so every edit meant a fresh id written into three places and
transcribed by eye, with `0`/`O` and `l`/`1` slips costing a round trip. A
redelivery is now `git push`, and the user re-runs the same two lines.

Still true for a hand-typed download, and the reason `update` exists:
**every download is TWO lines.** CC's
`wget` refuses to overwrite an existing file -- it prints `File already exists`,
downloads nothing, and reads like success. No force flag, and the CC shell has
no `&&` or `;`.

**Verify after a push** by fetching the raw URL back here and diffing it against
disk -- but fetch the **commit-pinned** URL, not the branch one:

```
curl -sS https://raw.githubusercontent.com/zaBees/cc/$(git rev-parse HEAD)/quarry.lua
```

The `/main/` URL is CDN-cached and was still serving the previous build more
than two minutes after a push on 2026-08-28, which looks exactly like a failed
push. The commit-pinned URL is not cached that way and settles it immediately.
The cache matters to the user too: if they re-download within a few minutes of
being told a build is ready, they can get the old one. Tell them to wait a
moment and repeat the two lines.

**paste.rs is retired.** It stopped accepting uploads over roughly 80,000 bytes
on 2026-08-28 (nginx 500; even the 96,594-byte file already live as `3PcMy`
could no longer be re-uploaded), and quarry.lua is past 100,000. Old pastes are
still fetchable, so the historic builds can be read: `3PcMy` quarry, `4uJB7`
probe, and the superseded ids listed under Delivered.

**cloudcat is archived in `attic/` and is not to be used unless the user asks
for it.** It works and it is the fallback if GitHub is ever unreachable in-game;
`attic/test_cloudcat.py` still passes from where it sits. What it does: pushes a
file straight into the game over cloud-catcher, splitting it across packets and
stitching it back, so nothing is transcribed at all. It needs `websockets`
(not installable system-wide here under PEP 668 -- use a venv) and the in-game
computer running `cloud <token>`. `attic/sumfile.lua` is its verifier: pushed to
the machine, it prints the file's fletcher32 to compare against
`cloudcat.fletcher32` locally, because a file over ~18 KB cannot be pulled back.

## Files

| File | What it is |
| --- | --- |
| `MASTERMINE-PLAN.md` | The design, every decision and its reasoning. Read second. Trimmed 2026-08-28: §11 is now a status table, and the rules it used to carry are in this file's Settled and Corrections lists. |
| `quarry.lua` | **The deliverable.** ~2,430 lines, Phases 1–5. Opens `local DRY = true`; the config lowers it. |
| `test_quarry.lua` | Five suites against stubbed CC worlds, 62 checks. Tests 40–48 are the 2026-08-28 review regressions; 49–55 the evening fixes; 56–60 the night ones; 62–63 the late-night ones. `lua5.3 test_quarry.lua` |
| `update.lua` | The in-game updater: `update` replaces `quarry` and itself from GitHub. Downloaded once by hand. |
| `test_update.lua` | Stubbed `http`/`fs` around the updater: the failed download, the HTML 404, the cache-buster, the checksum. `lua5.3 test_update.lua` |
| `probe.lua` | The Phase 5 probe. `probe` is a dry run, `probe go` is the real one. |
| `test_probe.lua` | Stubbed world for the probe, live and DRY paths. `lua5.3 test_probe.lua` |
| `SETUP.md` | What the user does in-game. The setup artifact is generated from it. |
| `reports/history-2026-08.md` | **Everything this file used to say.** The phase narratives, the deploy-run post-mortems, the probe findings. |
| `reports/code-review-quarry.md` | The 2026-08-28 review. All nine findings, all fixed, each with its test. |
| `reports/check-1-2026-08-24.txt` | The first real `--check` output, verbatim. |
| `reports/mine-live-1-turtle2-2026-08-27.txt` | The 177-block in-game run. |
| `reports/deploy-live-1..4-2026-08-27.txt` | The four failed deploy runs. |
| `test_pattern.lua`, `test_coverage.lua` | The pattern proofs: `1,3,5,2,4`, and dug%/unseen% per candidate. |
| `reports/plan-2026-08-25-full.md` | `MASTERMINE-PLAN.md` before its 2026-08-28 trim, with the original phase schedule. |
| `HANDOFF-PROMPT.md` | The prompt to paste into a fresh session. |
| `attic/` | Superseded and reserve work. `tunnel.lua` and its test, and the cloudcat delivery client. |
| `attic/cloudcat.py` | **Archived 2026-08-28. Do not use unless the user asks.** Pushes files into the game over cloud-catcher, split and stitched. The fallback if GitHub is ever unreachable in-game. |
| `attic/test_cloudcat.py` | fletcher32 vectors, plus a real split of `quarry.lua` whose generated joiner is run under `lua5.3` and diffed byte-for-byte. Run from inside `attic/`. |
| `attic/sumfile.lua` | cloudcat's verifier: prints a file's fletcher32 in-game. Arithmetic-only, because CC is Lua 5.2. |

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
- **The deployment kit never goes into the depot.** `dumpLoad` and `restock`
  skip anything matching turtle, computer, disk, modem, chest, barrel, shulker
  or bucket. Before this, `quarry 1` carrying turtles 2 and 3 posted them into
  the dump chest as spoil, which is what happened in `45bPE`.
- **The depot queue is the waiting, not a queue** [5]. Mastermine's linked-list
  route was for a hub with a monitor and any number of turtles. Do not build it.
- **Right of way by launch index** — lower wins, higher moves [8]. `giveWay`
  only ever waits; moving aside is `goTo`'s job, because a sidestep inside
  `mineLeg` would desync `st.along`.
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
- **Depot fuel rationed by a FLOOR, not a fraction** [7]. **Learned by taking,
  because a turtle cannot read a chest it is not wired to.** A turtle takes
  what the trip needs (`want`) down to `fuelFloor` coal per OTHER turtle --
  default 8, so 16 with three running -- and takes nothing at all below that,
  which drops it into the designed forage path. Changed 2026-08-28 at the
  user's instruction. The old rule took `floor(total / 3)` and made the shares
  unequal: on 300 coal three dockers took 100, then 66, then 44, because each
  took a third of what the last one left, and 90 sat in the chest for good. It
  also divided by a literal 3 however many turtles were configured. Tests 51
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
- **The monitor is Phase 6.**

## The defaults, changed 2026-08-27 at the user's instruction

`quarry.conf` ships **`dry = false`** and **`lava = true`**.

This overrides the old convention that the program is never handed over ready
to mine. `local DRY = true` still opens the file and the config lowers it as it
always did — the change is only to what the seeded config says. It matters more
than it looks: **`deploy` copies that same file to every turtle**, so the old
`dry = true` default is what stranded turtle 2 on the first live run. Test 38
asserts both values so a later edit cannot revert them quietly. Tests that want
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
- **"Burn on pickup, carry no fuel items" is about depot coal, not mined coal.**
  Coal dug on a branch rides home to the chest. Do not add a burn-it-where-you-
  find-it rule; that is the hoarding the sharing rule exists to stop.
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
  boolean. This has now been got wrong four times, in `checkLava`, `deployOne`,
  `buildDepot` and `turtleAhead`. Capture both values and test the second
  against `false` explicitly — and remember a *failed* `pcall` puts an error
  STRING second, which is not `false`. Tests 41, 44, 46.
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

- **Breaking the two chests turtle 1 built at 248,-59,711.** See Next action —
  this is the blocker, and turtles 2 and 3 are inside one of them.
- **The `passed over:` line from a real run** — this pack's real ore ids.
- **192 coal or charcoal**, a stack per turtle. The only thing `deploy` is
  short of.
- **Break turtle 2 and pick it up** before the next deploy: it stands in the
  deployment spot with a seeded DRY config, and `deploy` needs that block
  clear. A broken turtle may come back with the modem attached as an upgrade
  rather than as a loose item, in which case the kit audit reads 2 modems and
  says `SHORT 1`. Believe the audit.

## Conventions that govern the code

One self-contained file, no `require`, delivered as a single `wget` from the
GitHub repo. Opens `local DRY = true`; `quarry.conf` may lower it and may never
raise it. Persist state every meaningful step. `pcall` every peripheral call —
and remember it prepends its own success flag. Test under `lua5.3` before
delivering; `test_quarry.lua` is the stubbed world to extend, not replace.
**When you fix a bug, add a test and verify it FAILS against the unfixed
code** — nine tests have been confirmed non-vacuous that way and it is worth
the extra minute. Diagnostics go *in* the program so one in-game run answers
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
- **How the sessions actually go:** the user pastes a paste.rs id of an in-game
  log and little else — the program still uploads its own crash reports there,
  and that side of paste.rs works fine; it is only uploads over ~80,000 bytes
  that fail. Fetch it, read it as the primary evidence, and put the
  diagnostic INTO the program so the next single run answers the question. Five
  deploy runs were spent on a chain of separate bugs, each hidden behind the
  last. Do not theorise past the evidence — when a log cannot distinguish two
  causes, add the line that will, and say so.

## Open questions

None on the design, and none blocking. What is left is verification: the depot
cycle and two turtles running at once.
