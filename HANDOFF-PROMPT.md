# Handoff prompt

Paste the block below into a fresh session to resume the turtle mining build.
Rewritten whole 2026-08-28 after the auto-deploy and full-depot build, when the
four dated logs it had accreted were folded into one.

---

```
Working in /home/ubuntu/mods/computer on a CC:Tweaked turtle mining program
(quarry.lua). Read RESUME.md first, then MASTERMINE-PLAN.md, before doing
anything else. RESUME.md carries the state, the rules and the next action;
everything it has dropped -- the phase narratives, the code review, the four
failed deploy runs, the probe results, the day's four shipping logs -- is in
reports/history-2026-08.md, whole and unedited. Do not read that up front. Go
there for the reasoning behind something RESUME.md states flatly, or when
something settled starts misbehaving again.

WHERE THE RUN STANDS, 2026-08-28.

Nothing is blocking a run. On the turtle: `update`, then `quarry 1` from the
same launch block as log Rpv9m (243,73,734), carrying a barrel, turtles 2 and
3, the disk drive and the floppy. A plain `quarry 1` now deploys the other two
at the launch block before it descends; `quarry 1 deploy` still does only the
deployment. A full depot no longer stops the run -- the junk tier goes on the
tunnel floor and the turtle broadcasts on the rednet protocol "quarry", which
the new alert.lua prints on a computer. That message is best effort: a modem's
range shrinks with depth, so a turtle at y=-59 may reach nobody. It is always
in the uploaded log as well. Do not build anything that depends on it arriving.

Phases 1 to 5 are built and all five have run in-game. Phase 6 (monitor,
full-clear mode) is deferred. What is unproven in-game is fuel rationing (every
dock so far found the tank full), two turtles working at once, and the two
changes in the last build.

Expect the run to say "the floor under the trunk will not open -- placed a
container beside the trunk at y=-58 instead". Bedrock scatters up through y=-60
and the floor stands at y=-59, so on most trunks the block below will not open;
that line is the fallback working, not a fault.

TESTING. Run `lua5.3 test_quarry.lua`, `lua5.3 test_probe.lua` and `lua5.3
test_update.lua` before and after any change. All must pass: 66 tests in
test_quarry, about 9 seconds. When you fix a bug, add a test and verify it
FAILS against the unfixed code -- eighteen tests have been confirmed
non-vacuous that way and it is worth the extra minute every time. Test worlds
cap topY on purpose: with a full depot no longer stopping a run, an uncapped
world mines its whole third and the suite takes a minute instead of nine
seconds.

DESIGN. Settled. Do not reopen anything in RESUME.md's "Settled" list and do
not reintroduce anything in its "Corrections already made" list. If you think a
settled decision is wrong, say so and wait; do not quietly redesign. Two
entries changed on 2026-08-28 on new evidence rather than second thoughts: the
GPS one, and the fuel ration, now a floor rather than a fraction because
floor(total/3) gave three dockers 100, then 66, then 44 of a 300-coal chest.
One probe finding was later overturned in-game -- "a turtle is not a peripheral
to another turtle" was the probe looking from a position it had already left --
so trust RESUME.md over the probe results wherever they disagree.

Storage is one substring word list: chest, barrel, shulker, crate, item_vault.
It answers all four questions the program asks about storage. Drawers and bins
are deliberately off it -- they lock to one item type, so a mixed dump fails on
the second stack.

GPS is up but not reliable. It answered on 2026-08-28 morning, was dead that
evening, and was rebuilt that night. It does not reach the claim floor at all
and never will: a wireless modem's range shrinks with depth. Every fix a run
gets is taken at the launch block; from there it dead-reckons and quarry.state
is what a turtle at the floor resumes on. A NO FIX crash now names which of its
three causes it is and uploads gps.locate's own debug output -- read those
`gps    :` lines before theorising, and if a log has none, it predates them.

WRITING LUA. Invoke the cc-tweaked-pack skill first. Its peripheral dump
outranks the wiki for what methods exist -- but read its headers: the dump was
taken from a COMPUTER (turtle=false), so it does not describe what a turtle
sees. That distinction has already cost one wrong conclusion. If a method you
need is not in the dump, say so and ask for a re-survey; do not guess it. For
behaviour that belongs to another mod, read that mod's own jar and config off
disk (unzip, javap -c, config/*.toml). No CC:Tweaked jar or config is in this
sandbox -- checked -- so CC mod-side behaviour comes from tweaked.cc or from
the user. CC:Tweaked is Lua 5.2: no // and no bitwise operators.

DELIVERY IS GITHUB. This directory is the working tree of
https://github.com/zaBees/cc (public). Ship a fix by pushing and telling the
user to run `update`, which replaces quarry, alert and itself, defeats the CDN
cache with a `?t=` query and prints each file's fletcher32.

VERIFY A PUSH AGAINST THE COMMIT-PINNED URL, never the branch one:

  curl -sS https://raw.githubusercontent.com/zaBees/cc/$(git rev-parse HEAD)/quarry.lua

The /main/ URL is CDN-cached and served the previous build for over two minutes
after a push on 2026-08-28, which looks exactly like a failed push. The same
cache can hand the user a stale file if they re-download immediately.

A hand-typed download is always TWO lines, `delete <name>` then the `wget`:
CC's wget refuses to overwrite an existing file, prints "File already exists"
and downloads nothing, which reads like success. There is no force flag and the
CC shell has no && or ;.

  delete quarry
  wget https://raw.githubusercontent.com/zaBees/cc/main/quarry.lua quarry

paste.rs is retired for delivery -- it began refusing uploads over ~80,000
bytes on 2026-08-28 and quarry.lua is past 120,000 -- but the program still
POSTS its own crash reports there and that side works fine. Old pastes are
still fetchable, so the historic builds can be read.

cloudcat.py is archived in attic/ and must NOT be used unless the user asks for
it by name. It pushes files into the game over cloud-catcher, split across
packets and stitched back, and it is the fallback if GitHub is ever unreachable
in-game. It needs the websockets module (not installable system-wide here under
PEP 668) and the in-game computer running `cloud <token>`.

quarry.conf ships dry = false and lava = true, both at the user's explicit
instruction on 2026-08-27. This overrides the old "never hand it over ready to
mine" convention. Test 38 asserts both; do not revert them without being asked.

This directory also holds an unrelated second thread: ROCKET-PLAN.md,
spacex.lua and icmb.lua, a Create Aeronautics flight controller. Nine fixes are
planned and none are implemented. Leave it alone unless the user raises it.

THREE STANDING RULES FROM THE USER.
- Work must survive their budget running out. Write deliverables and handoff
  updates to disk as you go, never only in chat. Rewrite RESUME.md whole at the
  end of every phase; never patch it with a blind search-and-replace.
- Test under lua5.3 here before anything reaches their server. They run the
  code and you never see the game, so a bug that ships costs a round trip.
- Ask before reverting or deleting anything. This directory became a git
  repository on 2026-08-28, so there is an undo now, but the rule stands: ask,
  then revert deliberately with git rather than by hand.

HOW THESE SESSIONS ACTUALLY GO, because it will repeat: the user pastes a
paste.rs id of an in-game log and little else. Fetch it, read it as the primary
evidence, and put the diagnostic INTO the program so the next single run
answers the question. Five deploy runs were spent on a chain of separate bugs,
each hidden behind the last, and a sixth on a crash whose message named the
symptom ("calibration moved 0,0") instead of the cause (a config that pinned
the position). Do not theorise past the evidence -- when a log cannot
distinguish two causes, add the line that will, and say so.
```

---

## If the fresh session has no memory access

Everything it needs is in `RESUME.md`. The memory files at
`~/.claude/projects/-home-ubuntu-mods-computer/memory/` are a summary of the
same thing and are outranked by `RESUME.md` and `MASTERMINE-PLAN.md`.
