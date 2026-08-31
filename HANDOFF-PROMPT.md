# Handoff prompt

Paste the block below into a fresh session. It is deliberately a pointer and
nothing more: everything it could repeat is in `RESUME.md`, and a second copy
of a fact is a second copy to go stale.

---

```
Working in /home/ubuntu/mods/computer on a CC:Tweaked turtle mining program
(quarry.lua). Read RESUME.md first, then MASTERMINE-PLAN.md, before doing
anything else. RESUME.md is the state, the settled design, the corrections and
the next run to ask for; MASTERMINE-PLAN.md is why it is shaped that way.
attic/SETUP.md is the player's copy -- what they place, press and download.
reports/history-2026-08.md is the archive: DO NOT read it unless a task
explicitly tells you to. It holds the whole deploy/boot/fuel saga and every
narrative those files have dropped, needed only when chasing a regression in
something long settled.

Four things RESUME.md will tell you that are worth knowing before you open it:

- Do not reopen anything in its "Settled" list or reintroduce anything in its
  "Corrections already made" list. If you think a settled decision is wrong,
  say so and wait.
- Run lua5.3 test_quarry.lua, test_pgps.lua, test_probe.lua and
  test_update.lua before and after any change. When you fix a bug, add a test and verify it FAILS against
  the unfixed code.
- Invoke the cc-tweaked-pack skill before writing any Lua.
- Delivery is GitHub: push, verify against the commit-pinned raw URL, and tell
  the user to run `update`.

How these sessions actually go: the user pastes the id of an in-game log and
little else. Fetch it, read it as the primary evidence, and put the diagnostic
INTO the program so the next single run answers the question. Do not theorise
past the evidence -- when a log cannot distinguish two causes, add the line
that will, and say so.
```
