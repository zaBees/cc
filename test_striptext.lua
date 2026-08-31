-- Exercises the real Q.stripText from quarry.lua: it now drops trailing comments
-- to keep the ~110 KB program under the floppy, and the one thing that must not
-- break is a "--" INSIDE a string (the messages are full of " -- ").

local src = assert(io.open("quarry.lua")):read("*a")
-- Pull the function verbatim: it ends at the first column-0 `end`.
local body = src:match("(function Q%.stripText%(body%).-\nend)\n")
assert(body, "could not extract Q.stripText from quarry.lua")

local Q = {}
assert(load("local Q = ...\n" .. body .. "\nreturn Q", "striptext", "t"))(Q)
local strip = assert(Q.stripText, "stripText not defined")

local function one(input) return (strip(input):gsub("\n$", "")) end

-- a bare trailing comment is removed, code kept and tightened
assert(one("  local x = 1   -- a note") == "local x = 1", one("  local x = 1   -- a note"))
-- a -- inside a double-quoted string survives untouched
assert(one('say("a -- b")') == 'say("a -- b")', one('say("a -- b")'))
-- string kept, trailing comment after it removed
assert(one('say("a -- b")  -- real') == 'say("a -- b")', one('say("a -- b")  -- real'))
-- a full-line comment is dropped entirely (empty output)
assert(one("   -- whole line") == "", "[" .. one("   -- whole line") .. "]")
-- single quotes count too
assert(one("f('x--y') -- c") == "f('x--y')", one("f('x--y') -- c"))
-- an escaped quote does not end the string early
assert(one('g("a\\"b -- c") -- d') == 'g("a\\"b -- c")', one('g("a\\"b -- c") -- d'))
-- a [[ long string spanning lines is preserved verbatim (config template)
local long = 'local C = [[\n  key = 1   # keep\n]]\n'
assert(strip(long):find("key = 1   # keep", 1, true), "long-string body was altered:\n" .. strip(long))

-- and the whole program still compiles after stripping
assert(load(strip(src), "stripped"), "the stripped program does not compile")

print("all stripText checks passed")
