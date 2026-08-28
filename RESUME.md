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
audit that has been acted on. This file carries the state, the rules and the
next action. Go there for the reasoning behind anything stated flatly here, or
when something settled starts misbehaving again.

---

## Where the work stands

Last rewritten **2026-08-28, last**, after a day that shipped four builds. The
mine is not blocked on anything: `update`, then `quarry 1` from the surface.

| Phase | State |
| --- | --- |
| 1 — claim maths, iterators, `--check`, kit audit | **Done. Ran in-game 2026-08-24.** |
| 2 — one turtle, one branch | **Done. Ran in-game 2026-08-27** (turtle 2, 177 blocks). |
| 3 — depot cycle, fuel, the work loop | **Partly run.** Travel, fuel, the work loop, building the depot, docking and dumping all ran in-game 2026-08-28. Rationing has still never handed out coal — the tank was full every time it docked. |
| 4 — three turtles | **Partly run.** Turtle 2 worked its own third correctly. Two turtles have never run at once. |
| 5 — deployment | **Done. Ran in-game 2026-08-27** after four failed attempts; turtle 2 deployed, booted and mined. A plain `quarry 1` now deploys the others itself; that part has not run in-game. |
| 6 — deferred (monitor, full-clear mode) | Not started. |

**What is unproven in-game: rationing, two turtles at once, and the two changes
from the last build** — the automatic deployment and the full-depot behaviour.

The last log out of the game is `Rpv9m`. It got a fix, crossed to its trunk,
descended to y=-59, and could not build a depot at all: **the block under the
trunk floor was bedrock.** With no depot anywhere it mined 39 blocks and
stopped, over coal it could have burnt itself. Both are fixed. The run before
it, `45bPE`, mined 251 blocks and stopped on its own depot — two chests it had
placed beside the trunk floor, which the pattern later walked into and refused
to dig. That is why the depot goes under the floor, and why the fallback niche
is a level up rather than beside it.

## Next action

**Run it from the surface**, from the same launch block as `Rpv9m`
(243,73,734), carrying **a barrel, turtles 2 and 3, the drive and the floppy**.

1. **`update`** on the turtle.
2. **`quarry 1 --check`**, and read the `position:` line against F3. Nobody has
   ever confirmed the turtle's fix matches the real world, and the pattern
   anchors to absolute coordinates — a wrong origin mines a correct claim in
   the wrong place. The same `--check` reports the kit; believe it.
3. **Launch from the same block** to reuse the trunk already cut at
   248,-59,711. The claim anchors to the launch block: `Rpv9m` anchored at
   243,73,734, claim x 224..271, z 704..751. Somewhere else cuts a fresh trunk
   somewhere else, which is correct and probably not what is wanted.
4. **`quarry 1`.** With the kit aboard it now deploys turtles 2 and 3 at the
   launch block before it descends — `deploy : turtles in the hold -- staffing
   the mine before I descend` — and only then crosses to its trunk.
   `quarry 1 deploy` still does the deployment alone if that is wanted.
5. **Optional, and the only way to hear from the mine:** a computer with a
   wireless modem near the claim running `alert`. A full depot broadcasts on
   the `quarry` protocol; nothing else does yet.

**Expect `depot  : the floor under the trunk will not open — placed a container
beside the trunk at y=-58 instead`** (a plain `--` in the real line). That is
the bedrock fallback working, not a fault. `nothing beside the trunk will open`
instead means all three candidate spots refused to be dug; read the lines above
it.

**Two rows of the old trunk level are gone for good.** `Rpv9m` reported
`taken  : y=-59 z=711 is already cut`, and the same for z=706 — its own earlier
work, read back as another turtle's once `quarry.state` was deleted.
`mouthTaken()` cannot tell the difference and by design does not try.
Restarting over an old mine costs those rows; it is not a bug.

Then watch a dock: dump, ration, restock. That is the untested half of Phase 3.

**Fast-forward the run with `/tick sprint`.** A mining run is hours of real time
and almost all of it is the turtle moving, which is tick-bound, so the vanilla
1.20.3+ tick commands compress it:

```
/tick sprint 20000     -- run 20,000 ticks as fast as the server can, ~17 min of game time
/tick sprint stop      -- back to normal before the sprint finishes
/tick query            -- what the rate is now
```

Cheats or op are needed. The client looks frozen or badly lagged while a sprint
runs — that is the server ticking flat out, not a crash. **Stay put while it
runs:** the claim is loaded because the player stands in the centre chunk, and
nothing else loads it. A sprint does not speed up the turtle's own computer
budget, only the clock it moves on, so expect a large speed-up rather than an
instant one.

## What shipped on 2026-08-28

Four builds in a day, each one from an in-game log. The full write-up of each
is in `reports/history-2026-08.md`; this is the list. Every fix has a
regression test confirmed to fail against its own unfixed code.

**Morning, from the code review** (`reports/code-review-quarry.md`): all nine
findings fixed, tests 40–48. The vein-chase counter, the empty-tank guard, the
absolute vein sweep, three `pcall` result bugs, and the lava dedupe.

**Evening**, tests 49–55: the fuel ration became a floor rather than a fraction
(`fuelFloor`, default 8); `--check` asks the turtle for its own tank limit
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
| `quarry.lua` | `raw.githubusercontent.com/zaBees/cc/main/quarry.lua` | **CURRENT — 2026-08-28, last.** Auto-deploy from a plain `quarry 1`, and a full depot that drops junk and calls home instead of stopping. 123,516 bytes, fletcher32 `522321319`. |
| `probe.lua` | `raw.githubusercontent.com/zaBees/cc/main/probe.lua` | The Phase 5 deployment probe. |
| `update.lua` | `raw.githubusercontent.com/zaBees/cc/main/update.lua` | The in-game updater. Downloaded once by hand; after that `update` replaces `quarry`, `alert` and itself. |
| `alert.lua` | `raw.githubusercontent.com/zaBees/cc/main/alert.lua` | **NEW.** For a computer, not a turtle: prints what the mine broadcasts on the `quarry` protocol. 1,379 bytes, fletcher32 `142400053`. |

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

And on the computer that is to hear from the mine:

```
delete alert
wget https://raw.githubusercontent.com/zaBees/cc/main/alert.lua alert
```

```
update            -- every program: quarry, alert and update itself
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
| `test_quarry.lua` | Five suites against stubbed CC worlds, 66 tests. Tests 40–48 are the 2026-08-28 review regressions; 49–55 the evening fixes; 56–60 the night ones; 62–64 the late-night ones; 65–66 the auto-deploy and the full depot. `lua5.3 test_quarry.lua` |
| `alert.lua` | For a computer: prints what the turtles broadcast on the `quarry` protocol. |
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
- **One STORAGE word list decides what storage is**, matched as a substring of
  the block id: `chest`, `barrel`, `shulker`, `crate`, `item_vault`. Enumerating
  every tier of every storage mod is a losing game; matching the word is not.
  Drawers and bins stay off it on purpose — they lock to one item type, so a
  mixed dump fails on the second stack. Do not re-split this into per-question
  copies; there were four.
- **The depot is ONE box.** Fuel and spoil share it, which is what the ration
  was written for. The kit audit asks for one.
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
cycle, two turtles at once, and the two changes in the last build.
