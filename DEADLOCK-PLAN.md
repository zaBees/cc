# Three turtles, one corner: the deadlock plan

Written 2026-08-29 from in-game logs `qhVSH` (turtle 1) and `fPSF1` (turtle 2).
This is the design note for the fix. Implement against this, not against a
reading of the logs.

## What the logs actually show

Both turtles worked well: 635 and 639 blocks, 11 and 12 branches, five depot
trips each, lava scooped, the parking fix from the previous build doing its job.
Neither crashed. Both ended the same way:

```
depot  : docking with 6 slots used, 4066 fuel
giveway: turtle 1 waiting, another one is in the way (1 of 12)
... twelve times ...
park   : stepped off the spine to 1864,-58,150
work complete
```

`work complete` is a lie there — the run stopped because it could not reach the
depot, not because the third was finished.

## The real cause

Three facts together make a guaranteed deadlock, and no amount of waiting fixes
it:

1. **There is one depot.** In this run it is under turtle 1's trunk at z=151
   (turtle 1 could not reach the middle trunk, so it fell back to its own —
   working as designed).
2. **Every dock trip from every turtle ends at that one block.** `dock()` walks
   to `st.depot` and there is only one.
3. **The spine is one block wide** and the only passing places are branch
   mouths, every 5 blocks.

So every dock funnels all three turtles down a single-file corridor to a single
block. Turtle 1 walks +z toward z=151; turtle 2 walks −z toward z=151; they meet
head-on. `giveWay` only ever waits. Both wait. Neither is going anywhere, so
after twelve tries both give up.

The symmetry is the bug. **Waiting cannot resolve a head-on meeting in a 1-wide
corridor — somebody has to reverse.**

`stepAside()` exists and is meant to be that, but it does not clear a corridor:
it enters a branch mouth only when the turtle is *already standing on a branch
row*, and otherwise steps back exactly one block, which leaves it still in the
corridor. It is also only reachable from `goTo`'s `blocked()`, capped at three.

## The fix, in three layers

Layer 1 removes most of the meetings. Layer 2 resolves the ones that remain.
Layer 3 is unrelated and is about the boot problem. **All three are wanted.**

---

### Layer 1 — one depot per turtle, under its own trunk

This reopens a Settled decision ("The depot is ONE box", "One container serves
all three"). It is being reopened deliberately, because it is the direct cause
of the funnel.

With a depot under each turtle's own trunk, **no turtle needs to leave its own
third while mining at all.** The spine between thirds is used once, on the way
in. The head-on meetings stop happening rather than being recovered from.

- `kitWants`: `chest = n` (one per turtle), not `1`.
- `deployOne`: `handOver("chest"/storage, 1, "container")` alongside the modem,
  coal and bucket — same pattern as the bucket, which is already one per turtle.
  Match with the existing `STORAGE` word list, not a new one.
- `buildDepot`: build under **this turtle's own trunk**. Delete the walk to the
  middle trunk — it exists only because there was one box. Keep the bedrock
  fallback (under the floor first, x-side niche a level up when bedrock blocks
  it) exactly as it is.
- `findSharedDepot` **stays** as the fallback for a turtle that has no container
  and finds nothing under its own trunk. It is still correct and still needed.
- The kit audit's `why` text for the container becomes "one per turtle, under
  its own trunk".

**Known cost, accepted:** coal sharing degrades. `fuelShare` and the `fuelFloor`
ration were written for one shared box; with three, a find by turtle 1 cannot be
burnt by turtle 3. The ration logic does not need changing — it rations from
whatever box the turtle is docked at, and the floor is per-other-turtle, which
is now conservative rather than wrong. Do not rewrite the ration.

**Do not** add a config key for this. The kit decides: a turtle that has a
container builds its own; one that does not falls back to the shared sweep,
which is the behaviour that already exists.

---

### Layer 2 — a yield that actually clears the corridor

Still needed: two turtles can still meet on the way in, at the launch column,
and on a `recall`.

**2a. Retreat to a passing bay.** Replace `stepAside()`'s "step back one block"
with a real retreat:

- Walk *backwards along the spine*, away from the blocker, up to 5 blocks,
  until standing on a branch row (`isBranch`).
- Turn into the mouth (west) and step in. That is a row that gets mined anyway,
  so it costs nothing.
- Return true. The caller waits there until the way is clear, then resumes.

If no bay is found inside 5 blocks, fall back to the current one-block reverse
— better than nothing.

**2b. Break the tie by index, with no messaging.** A blocked turtle cannot see
the other's index, so the asymmetry has to come from its own:

```
retreatAfter = math.max(1, YIELD_TRIES - 3 * idx)
```

Turtle 3 retreats after 3 waits, turtle 2 after 6, turtle 1 after 9. That is the
settled "lower wins, higher moves" rule implemented with local knowledge only.
The index-scaled sleep already in `giveWay` stays.

**2c. Keep the split.** `giveWay` called from inside `mineLeg` must stay
wait-only — a sidestep there desyncs `st.along`, which is settled and was paid
for once already. The retreat belongs in `goTo`. Do not move it.

**2d. `work complete` must not be printed for a run that gave up.** A run that
ends on a jam sets `halt` with a real reason: name the block, the position, and
that it was another turtle. Reaching the depot and failing is a stop, not a
finish.

---

### Layer 3 — the boot problem

Evidence: "reboot works, running the actual code doesn't, still doing it
manually." So `peripheral.call("front","reboot")` reaches the new turtle and it
reboots — and the program still does not start. Something between "the turtle
booted" and "BOOT ran" is failing, and no log distinguishes them.

**Do not guess. Split the boot so one in-game run says which half failed.**

- `/disk/startup` (and `/disk/startup.lua`) becomes a **tiny** bootstrap: append
  one line to a floppy log saying it ran, then `shell.run` the real script.
  Nothing else. No peripheral calls, no loops, nothing that can throw before it
  has left a trace.
- The real logic moves to `/disk/boot.lua`, unchanged apart from being a
  separate file, and is wrapped so a failure is written to the floppy log rather
  than only to a screen nobody is reading.
- The deployer already tails that floppy log. With this split its output tells
  the difference between:
  - nothing at all — the disk startup never ran, so this is a CC-side problem
    (`shell.allow_disk_startup`, or the drive not being seen);
  - "startup ran" and no more — the real script threw, and the next line says
    where.

That is one run to a real answer instead of three to a guess.

---

## Constraints — do not break these

Every item below is settled and was paid for with an in-game run. Re-read
`RESUME.md`'s Settled and Corrections lists before touching anything.

- **CC:Tweaked is Lua 5.2.** No `//`, no bitwise. `goto` is fine.
- **`pcall` prepends its own success flag.** This has been got wrong four times.
- The depot goes **under** the trunk floor, x-side niche a level up when bedrock
  blocks it, **never** beside the floor.
- `giveWay` inside `mineLeg` stays wait-only.
- One self-contained file, no `require`. `local DRY = true` at the top.
- The `STORAGE` word list is the single answer to "what is storage". Do not
  re-split it.
- Nothing hard-codes `/disk`; `diskPath()` asks the drive.
- Do not sweep the spine for the shared depot on boot.

## Tests

Every change gets a test in `test_quarry.lua`, appended after the last one, and
**each must be confirmed to FAIL against the unfixed code** — revert the one
hunk, run the suite, check it stops on that test's own assertion. A test that
passes against the bug asserts nothing.

Minimum set:

1. Three turtles, three containers: each builds under its own trunk, and no
   turtle's dock walk leaves its own third.
2. The kit audit asks for `turtles` containers and says so.
3. `deployOne` hands a container across.
4. A turtle blocked head-on retreats to a branch mouth and ends up off the
   spine, more than one block back.
5. The retreat threshold falls with index: turtle 3 retreats sooner than
   turtle 1.
6. A run that ends on a jam reports a stop, not `work complete`.
7. The boot script written to the floppy is a bootstrap that logs before it
   runs anything, and the real logic is a separate file on the floppy.

Existing tests that encode the one-shared-depot behaviour (33, 62, 100, and any
that assert the middle-trunk walk) will need rewriting to the new rule. Rewrite
them; do not delete them.

Run all three suites before and after:

```
lua5.3 test_quarry.lua && lua5.3 test_probe.lua && lua5.3 test_update.lua
```
