# quarry — setup, from placing blocks to pasting code

Everything you do in-game, in order. **Phases 1 to 5 are all built and all have
run in-game** — the check, one branch, the depot cycle, three turtles, and
turtle 1 deploying the other two. Each section says what it needs from you.

The short version: **place one mining turtle where you are happy to stand for a
long time, get the code onto it, run `--check`, and send me the URL it prints.**
Nothing else is needed to begin. The turtles dig their own trunks and can build
their own depot, so nothing gets hand-dug and nothing gets hand-placed unless
you want it to.

The one thing never yet proven in-game is the **depot cycle**: no container has
ever been placed down there, so docking, rationing and restocking are tested
only against the stubbed world here. §5c is the section that changes that.

---

## 1. Load the kit into turtle 1

**Put the whole kit into turtle 1's inventory and let it tell you what is
missing.** `--check` audits every slot against this list and prints a
`MISSING:` line naming the shortfall. You do not have to count anything
yourself.

| Item | How many | For |
| --- | --- | --- |
| Mining Turtle | 3 | one to run the program, two as *items in its inventory* for it to place later |
| Coal or charcoal | 192 (3 stacks) | a stack per turtle. The whole claim wants about 3,300. |
| Storage block | 1 | the depot: one box, for ore and for the coal all three share. A chest, a vanilla barrel, a Sophisticated Storage barrel or chest of any tier, an Iron Chest, a shulker box or a Create item vault all count. Bigger is better — a Sophisticated barrel is the best of these. A full depot no longer stops the run (the junk goes on the tunnel floor and the turtle calls home), but everything it digs after that is lost. |
| Disk Drive | 1 | the lava map, and the only way one turtle can hand code to another |
| Floppy Disk | 1 | goes in the drive |
| Wireless Modem | 3 | GPS. Turtle 1 is already wearing one, so 2 spares in the inventory. |
| Bucket, empty | 3 | one per turtle. Lava scooping is **confirmed working** on this server. |

The audit matches item names by pattern, not by exact id, and anything it does
not recognise it prints verbatim — so if it says `not recognised: …`, send me
that line and the audit learns this pack's real names.

A **Mining Turtle** is a turtle with a diamond pickaxe on it. A plain turtle
cannot dig and the program will do nothing useful. In a creative world take the
Mining Turtle straight from the inventory; on survival it is Turtle + Diamond
Pickaxe in a crafting grid.

**Every turtle needs a wireless modem.** `gps.locate` works through one and
nothing else, and GPS is how a turtle knows where it is after you walk away and
it freezes. Turtle 1 already has one — that is why its check got a fix — so the
audit asks for two spares and credits the one it is wearing.

To fit one by hand: put the modem in a slot, then `equip right` (the pickaxe is
on the other side). A turtle with no modem still runs, but only with a fixed
position in `quarry.conf`, and that cannot survive a freeze.

You do **not** need a chunk loader or a hub computer. The design uses neither.

---

## 2. Pick the spot — this is the one decision that matters

The claim is **3×3 chunks (48×48 blocks) centred on the chunk the turtle is
standing in when you first run it.** CC:Tweaked does not chunk-load, so what
keeps all nine chunks loaded is **you, standing in the centre chunk.** Walk
away and the turtles freeze mid-instruction; they resume from their state file
when you come back, so nothing is lost, but nothing progresses either.

So pick somewhere you are happy to sit, AFK, for a long time.

- Press **F3+G** to draw chunk borders, and **F3** to read your coordinates.
- Stand where you intend to stay. That chunk is the centre chunk.
- Put the turtle down **anywhere in that same chunk**. Exact block does not
  matter, and turtles 2 and 3 can go anywhere in it too — the branch pattern is
  keyed to the claim's corner, not to where a turtle happens to stand, so all
  three compute the same grid without talking to each other.

The claim then runs 16 blocks out from that chunk in every horizontal
direction, and from y=60 down to bedrock. `--check` prints the exact corners so
you can confirm before anything digs.

If you have OPAC claims to spare, forceloading those nine chunks is a bonus —
but the design does not assume it, and you should not count on it.

---

## 3. Place and prepare turtle 1

1. **Place the turtle** in your centre chunk, on the surface, with at least one
   block of air in front of it. It needs room to move later.
2. **Right-click it** to open its terminal.
3. **Label it.** Type:

   ```
   label set quarry1
   ```

   This is not cosmetic. An **unlabelled turtle loses its entire filesystem and
   inventory when broken**; a labelled one keeps both. If a turtle ever needs
   picking up and re-placing, this is what saves the state file.
4. **Fuel it.** Put a stack of coal in any slot and type:

   ```
   refuel all
   ```

   One coal is 80 fuel and the tank holds 20,000, so a stack gets you 5,120 —
   plenty for `--check` and the first real branches. Top it up before Phase 2.
5. **Check GPS.** Type:

   ```
   gps locate
   ```

   If it prints coordinates, you are done — the program will use them. If it
   prints that it could not find a position, that is fine too; see §6.

Leave turtles 2 and 3 in your inventory for now. Phase 4 is when they matter.

---

## 4. Get the code onto the turtle

**In the turtle's terminal**, type these two lines:

```
delete quarry
wget https://raw.githubusercontent.com/zaBees/cc/main/quarry.lua quarry
```

> **The `delete` is not optional.** CC's `wget` refuses to overwrite a file that
> already exists: it prints `File already exists` and downloads nothing, which
> looks very much like success. There is no force flag, and the CC shell has no
> `&&` or `;`, so it has to be two lines. If the turtle is brand new and has no
> `quarry` yet, `delete` says it cannot find the file — harmless, carry on.
>
> **The URL never changes.** It is the same two lines every time, however many
> builds go by. Everything is delivered from the GitHub repo.

**Then get the updater, once, and you never type those lines again:**

```
delete update
wget https://raw.githubusercontent.com/zaBees/cc/main/update.lua update
```

From then on, whenever a new build ships:

```
update
```

That pulls `quarry`, `alert` and `update` itself, does the `delete` for you, and prints
`quarry: N bytes, fletcher32 N` so the download can be checked against the
copy on my side without anybody transcribing anything. `update quarry` does
just the one. It never touches `quarry.conf` or `quarry.state`, and a download
that fails leaves the working copy alone — the turtle always has a program.

It also appends a timestamp to the URL, which matters: the `/main/` address is
CDN-cached and has served a previous build for minutes after a push. Typed by
hand you may get the old file and not know it; `update` cannot.
>
> The Phase 5 deployment probe is a separate, smaller program:
>
> ```
> delete probe
> wget https://raw.githubusercontent.com/zaBees/cc/main/probe.lua probe
> ```

**And one program that goes on a computer rather than a turtle:**

```
delete alert
wget https://raw.githubusercontent.com/zaBees/cc/main/alert.lua alert
```

`alert` prints what the mine sends home — so far, a depot that has filled up.
Run it on a computer with a wireless modem, near the claim: a modem's range
shrinks with depth, the same thing that stops GPS reaching the mine floor, so a
computer far away will hear nothing. An ender modem hears everything. Whatever
it misses is still in the report the turtle posts at the end.

Those lines are the whole delivery. The build behind them is the one tested
here — 66 tests against stubbed CC worlds, including a fake world with blocks
in it that the turtle actually mines.

Note that **Ctrl+V in a CC terminal pastes one line only** — that is why
delivery is a single `wget` and never the program text itself. Do not try to
paste the program.

When I change `quarry.lua` the URL stays the same — I push to the repo and you
re-run those same two lines. **The `delete` still matters every time:** `wget`
will not overwrite, so skipping it leaves you running the old build while the
screen says it downloaded. If you re-download within a few minutes of my saying
it is ready and get the old version anyway, that is GitHub's CDN cache — wait a
moment and do it again.

---

## 5. Run the check

```
quarry 1 --check
```

The `1` is the turtle index. It does not move, does not dig, and does not place
anything — Phase 1 is maths and a report. It will:

- write `quarry.conf` on first run, with every setting commented,
- print the claim corners, the three trunk positions, the branch pattern, the
  block and fuel totals, and how long a state save takes,
- **post the whole report to paste.rs and print a URL.**

**Send me that URL.** That is the round trip — I cannot see your screen, and a
CC terminal cannot be copied from, so the upload is how the numbers reach me.

What to look at yourself while you are there:

- **`corners:`** — are those chunks you are happy to stand in the middle of? If
  not, break the turtle, move, and re-run. Nothing has been dug.
- **`position:`** — if it says `NO FIX`, go to §6.
- **`state  :`** — the milliseconds-per-save figure. Measured at 1.35 ms on your
  server against a 400 ms move, so saving every block is free, as designed.
- **`kit    :`** — the audit. A `MISSING:` line tells you what to go and get.
- **`pattern:`** — a fingerprint. Run `--check` on all three turtles and this
  line, and the `corners:` line, must match exactly. If they do, the three are
  provably mining the same grid.

---

## 5b. Run Phase 2 — one branch, start to finish

Phase 2 makes the turtle actually mine: it drops to y=60, walks to its trunk,
sinks the trunk to the working level, takes the nearest branch row in its own
third, and mines all 48 blocks of it, chasing any ore vein it passes.

**It ships ready to mine.** Since 2026-08-27, at your instruction, the config it
writes on first run carries `dry = false` — so a bare `quarry 1` digs:

```
quarry 1
```

That is deliberate, and it matters more than it looks: `deploy` copies this same
file to turtles 2 and 3, and the old `dry = true` default is exactly what left
turtle 2 standing still on the first live deployment.

**To plan without digging**, set one line in the config — not in the program:

```
edit quarry.conf
```

Change `dry = false` to `dry = true`, save, exit. A dry run walks nowhere and
digs nothing; it prints the route it would take and what that costs. Read the
`route  :` and `fuel   :` lines. If the fuel line says `SHORT`, put more coal in
a slot and `refuel all` before going further.

The config survives a re-download; the program does not. That is why the switch
lives there — otherwise a new `wget` would silently reset whatever you chose.

What it does, in order, with a printed line at each step:

1. straight down to y=60 (above that is travel, not mining — your surface
   builds are safe),
2. across to the trunk at the centre of its third,
3. down the trunk to the working level (deepest first, so y=-59 unless bedrock
   stops it higher),
4. along the spine to the nearest branch row,
5. 24 blocks west, back, 23 blocks east, back.

Then it parks on the spine, prints a summary and posts it to paste.rs. **Send
me that URL too** — it carries the block counts, the fuel left, and the
`passed over:` line naming every ore-ish block this pack has that the config
does not yet mine.

## 5c. Phase 3 — the depot cycle

Phase 3 turns one branch into the whole job: branch after branch, level after
level, with a trip to the depot whenever the hold fills up.

**What you place, once, before running it:**

1. **A barrel under the trunk floor.** Go down the trunk the Phase 2 run cut,
   to the bottom. Break the block *below* the bottom block of the shaft and put
   a barrel there, so the turtle stands on it. That is the whole depot. The
   turtle finds it by looking down — nothing goes in `quarry.conf`.

   **Under, not beside.** The four sides of the trunk floor are all working
   rows: the branch legs run east–west through them and the spine runs
   north–south through them. A container on any side is a block the turtle
   later walks into and refuses to dig, which ends that leg and then stops the
   run outright. Underneath is the one neighbour the pattern never touches.
   A barrel rather than a chest because a chest with a block above it cannot be
   opened by hand — and the turtle is standing on this one.
2. **Coal in that barrel.** Every turtle takes what its trip needs and stops at
   a floor held back for the others (`fuelFloor`, 8 each by default), so three
   turtles share it without any coordination.
3. **Or hand the container to the turtle.** Run `quarry 1` with a barrel or a
   chest in its inventory and it digs out the block under the trunk floor,
   places the container there itself and banks its own coal into it.
4. **Optional: a disk drive with a floppy**, beside the trunk floor. That is
   the shared lava map: every source a turtle walks past gets written to
   `/disk/lava.txt`, and any turtle can go and fetch one when the coal runs out.
   A drive on a side does get mined out eventually, which costs the map and
   nothing else.

One container does both jobs: the spoil goes in and the fuel comes out of the
same box. That is the case the ration is written for — it sucks the lot, keeps
its share of the coal and puts everything else straight back.

**Lava is proven on this server, and it is on by default.** `quarry.conf` now
ships `lava = true`: the `--check` scoop test was run in-game on 2026-08-27, the
bucket came back, and issue #530 does not apply here. Nothing to switch on — the
turtle scoops sources it walks past whenever the tank is under `lavaFloor`
(4,000 by default), which is 1,000 fuel a bucket against coal's 80. Give each
turtle an empty bucket and that is all it needs.

**What the new report lines mean:**

- `depot  : container at the trunk floor x,y,z (dump down, fuel down)`
  — it found the barrel. `dump`/`fuel` read `down` for the one underneath, or a
  side number 0–3 for a container someone placed beside the floor. No such line
  at all and it mines one load and stops.
- `depot  : placed a container under the trunk floor` — it built the depot from
  a barrel or chest it was carrying.
- `depot  : docking with N slots used` — a trip home.
- `depot  : dumped; chest held N fuel items, took N fuel, tank N` — the ration.
- `resume : west leg of y=.. z=.., N out` — back to the exact block it left.
- `forage : depot is dry` — no coal left, so it goes to mine a top branch where
  the coal generates, which is work that was on the schedule anyway.
- `done   : N branches finished in this third` — in the summary.

**Lootr chests.** If a leg stops early with `blocked: lootr:lootr_chest`, that
is working as intended. Lootr containers cannot be broken by a turtle and hold
no items until *you* open them — mineshaft chest minecarts are Lootr chests in
this pack, so branches meet them fairly often. The turtle leaves the rest of
that leg, comes back to the spine and carries on with the other one. The
`left alone:` line in the summary gives you the block and its coordinates: go
and open it yourself, the loot is still there.

Roughly 250 moves plus vein chases. It stops itself in three cases, each
printed as `STOPPED:`:

- **not enough fuel** — refused before descending, so it is still on the
  surface where you can reach it,
- **fuel reserve** — it stopped mid-branch while it still had the fuel to walk
  home. Refuel it and run `quarry 1` again; it resumes the same branch from the
  block it stopped on,
- **inventory full** — Phase 2 has no depot yet, so a full turtle stops rather
  than digging into a full inventory, which destroys the drop. Empty it by hand
  and re-run.

It also refuses, always, to dig storage — a chest, a barrel of any mod, a
shulker box, a Create item vault — or a turtle, computer or disk drive. If one
is in its way it stops and names it rather than breaking it.

You can kill it at any moment — log off, walk away, break the world. It saves
its position and task on every single block, so `quarry 1` picks up where it
stopped. Carry the turtle to a different chunk and it notices, drops the old
claim, and starts a new one.

---

## 5d. Phase 4 — all three turtles

Phase 3 is one turtle doing the whole claim alone. Phase 4 is the other two
joining it. Nothing about the claim changes: the same 48x48, the same pattern,
split into three 16-block strips of z, one turtle to a strip.

**Where to put turtles 2 and 3.** Within a few blocks of where you put turtle
1, and in the same chunk if you can. The claim is worked out from the block a
turtle is launched on and snapped to chunk borders, so two turtles launched a
few blocks apart get the same claim — but two launched sixty blocks apart get
two different claims and will mine two different regions quite happily.

Each one needs the same kit as turtle 1: a diamond pickaxe equipped, a wireless
modem equipped on the other side, coal, and a bucket if you have lava turned
on. Get the code onto each of them the same way as section 4.

**Then run them with their own number:**

```
quarry 1
quarry 2
quarry 3
```

The number is not a label, it is the strip: 1 takes the lowest z third, 3 the
highest. Run the same number on the same turtle every time — a turtle handed a
different number picks up a different strip and leaves its old one unfinished.
`turtles = 3` in `quarry.conf` is what splits the claim; lower it to 2 and each
turtle gets half.

**One chest is enough for all three.** Put the depot under whichever trunk you
like — turtle 1's is the obvious one. The other two probe under their own trunk
first, find nothing, and then walk the spine and look under the others. They do
that once, remember the answer, and go straight there afterwards. Three chests,
one under each trunk, also works and saves the walk, but then each turtle has
its own coal and they stop sharing a find.

**What the new lines mean:**

- `taken  : y=.. z=.. is already cut -- another turtle has it` — it walked to a
  branch mouth, found air, and left the row to whoever is in it. That is the
  whole claiming protocol: no messages, no shared file, one look.
- `giveway: turtle 2 waiting, another one is in the way (1 of 6)` — two turtles
  met in a 1-wide tunnel. The lower number waits in shorter bursts and
  effectively wins the corridor; the higher one is the one that ends up moving.
- `giveway: the way is still held -- going back to the depot to re-pick` — six
  tries and still blocked, so it gives that branch up and takes another. A
  wasted trip is cheaper than two turtles nose to nose forever.
- `depot  : looking under turtle 1's trunk at z=..` — the walk to find the
  shared chest. Once per claim.

**Recall — bringing them up.** When you want to log off somewhere else, move
the mine, or just collect them:

```
Ctrl+T        (hold it, to stop the miner)
quarry 1 recall
```

on each turtle. It walks back along its branch to the trunk, climbs the shaft
it cut, crosses to the block it was launched on, and parks. Nothing is lost —
the branch it was on is still in `quarry.state`, so `quarry 1` with no argument
sends it straight back to the block it stopped on.

Recall is per-turtle on purpose. Normal returns are not: a turtle that fills up
goes to the depot on its own without idling the other two.

**Do not stand in the mine.** The turtles refuse to dig each other, and they
will refuse to dig around you the same way — you are not on the deny list, so
what actually happens is worse: they attack. Watch from the surface, or from
the depot corner.

---

## 6. If it says NO FIX

There is no GPS constellation in range. Two options, and the second is
one line:

- Build a GPS constellation (four computers with wireless modems at known
  coordinates). Overkill for this.
- **Tell the program where it is.** Read your coordinates off F3, then in the
  turtle terminal:

  ```
  edit quarry.conf
  ```

  Find the three commented lines near the top and uncomment them with the
  turtle's own position:

  ```
  startX = 137
  startY = 71
  startZ = -42
  ```

  Ctrl to open the menu, Save, Exit. Re-run `quarry 1 --check`.

Use the **turtle's** block position, not yours, if you are standing next to it.

`startDir` has to go in too, because a turtle told its position by hand cannot
measure which way it faces: `0` = +z, `1` = -x, `2` = -z, `3` = +x. At the
prompt you can also type what F3 actually shows — `+z` or `south`, `-x` or
`west`, `-z` or `north`, `+x` or `east`. In the config file itself it has to be
the number.

Deploying with manual coordinates is fine. Turtle 1 writes each deployed
turtle's OWN position and heading onto the floppy rather than handing on its
own, so turtles 2 and 3 do not both think they are standing where turtle 1
stands.

**With all four lines set, no turtle needs a modem at all.** Nothing calls GPS
any more, so the kit audit stops asking for modems and a deployed turtle no
longer waits for one before it starts. Keep one on if you want the `alert`
messages; the mine does not need it.

**It asks, rather than giving up.** A run that cannot find itself now says what
is wrong and then wants the four numbers typed in on the turtle:

```
position: my x?
```

Type it, press enter, answer y, z and the heading the same way. It writes them
into `quarry.conf` for you, so the next reboot does not ask again. Press enter
on an empty line — or leave it alone for a minute — and it stops exactly as it
used to, without guessing anything.

An answer it cannot read only costs you that one answer: it says so, asks the
same question again, and keeps the coordinates you already typed.

**Delete those four lines once GPS works again.** A pinned position is a
starting value, not a sensor: the turtle believes it until its own
`quarry.state` takes over, and a turtle picked up and carried somewhere else
cannot tell.

---

## 7. Lava bucket — already settled, keep one on each turtle

**Tested and working on this server.** The bucket comes back and the fuel goes
up, so issue #530 is not live here. Give every turtle **one empty bucket** and
leave it there — a lava source is 1,000 fuel against coal's 80, and the turtles
will scoop the ones they walk past.

The original test procedure, kept in case you ever want to re-run it:

The design wants turtles to scoop lava sources for fuel — 1,000 fuel each,
against coal's 80. There was a CC:Tweaked bug (issue #530) that deleted lava
buckets on placement, and I would rather find out on one bucket than on three
turtles mid-job.

If you want to close it now:

1. Find a lava source at the surface, or in a cave you can reach.
2. Put the turtle **directly above it**, with an **empty bucket** in a slot.
3. Open the turtle terminal and confirm `quarry.conf` has `dry = false` — it
   ships that way now, so there is usually nothing to change.
4. Run `quarry 1 --check` again.

The report will say whether the fuel level rose and whether the bucket came
back. The bucket is the only thing at risk in that test; nothing else moves.
Remember that a bare `quarry 1` afterwards will mine for real.

Skip this if you would rather not — the program just leaves the feature off and
loses a slot's worth of convenience.

---

## 8. Later — do not build these yet

**The depot (Phase 3) has landed — §5c is the current word on it.** In short:
one box, UNDER the trunk floor, roughly 130 blocks straight down, and the
turtle will place it itself if you hand it a barrel. Do **not** hand-dig down
to it; the turtles cut their own trunks and you take that shaft afterwards.
Optionally a disk drive with a floppy beside the floor — the shared lava map,
plain text, one source per line, readable in-game with `edit`.

**Turtles 2 and 3 (Phase 4, or Phase 5 automatically).** By hand it is the same
preparation as turtle 1 — label them `quarry2` and `quarry3`, fuel them, `wget`
the same URL — launched as `quarry 2` and `quarry 3`. Place them anywhere in the
centre chunk; they will agree with turtle 1 on the grid.

**Turtle 1 does this for you, and it is built.** Standing on its launch block
with the whole kit aboard, a plain

```
quarry 1
```

deploys the other two before it descends — `deploy : turtles in the hold --
staffing the mine before I descend` — and then goes and mines. Turtles in its
inventory are the signal; once they are placed it never does it again on that
claim. To deploy and nothing else, run `quarry 1 deploy`.

It audits the kit first, against what `turtles` in `quarry.conf` actually asks
for, and asks before going on short. Then it places the disk drive one block up
and in front of itself, drops the floppy into it, copies its own program onto
the floppy, and for each of the other turtles: places it on the ground under
the drive, hands it a wireless modem, 64 coal and a bucket, and waits for it to
walk off to its own trunk.

**Be ready to right-click each new turtle.** Deploy sends it a `turnOn`, and
that has worked, but twice in-game the new turtle was still dark afterwards —
unlabelled, program still only on the floppy. One right-click always fixes it:
that turns it on and the disk startup runs, which labels it, takes the program,
the config and the claim anchor off the floppy, equips the modem on whichever
side is not its pickaxe, burns the coal and sends it to its own trunk. Deploy
asks for the click by name after twelve seconds of silence, and waits:

```
deploy : nothing from turtle 2 yet -- it is still switched off.
         RIGHT-CLICK IT. That turns it on and the disk startup runs.
deploy : enter = done, s = skip this turtle, q = stop deploying.
```

Enter when you have clicked it, `s` to leave that one in the hold and go on to
the next, `q` to stop deploying altogether. Say nothing for sixty seconds and it
carries on waiting exactly as it used to — a turtle rebooted by a chunk reload
with nobody watching still gets on with it.

Leave two blocks clear in front of turtle 1, at its own height and one above.
It will not dig your build to make room; it stops and says so.

The drive and the floppy stay where they are afterwards. That is the lava map's
home, and it is the only channel by which one turtle can hand code to another.

**Deployment happens up here, not at the claim floor.** Each turtle digs its own
trunk. All three agree on the same claim because the claim comes from the block
each was standing on when it started, and they all start in the centre chunk.

**The depot builds itself too.** Hand turtle 1 a barrel instead of placing one
yourself and, at its trunk floor, it digs out the block underneath and puts the
barrel there, then banks the coal it is still carrying into it. If the block
below is bedrock — which it usually is, since bedrock scatters up through y=-60
and the floor sits at y=-59 — it falls back to a niche beside the trunk one
level up and says so. A depot it finds always beats one it would build, so
place one yourself if you would rather. It keeps the coal for the depot rather
than burning it, so expect `fuel   : keeping 64 minecraft:coal for the depot`
on the way down.

That is why the kit in §1 lists three turtles when only one of them runs the
program — the other two ride in turtle 1's inventory as items.

---

## 9. If something goes wrong

| Symptom | What it means |
| --- | --- |
| `run this on a turtle, not a computer` | You are on a computer, or a plain turtle. Needs a Mining Turtle. |
| `quarry.conf:12: bottomY wants a number` | You typed something the config parser could not read. It names the line; fix it and re-run. Nothing digs until the config parses. |
| `NO FIX` | No GPS. See §6. |
| `turtle index 4 is outside 1..3` | Launch it as `quarry 1`, `2` or `3`. |
| Nothing printed at all after `quarry starting` | It is working, or it is stuck. That first line exists precisely so silence afterwards means something. Give it a moment, then tell me. |
| Turtle stopped and will not resume | You probably walked out of the centre chunk. Come back; it picks up from `quarry.state`. |
| `STOPPED: not enough fuel` | It refused the trip while still on the surface. `refuel all` and re-run. |
| `STOPPED: fuel reserve` | It stopped mid-branch with just enough left to walk home. Refuel and re-run; it resumes the same branch. |
| `STOPPED: inventory full` | Phase 2 has no depot. Empty it by hand and re-run. It stopped rather than destroying the drop. |
| `STOPPED: refusing to dig …` | Something on the deny list — any storage block, turtle, computer, disk drive — was in its path. Move it or move the turtle. |
| `notify : the depot at x,y,z is FULL` | The depot will not take another stack. The junk tier goes on the tunnel floor and the run carries on, but everything dug after that is lost. Empty the box. If the hold is full of ore as well it stops instead, and waits for you. |
| `moved: this is not the claim in quarry.state` | You carried it to a different chunk. It dropped the old claim and started a new one. That is intended. |
| It prints the route and stops | `dry = true` in `quarry.conf`. Set it false to mine. |
| `no http, report not uploaded` | HTTP is off for that computer. Read the numbers off the screen and tell me the ones you can. |
| A turtle sitting there saying nothing | Run `quarry 2 --check` on it. The `last   :` line is why its previous run stopped — the reason is kept in `quarry.state`, so it survives the reboot and the scrollback. |
| A deployed turtle never moved | It is switched off. Right-click it. If its screen is already lit, type `disk/startup` on it. |
| `something is in front of me, and it is not a turtle` | The deploy spot is blocked by your build or by terrain. It asks: `d` digs it out, enter says you have cleared it, `s` skips that turtle, `q` stops. Unattended it refuses rather than digging. |
| `a turtle is already standing here -- adopting it` | A turtle from an earlier deploy never booted and is still in the spot. It is not in the way, it *is* that turtle: the deploy switches it on and feeds it where it stands, rather than refusing. |
| `the drive from the last run is still here -- reusing it` | Normal on every deploy after the first. The drive and floppy are told to stay put, so the next deploy picks them up again instead of failing. |
| `I cannot read "..."` after typing a heading | Type any of `0`/`+z`/`south`, `1`/`-x`/`west`, `2`/`-z`/`north`, `3`/`+x`/`east`. It asks again for just that one answer and keeps the coordinates you already typed. Enter on its own still gives up. |
| `turtles = 1 in quarry.conf, so there is nobody to deploy` | You lowered `turtles`. Raise it, or just run `quarry 1` and mine the whole claim with one. |

---

## The one-page version

```
                        Stand in the chunk you will AFK in
                                     |
                        Place Mining Turtle in that chunk
                                     |
              label set quarry1  ->  refuel all  ->  gps locate
                                     |
        (turtle)  delete update
        (turtle)  wget https://raw.githubusercontent.com/zaBees/cc/main/update.lua update
        (turtle)  update                    <- gets quarry and alert, and every build after
                                     |
                          (turtle)  quarry 1 --check
                                     |
                        send me the URL it prints
                                     |
                  (turtle)  quarry 1        <- deploys 2 and 3, then mines for real
                                     |
        (optional, on a computer near the mine)  alert
                                     |
        (optional)  edit quarry.conf        <- dry = true to plan, not dig
                                     |
                        send me that URL too
```
