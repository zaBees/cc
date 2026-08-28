# Handoff prompt

Paste this into a fresh session to resume the turtle mining build.

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

The design is settled. Do not reopen anything in RESUME.md's "Settled" list and
do not reintroduce anything in its "Corrections already made" list. If you think
a settled decision is wrong, say so and wait; don't quietly redesign. Note that
one probe finding was later overturned in-game -- "a turtle is not a peripheral
to another turtle" was the probe looking from a position it had already left --
so trust RESUME.md over the probe results wherever they disagree.

Invoke the cc-tweaked-pack skill before writing any Lua. Its peripheral dump
outranks the wiki for what methods exist -- but read its headers: the dump was
taken from a COMPUTER (turtle=false), so it does not describe what a turtle
sees. That distinction has already cost one wrong conclusion. If a method you
need is not in the dump, say so and ask for a re-survey; do not guess it. For
behaviour that belongs to another mod, read that mod's own jar and config off
disk (unzip, javap -c, config/*.toml). No CC:Tweaked jar or config is present
in this sandbox -- checked -- so CC mod-side behaviour has to come from the
wiki at tweaked.cc or from the user.

GPS is DOWN on this server as of 2026-08-28 evening: gps.locate returns nil
from turtle 1 with a modem equipped. It worked that morning. A run therefore
needs either the constellation fixed, or startX/Y/Z plus startDir in
quarry.conf -- see RESUME.md's "GPS is down". The live config on turtle 1 sets
startX/Y/Z and NO startDir, so a run currently refuses to start.

Phases 1 to 5 are built and ALL have now run in-game. Turtle 1 deployed turtle
2, which booted, equipped its modem, calibrated, descended to y=-59 and mined
177 blocks. What has never run is the DEPOT CYCLE: no container has ever been
placed, so docking, rationing, restocking, and two turtles working at once are
stub-tested only.

Run `lua5.3 test_quarry.lua` and `lua5.3 test_probe.lua` before and after any
change; all six suites must pass (55 checks). When you fix a bug, add a test and
verify it FAILS against the unfixed code -- nine tests have been confirmed
non-vacuous that way and it is worth the extra minute.

quarry.lua was code-reviewed on 2026-08-28 and ALL NINE findings are fixed, each
with a regression test (40-48) confirmed to fail against its own unfixed code.
reports/code-review-quarry.md records what each one was; RESUME.md summarises
them. Nothing from that review is outstanding -- do not go looking for the "six
open findings" an older copy of this prompt mentions.

Delivery is GitHub, changed 2026-08-28: this directory is the working tree of
https://github.com/zaBees/cc (public). The in-game download is

  delete quarry
  wget https://raw.githubusercontent.com/zaBees/cc/main/quarry.lua quarry

and the URL never changes, so a redelivery is `git push` and the user re-runs
those same two lines. Verify a push by fetching the raw URL back and diffing
against disk; raw.githubusercontent.com is CDN-cached for a few minutes, so a
fetch straight after a push can serve the old version.

quarry.conf now ships dry = false and lava = true, both at the user's explicit
instruction on 2026-08-27. This overrides the old "never hand it over ready to
mine" convention. Test 38 asserts both; do not revert them without being asked.

Every download line handed to the user is TWO lines, `delete <name>` then the
`wget`: CC's wget refuses to overwrite an existing file, prints "File already
exists" and downloads nothing, which reads like success. There is no force flag
and the CC shell has no && or ;.

paste.rs is retired for delivery -- it began refusing uploads over ~80,000 bytes
on 2026-08-28 and quarry.lua is past 100,000 -- but the program still POSTS its
crash reports there and that works fine. Old pastes are still fetchable.

cloudcat.py is archived in attic/ and must NOT be used unless the user asks for
it. It pushes files straight into the game over cloud-catcher, split across
packets and stitched back, and it is the fallback if GitHub is ever unreachable
in-game.

Pick up at RESUME.md's "Next action": the mine needs a depot. Either run
`quarry 1` so turtle 1 builds one from the chests it carries, or have the user
place a chest against a trunk's bottom block.

Three standing rules from the user:
- Work must survive their budget running out. Write deliverables and handoff
  updates to disk as you go, never only in chat. Rewrite RESUME.md whole at the
  end of every phase; never patch it with a blind search-and-replace.
- Test under lua5.3 here before anything reaches their server. They run the
  code and you never see the game, so a bug that ships costs them a round trip.
- Ask before reverting or deleting anything. This directory became a git
  repository on 2026-08-28, so there is an undo now, but the rule stands: ask,
  then revert deliberately with git rather than by hand.

How this session actually went, because it will repeat: the user pastes a
paste.rs id of an in-game log and little else. Fetch it, read it as the primary
evidence, and put the diagnostic INTO the program so the next single run answers
the question. Five deploy runs were spent on a chain of separate bugs, each
hidden behind the last. Do not theorise past the evidence -- when a log cannot
distinguish two causes, add the line that will and say so.
```

---

## If the fresh session has no memory access

Everything it needs is in `RESUME.md`. The memory files at
`~/.claude/projects/-home-ubuntu-mods-computer/memory/` are a summary of the
same thing and are outranked by `RESUME.md` and `MASTERMINE-PLAN.md`.
