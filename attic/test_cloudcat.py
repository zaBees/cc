from cloudcat import fletcher32

# Standard fletcher-32 test vectors (same padding rule as the host's encode.lua).
assert fletcher32(b"abcde") == 0xF04FC729
assert fletcher32(b"abcdef") == 0x56502D2A
assert fletcher32(b"abcdefgh") == 0xEBE19591
assert fletcher32(b"") == 0
print("ok")

# --- chunked push: the split must rejoin, and the joiner must be real Lua -----
# The transport caps a packet at ~18 KB, so quarry.lua goes over as parts plus a
# generated joiner. Both halves of that are worth a check: a split that does not
# rejoin byte-for-byte ships a corrupt program, and a joiner with a syntax error
# only shows up in-game, which is the expensive place to find it.
import json, os, shutil, subprocess, tempfile
import cloudcat

# quarry.lua lives one level up: cloudcat was archived into attic/ on
# 2026-08-28 when delivery moved to GitHub.
SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "quarry.lua")
text = open(SRC).read()

parts = cloudcat.split_lines(text, "quarry")
assert "".join(parts) == text, "the split does not rejoin to the original"
assert len(parts) > 1, "quarry.lua should need more than one packet"
for i, p in enumerate(parts, 1):
    n = len(cloudcat.file_packet("quarry.p%d" % i, p))
    assert n <= cloudcat.PACKET_BUDGET, "part %d encodes to %d bytes, over budget" % (i, n)

# Run the generated joiner under lua5.3 against a stub fs, and diff the result.
tmp = tempfile.mkdtemp()
try:
    for i, p in enumerate(parts, 1):
        open(os.path.join(tmp, "quarry.p%d" % i), "w").write(p)
    open(os.path.join(tmp, "join.lua"), "w").write(cloudcat.joiner_source("quarry", parts))
    # CC's file handles take their argument with a dot, not a colon --
    # o.write(s), not o:write(s) -- so the stub matches that, or the joiner
    # would pass the test here and fail in the game.
    open(os.path.join(tmp, "shim.lua"), "w").write("""
local dir = ...
fs = {
  open = function(name, mode)
    local h = io.open(dir .. "/" .. name, mode == "w" and "w" or "r")
    if not h then return nil end
    return { readAll = function() return h:read("*a") end,
             write   = function(s) h:write(s) end,
             close   = function() h:close() end }
  end,
  delete = function(name) os.remove(dir .. "/" .. name) end,
}
dofile(dir .. "/join.lua")
""")
    r = subprocess.run(["lua5.3", os.path.join(tmp, "shim.lua"), tmp],
                       capture_output=True, text=True)
    assert r.returncode == 0, "the joiner failed:\n" + r.stdout + r.stderr
    joined = open(os.path.join(tmp, "quarry")).read()
    assert joined == text, "the joiner produced %d bytes, wanted %d" % (len(joined), len(text))
    for i in range(1, len(parts) + 1):
        assert not os.path.exists(os.path.join(tmp, "quarry.p%d" % i)), \
            "part %d was left behind" % i
finally:
    shutil.rmtree(tmp)

print("chunked push ok: %d parts, joins byte-for-byte" % len(parts))
