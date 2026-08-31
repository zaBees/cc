# Resume here

Handoff for the turtle mining build. A fresh session reads this file, then
`MASTERMINE-PLAN.md`, and continues without re-deriving anything.

**This file carries only what a session needs to write code**: the live
constraint, the state, the settled design, the bug traps, the conventions and
the next run. It is rewritten whole at the end of every phase — never a blind
search-and-replace, which has failed silently here before.

**Do NOT read `reports/history-2026-08.md` unless explicitly told to.** It is
the archive — the whole deploy/boot/fuel/harvest saga, items 1–60, every dated
"what shipped" block and log post-mortem. It is there for when something settled
starts misbehaving again, not for orientation. Nothing in it is needed to write
code today.

---

## The locals ceiling — fixed 2026-08-31, headroom now ~143

**The namespace refactor is done.** The ~120 `local function`s and the 11
forward-declared functions are packed into one table `Q` (`local Q = {}` near
the top; every helper is `function Q.foo(...)` and every call is `Q.foo(...)`).
Top-level `local`s went **178 → 57**, so there is now ~143 of real headroom
against Lua's 200-per-function cap. The four forward-declaration lines are gone —
`Q.foo` resolves at call time, so the ordering hack they existed for is no longer
needed.

Two names were deliberately left as plain top-level locals, not namespaced:
`slotLike` (redefined nested inside another function) and `modemSide` (shadowed
by a local variable). Namespacing them would have been wrong; they cost 2 of the
57 slots and are harmless.

**Rule now: still prefer `Q.foo` for any new helper** rather than a new
top-level local, but the pressure is off — you have ~143 slots. Check with
`grep -c '^local ' quarry.lua`. The refactor was done as a tokenizer-based pass
(strings/comments untouched) and verified byte-for-byte: all five suites produce
**identical output** before and after. **Unproven in-game** — it can only lower
the local count, so it cannot reintroduce the ceiling, but it has not run on a
turtle yet.

---

## Where the work stands

Last rewritten **2026-08-31**. The mine is not blocked. Boot, placing turtles
and mining all work in-game: the turtles deploy from a plain `quarry 1`, boot
themselves, and mine their thirds as intended. Phases 1–5 are functionally
proven; Phase 6 (off-turtle monitor + pocket client; full-clear cut) is deferred and unstarted -- see its settled shape below.

**`main` is the only branch that ships.** `update.lua` pulls from `/main/` and
nothing else ever should.

**Newest build — the private GPS constellation (2026-08-31, commits `3d5554e`
→ `5534359`), unproven in-game:**

- **`pgps.lua`** is a private GPS host/client on a channel of your own, so a
  stranger's host with wrong coordinates cannot poison your fix. `pgps channel
  <n>` sets it, `pgps host [x y z]` runs a host (and writes its own `startup` so
  it comes back after a reboot; typed coordinates are saved, and a host with
  none asks the constellation where it is — so the first four are always typed
  by hand), `pgps locate [t]` is a client fix. It reuses `rom/apis/gps.lua`
  patched from channel 65534 to yours — the only way to get its trilateration.
  Drives no actuator, so no DRY flag. New file; `update` now installs it.
- **`quarry.conf gpsChannel`** (default `0` = off). When set, `locate()` asks
  the private constellation first, falls back to public GPS on 65534, then dead
  reckoning. Returns source `"pgps"` when the private fix answered.
- **Blacklist wins over the ore tag.** A pack can tag junk (cobble, deepslate)
  into `c:ores`; `isOre` now returns false for any blacklisted name before it
  checks the tag or `oreNames`, so a vein chase no longer follows cobble across
  the claim [user, 2026-08-31]. `only` still wins over the blacklist. `isJunk`
  moved above `isOre` for this.

All five suites pass under lua5.3 (`test_quarry`, `test_update`, `test_pgps`,
`test_probe`, plus the pattern/coverage proofs).

## Next action

**Ask for `update`, then `quarry 1`** from the surface launch block, carrying a
barrel, turtles 2 and 3, the drive and the floppy. `quarry 1` deploys the others
itself, then mines. Stay at the turtle: it asks for each new turtle to be
right-clicked and waits 60s.

For the private GPS, the player sets up four hosts with `pgps host x y z` on a
chosen channel, sets the same channel in every `quarry.conf` as `gpsChannel`,
and reads `position: … (pgps)` on `quarry 1 --check` as the private fix working.
`gpsChannel = 0` keeps the old public-GPS behaviour.

**Read in the log:** `position:` source (`pgps` / `gps` / dead reckoning) against
F3; that a blacklisted block is dumped, never chased; and — still unproven from
earlier builds — the floppy write-back (`copied … to /disk/quarry`), the coal
split, a jam naming its blocker, and `lavamap: turtle N found a source`.

---

## Phase 6 — settled shape, not started (grilled 2026-08-31)

Deferred until the current builds are proven in-game. The design tree is closed;
build to this when the time comes.

**Off-turtle — two new programs, no locals cost to `quarry.lua`:**
- A **monitor** (`monitor.lua`, screen on a computer) and a **pocket-computer
  client**, both grown from `alert.lua`'s pattern — listen for the turtles'
  heartbeats, and send `recall`/`locate` commands. Their local budgets are their
  own; the ceiling does not touch them.

**Turtle-side — small additions to `quarry.lua`, within the ~22 slots:**
1. **A status heartbeat** — index, level, fuel, blocks, state — on the `quarry`
   protocol, once per dock and on every state change. Extends `notify()`.
2. **A command listener** — fold `recall` and **locate-on-ping** into the
   existing `lavaListen` coroutine, which is already blocked on `rednet.receive`
   under `parallel.waitForAny` for the whole run.
3. **Remote recall = typed recall** (surface, park, strip `startup`): the
   listener sets the flag the loop already routes via `st.task = "recall"`. No
   second "pause-in-place" concept unless asked — that would be its own command.
4. **All remote commands gated on the private channel** (`gpsChannel` / a shared
   secret, the `pgps` machinery). Recall moves the whole fleet and public rednet
   is spoofable, so an unauthenticated recall is ignored; locate-ping rides the
   same gate for free. **This is a trust boundary — do not lazy it away.**

**Full-clear mode is cut** (user, 2026-08-31). **Area growth is already
`chunksX`/`chunksZ`** — config only, no code; a claim over 3×3 needs a
player-placed chunk loader or branches strand.

## Settled — do not reopen these

Plan section numbers in brackets.

- **Harvest Mastermine, do not port it** [1]. `forge:ores` must become `c:ores`.
- **Claim is chunk-snapped**, `chunksX`×`chunksZ` chunks centred on the start
  chunk, 3×3 (48×48) default; **the pattern anchors to the claim corner and
  absolute y**, never to a turtle's start block [2]. The claim anchors to
  `st.home`, the launch block, and is persisted. **Both chunk values are
  fleet-wide** like `topY` — every turtle must carry the same two or their
  branch mouths will not line up — and every chunk must stay loaded.
- **Geometry: 1-high branches along x**, sunk where `z ≡ 2y (mod 5)` measured
  from the claim corner [3]. Spine along z at the x-centre, branches 24 west and
  23 east. One trunk per turtle at the centre of its third, on the spine, so
  trunks cost **no extra blocks** [3, 4].
- **Bottom is one level above bedrock**, found by failed dig; `bottomY=-59` is
  the safety stop. **Top is y=60.** Deepest first, working up. All configurable.
- **GPS does not reach the claim floor — physics, not a fault.** A wireless
  modem's range shrinks with depth; hosts sit near the surface, the floor is
  y=-59. Every fix is taken at the launch block before descending; from there
  the turtle dead-reckons, and `quarry.state` is what it resumes on. **GPS is
  also not reliable on this server** — the constellation cannot be assumed up.
  A turtle reaches GPS only through an equipped wireless modem. See `startDir`
  and `gpsChannel`.
- **One depot per turtle, under its own trunk.** No turtle leaves its third to
  bank, so corridor meetings stop rather than being recovered from. Coal sharing
  degrades as the accepted cost. A hand-placed chest beside the trunk floor is
  honoured but stands on a branch/spine row and is in the way.
- **Deployment is at the surface launch block, not the claim floor.** The drive
  sits directly above the placed turtle; every turtle anchors its claim where it
  wakes, and they all wake in the centre chunk. Turtles in turtle 1's hold mean
  the mine is unstaffed, so a plain `quarry 1` deploys them first; `quarry 1
  deploy` is the explicit form, recorded in `quarry.state` before it runs.
- **`quarry stop`** deletes `/startup` and `quarry.state` and comments out the
  pinned `startX/Y/Z/startDir`, to move a turtle without it resuming on the old
  spot. Ctrl+T first if still running.
- **A full depot is not a reason to stop.** The junk tier goes on the tunnel
  floor and the run carries on; only a hold that still cannot be emptied of ore
  stops it. The player is told over rednet.
- **Notifications are best effort and always logged.** A broadcast from y=-59
  may reach nobody; `notify()` writes the line regardless. Do not build anything
  that depends on the message arriving. `alert.lua` is the receiver.
- **Claim exhaustion: stop, report, idle** [12]. **The monitor is Phase 6.**

## Corrections already made — do not reintroduce

- **CC:Tweaked is Lua 5.2 (Cobalt).** No `//`, no bitwise operators. `goto` is
  fine. All-doubles; use `math.floor`, not a bare `/`.
- **`pcall` prepends its own success flag** — this has been got wrong five times.
  Capture both values and test the second against `false` explicitly; a *failed*
  pcall puts an error STRING second, which `type(x)=="string"` guards wave
  through. **There is one door: `periph(fn, ...)`**, beside `equippedItem`,
  returning nil when the call did not live. Use it for every `peripheral.*` read.
- **The vein sweep must be absolute.** `goTo` faces the direction it travels, so
  anchor the four-way sweep to a `d0` captured on entry, not `st.dir`.
- **`st.chased` is a per-chase counter, not a run total** — reset where a chase
  begins, never where a run begins. `st.veined` is the run total.
- **An empty tank is not a wall.** `turtle.forward()` returns false either way;
  the guard lives at the top of `clear()`, which every stepper routes through.
  Without it, and with `halt` unset, `report` calls a stranded turtle finished.
- **Blacklist wins over the ore tag** [2026-08-31]. Do not let a `c:ores`-tagged
  junk block be chased; `only` still outranks the blacklist.
- **Burn on pickup is about depot coal, and only at a turtle's OWN box.** At a
  turtle's private depot `keepFuel` burns the hold up to `fuelKeep` at every leg
  end and dock. At a shared box coal rides home unburnt — do not add a
  burn-where-found rule there; that is the hoarding the sharing rule stops.
- **Never derive the claim from the turtle's position after boot.** **`DRY` is
  not edited in the program** — `dry` in `quarry.conf` is what goes live.
- **`os.getComputerLabel()` returns NO values on an unlabelled computer**, not
  nil; `tostring()` of it throws. A local absorbs the zero-return; an argument
  list does not.
- **A placed turtle IS a peripheral on `front`**, but discovery goes stale
  (CC:Tweaked #660), so it reads as air right after `turtle.place`; `deploy`
  retries with a turn to force a refresh (the cosmetic spinning). On a turtle
  `left`/`right` report the EQUIPPED upgrade, not the adjacent block.
- **A deploy is resumable; `st.staffed` is the record** (not `deployed`, a dead
  name). **Adoption is for a turtle a PREVIOUS run stranded, never this run's.**
- **1-high tunnels at 3×3 leave 44% unseen; the mod-5 stagger reads the claim
  interior for ~22% dug** — the proven floor. The 0%-unseen figure is toroidal;
  on the real claim it is 1.16%, all on the claim face. Do not "fix" it. Trunks
  cost no blocks — do not re-add a 360-block line to any cost table.
- **`turtle.dig` on a full inventory destroys the drop** (issue #1046). Turtles
  are lavaproof and submersible; `detect()` is false for liquid — no
  liquid-sealing logic. Lootr loot is unreachable to a turtle; do not add a
  `turtle.suck` at one. Ancient debris is nether-only.
- **A deployed turtle takes the deployer's `quarry.conf` on EVERY boot now**
  [user, 2026-08-31], so a `gpsChannel` (or any setting) changed on turtle 1
  reaches turtles 2/3 on their next deploy. The old "copy only when absent"
  guarded hand-typed coordinates from being wiped [user, 2026-08-28]; that is now
  handled by **carrying the child's `startX/Y/Z/startDir` lines across the
  overwrite** (unless the floppy's own conf pins coordinates, in which case the
  floppy wins). A modem-less turtle finds itself only from those lines — losing
  them is the "asks for coordinates forever" bug. The logic lives in the `BOOT`
  template; `test_boot_conf.lua` runs the rendered boot.lua and proves it.
- **A GPS deploy now pins each child's coordinates too, if turtle 1 knows its
  heading** [user, 2026-08-31]. `confForPlaced` used to fire only in manual mode
  (`startX` pinned); it now fires whenever turtle 1 has a heading — measured
  `st.dir` or a stated `startDir` — stamping the placed turtle's own absolute
  coordinates on the floppy conf. A modem child still finds itself by GPS
  (locate prefers it); a **modem-less child adopts the parent-derived pin**
  instead of asking. So in GPS mode, set `startDir` in `quarry.conf` and
  modem-less turtles self-locate. The pin is computed off `st.home` (the launch
  block), **not** `st.x/y/z` — turtle 1 rises a block to place the drive before
  the conf is written, and pinning that y put the child one block too high (a
  latent bug in the old manual-mode path, now fixed). Proven in `test_quarry`
  test 35b.
- **The `BOOT`/`BOOTSTRAP` templates are long strings, not live code.** They
  define their OWN `note`/`main` as plain globals — do NOT namespace them onto
  `Q` (the child's boot.lua has no `Q`; `function Q.note` there crashes deploy at
  runtime while still *compiling*, so the compile-only boot tests miss it). The
  namespace refactor's tokenizer leaked into here once and was caught only by
  running the rendered boot.lua. Any edit to those strings stays bare.

## The design in one paragraph

Three turtles work a chunk-snapped claim, `chunksX`×`chunksZ` chunks centred on
the start chunk, 3×3 (48×48) by default, with no chunk loader — the player
standing in the centre chunk holds those nine open. Branches are 1-high, 1-wide,
run along x, sunk wherever `z ≡ 2y (mod 5)` measured from the claim corner (the
`1,3,5,2,4` sequence, ~22% dug). A spine runs along z at the x-centre with branch
mouths every 5; branches run 24 west and 23 east. Each turtle has its own trunk
at the centre of its third and its own depot under that trunk. Levels run
deepest first, one above bedrock up to y=60. Turtles never surface except on
`recall` and when foraging coal above y=0.

## Conventions that govern the code

One self-contained file, no `require`, delivered as a single `wget` from the
GitHub repo. Opens `local DRY = true`; `quarry.conf` may lower it, never raise
it. **Prefer `Q.foo` over a new top-level local** — the file was refactored onto
a `Q` namespace table (see the top of this file); there is now ~143 slots of
headroom against the 200-per-function cap, but the habit stays. Persist state
every meaningful step. `pcall` every
peripheral call through `periph()`. Diagnostics go *in* the program so one
in-game run answers the question. Print a liveness line before any long work.

**Test under `lua5.3` before delivering; when you fix a bug, add a test and
verify it FAILS against the unfixed code** — a test that passes against the bug
asserts nothing. The peripheral dump in `~/.claude/skills/cc-tweaked-pack/
references/` outranks the wiki but was taken from a COMPUTER, which has no turtle
API; if a method is not in it, ask for a re-survey rather than guessing. No
CC:Tweaked jar is in this sandbox, so CC mod-side behaviour comes from
tweaked.cc or from the user.

## Standing rules from the user

- **Work must survive their budget running out.** Write deliverables and this
  handoff to disk as you go, never only in chat. Rewrite this file whole at the
  end of every phase.
- **Test under lua5.3 here before anything reaches their server.** The user runs
  the code and you never see the game, so a shipped bug costs a round trip.
- **Ask before reverting or deleting anything.** This is a git repository, so
  there is an undo — but ask, then revert deliberately with git.
- **How sessions go:** the user pastes the id of an in-game log (the program
  POSTs its report to paste.rs and prints the id) and little else. Fetch it,
  read it as the primary evidence, and put the next diagnostic INTO the program.
  Do not theorise past the evidence — when a log cannot distinguish two causes,
  add the line that will, and say so.

## Delivery goes through GitHub

Repo **https://github.com/zaBees/cc**, public; this directory is its working
tree. **Ship a fix by pushing**, then tell the user to run `update`.

**Verify every push against the commit-pinned URL, never the branch one** — the
`/main/` URL is CDN-cached and served a previous build for minutes after a push:

```
curl -sS https://raw.githubusercontent.com/zaBees/cc/$(git rev-parse HEAD)/quarry.lua
```

`update` replaces `quarry`, `update`, `alert` and `pgps` from GitHub: it writes
`<name>.new` and moves it into place, refuses an empty body or an HTML 404, and
appends `?t=<epoch>` to defeat the cache. Configs are never touched. A hand-typed
download is always TWO lines, `delete <name>` then `wget` — CC's `wget` refuses
to overwrite and the CC shell has no `&&` or `;`. **cloudcat is archived in
`attic/`; do not use unless the user asks for it by name.**

## Delivered

| Program | URL | What it is |
| --- | --- | --- |
| `quarry.lua` | `…/zaBees/cc/main/quarry.lua` | **CURRENT.** Phases 1–5: auto-deploy from `quarry 1`, one depot per turtle, coal burnt on pickup, climb-for-coal foraging, lava map shared over rednet, `quarry stop`, `chunksX/Z` claim sizing, private GPS (`gpsChannel` + `pgps.lua`), blacklist-wins-over-tag. Functions on a `Q` namespace table; ~143 locals of headroom. |
| `pgps.lua` | `…/zaBees/cc/main/pgps.lua` | **NEW.** Private GPS constellation host/client on your own channel. Installed by `update`. |
| `update.lua` | `…/zaBees/cc/main/update.lua` | In-game updater: replaces `quarry`, `update`, `alert`, `pgps` and itself. Downloaded once by hand. |
| `alert.lua` | `…/zaBees/cc/main/alert.lua` | For a computer: prints what the mine broadcasts on the `quarry` protocol. |
| `probe.lua` | `…/zaBees/cc/main/probe.lua` | The Phase 5 deployment probe. |

The setup artifact at
https://claude.ai/code/artifact/6989784d-6bae-4da6-8158-0dc6464885c5 predates
GitHub delivery and is **out of date** — update that same URL if it is
regenerated.

## Files

| File | What it is |
| --- | --- |
| `MASTERMINE-PLAN.md` | The settled design and its reasoning. Read second. |
| `quarry.lua` | **The deliverable.** ~4,650 lines, Phases 1–5. Opens `local DRY = true`. Functions live on a `Q` namespace table (`function Q.foo`); ~143 top-level-local slots free. |
| `test_quarry.lua` | Five suites against stubbed CC worlds. `lua5.3 test_quarry.lua`. |
| `test_boot_conf.lua` | Runs the rendered `BOOT` boot.lua against a stub fs: force-overwrite of the config, and a modem-less turtle keeping its own coordinates. |
| `pgps.lua`, `test_pgps.lua` | Private GPS and its stubbed-world tests. |
| `update.lua`, `test_update.lua` | The updater and its tests. |
| `alert.lua` | The rednet receiver for a computer. |
| `probe.lua`, `test_probe.lua` | The Phase 5 probe and its tests. |
| `test_pattern.lua`, `test_coverage.lua` | The pattern proofs: `1,3,5,2,4`, and dug%/unseen% per candidate. |
| `reports/history-2026-08.md` | **Archive. Do not read unless instructed.** Everything this file has ever dropped: phase narratives, deploy post-mortems, items 1–60, the fuel/harvest/claim-size builds. |
| `reports/code-review-quarry.md` | The 2026-08-28 review, all nine findings fixed. |
| `FUEL-PLAN.md`, `HARVEST-PLAN.md`, `DEADLOCK-PLAN.md`, `DEPLOY-PLAN.md` | Design notes for shipped builds; the reasoning survives here. |
| `HANDOFF-PROMPT.md` | The pointer to paste into a fresh session. |
| `ROCKET-PLAN.md`, `spacex.lua`, `icmb.lua` | **Unrelated second thread**: a Create Aeronautics flight controller. Leave it alone unless the user raises it. |
| `attic/` | Superseded and reserve work, incl. `SETUP.md` and the cloudcat delivery client. |

## Open questions

None on the design, and none blocking. What is left is in-game verification of
the private GPS build and of the earlier unproven builds (the coal split, a
jam naming its blocker, the floppy write-back).
