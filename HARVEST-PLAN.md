# Harvest plan — boot, routing, and the fuel split

Written 2026-08-29 from the user's three complaints and one reference program.
Same shape as `FUEL-PLAN.md`: this is the reasoning, the code is the delivery.

Read `RESUME.md` first. Nothing here reopens anything on its Settled list.

---

## The three complaints

1. **"I still need to manually run `cd disk` and run `quarry 2`/`quarry 3`."**
   The deploy places the turtle, turns it on, reboots it twice, and still ends
   with a player walking over and typing. Two builds have attacked this and it
   is still happening.
2. **"Turtles still return to the spine sometimes to start a new tunnel — make
   it return through a tunnel it has to dig anyway."** `pairPlan` already does
   exactly this. Something is throwing the pair away.
3. **"How does fuel get split when only 1 turtle is provided, or less?"** The
   kit audit, the hand-over and the ration were all written for three turtles.

And one reference to mine: `jnordberg/minecraft-replicator`.

---

## What the replicator is worth, and what it is not

`replicator` is a 1,641-line self-replicating turtle from the CC 1.6 era. Read
in full. Its movement primitives (`simpleMove`), its refuel, its inventory
compaction and its anti-collision dance are all things `quarry.lua` already
does at least as well — `clear()` already re-digs falling gravel, already
attacks, already guards an empty tank, and `giveWay`/`stepAside` beat a random
back-off. **Three things in it are worth taking.**

- **`peripheral.call(side, 'isOn')`.** Replicator asks the turtle it placed
  whether it is switched on. `quarry.lua` never asks, so every message it
  prints about turtle 2 being "still switched off" is a guess. `isOn` turns
  the guess into a fact and picks the right action: `turnOn` for a turtle that
  is off, `reboot` for one that is on and never ran the disk startup. Those
  are different failures and they have been indistinguishable in every log so
  far.
- **`setupFloppy`'s retry.** Replicator loops on `disk.getMountPath` up to 20
  times, with a move up and back down after ten, because *"sometimes the disk
  drive won't show up."* `runDeploy` calls `diskPath()` once after dropping the
  floppy in and errors out if it is nil. Same stale-peripheral problem as
  CC:Tweaked #660, which this program already works around elsewhere.
- **`disk.setLabel`.** Replicator names each floppy after the baby it is for.
  Costs one line and puts the turtle number on the disk in the drive.

**The Advanced-Math library is not applicable.** Its five modules are matrix,
quaternion, linear-equation solving, PID and statistics. There is no vector,
geometry, pathfinding or fuel maths in it, it is a multi-file `require`
library, and this program is one self-contained file by rule. The fuel maths
below stays arithmetic in-file.

---

## A — the boot, fully automatic

**The user's instruction, 2026-08-29: "make it auto run quarry 2/3 I don't want
to do it myself."**

### The cause, settled in-game the same day

Turtle 2's screen, before anybody types anything:

```
CraftOS 1.9
> _
```

A bare shell prompt. The turtle is placed, switched on, and idle. And:

> *"`disk/startup` doesnt work, quarry never ran so no startup. `disk/quarry 2`
> works tho"* [user, 2026-08-29]

**There is no `startup` file on the floppy.** The program is there —
`disk/quarry 2` runs it — and the boot script that should have run it is not.
The disk startup never fires because there is nothing to fire.

That retires the whole reboot theory. The turtle boots correctly; nothing is
stale, nothing needs turning on twice. Three builds have now been spent making
a turtle re-run a boot script that was never on its disk.

### Why the floppy has a program and no boot script

`runDeploy` writes the floppy in this order:

1. `copyStripped(me, DISK .. "/quarry")` — the program, about **83 kB**.
2. `quarry.conf`, then `quarry.state`.
3. Inside the per-turtle loop: `startup.lua`, `startup`, `boot.lua` — a few
   hundred bytes each, and the only three files that make a turtle boot.

**The three that matter are written last, and they are the ones that get
squeezed out.** A floppy holds 125 kB by default and the server may be set
lower. Worse, nothing notices: the write loop counts *handles opened*, not
bytes landed —

```lua
local h = fs.open(name, "w")
if h then h.write(BOOTSTRAP:format(n)) h.close() wrote = wrote + 1 end
```

`fs.open(..., "w")` succeeds on a full disk. The `write` is what fails, and its
failure is never looked at. So the deploy prints *"wrote the boot script for
turtle 2 (2 startup names + boot.lua)"* about a floppy carrying none of them,
and then spends ninety seconds wondering why the turtle will not boot.

### The fix

**A1. Write the boot files FIRST.** `startup`, `startup.lua` and `boot.lua`
before the 83 kB payload. They are the smallest files on the disk and the only
ones without which nothing happens. The startup body needs only N, which is
known before the copy.

**A2. Read back every write.** Reopen each file after closing it, read it, and
compare. A write that did not land is reported loudly and by name. Same check
on `quarry` itself.

**A3. Report the space.** `fs.getFreeSpace(DISK)` before and after the payload,
and the size of every file written, on one line. If the payload will not fit
alongside the boot files, **refuse the payload rather than write a floppy that
cannot boot** — a turtle that can be started with `disk/quarry N` beats one
carrying a truncated program.

**A4. Retry the mount.** Harvested from replicator, which loops on
`disk.getMountPath` up to 20 times because *"sometimes the disk drive won't
show up."* `runDeploy` calls `diskPath()` once and errors if it is nil. 20
tries, half a second apart, with a `turnRight`+`turnLeft` after the tenth to
force the peripheral refresh — the same trick `deployOne` already uses.

**A5. The floppy carries the turtle number.** `quarry.lua` reads
`index = index or 1`, so `cd disk` then `quarry` — what the user has been
typing — runs **turtle 1's** program: turtle 1's third, turtle 1's trunk, and a
deploy that places yet another turtle. Write N to `DISK/index` beside
`boot.lua`, and on the off-the-floppy route take the index from there when no
number was typed. `disk.setLabel(dir, "quarry" .. n)` at the same time,
harvested from replicator.

**A6. The fallback line is `disk/quarry <n>`, not `disk/startup`.** The user has
confirmed which of the two works. With A5, a bare `disk/quarry` is correct too.

### Kept, demoted

**`isOn`, `getLabel` and the reboot ladder stay** — harvested from replicator,
and cheap. `peripheral.call("front","reboot")` is a no-op on a computer that is
OFF, and the old code fired it at 6s and 16s without ever confirming the turtle
came on, so on a turtle whose `turnOn` did not take it did nothing at all. The
order is now turnOn → confirm `isOn` → reboot → reboot → shutdown + turnOn, and
`getLabel` is a faster liveness signal than the floppy log because a booted
turtle labels itself `quarryN` within seconds. None of this is the fix any
more. It is the backstop, and it costs nothing when it is not needed.

---

## B — coming home through rock

`pairPlan` cuts a row pair as four legs — `a` west out, `b` west inward, `b`
east out, `a` east inward — with a 5-block jog at each rim instead of a
24-block walk back down a corridor that is already air. It works. **Two paths
throw it away, and both of them run constantly.**

**B1. A dock destroys the plan.** `mineLeg` sets
`st.needDock, st.branch, st.plan, st.step = true, nil, nil, nil` when it gives
a leg up to a jam, and the dock path in `runMine` clears `st.plan` through
`forage`. A hold fills every couple of legs, so most pairs never get past their
second leg. The plan and the step survive a dock; only the *branch* is
re-picked, and only when foraging actually moved the turtle to another level.

**B2. An interrupted row is re-cut out of the spine, unpaired.** `pairPlan`'s
first branch: a row with a half-filled `st.cut` entry returns its leftover legs
as a bare list with no `inward` on any of them and no partner row. That is
correct for *where the turtle stands* the moment it comes back from the depot —
it is on the spine, and the cut part of the leg is air from the spine outward —
but it should only apply to the leg that was actually interrupted. Once that
leg reaches the rim, the rest of the row pairs with a neighbour exactly as a
fresh row does.

**B3. A dock is not an obstacle.** `runMine` drops `inward` from every
remaining leg when a leg stops short, on the reasoning that the rock it stopped
on is between the turtle and the rim. A dock also stops a leg short, and there
the reasoning does not hold: nothing is in the way, the turtle simply went to
empty out. Downgrade only when `obstacle` is set, not when `st.needDock` is.

Together these mean a turtle that docks mid-pair comes back, finishes the leg
it was on, and keeps jogging at the rim for the rest of the pair. No new
geometry, no change to the pattern, no change to `isBranch`. The claim is the
same claim; only the order of the legs changes.

---

## C — the fuel split with one turtle, or with less

Three separate questions the code currently answers by accident.

**C1. `turtles = 1` still demands a drive and a floppy.** `kitWants` returns
`drive = 1, floppy = 1` unconditionally. A solo mine deploys nobody and shares
its lava map with nobody, so both are dead weight and the audit refuses a kit
that is in fact complete. With `turtles == 1`: no drive, no floppy, no turtle
item, one container, one bucket, 64 coal.

**C2. The hand-over gives 64 from one slot and does not count the cost.**
`handOver("coal", 64, ...)` finds the *first* coal slot and drops up to 64 out
of it. A slot holding 30 hands over 30 and says it succeeded. Worse, with
`turtles = 3` and 100 coal aboard, turtle 2 gets 64, turtle 3 gets 36, and
turtle 1 descends 119 blocks on what is left, which may be nothing.

**The rule, stated once:** *coal aboard at the start of a deploy is divided
evenly between every turtle the mine will run, the deployer included.* With
`C` coal aboard and `k` turtles still to place, each placed turtle gets
`min(64, floor(C / (k + 1)))` and the deployer keeps the rest. A full kit
(64 × n) splits into exactly 64 each and the rule is invisible.

**Worked example, the user's own [2026-08-29]: 128 coal, three turtles.** Two
still to place, so the divisor is three. Turtle 2 gets 42, turtle 3 gets 42,
and turtle 1 keeps the remaining 44 — 42 each and the two-coal remainder stays
with the deployer, which is the turtle nobody can hand coal to later. Today
that same 128 goes 64 to turtle 2, 64 to turtle 3, and **nothing** to turtle 1,
which then descends 119 blocks on an empty tank. A short kit is
shared instead of being spent first-come — and the deployer, which is the one
turtle that cannot be handed coal by anybody, is no longer the one that goes
without. Hand-over walks every coal slot rather than the first.

**C3. `turtles = 1` is a whole-claim run and needs no ration.**
`thirdOf(c, 1, 1)` is the whole claim, the depot under the only trunk is that
turtle's own, `ownDepot()` is true, `sharePerDock` never applies and `restock`
takes what the trip needs. That is already right. It gets a test so it stays
right, because every ration bug so far has been a shared-box rule leaking into
a private box.

**"Or less" — fewer turtles provided than `conf.turtles`.** The deploy already
records `st.staffed` and carries on; the claim is still split `conf.turtles`
ways, so an unstaffed third is simply never mined. That is the correct
behaviour and it is not changed here: lowering `turtles` mid-run would move
every other turtle's trunk and third, and the trunks are already cut. What
changes is that the coal is split by how many will actually run.

---

## Work packages

| # | Package | Touches |
| --- | --- | --- |
| A | boot: `isOn`, mount retry, floppy index, one instruction | `deployOne`, `runDeploy`, the floppy route in `main` |
| B | routing: keep the pair across a dock | `mineLeg`, `pairPlan`, the plan loop in `runMine` |
| C | fuel: solo kit, even coal split | `kitWants`, `handOver`, `runDeploy` |

Run in that order, one at a time — all three edit `quarry.lua` and append to
`test_quarry.lua`. Every change gets a regression test **confirmed to fail
against its own unfixed code**, per the standing rule. `lua5.3
test_quarry.lua`, `lua5.3 test_update.lua`, `lua5.3 test_probe.lua` all pass
before anything is pushed.
