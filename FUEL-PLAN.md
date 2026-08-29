# Coal in the box, none in the tank: the fuel plan

Written 2026-08-29 from in-game logs `E5wWw` (turtle 1) and `hkgWh` (turtle 2),
and settled with the user in a design interview the same day. This is the design
note for the fix. Implement against this, not against a reading of the logs.

**Built and shipped 2026-08-29.** Changes 35–47 are in `quarry.lua`, tests
110–118 are in `test_quarry.lua` and each was confirmed to fail against the
unfixed code. What survives here is the reasoning: the log evidence, the
rejected alternatives, and the one thing deliberately left undone.

## What the logs actually show

Both turtles ran well and both stopped the same way, with coal in their own
depot:

```
depot  : dumped; chest held 16 fuel items, took 0 fuel, tank 93
forage : depot is dry -- taking a branch at y=60 instead, where the coal is
depot  : dumped; chest held 16 fuel items, took 0 fuel, tank 93
STOPPED: depot is dry and there is nothing to forage: 93 fuel, 400 needed
```

Turtle 1 dug 2,751 blocks over 27 trips and finished 44 branches; turtle 2 dug
1,621 over 17 trips and finished 25. Neither crashed. Both ended holding under
160 fuel with a container of coal one block away.

## Three separate causes

### 1. The ration floor reserves coal in a box nobody else visits

`restock` holds back `(turtles - 1) * fuelFloor` = 2 x 8 = **16** coal
(quarry.lua:2221). That number was written when the mine had one shared depot
and the first turtle to dock could starve the other two.

Change 30 (2026-08-29) gave every turtle its own depot under its own trunk. No
other turtle ever docks there, so those 16 coal — 1,280 fuel — are reserved for
nobody, permanently. The chest count pinning at exactly 16 in both logs is that
floor, not a coincidence.

### 2. `restock` cannot see past the first 16 stacks

The chest count is "learned by taking": `for _ = 1, 16 do suck end`, bounded by
the turtle's 16 inventory slots. Dump and fuel are the same box, so spoil
accumulates at the front and coal banked later lands behind the window.

The evidence is that the count only ever fell — 64, 61, 57, ... 16 — across a
run that hauled 3,020 items. Mined coal went into the box and was never counted
again. The user reports the depot is larger than the default 27 slots, which is
exactly the condition that buries it.

`turtle.suck` only ever pulls the container's **first** slot. A peripheral wrap
does not fix this: `pushItems`/`pullItems` address peripherals by name and a
turtle has no name for itself, so a wrap can **read** the whole box and still
cannot **take** from slot 40.

### 3. The ascent to the top level is unreachable by construction

`forage` is only called when `fuelLevel() < want`. A branch at `topY` costs
about 400 fuel (119 up, 94 legs, 119 back, 64 margin), so the turtle only
attempts the climb once it holds less than the climb costs.

Worse, it half-committed: `forage` set `st.level = 60` and returned true, the
next pass priced that branch at 400 against a tank of 93, docked again, and this
time `if st.level ~= top` was false — so `forage` returned false and the run
halted. The feature has never once worked.

Note that coal does not generate below y=0 in 1.21, so a turtle at y=-45 cannot
mine its way out of this. Climbing is the only remedy.

## The design

Twelve changes. Numbering continues the RESUME series at 35.

### Fuel lives in the tank, not the box

**35. Mined coal is burnt on pickup, up to a configurable ceiling.**
`fuelKeep = 2000` in `NUM`, a **fuel level**, not a coal count. At the end of
every leg and at every dock, call the existing `burnFrom(l, conf.fuelKeep)`
(quarry.lua:1731) — it already burns the least coal that reaches a target and
is already called from four places.

This applies at a **private** depot only. At a shared one, coal still rides home
unburnt so the other turtles can draw on it.

This deliberately brushes against the correction at `RESUME.md:695` — "do not
add a burn-it-where-you-find-it rule; that is the hoarding the sharing rule
exists to stop". The condition that justified it is gone: with one depot per
turtle there is no sharing to protect. Confirmed with the user 2026-08-29.

Do **not** fire this per dug block (quarry.lua:1270). That is 2,751 sixteen-slot
`getItemDetail` scans on a run of this size, to catch the rare coal. A leg is 24
blocks, so leg-end plus dock is frequent enough that coal never rides long.

**36. A depot is this turtle's own unless it is explicitly shared.**
`buildDepot` (quarry.lua:2114) and `probeDepot` (quarry.lua:1991) write
`own = true`; `findSharedDepot` (quarry.lua:2587) writes `own = false`.
Everything that reads it tests `st.depot.own ~= false`, never truthiness.

The explicit-`false` test is what makes the field safe to add: every
`quarry.state` currently in the world was written before it existed, and every
one of those turtles built its own box. Under `~= false` an old file falls the
right way and the fix takes effect without deleting state. This is the same
discipline as the `pcall` lesson at `RESUME.md:727`, and the opposite of the
`deployed`/`staffed` mistake at `RESUME.md:161`.

A turtle with no depot at all — before `buildDepot` runs, or with `st.noDepot`
set — counts as private. `RESUME.md:396` already settled that spare coal is not
a reason to stop when there is nowhere to bank it; burning it to the ceiling is
the same judgement.

### Rationing

**37. `fuelFloor` is deleted.** Nothing is held back at a private box. The key
goes from `NUM`, from the seeded `quarry.conf`, and from the `--check` print.

**38. A shared box hands out a per-dock cap instead of a reserve.**
`sharePerDock = 16` in `NUM`, a **coal count** — the unit `restock`'s `keep` is
already in, since `dock` passes `need = ceil((target - fuelLevel()) / 80)`. The
line becomes `keep = min(share, want, conf.sharePerDock)`.

A reserve leaves coal nobody can spend; a cap divides the box fairly across
visits without stranding any of it. 16 coal is 1,280 fuel, roughly three deep
branches.

**39. `fuelShare`'s dock trigger fires only at a shared depot**
(quarry.lua:1834 and :2928). Its stated purpose is banking a find "for the
others". At a private box there are no others, so the trip only moves coal into
a container the same turtle will draw back out later.

### The ascent

**40. `forageCoal = true` in `BOOL`**, beside `lava`. Named for the arm it
gates: `lava` already gates the mapped-lava-source scoop inside the same
`forage()`, so a bare `forage` key would silently switch that off too.

Seeded line:

```
forageCoal   = true    # depot dry = climb to topY and mine for coal. false = stop instead
```

`deploy` copies `quarry.conf` to every turtle, so this is one setting for the
whole mine, not per-turtle. Test 38 is extended to pin the default, the same
guard `dry` and `lava` already have.

**41. The ascent is launched while it is still affordable.** In `dock`, after
`restock`: if the depot gave nothing **and** the tank is under twice the
top-branch cost, forage now rather than waiting for `fuelLevel() < want`. On
`E5wWw` that fires at the `tank 413` dock — the first one that took 0 — instead
of at 93.

**42. It refuses a climb it cannot finish.** Before committing, check
`fuelLevel()` plus what `burnFrom` could still raise from the hold against the
cost of the climb. Short, halt **at the depot** naming the shortfall.

Halting at the depot leaves the turtle somewhere the player can reach with coal.
Halting at y=20 in a one-wide trunk shaft does not. Price the climb from the
trunk column, not from a branch end.

`forageCoal = false` halts at the depot too, naming the switch.

**43. Up top it mines until the tank reaches `fuelKeep`.** Not one branch and
back — it keeps working the top level until it has enough, which is `fuelKeep`
and not a new number: burn-on-pickup already tops the tank to that ceiling at
every leg end, so foraging terminates by itself the moment the ceiling is met.

While foraging, a full hold drops junk on the tunnel floor through the existing
`makeRoom` path and the turtle descends only when it is holding ore. The depot
is 119 blocks below, so an unconditional dock costs a 238-fuel round trip —
more than the branch that triggered it.

**44. Then it re-enters the normal schedule at the deepest unfinished level.**
`st.done` is already a per-level record, so that level is known and needs no new
state. Do not treat the forage level as the new schedule position: that
silently reverses `deepestFirst`, which is settled.

Today `forage` sets `st.level = topY` and clears the plan, and with every level
below marked done the turtle would call the claim exhausted and stop. That is
the second half of cause 3 and it has to go with the first.

**45. A turtle that cannot reach `fuelKeep` parks at the top of its own trunk,
y=60.** Not where the fuel ran out, and not at the depot.

Each turtle's trunk is private to its own third, and the only trunk block on the
shared spine is the floor — which is the depot, so a turtle that can reach it
docks rather than parks. The settled "park off the spine" rule
(`RESUME.md:551`) therefore cannot come into conflict. y=60 is also the point
nearest the surface, which is where the player can most easily bring coal.

**46. `notify()` on both events** — one kind when the ascent starts, one when it
parks, carrying its position. The ascent notify is the early warning that the
mine is running out of coal, which is something the player can act on before a
turtle strands. Both are best effort and always logged (`RESUME.md:654`).

### Measurement

**47. The depot's true size and coal total are printed once per run.**
A `pcall`-wrapped `peripheral.wrap` on the depot side, using `size` and `list`.
Read-only: the run is unchanged when the wrap returns nothing, and `restock`'s
suck path is untouched.

This does two jobs. It confirms or refutes the user's observation that coal is
sitting in the box unseen, and it settles whether a turtle can wrap an adjacent
inventory at all — which cannot be checked from the sandbox, because the
peripherals dump in the skill's references was taken from a **computer**
(`RESUME.md:721`). The `inventory` type and its `size`/`list`/`getItemDetail`/
`getItemLimit`/`pushItems`/`pullItems` methods are confirmed on
`minecraft:barrel` in that dump (`references/peripherals.md:160`); what is not
confirmed is a turtle's side of it.

## What is deliberately not being done

**The 16-stack read cap stays.** Cause 2 is understood and is being left in
place, at the user's decision. Change 35 still banks coal above `fuelKeep`, so
coal can still end up in a slot the turtle cannot reach — the difference is that
a turtle topping itself to 2,000 off the coal it digs rarely needs to go
looking.

Change 47 is what will tell us whether that residual costs anything. **If the
diagnostic comes back showing a deep box full of buried coal, splitting the
depot into two containers is the next change** — dump and fuel — which
`probeDepot` already supports today: "one chest only: it is both. Two or more:
the one with coal in it feeds" (quarry.lua:1990). The cost is `kitWants` asking
for `2 * turtles` containers, six instead of three.

Two other options were considered and rejected in the interview:

- **Burning coal to the tank limit before dumping**, so nothing coal-shaped ever
  enters a private box. Rejected in favour of leaving the read cap alone for
  now.
- **A wrap-based read of the whole container as a fix.** It is not one — see
  cause 2. It survives only as the diagnostic in change 47.

## Tests

Tests 110–117, in `test_quarry.lua`, plus test 38 extended for `forageCoal`.
**Every one confirmed to fail against its own unfixed code** — a test that
passes against the bug asserts nothing, and eighteen tests here have been
confirmed non-vacuous that way.

| # | Asserts |
| --- | --- |
| 110 | A private depot rations to zero: a turtle docking at its own box takes what the trip needs with nothing held back. |
| 111 | `own` absent from an old `quarry.state` reads as private, not shared. |
| 112 | A shared box hands out at most `sharePerDock` in one dock. |
| 113 | Coal in the hold is burnt to `fuelKeep` at a leg end, and the overflow is banked. |
| 114 | `fuelShare` does not trigger a dock at a private depot. |
| 115 | The ascent fires at the first dry dock under twice the top-branch cost, not at `fuelLevel() < want`. |
| 116 | A climb it cannot afford halts at the depot, not part way up the trunk. |
| 117 | Foraging runs until the tank reaches `fuelKeep`, then resumes at the deepest unfinished level; a turtle that cannot reach `fuelKeep` parks at y=`topY` in its trunk (test 21 asserts the park). |
| 118 | `forageCoal = false` stops at the depot naming the switch, and does not climb. |

## Delivery

`lua5.3 test_quarry.lua`, `test_probe.lua` and `test_update.lua` before and
after. Push to `https://github.com/zaBees/cc`, verify against the commit-pinned
raw URL rather than `/main/` (CDN cache), then tell the user to run `update`.

Rewrite `RESUME.md` whole afterwards — changes 35–47 into the shipped list,
`fuelFloor` out of the Settled list and the per-turtle-depot entry amended,
`fuelKeep`/`sharePerDock`/`forageCoal` into the config notes, and the
`RESUME.md:695` correction amended rather than deleted, since it still holds
wherever a depot is shared.
