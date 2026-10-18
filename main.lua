-- A typing test modelled on Monkeytype's default: 30 seconds of random words from the english 200
-- list. Results add a saved personal best and the keys you missed most. Three lines of words are visible; when the caret reaches the third line the
-- first line scrolls off. Words are generated lazily as the layout needs them.
local wordList = require("words")
local stats = require("stats")

local DURATION = 30
local EXTRA_LIMIT = 20

local function hex(s)
	return { tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255 }
end

local C = {
	bg = hex("#17191e"), main = hex("#78dba9"), sub = hex("#4c5261"), subAlt = hex("#22252c"),
	text = hex("#d6d9e0"), err = hex("#f2696b"), errExtra = hex("#8c3b40"),
}
local BEST_FILE = "best-" .. DURATION

local fonts, lineH
local state, words, typed, cur, firstWord, pos
local startTime, lastKey, caretX
local accKeys, accCorrect, secChars, secErrs
local wpmHist, rawHist, errHist, misses, result, best

local function loadFonts()
	-- shortcut: Menlo exists only on macOS; other systems get LOVE's default font. Bundle Roboto Mono for an exact match.
	local file = io.open("/System/Library/Fonts/Menlo.ttc", "rb")
	local data = file and love.filesystem.newFileData(file:read("*a"), "Menlo.ttc")
	if file then file:close() end
	local function font(size) return data and love.graphics.newFont(data, size) or love.graphics.newFont(size) end
	fonts = { s = font(16), m = font(24), l = font(32), xl = font(64) }
	lineH = math.floor(fonts.l:getHeight() * 1.3)
end

local function area()
	local W, H = love.graphics.getDimensions()
	local w = math.min(W - 160, 1000)
	return (W - w) / 2, H / 2 - lineH * 1.5, w
end

local function addWord()
	local w
	repeat w = wordList[love.math.random(#wordList)] until w ~= words[#words]
	words[#words + 1] = w
end

-- Extra letters are drawn after the target word, so they widen it.
local function display(i)
	return words[i] .. (typed[i] or ""):sub(#words[i] + 1)
end

local function relayout()
	local _, _, aw = area()
	local space = fonts.l:getWidth(" ")
	while true do
		pos = {}
		local x, line, i = 0, 0, firstWord
		while true do
			while #words < i do addWord() end
			local ww = fonts.l:getWidth(display(i))
			if x > 0 and x + ww > aw then x, line = 0, line + 1 end
			if line == 3 then break end
			pos[i] = { x = x, line = line, w = ww }
			x = x + ww + space
			i = i + 1
		end
		if pos[cur].line < 2 then return end
		repeat firstWord = firstWord + 1 until pos[firstWord].line == 1
	end
end

local function restart()
	state, words, typed, cur, firstWord = "idle", {}, { "" }, 1, 1
	accKeys, accCorrect, secChars, secErrs = 0, 0, 0, 0
	wpmHist, rawHist, errHist, misses, result = {}, {}, {}, {}, nil
	lastKey, caretX = 0, nil
	relayout()
end

local function finish()
	local c = stats.count(words, typed, cur)
	state = "result"
	result = {
		c = c,
		wpm = stats.wpm(c.correctWordChars, DURATION),
		raw = stats.wpm(c.correct + c.incorrect + c.extra + c.spaces, DURATION),
		acc = accKeys > 0 and accCorrect / accKeys * 100 or 0,
		consistency = stats.consistency(rawHist),
		best = best,
		trouble = {},
	}
	for key, n in pairs(misses) do result.trouble[#result.trouble + 1] = { key = key, n = n } end
	table.sort(result.trouble, function(a, b) return a.n > b.n or (a.n == b.n and a.key < b.key) end)
	local wpm = math.floor(result.wpm + 0.5)
	if wpm > best then
		best = wpm
		love.filesystem.write(BEST_FILE, tostring(best))
	end
end

function love.load()
	love.keyboard.setKeyRepeat(true)
	loadFonts()
	best = tonumber((love.filesystem.read(BEST_FILE))) or 0
	restart()
end

function love.resize()
	caretX = nil
	relayout()
end

function love.update(dt)
	if state == "running" then
		local elapsed = love.timer.getTime() - startTime
		while #wpmHist < math.min(math.floor(elapsed), DURATION) do
			local s = #wpmHist + 1
			wpmHist[s] = stats.wpm(stats.count(words, typed, cur).correctWordChars, s)
			rawHist[s], errHist[s] = stats.wpm(secChars, 1), secErrs
			secChars, secErrs = 0, 0
		end
		if elapsed >= DURATION then finish() end
	end
	if state ~= "result" then
		local tx = pos[cur].x + fonts.l:getWidth(display(cur):sub(1, #typed[cur]))
		caretX = caretX and caretX + (tx - caretX) * math.min(1, dt * 25) or tx
	end
end

function love.textinput(t)
	if state == "result" or #t ~= 1 or t:byte() < 32 or t:byte() > 126 then return end
	local w, tp = words[cur], typed[cur]
	if t == " " then
		if tp == "" then return end
		accKeys, secChars = accKeys + 1, secChars + 1
		if tp == w then accCorrect = accCorrect + 1 else secErrs = secErrs + 1 end
		cur = cur + 1
		typed[cur] = ""
	else
		if #tp >= #w + EXTRA_LIMIT then return end
		if state == "idle" then state, startTime = "running", love.timer.getTime() end
		accKeys, secChars = accKeys + 1, secChars + 1
		local want = w:sub(#tp + 1, #tp + 1)
		if want == t then
			accCorrect = accCorrect + 1
		else
			secErrs = secErrs + 1
			if want ~= "" then misses[want] = (misses[want] or 0) + 1 end
		end
		typed[cur] = tp .. t
	end
	lastKey = love.timer.getTime()
	relayout()
end

function love.keypressed(key)
	if key == "tab" then return restart() end
	if key ~= "backspace" or state == "result" then return end
	local wordDelete = love.keyboard.isDown("lctrl", "rctrl", "lalt", "ralt", "lgui", "rgui")
	if typed[cur] == "" then
		-- Only an incorrect word on a visible line can be re-entered.
		if cur == firstWord or typed[cur - 1] == words[cur - 1] then return end
		typed[cur] = nil
		cur = cur - 1
		if wordDelete then typed[cur] = "" end
	else
		typed[cur] = wordDelete and "" or typed[cur]:sub(1, -2)
	end
	lastKey = love.timer.getTime()
	relayout()
end

local function drawTest()
	local ax, ay, aw = area()
	local f = fonts.l
	love.graphics.setFont(fonts.m)
	if state == "running" then
		local elapsed = love.timer.getTime() - startTime
		love.graphics.setColor(C.main)
		love.graphics.print(DURATION - math.floor(elapsed), ax, ay - 20 - fonts.m:getHeight())
		love.graphics.setColor(C.subAlt)
		love.graphics.rectangle("fill", ax, ay - 14, aw, 3)
		love.graphics.setColor(C.main)
		love.graphics.rectangle("fill", ax, ay - 14, aw * math.max(0, 1 - elapsed / DURATION), 3)
	else
		love.graphics.setColor(C.sub)
		love.graphics.printf("english 200 \194\183 " .. DURATION .. "s", ax, ay - lineH, aw, "center")
	end
	love.graphics.setFont(f)

	for i, p in pairs(pos) do
		local w, t = words[i], typed[i] or ""
		local colored = {}
		for j = 1, math.max(#w, #t) do
			local col
			if j > #w then
				col = C.errExtra
			elseif j > #t then
				col = C.sub
			elseif t:sub(j, j) == w:sub(j, j) then
				col = C.text
			else
				col = C.err
			end
			colored[#colored + 1] = col
			colored[#colored + 1] = j <= #w and w:sub(j, j) or t:sub(j, j)
		end
		local y = ay + p.line * lineH
		love.graphics.setColor(1, 1, 1)
		love.graphics.print(colored, ax + p.x, y)
		if i < cur and t ~= w then
			love.graphics.setColor(C.err)
			love.graphics.rectangle("fill", ax + p.x, y + f:getHeight(), p.w, 2)
		end
	end

	local now = love.timer.getTime()
	local alpha = (state == "running" or now - lastKey < 0.5) and 1 or math.abs(math.cos(now * math.pi))
	love.graphics.setColor(C.main[1], C.main[2], C.main[3], alpha)
	love.graphics.rectangle("fill", ax + caretX - 1, ay + pos[cur].line * lineH, 3, f:getHeight())
end

local function drawChart(cx, cy, cw, ch)
	local n = #wpmHist
	if n == 0 then return end
	local top = 0
	for s = 1, n do top = math.max(top, wpmHist[s], rawHist[s]) end
	top = math.max(20, math.ceil(top / 20) * 20)
	local function px(s) return cx + (n == 1 and 0 or (s - 1) / (n - 1) * cw) end
	local function py(v) return cy + ch - v / top * ch end

	love.graphics.setFont(fonts.s)
	love.graphics.setLineWidth(1)
	for g = 0, 4 do
		local v = top * g / 4
		love.graphics.setColor(C.subAlt)
		love.graphics.line(cx, py(v), cx + cw, py(v))
		love.graphics.setColor(C.sub)
		love.graphics.printf(math.floor(v), cx - 50, py(v) - 9, 40, "right")
	end

	local raw, wpm = {}, {}
	for s = 1, n do
		raw[#raw + 1], raw[#raw + 2] = px(s), py(rawHist[s])
		wpm[#wpm + 1], wpm[#wpm + 2] = px(s), py(wpmHist[s])
	end
	love.graphics.setLineWidth(2)
	if n > 1 then
		love.graphics.setColor(C.sub)
		love.graphics.line(raw)
		love.graphics.setColor(C.main)
		love.graphics.line(wpm)
	end
	-- Errors are marked on the raw line at the second they happened.
	love.graphics.setColor(C.err)
	for s = 1, n do
		if errHist[s] > 0 then
			local x, y = px(s), py(rawHist[s])
			love.graphics.line(x - 4, y - 4, x + 4, y + 4)
			love.graphics.line(x - 4, y + 4, x + 4, y - 4)
		end
	end
end

local function drawResult()
	local ax, _, aw = area()
	local y0 = love.graphics.getHeight() / 2 - 210
	local function stat(label, value, x, y, labelFont, valueFont)
		love.graphics.setFont(labelFont)
		love.graphics.setColor(C.sub)
		love.graphics.print(label, x, y)
		love.graphics.setFont(valueFont)
		love.graphics.setColor(C.main)
		love.graphics.print(value, x, y + labelFont:getHeight())
	end

	local wpm = math.floor(result.wpm + 0.5)
	stat("wpm", wpm, ax, y0, fonts.l, fonts.xl)
	love.graphics.setFont(fonts.s)
	local bx, by = ax + fonts.l:getWidth("wpm "), y0 + fonts.l:getHeight() - fonts.s:getHeight() - 4
	if wpm > result.best then
		love.graphics.setColor(C.main)
		love.graphics.print(result.best > 0 and "new best +" .. wpm - result.best or "first best", bx, by)
	else
		love.graphics.setColor(C.sub)
		love.graphics.print("best " .. result.best, bx, by)
	end
	stat("acc", math.floor(result.acc) .. "%", ax, y0 + 120, fonts.l, fonts.xl)
	drawChart(ax + 260, y0 + 10, aw - 260, 200)

	local c = result.c
	local row = {
		{ "test type", "time " .. DURATION .. "\nenglish" },
		{ "raw", math.floor(result.raw + 0.5) },
		{ "characters", c.correct .. "/" .. c.incorrect .. "/" .. c.extra .. "/" .. c.missed },
		{ "consistency", math.floor(result.consistency + 0.5) .. "%" },
		{ "time", DURATION .. "s" },
	}
	local widths, total = {}, 0
	for k, item in ipairs(row) do
		widths[k] = math.max(fonts.s:getWidth(item[1]), fonts.m:getWidth(item[2]))
		total = total + widths[k]
	end
	local x, gap = ax, (aw - total) / (#row - 1)
	for k, item in ipairs(row) do
		stat(item[1], item[2], x, y0 + 260, fonts.s, fonts.m)
		x = x + widths[k] + gap
	end

	local ty = y0 + 350
	love.graphics.setFont(fonts.s)
	love.graphics.setColor(C.sub)
	love.graphics.print("trouble keys", ax, ty)
	ty = ty + 26
	if #result.trouble == 0 then
		love.graphics.setFont(fonts.m)
		love.graphics.setColor(C.main)
		love.graphics.print("none", ax, ty + 4)
	end
	local kx = ax
	for i = 1, math.min(5, #result.trouble) do
		local t = result.trouble[i]
		love.graphics.setColor(C.subAlt)
		love.graphics.rectangle("fill", kx, ty, 40, 40, 6)
		love.graphics.setFont(fonts.m)
		love.graphics.setColor(C.text)
		love.graphics.printf(t.key, kx, ty + (40 - fonts.m:getHeight()) / 2, 40, "center")
		love.graphics.setFont(fonts.s)
		love.graphics.setColor(C.err)
		love.graphics.print(t.n, kx + 48, ty + (40 - fonts.s:getHeight()) / 2)
		kx = kx + 48 + fonts.s:getWidth(t.n) + 20
	end
end

function love.draw()
	local W, H = love.graphics.getDimensions()
	love.graphics.clear(C.bg)
	if state ~= "running" then
		love.graphics.setFont(fonts.l)
		love.graphics.setColor(1, 1, 1)
		love.graphics.print({ C.main, "l", C.text, "typer" }, 40, 30)
		love.graphics.setFont(fonts.s)
		love.graphics.setColor(C.sub)
		love.graphics.printf("tab - restart test", 0, H - 50, W, "center")
	end
	if state == "result" then drawResult() else drawTest() end
end
