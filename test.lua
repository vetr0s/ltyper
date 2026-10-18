-- Run with: luajit test.lua
local stats = require("stats")

local c = stats.count({ "the", "be", "of" }, { "the", "bx", "o" }, 3)
assert(c.correct == 5 and c.incorrect == 1 and c.extra == 0 and c.missed == 0)
assert(c.spaces == 2 and c.correctWordChars == 5)

c = stats.count({ "the", "be" }, { "thee", "" }, 2)
assert(c.extra == 1 and c.correctWordChars == 0)

c = stats.count({ "have", "a" }, { "ha", "" }, 2)
assert(c.missed == 2)

assert(stats.wpm(50, 60) == 10)
assert(stats.consistency({ 50, 50, 50 }) == 100)
assert(stats.consistency({ 0, 0 }) == 0)
assert(stats.consistency({ 10, 90 }) < 50)

print("ok")
