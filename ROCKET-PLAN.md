# Rocket flight controller — improvement plan

Written 2026-08-28. Covers `spacex.lua` (530 lines) and `icmb.lua` (601 lines).
No code has been changed yet; this is the plan and the reasoning behind it.

## What exists today

Both files are the same flight controller: one computer, four Create Aeronautics
cross-thrusters vectoring in unison, sensed entirely through CC:Sable
(`sublevel.getLogicalPose()` for attitude and position, `getLinearVelocity()` for
velocity), driven through five analog redstone sides. No yaw authority; aiming is
by world coordinate re-projected onto the live body axes every tick, so passive
aerodynamic spin does not matter.

They differ only in the terminal phase:

- `spacex.lua` flies a **ballistic arc** — a tent-shaped altitude schedule that
  peaks at the halfway point, with guidance and thrust live all the way onto the
  target.
- `icmb.lua` flies **climb, brake, dive** — a steep diagonal climb, a retro-lean
  brake that kills all horizontal speed near the target, then a near-vertical
  nose-down drop with a frozen heading inside a 20-block deadzone.

Everything else — the quaternion maths, the attitude PD, the drag-trim
feed-forward, the sign bring-up procedure, the logging — is duplicated. A `diff`
is 205 lines against 1,131.

## The fixes, in value order

### 1. Measure `dt`; do not assume it

`local dt = C.flight.LOOP_PERIOD` is a fixed 0.05 in both files, and every
derivative and integral in the controller divides by it: the world-frame lean
rate (`rawRX = (wlx - prevWLX) / dt`), the yaw rate, and both attitude
integrators.

The loop cannot actually run at 0.05 s. Each tick makes two yielding CC:Sable
calls before `os.sleep(0.05)`, so the true period is at least 0.1 s and varies
with server load. Every `KD` term is therefore scaled by roughly 2x or more, and
the integrators wind at half the intended rate. The gains that were tuned in
flight are compensating for this error, which means they are also compensating
for whatever the server load happened to be that day.

Fix: take `os.clock()` at the top of each update, use the real elapsed time, and
clamp it to a sane range (say 0.02 to 0.5) so one long pause cannot spike the
derivative. Retune `TILT_KD` afterwards — expect it to come down.

This is the highest-value change in the list because it makes every other gain
mean what it says.

### 2. Persist flight state; survive a reboot

Neither program writes a state file. The project convention is that a program
resumes from disk, not from memory, and that it is safe to kill at any
instruction. A rocket that reboots mid-flight — chunk unload, server restart,
a chunk boundary crossed at speed — restarts in `CLIMB` and re-latches
`launchAlt` to whatever altitude it is currently at, so it believes it is on the
pad at 1,200 blocks and flies the whole profile again from there.

Fix: write `{phase, launchAlt, target, cruiseDist0, braking, diving}` to disk on
every phase transition and every N ticks, and read it back at boot. The log file
should be opened in append mode too — `fs.open(FILE, "w")` truncates on reboot,
which destroys exactly the evidence needed to explain the reboot.

### 3. Add a flight termination path

There is no abort. The main loop is one `while true` with `os.sleep`, so the
only way to stop a flight is to kill the computer, which leaves the last redstone
levels latched — full thrust included.

Fix: `parallel.waitForAny` with three tasks — the control loop, a key/redstone
abort listener, and a geometry watchdog. The abort neutralises steering and cuts
thrust. The watchdog trips on the conditions that mean the flight is already lost:
tilt past ~110 degrees, altitude below launch minus a margin, target distance
growing for more than a few seconds, or no pose for more than a second. Every real
launch vehicle has this; here it is about 25 lines.

### 4. Proportional navigation on the terminal leg

The current cross-track term is `-VEL_KP * vCross / GRAVITY` — pure drift
cancellation. It nulls sideways velocity but it does not null the *miss*, so it
converges slowly and leaves a residual offset that the along-track loop has to
work out.

Proportional navigation is the guidance law actual missiles use, and it is
shorter than what is there now:

```
lambda   = atan2(dx, dz)              -- line-of-sight angle to the target
lamDot   = angleDiff(lambda, lambdaPrev) / dt
Vc       = (distPrev - dist) / dt     -- closing speed
aLat     = N * Vc * rad(lamDot)       -- N = 3..4
leanCmd  = deg(atan(aLat / GRAVITY))
```

It drives the line-of-sight rate to zero, which is the condition for a hit, and
it does so with a lead angle rather than by chasing the error after it appears.
It replaces the cross-track block entirely; the along-track drag-trim
feed-forward stays as it is, because that part is already right.

Keep `icmb.lua`'s `DIVE_DEADZONE` heading freeze — PN's LOS rate goes to infinity
as range goes to zero, and freezing the command inside a fixed radius is the
standard guard, not a hack.

### 5. Gravity turn instead of a pitch-over step

`CLIMB` goes straight up to 350 blocks and then hands over to a phase that
immediately commands a large lean. The `CLIMB_TAPER` in the thrust loop exists to
soften the vertical-speed side of that step; the attitude side still steps.

A gravity turn ramps the commanded pitch with altitude — a small lean introduced
early, then the velocity vector carried around by gravity rather than by lateral
thrust. Concretely: replace the hard phase boundary with
`pitch = MAX_PITCH * clamp((alt - PITCH_START) / PITCH_SPAN, 0, 1)`. It costs
less lateral authority, removes the transient, and the existing `CLIMB_ANGLE` in
`icmb.lua` is already halfway there — it just needs to be a function of altitude
rather than a constant.

### 6. Conditional integration

Both integrators clamp to `I_LIMIT` for anti-windup, but they keep integrating
while the steering output is saturated at `OUTPUT_LIMIT = 15`. When the actuator
is already at the stop, more integral does nothing but guarantee an overshoot on
the way back. Standard fix, one line: skip the integrator update on an axis whose
output is at the limit and whose error still points the same way.

### 7. Sample the two sensors together

`readAttitude()` and `readVelocity()` are sequential yielding calls, so velocity
is sampled a tick after attitude and the two describe different moments. Batch
them with `parallel.waitForAll` — the pack convention for exactly this reason —
and the controller gets one coherent state vector instead of two skewed ones.

### 8. Merge the two files

They are one program with two terminal profiles. A fix to the attitude PD
currently has to land twice and, judging by the comment drift, has not always.
`CONFIG.profile = "ARC"` or `"STOP_DIVE"` selects the terminal leg; everything
above the terminal leg is shared. The one-file-per-program rule is about not
using `require`, not about shipping the same 900 lines twice.

### 9. Housekeeping

- Both files ship `DRY_RUN = false`. Nothing is ever handed over armed; the flag
  goes back to `true` and the pilot flips it.
- `math.atan2` was removed in Lua 5.3. It exists in CC:Tweaked (Lua 5.2 via
  Cobalt) so the flight is fine, but it makes the program untestable under the
  local `lua5.3`. Use `math.atan(y, x)`, which is correct in both.

## Deliberately not doing

- **Kalman filtering or sensor fusion.** CC:Sable returns exact state with no
  noise. There is nothing to filter.
- **Full powered-explicit guidance (PEG).** Solving the optimal burn is a real
  win for an orbital vehicle with a mass budget. Here thrust is a redstone level
  from 0 to 15 and there is no fuel model, so the arc schedule plus PN gets the
  same place with a tenth of the code.
- **Individual thruster control or yaw.** The hardware does not expose it.

## Suggested order

Items 1, 2 and 3 first: they are correctness and safety, they need no retuning
beyond `TILT_KD`, and item 3 makes every later test flight cheaper to abort.
Then 8 (merge) so that 4, 5, 6 and 7 land once instead of twice.
