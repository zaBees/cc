#!/usr/bin/env python3
"""Headless cloud-catcher client: push files to a CC:Tweaked computer, or type at it.

Usage:
  cloudcat.py <token> push <local-file> [remote-path]     (splits if oversized)
  cloudcat.py <token> pull <remote-path> [local-file]
  cloudcat.py <token> run  "<command>"
  cloudcat.py <token> watch

Token is the 32-char id from your cloud-catcher URL (?id=...).
The in-game computer must be running `cloud <token>`.
"""
import asyncio, json, sys, os

try:
    import websockets
except ImportError:                      # the pure helpers stay testable without it
    websockets = None

SERVER = os.environ.get("CLOUD_CATCHER", "wss://cloud-catcher.squiddev.cc")
MAX_PACKET = int(os.environ.get("CLOUD_MAX_PACKET", "20000"))

# The server closes the socket with 1009 "message too big" on an oversized
# frame, and the whole push is lost. Measured 2026-08-28: a 16,000-byte file
# went through, 32,000 did not. The budget below is on the ENCODED packet, not
# the file, because JSON escaping inflates Lua source by roughly a sixth --
# every newline and quote costs two characters instead of one.
PACKET_BUDGET = int(os.environ.get("CLOUD_PACKET_BUDGET", "18000"))

PING, TERM_CONTENTS, TERM_EVENTS, FILE_ACTION, FILE_CONSUME = 0x02, 0x10, 0x11, 0x22, 0x23
CONSUME = {1: "ok", 2: "rejected (checksum)", 3: "write failed"}


def fletcher32(data: bytes) -> int:
    if len(data) % 2:
        data += b"\0"
    s1 = s2 = 0
    for i in range(0, len(data), 2):
        s1 = (s1 + data[i] + (data[i + 1] << 8)) % 0xFFFF
        s2 = (s2 + s1) % 0xFFFF
    return s2 * 0x10000 + s1


async def session(token, caps, job):
    if websockets is None:
        sys.exit("this needs the websockets module: pip install websockets")
    url = f"{SERVER}/connect?id={token}&capabilities={','.join(caps)}"
    async with websockets.connect(url, max_size=MAX_PACKET) as ws:
        await job(ws)


async def pump(ws, on_packet, idle=None):
    """Read packets until on_packet returns True, or until `idle` seconds of quiet."""
    while True:
        try:
            raw = await asyncio.wait_for(ws.recv(), idle)
        except asyncio.TimeoutError:
            return
        p = json.loads(raw)
        if p.get("packet") == PING:
            await ws.send('{"packet":2}')
        elif on_packet(p):
            return


def file_packet(remote_path, contents):
    return json.dumps({
        "packet": FILE_ACTION, "id": 0,
        # flags 0x1 => host skips the checksum check and overwrites
        "actions": [{"file": remote_path, "checksum": fletcher32(contents.encode()),
                     "flags": 0x1, "action": 0x0, "contents": contents}],
    })


async def send_one(ws, remote_path, contents):
    """One file, one packet. Caller has already checked it fits."""
    await ws.send(file_packet(remote_path, contents))
    results = []

    def done(p):
        if p.get("packet") != FILE_CONSUME:
            return False
        for f in p["files"]:
            results.append(f["result"])
            print(f"{f['file']}: {CONSUME.get(f['result'], f['result'])}")
        return True

    await pump(ws, done)
    if results and results[0] != 1:
        sys.exit(f"{remote_path}: host refused the write")


def split_lines(contents, remote_path):
    """Cut on line boundaries so each ENCODED packet fits under the budget.

    Measuring the encoded packet rather than guessing from the raw length
    matters: a comment-heavy stretch of Lua escapes far less than a stretch
    full of quoted strings, so a fixed raw chunk size is either wasteful or
    occasionally over the line.
    """
    parts, cur = [], []
    for line in contents.splitlines(keepends=True):
        trial = cur + [line]
        if cur and len(file_packet(f"{remote_path}.p{len(parts) + 1}", "".join(trial))) > PACKET_BUDGET:
            parts.append("".join(cur))
            cur = [line]
        else:
            cur = trial
    if cur:
        parts.append("".join(cur))
    if any(len(file_packet(remote_path, p)) > PACKET_BUDGET for p in parts):
        sys.exit("a single line is too long to fit in one packet")
    assert "".join(parts) == contents
    return parts


def joiner_source(remote_path, parts):
    """A CC program that stitches the parts back together and checks as it goes.

    The length check per part is what catches a truncated or missing piece;
    without it a short part just silently produces a shorter program, which
    would fail somewhere far away from the real cause.
    """
    table = ",\n".join(
        '  { "%s.p%d", %d }' % (remote_path, i + 1, len(p)) for i, p in enumerate(parts))
    return f'''-- written by cloudcat: reassembles {remote_path} from {len(parts)} pushed parts
local parts = {{
{table}
}}
local buf = {{}}
for i, p in ipairs(parts) do
  local h = fs.open(p[1], "r")
  if not h then error("missing " .. p[1], 0) end
  local s = h.readAll()
  h.close()
  if #s ~= p[2] then
    error(("%s is %d bytes, expected %d"):format(p[1], #s, p[2]), 0)
  end
  buf[i] = s
end
local all = table.concat(buf)
if #all ~= {len("".join(parts))} then
  error(("joined to %d bytes, expected {len("".join(parts))}"):format(#all), 0)
end
local o = fs.open("{remote_path}", "w")
o.write(all)
o.close()
for _, p in ipairs(parts) do fs.delete(p[1]) end
print(("{remote_path}: %d bytes from %d parts, parts deleted"):format(#all, #parts))
'''


async def push(ws, remote_path, contents):
    """One packet if it fits, otherwise parts plus a joiner program."""
    if len(file_packet(remote_path, contents)) <= PACKET_BUDGET:
        await send_one(ws, remote_path, contents)
        return

    parts = split_lines(contents, remote_path)
    join_name = f"{remote_path}.join"
    print(f"{len(contents)} bytes is over the {PACKET_BUDGET}-byte packet budget: "
          f"sending {len(parts)} parts plus {join_name}")
    for i, part in enumerate(parts, 1):
        await send_one(ws, f"{remote_path}.p{i}", part)
    await send_one(ws, join_name, joiner_source(remote_path, parts))
    print(f"\nnow run this on the computer:\n    {join_name}")


async def pull(ws, remote_path, local_path):
    """The host has no file-serving packet, but `cloud edit <file>` makes it push one."""
    await ws.send(json.dumps({"packet": TERM_EVENTS, "events": [
        {"name": "paste", "args": [f"cloud edit {remote_path}"]},
        {"name": "key", "args": [257, False]},
    ]}))

    def grab(p):
        if p.get("packet") != FILE_ACTION:
            return False
        for a in p["actions"]:
            with open(local_path, "w") as fh:
                fh.write(a["contents"])
            print(f"{a['file']} -> {local_path} ({len(a['contents'])} bytes)")
        return True

    await pump(ws, grab, idle=10.0)


async def run(ws, command):
    await ws.send(json.dumps({"packet": TERM_EVENTS, "events": [
        {"name": "paste", "args": [command]},
        {"name": "key", "args": [257, False]},   # 257 = enter
    ]}))
    # The host redraws on every change; stop once it has been quiet for a moment.
    await watch(ws, idle=2.0)


async def watch(ws, idle=None):
    def show(p):
        if p.get("packet") != TERM_CONTENTS:
            return False
        print("\n".join(line.rstrip() for line in p["text"]), flush=True)
        print("-" * p["width"], flush=True)
        return False
    await pump(ws, show, idle)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    token, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if len(token) != 32 or not token.isalnum():
        sys.exit("token must be 32 alphanumeric chars")

    if cmd == "push":
        local = args[0]
        remote = args[1] if len(args) > 1 else os.path.basename(local)
        with open(local) as fh:
            contents = fh.read()
        job, caps = lambda ws: push(ws, remote, contents), ["file:edit"]
    elif cmd == "pull":
        remote = args[0]
        local = args[1] if len(args) > 1 else os.path.basename(remote)
        job, caps = lambda ws: pull(ws, remote, local), ["file:edit", "terminal:view"]
    elif cmd == "run":
        job, caps = lambda ws: run(ws, args[0]), ["terminal:view"]
    elif cmd == "watch":
        job, caps = watch, ["terminal:view"]
    else:
        sys.exit(__doc__)

    asyncio.run(session(token, caps, job))


if __name__ == "__main__":
    main()
