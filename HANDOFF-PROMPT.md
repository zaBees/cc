# Handoff prompt

Paste this into a fresh session to resume the turtle mining build.
Rewritten whole 2026-08-28 evening, updated that night.

---

```
Working in /home/ubuntu/mods/computer on a CC:Tweaked turtle mining program
(quarry.lua). Read RESUME.md first, then MASTERMINE-PLAN.md, before doing
anything else. RESUME.md was trimmed on 2026-08-28 to what a session needs to
act; the history it used to carry -- phase narratives, the code review in full,
the four failed deploy runs, the probe results -- is in
reports/history-2026-08.md, complete and unedited. Do not read that up front.
Go there when you need the reasoning behind something RESUME.md states flatly,
or when something settled starts misbehaving again.

WHAT IS BLOCKING A RUN, as of 2026-08-28 night.

The user has to clear two chests in-game before the next run means anything.
Run 45bPE reached the claim floor with GPS up, built its own depot from the
chests turtle 1 was carrying, put them on sides 0 and 1 of the trunk floor, and
then stopped on them: every side of that block is a working row, so the branch
leg walked into one and the spine walked into the other, and a container is on
the never-dig list. The same run dumped turtles 2 and 3, the drive, the floppy
and the modems into a chest as spoil. Both are fixed here -- the depot goes
UNDER the trunk floor now and isKit keeps the deployment kit in the hold -- but
the two chests are still standing at 248,-59,711 with the kit inside them, and
the fixed build still reads a container beside the floor as a depot. The user
breaks both, takes everything back, re-downloads, and runs `quarry 1` with a
barrel aboard.

A crash they reported (URkmo, then td7FE) was `CRASHED: no position fix` while
they said "gps locate works". Both were true: the turtle was parked at the
depot at y=-59 with its modem equipped, and a wireless modem's range shrinks
with depth, so the surface constellation simply does not reach the claim floor.
locate() now falls back to quarry.state, which carries the heading GPS never
gives. Expect this to come back in some other shape -- ask for the crash line
or `quarry --check`, which name their own cause now, before theorising.

GPS itself is UP: run 45bPE opened with `quarry 1  at 243,73,734`, so the
constellation the user rebuilt answers and startX/Y/Z are out of quarry.conf.
It has failed once already, so do not assume it.

Phases 1 to 5 are built and all five have run in-game. Turtle 1 deployed turtle
2, which booted, equipped its modem, calibrated, descended to y=-59 and mined
177 blocks; turtle 1 has since mined 251 of its own and docked. Phase 6
(monitor, full-clear mode) is deferred and not started. Rationing has never
actually handed out coal -- every dock so far found the tank full -- and two
turtles have never run at once.

The design is settled. Do not reopen anything in RESUME.md's "Settled" list and
do not reintroduce anything in its "Corrections already made" list. If you think
a settled decision is wrong, say so and wait; don't quietly redesign. Two
entries were changed on 2026-08-28 on new evidence, not on second thoughts --
the GPS one above, and the fuel ration, which is now a floor rather than a
fraction because the old floor(total/3) gave three dockers 100, then 66, then
44 of a 300-coal chest. Note also that one probe finding was later overturned
in-game -- "a turtle is not a peripheral to another turtle" was the probe
looking from a position it had already left -- so trust RESUME.md over the
probe results wherever they disagree.

Invoke the cc-tweaked-pack skill before writing any Lua. Its peripheral dump
outranks the wiki for what methods exist -- but read its headers: the dump was
taken from a COMPUTER (turtle=false), so it does not describe what a turtle
sees. That distinction has already cost one wrong conclusion. If a method you
need is not in the dump, say so and ask for a re-survey; do not guess it. For
behaviour that belongs to another mod, read that mod's own jar and config off
disk (unzip, javap -c, config/*.toml). No CC:Tweaked jar or config is present
in this sandbox -- checked -- so CC mod-side behaviour has to come from the
wiki at tweaked.cc or from the user.

Run `lua5.3 test_quarry.lua`, `lua5.3 test_probe.lua` and `lua5.3
test_update.lua` before and after any change; all of them must pass, 60 checks
in test_quarry. When you fix a bug, add a test and
verify it FAILS against the unfixed code -- sixteen tests have been confirmed
non-vacuous that way and it is worth the extra minute every time.

quarry.lua was code-reviewed on 2026-08-28 and ALL NINE findings are fixed, each
with a regression test (40-48) confirmed against its own unfixed code.
reports/code-review-quarry.md records what each one was; RESUME.md summarises
them. Nothing from that review is outstanding -- do not go looking for the "six
open findings" an older copy of this prompt mentions. Tests 49-55 are the
2026-08-28 evening fixes: the tank limit read from the turtle instead of a
literal 20000, the fuel floor, the calibration guard, and startDir. Tests 56-60
and the rewritten 33 are that night's: the kit staying out of the depot, the
depot going under the trunk floor, the NO FIX crash naming its own cause,
quarry.state standing in as a position source where GPS cannot reach, and the
wired-modem case. A NO FIX now uploads gps.locate's own debug output -- if a
GPS question comes up, read those `gps    :` lines before theorising, and if
they are absent from a log, the run predates them.

DELIVERY IS GITHUB, changed 2026-08-28 at the user's instruction. This
directory is the working tree of https://github.com/zaBees/cc (public). The
in-game download is two lines:

  delete quarry
  wget https://raw.githubusercontent.com/zaBees/cc/main/quarry.lua quarry

The URL never changes, so a redelivery is `git push` and the user re-runs those
same two lines -- or, once `update.lua` is on the turtle, just `update`, which
does the delete, defeats the CDN cache with a `?t=` query and prints the file's
fletcher32. Ship a fix by pushing and telling them to run `update`. VERIFY A PUSH AGAINST THE COMMIT-PINNED URL, not the branch
one:

  curl -sS https://raw.githubusercontent.com/zaBees/cc/$(git rev-parse HEAD)/quarry.lua

The /main/ URL is CDN-cached and was still serving the previous build more than
two minutes after a push, which looks exactly like a failed push. The same
cache can hand the user a stale file if they re-download immediately; tell them
to wait a moment and repeat the two lines. `update` sidesteps that entirely by
appending `?t=<epoch>`, which is part of the CDN cache key.

Every download line handed to the user is TWO lines, `delete <name>` then the
`wget`: CC's wget refuses to overwrite an existing file, prints "File already
exists" and downloads nothing, which reads like success. There is no force flag
and the CC shell has no && or ;.

paste.rs is retired for delivery -- it began refusing uploads over ~80,000
bytes on 2026-08-28 and quarry.lua is past 100,000 -- but the program still
POSTS its own crash reports there and that side works fine. Old pastes are
still fetchable, so the historic builds can be read.

cloudcat.py is archived in attic/ and must NOT be used unless the user asks for
it by name. It pushes files straight into the game over cloud-catcher, split
across packets and stitched back by a generated joiner, and it is the fallback
if GitHub is ever unreachable in-game. It needs the websockets module, which is
not installable system-wide here under PEP 668, and the in-game computer
running `cloud <token>`. attic/sumfile.lua is its verifier: a file over ~18 KB
cannot be pulled back, so you check a delivery by printing its fletcher32
in-game and comparing against cloudcat.fletcher32 locally.

quarry.conf ships dry = false and lava = true, both at the user's explicit
instruction on 2026-08-27. This overrides the old "never hand it over ready to
mine" convention. Test 38 asserts both; do not revert them without being asked.

This directory also holds an unrelated second thread: ROCKET-PLAN.md, spacex.lua
and icmb.lua, a Create Aeronautics flight controller. Nine fixes are planned and
none are implemented. Leave it alone unless the user raises it.

Three standing rules from the user:
- Work must survive their budget running out. Write deliverables and handoff
  updates to disk as you go, never only in chat. Rewrite RESUME.md whole at the
  end of every phase; never patch it with a blind search-and-replace.
- Test under lua5.3 here before anything reaches their server. They run the
  code and you never see the game, so a bug that ships costs them a round trip.
- Ask before reverting or deleting anything. This directory became a git
  repository on 2026-08-28, so there is an undo now, but the rule stands: ask,
  then revert deliberately with git rather than by hand.

How these sessions actually go, because it will repeat: the user pastes a
paste.rs id of an in-game log and little else. Fetch it, read it as the primary
evidence, and put the diagnostic INTO the program so the next single run answers
the question. Five deploy runs were spent on a chain of separate bugs, each
hidden behind the last, and a sixth was spent on a crash whose message named the
symptom ("calibration moved 0,0") instead of the cause (a config that pinned the
position). Do not theorise past the evidence -- when a log cannot distinguish
two causes, add the line that will and say so.
```

---

## If the fresh session has no memory access

Everything it needs is in `RESUME.md`. The memory files at
`~/.claude/projects/-home-ubuntu-mods-computer/memory/` are a summary of the
same thing and are outranked by `RESUME.md` and `MASTERMINE-PLAN.md`.
