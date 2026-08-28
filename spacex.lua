-- ============================================================================
-- ROCKET FLIGHT CONTROLLER  (v4 -- single computer, drives all 4 thrusters)
-- ============================================================================
-- Runs on ONE computer (dir 3). Replaces the old two-computer split
-- (3 = right axis, 4 = forward axis) plus the altimeter and the rednet link.
--
-- WHY ONE COMPUTER: the 4 cross-thrusters vector in UNISON toward whichever side
-- gets signal, so the four steer sides are really a 2-axis lean joystick
-- (front/back = one axis, left/right = the other; two at once = diagonal; analog
-- = continuous direction+magnitude). One program drives both axes. There is no
-- individual-thruster control and NO yaw control.
--
-- SENSING is 100% CC:Sable -- no altimeter, no gimbal, no rednet:
--   attitude   : sublevel.getLogicalPose().orientation   (quaternion -> body axes)
--   altitude   : sublevel.getLogicalPose().position.y     (used RELATIVE to launch)
--   vert speed : sublevel.getLinearVelocity().y
--
-- OUTPUTS (CONFIG.io), all redstone-analog:
--   front / back  = RIGHT-axis (X) lean    -- computer 3's existing wiring (sign known-good)
--   left  / right = FORWARD-axis (Z) lean   -- re-homed from old computer 4 (VERIFY sign!)
--   bottom        = thrust (common to all 4 thrusters)
--   top           = wired modem carrying navigation_table  (input; not driven)
--
-- NO YAW: the rocket can't rotate on command; it yaws passively from aerodynamics.
-- The attitude loop reads the LIVE body axes every tick and damps lean-rate in the
-- WORLD frame, so it stays stable regardless of the slow spin. Aiming is by COORDINATE:
-- exact world bearing from pose.position to the typed-in target, projected onto the live
-- body axes each tick (so it stays aimed as the nose drifts/spins).
--
-- PHASES: CLIMB (full thrust, straight up to CLIMB_HEIGHT) -> CRUISE/ARC. In CRUISE the
-- thrust no longer holds a flat altitude: it tracks a BALLISTIC ARC -- climb to APEX at the
-- HALFWAY point of the flight, then descend onto the target -- while the lean does velocity
-- guidance toward the target. The old steep nose-over DIVE (cut thrust, plummet) is DISABLED
-- (guidance.ENABLE_DIVE): the guided arc descent replaces it and keeps full steering authority
-- all the way down, so it can null the horizontal overshoot the thrust-cut dive could not.
--
-- BRING-UP (the one unverified piece is the left/right = FORWARD axis sign):
--   1. DRY_RUN = true (default): boot, tilt the nose by hand, read flight_solo.log.
--      Each axis's steer must OPPOSE its lean (negative feedback):
--        front/back (RIGHT): known-good.
--        left/right (FORWARD): if FWD `eff`/`out` has the SAME sign as the forward
--          lean (positive feedback), flip CONFIG.sign.STEER_FWD (or swap io.FWD_POS/NEG).
--   2. DRY_RUN = false, launch: confirm it climbs straight then HOLDS altitude.
--   3. Tune thrust.HOVER (level where vs~0 at tilt 0). Then we wire real navigation.
-- ============================================================================

local CONFIG = {
    nav = {
        -- Target WORLD position. ENTERED BY THE PILOT at boot (terminal prompt); these are just the
        -- defaults (blank entry keeps them). Aiming is by COORDINATE from pose.position (confirmed world
        -- coords) -> exact bearing AND distance. The navigation_table is no longer used.
        TARGET = { x = -409, y = -11, z = -2091 },
        STEER_SIGN = 1,                         -- flip to -1 if leaning toward the target flies it AWAY (tgtDist grows)
    },

    -- body-frame axes (verified against sable_pose.log)
    pose = { UP_AXIS = "+Y", FORWARD_AXIS = "+Z", RIGHT_AXIS = "+X" },

    -- SIGNS -- the bring-up dial. STEER_RIGHT is proven; STEER_FWD is the new unknown.
    sign = {
        STEER_RIGHT =  1,   -- front/back outputs (computer 3's existing axis): KNOWN-GOOD
        STEER_FWD   = -1,   -- left/right outputs (re-homed forward axis): VERIFY ON PAD (may flip)
    },

    -- inner attitude PD (same gains that gave a calm, recoverable flight in v3)
    attitude = {
        TILT_KP = 3.0,
        TILT_KD = 4.0,
        TILT_KI = 1.5,       -- integral on lean error -> trims out the steady residual lean (the slow drift). 0 disables.
        I_LIMIT = 0.4,       -- anti-windup clamp (lowered so the integral can't wind up into a big lean overshoot)
        RATE_SMOOTH = 0.5,   -- low-pass on the world-frame lean rate
        OUTPUT_LIMIT = 15,
    },

    guidance = {
        GRAVITY = 11,
        CLIMB_HEIGHT = 350,  -- climb straight up this many blocks (relative), then cruise
        -- BALLISTIC ARC: in cruise, thrust tracks a tent-shaped altitude profile -- climb to APEX at the
        -- halfway point of the flight, then descend onto the target. apex = min(APEX_ALT, range*APEX_FRAC)
        -- so a long shot peaks at APEX_ALT while a short shot peaks lower (no insane climb demand). The
        -- apex is also clamped below thrust.CEILING, so it never approaches the 2000-block lid.
        APEX_ALT  = 1500,    -- max apex height (blocks above launch) for a long-range shot
        APEX_FRAC = 0.25,    -- apex auto-scales to range*this until it hits APEX_ALT (range/4 ~= a sane lob)
        -- velocity guidance (cruise): chase a target-ward speed that TAPERS as we approach, so the
        -- rocket decelerates and CONVERGES instead of orbiting the target (fixed-lean just circled it).
        MAX_SPEED = 40,      -- b/s cruise/approach speed (raised per pilot; lean-compensated thrust holds alt at the lean)
        APPROACH_GAIN = 0.12,-- desSpeed = min(MAX_SPEED, dist*this) -> brakes from ~MAX_SPEED/gain (~250) blocks out.
                             -- Keep MAX_SPEED*APPROACH_GAIN < g*tan(MAX_LEAN) so braking is achievable (no orbit).
        VEL_KP = 0.6,        -- CROSS-track gain: lean to cancel sideways drift (keeps it tracking straight in)
        MAX_LEAN = 35,       -- deg, hard cap on the commanded lean
        -- ALONG-track speed = FEEDFORWARD trim lean + proportional correction. The trim is the lean that
        -- exactly balances drag at desSpeed: tan(lean) = DRAG*v/g  (e.g. 40 b/s -> ~18 deg). This is the
        -- piece both earlier schemes lacked: the slow RAMP (pure integrator) and pure-P both drove lean->0
        -- at target speed, so the rocket stood VERTICAL, lost all speed, re-leaned -> ~9 s porpoise. With the
        -- trim, at cruise speed the lean HOLDS ~18 deg and the speed sticks; SPEED_KP only trims deviations
        -- (first-order stable, no integrator windup, no limit cycle).
        DRAG = 0.09,         -- CC:Sable universalDrag (sable_probe.txt) -- drag accel = DRAG*v; sets the trim lean
        SPEED_KP = 0.4,      -- deg of extra lean per (b/s) of along-track speed error (proportional trim)
        -- DISABLED: the ballistic ARC descent (above) now flies it onto the target under controlled thrust
        -- with guidance active the whole way -- the old thrust-cut nose-over dive plummeted ballistically
        -- and the 82-deg toward-target lean ACCELERATED it horizontally as it fell, so it coasted ~75 blk
        -- past the target. Flip back to true only if the arc floats/undershoots and you want a hard plunge.
        ENABLE_DIVE = false, -- nose over and strike at the target (fly in fast at an angle, then dive)
        DIVE_TILT = 82,
        DIVE_LEAD = 1.0,
        DIVE_MIN_DIST = 40,
    },

    -- thrust: full in climb, a vertical-speed loop holds altitude in cruise, low in dive.
    thrust = {
        -- CLIMB: climb fast but TAPER the target climb-rate near the top so it arrives at cruise altitude
        -- with vs~0 -- otherwise it enters cruise at terminal climb speed (+54) and the hold-altitude loop
        -- slams thrust to 0 to stop it, which kills steering authority ("pointing up, no speed") for ~1.5s.
        CLIMB_VS = 45,       -- target climb rate (b/s) until the taper kicks in
        CLIMB_TAPER = 0.3,   -- desClimbVS = (CLIMB_HEIGHT - alt) * this, clamped to [3, CLIMB_VS] (tapers ~last 140 blk)
        HOVER = 9,            -- ~hover redstone level (cruise data: thr settled 8.5 -> vs +4.5, so true hover ~7.8)
        VS_KP = 0.8,         -- thrust per (b/s) of vertical-speed error
        -- Cruise altitude = track the BALLISTIC ARC profile (guidance.APEX_*). The arc gives a vertical-rate
        -- feedforward (its slope * closing speed) so thrust follows the ramp without lag; ALT_KP is the P
        -- pull-back onto the profile when we drift off it. desVS is clamped to [-DESC_VS, CLIMB_VS].
        ALT_KP  = 0.10,      -- thrust-loop desVS per block of altitude error vs the arc profile
        DESC_VS = 20,        -- b/s: cap on the commanded descent rate on the back half of the arc
        CEILING = 1900,      -- blocks above launch; the arc apex is clamped below this (never nears the 2000 lid)
        DIVE = 2,
        MIN = 0, MAX = 15,
        SMOOTH = 0.3,        -- low-pass on thrust changes
    },

    flight = {
        LOOP_PERIOD = 0.05,
        LAUNCH_LEVEL = 1,    -- redstone level on io.LAUNCH that fires the launch (a redstone link gives 15)
        DRY_RUN = false,     -- true = drive NOTHING (thrust included), log only -- bench use. false = fly.
    },

    io = {
        RIGHT_POS = "front", RIGHT_NEG = "back",   -- front/back = RIGHT axis (X) lean  [known-good]
        FWD_POS   = "left",  FWD_NEG   = "right",  -- left/right = FORWARD axis (Z) lean [verified]
        THRUST    = "bottom",                       -- main thrust
        LAUNCH    = "top",                          -- redstone INPUT: arms on boot, launches when this goes high
    },

    log = { EVERY = 6, FILE = "flight_solo.log" },
}

local C = CONFIG

-- ============================================================================
-- helpers
-- ============================================================================
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function round(v) return math.floor(v + 0.5) end
local function len2(x, z) return math.sqrt(x * x + z * z) end
local function angleDiff(a, b) return ((a - b + 180) % 360) - 180 end
local function dirOf(deg) local r = math.rad(deg) return math.sin(r), math.cos(r) end

-- call a peripheral/global method that may or may not want `self`, swallowing errors.
local function call0(fn, self)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    if ok then return v end
    if self then ok, v = pcall(fn, self) if ok then return v end end
    return nil
end

local function extractQuaternion(q)
    if type(q) ~= "table" then return nil end
    local x, y, z, w
    if type(q.v) == "table" then
        x, y, z, w = tonumber(q.v.x), tonumber(q.v.y), tonumber(q.v.z), tonumber(q.a)
    else
        x, y, z, w = tonumber(q.x), tonumber(q.y), tonumber(q.z), tonumber(q.w)
    end
    if not (x and y and z and w) then return nil end
    local l = math.sqrt(x * x + y * y + z * z + w * w)
    if l < 1e-6 then return nil end
    return { x = x / l, y = y / l, z = z / l, w = w / l }
end

-- rotate a body-frame vector into the world frame (q*v*q^-1).
local function rotateBodyToWorld(qq, x, y, z)
    local qx, qy, qz, qw = qq.x, qq.y, qq.z, qq.w
    local tx = 2 * (qy * z - qz * y)
    local ty = 2 * (qz * x - qx * z)
    local tz = 2 * (qx * y - qy * x)
    return x + qw * tx + (qy * tz - qz * ty),
           y + qw * ty + (qz * tx - qx * tz),
           z + qw * tz + (qx * ty - qy * tx)
end

local function axisVec(name)
    local t = { ["+X"]={1,0,0}, ["-X"]={-1,0,0}, ["+Y"]={0,1,0},
                ["-Y"]={0,-1,0}, ["+Z"]={0,0,1}, ["-Z"]={0,0,-1} }
    return t[name]
end

local function worldAxis(qq, name)
    local v = axisVec(name); if not v then return nil end
    return rotateBodyToWorld(qq, v[1], v[2], v[3])
end

local function horizUnit(x, z)
    local l = len2(x, z)
    if l < 1e-9 then return nil end
    return x / l, z / l, l
end

-- ============================================================================
-- peripherals: none required -- attitude/position from CC:Sable, target typed in, launch via redstone
-- ============================================================================

local function hasSable()
    return type(sublevel) == "table" and type(sublevel.getLogicalPose) == "function"
end

-- ============================================================================
-- state
-- ============================================================================
local dt = C.flight.LOOP_PERIOD
local phase = "CLIMB"               -- CLIMB -> CRUISE -> DIVE
local launchAlt = nil               -- pose.position.y captured at launch (baseline)
local cruiseDist0 = nil             -- horizontal range to target snapshotted at CLIMB->CRUISE (arc reference)
local prevWLX, prevWLZ = nil, nil   -- previous world horizontal lean vector (up.x, up.z)
local wRateX, wRateZ = 0, 0         -- smoothed world-frame lean-vector rate (yaw-independent)
local iFwd, iRight = 0, 0           -- attitude integral accumulators (per axis)
local prevHeading = nil
local yawRate = 0                   -- deg/s, logged only (we can't control yaw)
local smoothedThrust = 0
local dbg = {}

local logFile = fs.open(C.log.FILE, "w")
local logCount = 0
local function logLine(s) if logFile then logFile.writeLine(s); logFile.flush() end end
logLine(("---- START v4 single-computer  sable=%s dry=%s ----")
    :format(tostring(hasSable()), tostring(C.flight.DRY_RUN)))

-- ============================================================================
-- sensing  (all CC:Sable + nav table)
-- ============================================================================
local function readAttitude()
    if not hasSable() then return nil end
    local ok, pose = pcall(sublevel.getLogicalPose)
    if not ok or type(pose) ~= "table" or not pose.orientation then return nil end
    local qq = extractQuaternion(pose.orientation)
    if not qq then return nil end

    local ux, uy, uz = worldAxis(qq, C.pose.UP_AXIS)
    local fx, _, fz = worldAxis(qq, C.pose.FORWARD_AXIS)
    local rx, _, rz = worldAxis(qq, C.pose.RIGHT_AXIS)

    local fhx, fhz = horizUnit(fx, fz)
    local rhx, rhz = horizUnit(rx, rz)
    if not fhx or not rhx then return nil end

    local px, py, pz
    if type(pose.position) == "table" then
        px, py, pz = tonumber(pose.position.x), tonumber(pose.position.y), tonumber(pose.position.z)
    end

    return {
        up = { x = ux, y = uy, z = uz },
        fwd = { x = fhx, z = fhz },
        right = { x = rhx, z = rhz },
        heading = math.deg(math.atan2(fhx, fhz)),
        tiltDeg = math.deg(math.acos(clamp(uy, -1, 1))),
        pos = { x = px, y = py, z = pz },
        posY = py,
    }
end

local function readVelocity()
    if type(sublevel) ~= "table" or type(sublevel.getLinearVelocity) ~= "function" then return nil end
    local ok, v = pcall(sublevel.getLinearVelocity)
    if ok and type(v) == "table" then
        return { x = tonumber(v.x) or 0, y = tonumber(v.y) or 0, z = tonumber(v.z) or 0 }
    end
    return nil
end

-- (navigation_table removed -- aiming is by coordinate from pose.position)

-- ============================================================================
-- guidance
-- ============================================================================
-- start the dive when remaining distance drops to the predicted ballistic lead.
local function shouldDive(tgtDist, vel, alt)
    if not C.guidance.ENABLE_DIVE or not tgtDist then return false end
    local g = C.guidance
    local vh = vel and len2(vel.x, vel.z) or 0
    local drop = math.max(0, alt)           -- alt is already relative to launch
    local fallT = math.sqrt(2 * drop / g.GRAVITY)
    local lead = math.max(g.DIVE_MIN_DIST, vh * fallT * g.DIVE_LEAD)
    return tgtDist <= lead
end

-- (guidance lean is computed inline in update(): vertical in CLIMB, velocity-guided in CRUISE)

-- ============================================================================
-- outputs
-- ============================================================================
local function writeAnalog(side, level)
    if C.flight.DRY_RUN then return end
    redstone.setAnalogOutput(side, clamp(round(level), 0, 15))
end

local function writeSigned(value, posSide, negSide, sgn, limit)
    value = clamp(value * sgn, -limit, limit)
    if value >= 0 then writeAnalog(posSide, value); writeAnalog(negSide, 0)
    else               writeAnalog(posSide, 0); writeAnalog(negSide, -value) end
    return value
end

local function setSteerRight(effort)   -- front / back
    dbg.steerRightOut = writeSigned(effort, C.io.RIGHT_POS, C.io.RIGHT_NEG, C.sign.STEER_RIGHT, C.attitude.OUTPUT_LIMIT)
end
local function setSteerFwd(effort)     -- left / right
    dbg.steerFwdOut = writeSigned(effort, C.io.FWD_POS, C.io.FWD_NEG, C.sign.STEER_FWD, C.attitude.OUTPUT_LIMIT)
end
local function setThrust(level)
    level = clamp(level, C.thrust.MIN, C.thrust.MAX)
    dbg.thrustOut = level
    writeAnalog(C.io.THRUST, level)
end
local function neutralSteer() setSteerRight(0); setSteerFwd(0) end

-- thrust per phase: full climb, arc-tracking vertical-speed loop in cruise, low in dive.
local function controlThrust(vs, tiltCos, alt, desVS)
    local level
    if phase == "CLIMB" then
        -- taper the climb rate near the top so cruise starts at vs~0 (no thrust-cut / pointing-up transient)
        local desClimb = clamp((C.guidance.CLIMB_HEIGHT - (alt or 0)) * C.thrust.CLIMB_TAPER, 3, C.thrust.CLIMB_VS)
        level = C.thrust.HOVER / math.max(tiltCos or 1, 0.5) + C.thrust.VS_KP * (desClimb - (vs or 0))
    elseif phase == "DIVE" then
        level = C.thrust.DIVE
    else
        -- CRUISE: LEAN-COMPENSATED hover (thrust*cos(tilt) cancels weight at any lean) + a VS loop that
        -- tracks the BALLISTIC ARC's desired vertical speed (desVS): climb out, coast the apex, descend onto
        -- the target. desVS is computed in update() from the arc profile + rate feedforward; nil (e.g. no
        -- target fix) falls back to holding altitude (vs=0).
        local base = C.thrust.HOVER / math.max(tiltCos or 1, 0.5)
        level = base + C.thrust.VS_KP * ((desVS or 0) - (vs or 0))
    end
    smoothedThrust = smoothedThrust + (level - smoothedThrust) * C.thrust.SMOOTH
    setThrust(smoothedThrust)
end

-- ============================================================================
-- control update
-- ============================================================================
local function update()
    local att = readAttitude()
    local vel = readVelocity()

    if not att then
        -- no attitude -> can't steer; hold a hover so a momentary glitch doesn't drop us.
        neutralSteer()
        smoothedThrust = smoothedThrust + (C.thrust.HOVER - smoothedThrust) * C.thrust.SMOOTH
        setThrust(smoothedThrust)
        dbg.note = "no-pose"
        return
    end
    dbg.note = nil

    if not launchAlt and att.posY then launchAlt = att.posY end
    local alt = (launchAlt and att.posY) and (att.posY - launchAlt) or 0
    local vs = vel and vel.y or 0
    local cruiseDesVS = nil             -- desired vertical speed from the arc profile (set in CRUISE), -> thrust loop

    -- ---- targeting: EXACT world bearing/distance from pose.position (confirmed world coords) to TARGET.
    -- dirOf(tgtBear) is the world unit vector to the target; recomputed each tick, so it stays aimed
    -- even as the nose spins (aero yaw).
    local tgtBear, tgtDist
    if att.pos and att.pos.x and att.pos.z then
        local dx = C.nav.TARGET.x - att.pos.x
        local dz = C.nav.TARGET.z - att.pos.z
        tgtBear = math.deg(math.atan2(dx, dz))
        tgtDist = len2(dx, dz)
    end

    -- ---- phase machine (one-way) ----
    if phase == "CLIMB" and launchAlt and alt >= C.guidance.CLIMB_HEIGHT then
        phase = "CRUISE"
        cruiseDist0 = (tgtDist and tgtDist > 1) and tgtDist or nil  -- snapshot full range for the arc (halfway = apex)
    end
    if phase == "CRUISE" and shouldDive(tgtDist, vel, alt) then phase = "DIVE" end

    -- yaw rate (logged only -- shows the passive aero spin)
    if prevHeading then yawRate = angleDiff(att.heading, prevHeading) / dt end
    prevHeading = att.heading

    -- ---- actual lean as a WORLD horizontal vector (up.x, up.z); rate in world frame ----
    local wlx, wlz = att.up.x, att.up.z
    if prevWLX == nil then prevWLX, prevWLZ = wlx, wlz end
    local rawRX = (wlx - prevWLX) / dt
    local rawRZ = (wlz - prevWLZ) / dt
    wRateX = wRateX + (rawRX - wRateX) * C.attitude.RATE_SMOOTH
    wRateZ = wRateZ + (rawRZ - wRateZ) * C.attitude.RATE_SMOOTH
    prevWLX, prevWLZ = wlx, wlz

    -- project lean + lean-rate onto the live body axes (both axes)
    local leanFwd   = wlx * att.fwd.x   + wlz * att.fwd.z
    local leanRight = wlx * att.right.x + wlz * att.right.z
    local rateFwd   = wRateX * att.fwd.x   + wRateZ * att.fwd.z
    local rateRight = wRateX * att.right.x + wRateZ * att.right.z

    -- ---- guidance -> desired lean as a WORLD horizontal vector, then projected to body ----
    -- CLIMB: vertical (0). CRUISE: velocity guidance -- lean to chase a target-ward speed that
    -- tapers with distance, so the rocket brakes and CONVERGES instead of orbiting the target.
    local lx, lz = 0, 0
    if phase == "CRUISE" and tgtBear and tgtDist then
        local g = C.guidance
        local dx, dz = dirOf(tgtBear)                         -- unit dir to target (world)
        local desSpeed = math.min(g.MAX_SPEED, tgtDist * g.APPROACH_GAIN)
        local vx, vz = (vel and vel.x or 0), (vel and vel.z or 0)
        local vAlong = vx * dx + vz * dz
        -- ALONG-track lean = FEEDFORWARD trim (the angle that HOLDS desSpeed against drag, nonzero at speed
        -- so it never stands the rocket vertical) + a proportional speed correction. No integrator => no
        -- ~9 s porpoise. At cruise speed leanCmd settles at ~atan(DRAG*desSpeed/g) and the speed sticks.
        local leanFF = math.deg(math.atan(g.DRAG * desSpeed / g.GRAVITY))
        local leanCmd = clamp(leanFF + g.SPEED_KP * (desSpeed - vAlong), 0, g.MAX_LEAN)
        local mag = math.sin(math.rad(leanCmd))
        lx, lz = dx * mag, dz * mag
        -- CROSS-track: a responsive lean to cancel sideways drift, so it still tracks straight in.
        local px, pz = -dz, dx
        local vCross = vx * px + vz * pz
        local cmag = clamp(-g.VEL_KP * vCross / g.GRAVITY, -0.3, 0.3)
        lx, lz = lx + px * cmag, lz + pz * cmag
        local lmag = len2(lx, lz)                             -- overall lean cap
        local maxLean = math.sin(math.rad(g.MAX_LEAN))
        if lmag > maxLean and lmag > 1e-9 then lx, lz = lx * maxLean / lmag, lz * maxLean / lmag end

        -- ---- BALLISTIC ARC altitude profile -> desired vertical speed (thrust tracks this, not a flat hold).
        -- progress 0..1 along the flight; tent peaks at APEX at the halfway point (prog 0.5), then descends to
        -- the target's altitude. Feed-forward the profile's vertical RATE (slope * dprog/dt, dprog/dt =
        -- closingSpeed/range) so thrust follows the ramp with no lag; ALT_KP pulls back onto the profile.
        if not cruiseDist0 and tgtDist > 1 then cruiseDist0 = tgtDist end  -- lazy snapshot if entry tick lacked a fix
        local D0 = cruiseDist0 or math.max(tgtDist, 1)
        local prog = clamp(1 - tgtDist / D0, 0, 1)
        local apex = math.min(g.APEX_ALT, D0 * g.APEX_FRAC, C.thrust.CEILING)
        local startA = g.CLIMB_HEIGHT
        local endA = (launchAlt and (C.nav.TARGET.y - launchAlt)) or 0
        local desAlt, slope
        if prog < 0.5 then
            desAlt = startA + (apex - startA) * (prog / 0.5);        slope = (apex - startA) / 0.5
        else
            desAlt = apex   + (endA - apex)   * ((prog - 0.5) / 0.5); slope = (endA - apex) / 0.5
        end
        local ff = slope * (math.max(vAlong, 0) / D0)         -- profile vertical rate (feedforward)
        cruiseDesVS = clamp(ff + (desAlt - alt) * C.thrust.ALT_KP, -C.thrust.DESC_VS, C.thrust.CLIMB_VS)
        dbg.desAlt = desAlt
    elseif phase == "DIVE" and tgtBear then
        local mag = math.sin(math.rad(C.guidance.DIVE_TILT))
        lx, lz = dirOf(tgtBear)
        lx, lz = lx * mag, lz * mag
    end
    lx, lz = lx * C.nav.STEER_SIGN, lz * C.nav.STEER_SIGN
    local desFwd   = lx * att.fwd.x   + lz * att.fwd.z        -- project world lean -> body fwd
    local desRight = lx * att.right.x + lz * att.right.z      -- project world lean -> body right
    local cmdLeanDeg = math.deg(math.asin(clamp(len2(lx, lz), 0, 1)))

    -- ---- inner attitude PD, BOTH axes ----
    -- integral of lean error trims the steady residual lean (the slow sideways drift); clamped (anti-windup)
    iRight = clamp(iRight + (desRight - leanRight) * dt, -C.attitude.I_LIMIT, C.attitude.I_LIMIT)
    iFwd   = clamp(iFwd   + (desFwd   - leanFwd)   * dt, -C.attitude.I_LIMIT, C.attitude.I_LIMIT)
    local effortRight = C.attitude.TILT_KP * (desRight - leanRight) - C.attitude.TILT_KD * rateRight + C.attitude.TILT_KI * iRight
    local effortFwd   = C.attitude.TILT_KP * (desFwd   - leanFwd)   - C.attitude.TILT_KD * rateFwd   + C.attitude.TILT_KI * iFwd
    setSteerRight(effortRight)   -- front/back
    setSteerFwd(effortFwd)       -- left/right

    -- ---- thrust ----
    controlThrust(vs, att.up.y, alt, cruiseDesVS)   -- att.up.y = cos(tilt) for lean comp; cruiseDesVS = arc target

    -- ---- stash for logging ----
    dbg.alt, dbg.posY, dbg.vs = alt, att.posY or 0, vs
    dbg.tiltDeg, dbg.cmdTilt, dbg.heading, dbg.yawRate = att.tiltDeg, cmdLeanDeg, att.heading, yawRate
    dbg.tgtBear, dbg.tgtDist = tgtBear or 0, tgtDist or -1
    dbg.leanFwd, dbg.leanRight = leanFwd, leanRight
    dbg.rateFwd, dbg.rateRight = rateFwd, rateRight
    dbg.desFwd, dbg.desRight = desFwd, desRight
    dbg.effortFwd, dbg.effortRight = effortFwd, effortRight
end

local function logState()
    logCount = logCount + 1
    if logCount % C.log.EVERY ~= 0 then return end
    logLine(("t=%d ph=%s alt=%.1f/%.0f vs=%.1f tilt=%.1f cmd=%.1f hdg=%.1f tgtBrg=%.1f tgtDist=%.0f")
        :format(logCount, phase, dbg.alt or 0, dbg.desAlt or 0, dbg.vs or 0, dbg.tiltDeg or 0, dbg.cmdTilt or 0,
                dbg.heading or 0, dbg.tgtBear or 0, dbg.tgtDist or -1))
    logLine(("   FWD(L/R) des=%+.3f act=%+.3f rate=%+.3f eff=%+.2f out=%+.1f | RIGHT(F/B) des=%+.3f act=%+.3f rate=%+.3f eff=%+.2f out=%+.1f | thr=%.1f%s")
        :format(dbg.desFwd or 0, dbg.leanFwd or 0, dbg.rateFwd or 0, dbg.effortFwd or 0, dbg.steerFwdOut or 0,
                dbg.desRight or 0, dbg.leanRight or 0, dbg.rateRight or 0, dbg.effortRight or 0, dbg.steerRightOut or 0,
                dbg.thrustOut or smoothedThrust, dbg.note and (" [" .. dbg.note .. "]") or ""))
end

-- ============================================================================
-- target entry  ->  launch arming  ->  main loop
-- ============================================================================
local function ask(label, dflt)
    write(("%s [%s]: "):format(label, tostring(dflt)))
    return tonumber(read()) or dflt
end

print(("=== ROCKET v4  sable=%s dry=%s ==="):format(tostring(hasSable()), tostring(C.flight.DRY_RUN)))
print("Enter target coords (blank = keep default):")
C.nav.TARGET.x = ask("  X", C.nav.TARGET.x)
C.nav.TARGET.y = ask("  Y", C.nav.TARGET.y)
C.nav.TARGET.z = ask("  Z", C.nav.TARGET.z)
print(("Target: %.0f, %.0f, %.0f"):format(C.nav.TARGET.x, C.nav.TARGET.y, C.nav.TARGET.z))
logLine(("target %.0f,%.0f,%.0f"):format(C.nav.TARGET.x, C.nav.TARGET.y, C.nav.TARGET.z))

print(("ARMED -- raise redstone on '%s' to launch..."):format(C.io.LAUNCH))
while redstone.getAnalogInput(C.io.LAUNCH) < C.flight.LAUNCH_LEVEL do
    neutralSteer(); setThrust(0)        -- sit inert on the pad until the launch signal
    os.sleep(0.1)
end
print("LAUNCH!"); logLine("---- LAUNCH ----")

while true do
    local ok, err = pcall(function() update(); logState() end)
    if not ok then
        local line = "[SOLO] ERROR: " .. tostring(err)
        print(line); logLine(line)
        neutralSteer()
        -- keep a hover rather than cutting thrust on a transient error
        smoothedThrust = C.thrust.HOVER
        setThrust(smoothedThrust)
        os.sleep(0.5)
    else
        os.sleep(dt)
    end
end
