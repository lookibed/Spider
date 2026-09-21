-- SECTION bit32
-- NEEDS bit
local bit32 = {}

local function bit32_countlz_impl(x)
	x = bit.band(x, 0xFFFFFFFF)

	if x == 0 then
		return 32
	end

	local count = 0

	while bit.band(x, 0x80000000) == 0 do
		x = bit.lshift(x, 1)
		count = count + 1
	end

	return count
end

local function bit32_countrz_impl(x)
	x = bit.band(x, 0xFFFFFFFF)

	if x == 0 then
		return 32
	end

	local count = 0

	while bit.band(x, 1) == 0 do
		x = bit.rshift(x, 1)
		count = count + 1
	end

	return count
end

bit32.countlz = bit32_countlz_impl
bit32.countrz = bit32_countrz_impl

-- SECTION bit32_and
-- NEEDS bit
local bit32_and = bit.band

-- SECTION bit32_or
-- NEEDS bit
local bit32_or = bit.bor

-- SECTION bit32_xor
-- NEEDS bit
local bit32_xor = bit.bxor

-- SECTION bit32_lshift
-- NEEDS bit
local bit32_lshift = bit.lshift

-- SECTION bit32_rshift
-- NEEDS bit
local bit32_rshift = bit.rshift

-- SECTION bit32_arshift
-- NEEDS bit
local bit32_arshift = bit.arshift

-- SECTION bit32_lrotate
-- NEEDS bit
local bit32_lrotate = bit.rol

-- SECTION bit32_rrotate
-- NEEDS bit
local bit32_rrotate = bit.ror

-- SECTION bit32_countlz
-- NEEDS bit32
local bit32_countlz = bit32_countlz_impl

-- SECTION bit32_countrz
-- NEEDS bit32
local bit32_countrz = bit32_countrz_impl

-- SECTION bit32_replace
-- NEEDS bit32_and
-- NEEDS bit32_lshift
-- NEEDS bit32_or
-- NEEDS bit32_xor
local function bit32_replace(src, repl, bits, off)
	local mask = bit32_lshift(2 ^ bits - 1, off)

	return bit32_or(bit32_and(src, bit32_xor(mask, 0xFFFFFFFF)), bit32_and(bit32_lshift(repl, off), mask))
end
