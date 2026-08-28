# Deploy plan -- issues found in-game 2026-08-28 (turtle 2 never moved)

**Status: all nine built and tested on 2026-08-28.** Tests 75-83 in
`test_quarry.lua` cover them, each confirmed to fail against the unfixed
code. `RESUME.md` carries the list of what shipped; this file is kept for the
reasoning behind each one.

Written from what the user reported after `quarry 1 deploy` on manual GPS:
turtle 2 stood there, its program was only on `/disk`, no modem got equipped,
it later dug a tunnel of its own, and both turtles ended up stacked on the
depot saying "stopped". Nine changes, in the order they should be made. Each
one names the code it touches, and the check that proves it.

Items 1, 2 and 4 were the ones actually blocking the run; the rest are things
the same report makes visible.

---

## 1. A placed turtle does not turn itself on -- ask, do not assume

**Evidence.** `deployOne` (quarry.lua:2823) places the turtle and sends
`peripheral.call("front", "turnOn")`. That has worked -- `RESUME.md` records a
placed turtle being visible on `front` in-game -- and it did not work here:
twice on 2026-08-28 the new turtle was left unlabelled, with no `/disk/startup`
run and no modem equipped. Whichever way that goes on the next run, a turtle in
that state is switched off, and one right-click is the one thing that always
fixes it. It also explains the rest of the report at once, including the
program being on `/disk` and not in root: `BOOT` is what copies it across, and
`BOOT` never ran.

**Change.** Stop pretending it boots. After placing and feeding the turtle,
print the one instruction that works and wait for the player:

```
deploy : turtle 2 is placed and fed. RIGHT-CLICK IT -- that turns it on and
         runs the disk startup. Then press enter here.
         enter = it is on   s = skip this turtle   q = stop deploying
```

Keep the existing 90s "did it walk off" watcher after the prompt, so the answer
is still verified rather than trusted, and keep the floppy log playback -- it is
what turns a screen nobody is looking at into output.

**Check.** `test_quarry.lua` drives the stub through a deploy where the placed
turtle never leaves, and asserts the prompt was printed and the answer honoured.

---

## 2. Prompt for what is missing instead of silently going on

The user's rule: when something fails, ask for it on the turtle's own screen,
let it be typed, and offer to skip -- never skip on our own.

**Where it applies.**

- **No position fix** (`runMine` quarry.lua:2287, `runDeploy` quarry.lua:3007,
  `check` quarry.lua:699). Today this is `error(noFix())` and the run is over.
  Instead: print the diagnosis `noFix()` already builds, then ask for `x`, `y`,
  `z` and `startDir` one at a time, and offer to write them into `quarry.conf`
  so the next reboot does not ask again. Enter on an empty line = give up, with
  the old error text.
- **A deploy that cannot finish** (`runMine` quarry.lua:2331). Today it prints
  "could not deploy the others, mining alone" and descends. That is exactly the
  automatic skip the user does not want: ask whether to retry, mine alone, or
  stop.
- **A short kit** (`auditKit` quarry.lua:2986). Ask whether to go on with what
  is aboard, rather than only refusing.

**Do not hang a headless turtle.** `/startup` reboots the mine with nobody
watching, so every prompt goes through one helper that gives up on a timer:

```lua
-- 60s and then the old automatic answer, so a chunk reload at 3am still runs.
local function ask(prompt, default) -- parallel.waitForAny(read, os.startTimer)
```

Say which default was taken when the timer wins, so the log shows an unattended
answer as an unattended answer.

**Check.** Stub `read` in `test_quarry.lua` to return a scripted answer, and add
a case where it never answers and the timer default is what happens.

---

## 3. Manual coordinates must not need a modem at all

With `startX/startY/startZ` and `startDir` set, GPS is never called, so a modem
buys nothing but the alert channel. Three places still demand one:

- `KIT` wants 3 wireless modems (quarry.lua:636) and `auditKit` refuses to
  deploy without them.
- `deployOne` treats a failed modem handover as fatal (quarry.lua:2879):
  "it cannot GPS, so it will never move".
- `BOOT` waits 60s for a modem and returns if none arrives (quarry.lua:2717),
  and stops again if the equip does not stick (quarry.lua:2751).

**Change.** One flag, computed once from the config: `manual = startX and
startY and startZ and startDir`. Under it, the modem is optional everywhere
above -- `KIT` wants 0, the handover is best-effort, and `BOOT` skips the wait
and the equip. `BOOT` is a format string, so pass the flag in with `N`.

Say it plainly on the deployed turtle's log either way: "no modem, running on
the coordinates in quarry.conf" is a fact worth having in the report.

**Check.** A manual-GPS deploy with no modem in the kit reaches the placement
step and hands over coal; the boot script it wrote contains no modem wait.

---

## 4. Under manual coordinates, saved state must beat the config pin

**Evidence.** `locate` (quarry.lua:403) returns `conf.startX/Y/Z` before it
looks at `quarry.state`. Those coordinates are the block the turtle was
launched from. The moment a manual-GPS turtle reboots -- chunk reload, server
restart, `/startup` -- it reads the launch block as its current position while
standing 100 blocks down a branch, and dead-reckons from there. There is no GPS
to catch it, by definition.

**Change.** Prefer `quarry.state` over the config pin when the state has a
position, a heading and a matching `st.index`; fall back to the pin when it does
not. The pin is a starting value, not a live sensor. Keep the `quarry.state`
line `calibrate` already prints, so the source is always in the log.

**Check.** A run with `startX/Y/Z` set and a state file 40 blocks away resumes
at the state's position, and one with no state file starts at the pin.

---

## 5. The deployed turtles must inherit the deployer's claim anchor

**Evidence.** The user saw turtle 2 start a tunnel of its own. `runMine`
(quarry.lua:2346) anchors the claim on `st.home`, which is wherever the turtle
wakes, and `claimOf` (quarry.lua:256) snaps that to a 3x3 chunk region. Turtles
2 and 3 wake one block IN FRONT of turtle 1. If that block is over a chunk
border, `claimOf` hands them a different region, and each then mines "its third"
of a claim turtle 1 knows nothing about. The comment at quarry.lua:2661 assumes
they agree; one block is enough for them not to.

**Change.** Deploy already writes the placed turtle's own position onto the
floppy (`confForPlaced`, quarry.lua:2961). Write the deployer's home with it --
simplest is a seeded `quarry.state` on the floppy holding `home = {x,y,z}`,
copied by `BOOT` when the turtle has no state of its own. `runMine`'s existing
"this is not the claim in quarry.state" guard stays correct: a claim is 48
blocks across, so a turtle one block away is always inside it.

**Check.** Deploy from a block whose front neighbour is in the next chunk, and
assert all three turtles compute the same `claimOf`.

---

## 6. `--check` must report the last halt

Both turtles "say stopped" and there is no way to ask them why after the fact.
`halt` (quarry.lua:843) holds the reason and is printed once by `report`, then
lost. Save it into `st.halt` when the run stops and print it in `check`, so
`quarry 2 --check` on the turtle's own screen answers "why are you stopped"
without a second run. Cheap, and it is the diagnostic the next log needs.

---

## 7. The kit audit must follow `conf.turtles`

`KIT` hard-codes 2 turtles, 3 modems and 3 buckets (quarry.lua:624-644), so
`turtles = 2` still fails the audit for a turtle and a bucket that will never be
used, and `turtles = 1` cannot pass at all. Derive the wants from
`conf.turtles`: `turtles - 1` turtle items, `turtles` buckets, `turtles` modems
(0 under item 3), `64 * turtles` coal. With `turtles = 1`, skip the deploy
entirely and say so.

---

## 8. Put the program in root under the name the rest of the world uses

`BOOT` copies `/disk/quarry` to `quarry` (quarry.lua:2686) while `update.lua`
(update.lua:13) and turtle 1 both use `quarry.lua`. Both names run under the CC
shell, so this did not break anything -- turtle 2's program was missing because
`BOOT` never ran (item 1), not because of the name -- but a deployed turtle that
is later updated ends up with two copies of the program in root, and the older
one is what `shell.run("quarry")` may pick. Copy to `quarry.lua`, and delete a
stale `quarry` beside it.

---

## 9. SETUP.md

Once the above lands, the player-facing sequence changes in two places, and
`SETUP.md` is the file that has to say so:

- deploy now stops and asks the player to right-click each new turtle;
- manual coordinates need no modem, but do need `startDir`, and a manual-GPS
  turtle that is picked up and moved cannot recover itself.

---

## Open question

Three trunks, one per turtle, is the design (`thirdOf`, quarry.lua:271): each
turtle owns a third of the claim's z range and sinks its own trunk at the centre
of it. "Turtle 2 starts a new tunnel" is that design working, PROVIDED item 5
lands and the claim is shared. If the intent was for all three to share one
trunk and split the branches instead, that is a different mine and wants saying
before any of this is built.
