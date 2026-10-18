-- Result math, following Monkeytype's definitions. Pure Lua so test.lua can run it without LOVE.
local M = {}

-- words[i] is the target, typed[i] the input; cur is the word being typed when time ran out.
function M.count(words, typed, cur)
	local c = { correctWordChars = 0, correct = 0, incorrect = 0, extra = 0, missed = 0, spaces = 0 }
	for i = 1, cur do
		local w, t = words[i], typed[i]
		for j = 1, #t do
			if j > #w then
				c.extra = c.extra + 1
			elseif t:sub(j, j) == w:sub(j, j) then
				c.correct = c.correct + 1
			else
				c.incorrect = c.incorrect + 1
			end
		end
		if i < cur then
			c.missed = c.missed + math.max(0, #w - #t)
			c.spaces = c.spaces + 1
			if t == w then c.correctWordChars = c.correctWordChars + #w + 1 end
		elseif w:sub(1, #t) == t then
			c.correctWordChars = c.correctWordChars + #t
		end
	end
	return c
end

function M.wpm(chars, seconds)
	return chars / 5 / (seconds / 60)
end

-- Monkeytype's "kogasa" curve over the coefficient of variation of per-second raw wpm.
function M.consistency(raw)
	local n, sum, sq = #raw, 0, 0
	for _, v in ipairs(raw) do sum = sum + v end
	local mean = sum / n
	if n == 0 or mean == 0 then return 0 end
	for _, v in ipairs(raw) do sq = sq + (v - mean) ^ 2 end
	local cov = math.sqrt(sq / n) / mean
	return 100 * (1 - math.tanh(cov + cov ^ 3 / 3 + cov ^ 5 / 5))
end

return M
