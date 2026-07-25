-- SECTION count_ones_i64
-- NEEDS count_ones_i32
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_count_ones_i64(source)
	local lo, hi = from_bits_i64(source)

	return into_bits_i64(rt_count_ones_i32(lo) + rt_count_ones_i32(hi), 0)
end

-- SECTION leading_zeroes_i64
-- NEEDS into_bits_i64
-- NEEDS raw_leading_zeroes_i64
local function rt_leading_zeroes_i64(source)
	return into_bits_i64(raw_leading_zeroes_i64(source), 0)
end

-- SECTION trailing_zeroes_i64
-- NEEDS into_bits_i64
-- NEEDS raw_trailing_zeroes_i64
local function rt_trailing_zeroes_i64(source)
	return into_bits_i64(raw_trailing_zeroes_i64(source), 0)
end

-- SECTION raw_leading_zeroes_i64
-- NEEDS from_bits_i64
local function raw_leading_zeroes_i64(source)
	local lo, hi = from_bits_i64(source)

	if hi == 0 then
		if lo == 0 then
			return 64
		end

		return rt_leading_zeroes_i32(lo) + 32
	end

	return rt_leading_zeroes_i32(hi)
end

-- SECTION raw_trailing_zeroes_i64
-- NEEDS from_bits_i64
local function raw_trailing_zeroes_i64(source)
	local lo, hi = from_bits_i64(source)

	if lo == 0 then
		if hi == 0 then
			return 64
		end

		return rt_trailing_zeroes_i32(hi) + 32
	end

	return rt_trailing_zeroes_i32(lo)
end

-- SECTION add_i64
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_add_i64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	local lo = lhs_lo + rhs_lo
	local hi = lhs_hi + rhs_hi

	if lo >= 0x100000000 then
		lo = lo - 0x100000000
		hi = hi + 1
	end

	return into_bits_i64(lo, hi)
end

-- SECTION subtract_i64
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_subtract_i64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	local lo = lhs_lo - rhs_lo
	local hi = lhs_hi - rhs_hi

	if lo < 0 then
		lo = lo + 0x100000000
		hi = hi - 1
	end

	return into_bits_i64(lo, hi)
end

-- SECTION multiply_i64
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_multiply_i64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	local a0 = lhs_lo % 0x10000
	local a1 = math.floor(lhs_lo / 0x10000)
	local a2 = lhs_hi % 0x10000
	local a3 = math.floor(lhs_hi / 0x10000)
	local b0 = rhs_lo % 0x10000
	local b1 = math.floor(rhs_lo / 0x10000)
	local b2 = rhs_hi % 0x10000
	local b3 = math.floor(rhs_hi / 0x10000)

	local carry = 0

	local digit0 = a0 * b0
	local c0 = digit0 % 0x10000
	carry = math.floor(digit0 / 0x10000)

	local digit1 = carry + a0 * b1 + a1 * b0
	local c1 = digit1 % 0x10000
	carry = math.floor(digit1 / 0x10000)

	local digit2 = carry + a0 * b2 + a1 * b1 + a2 * b0
	local c2 = digit2 % 0x10000
	carry = math.floor(digit2 / 0x10000)

	local digit3 = carry + a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0
	local c3 = digit3 % 0x10000

	local lo = c0 + c1 * 0x10000
	local hi = c2 + c3 * 0x10000

	return into_bits_i64(lo, hi)
end

-- SECTION raw_compare_u64
local function raw_compare_u64(lhs_lo, lhs_hi, rhs_lo, rhs_hi)
	if lhs_hi ~= rhs_hi then
		if lhs_hi < rhs_hi then
			return -1
		end

		return 1
	end

	if lhs_lo ~= rhs_lo then
		if lhs_lo < rhs_lo then
			return -1
		end

		return 1
	end

	return 0
end

-- SECTION raw_subtract_u64
local function raw_subtract_u64(lhs_lo, lhs_hi, rhs_lo, rhs_hi)
	local lo = lhs_lo - rhs_lo
	local hi = lhs_hi - rhs_hi

	if lo < 0 then
		lo = lo + 0x100000000
		hi = hi - 1
	end

	return lo, hi
end

-- SECTION raw_shift_left_one_u64
-- NEEDS bit32_lshift
-- NEEDS bit32_or
-- NEEDS bit32_rshift
-- NEEDS force_u32
local function raw_shift_left_one_u64(lo, hi)
	local new_lo = force_u32(bit32_lshift(lo, 1))
	local new_hi = force_u32(bit32_or(bit32_lshift(hi, 1), bit32_rshift(lo, 31)))

	return new_lo, new_hi
end

-- SECTION raw_unsigned_divide_u64
-- NEEDS bit32_and
-- NEEDS bit32_rshift
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
-- NEEDS raw_compare_u64
-- NEEDS raw_shift_left_one_u64
-- NEEDS raw_subtract_u64
local function raw_unsigned_divide_u64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)
	local quotient_lo = 0
	local quotient_hi = 0
	local remainder_lo = 0
	local remainder_hi = 0

	for bit = 63, 0, -1 do
		remainder_lo, remainder_hi = raw_shift_left_one_u64(remainder_lo, remainder_hi)

		local incoming

		if bit >= 32 then
			incoming = bit32_and(bit32_rshift(lhs_hi, bit - 32), 1)
		else
			incoming = bit32_and(bit32_rshift(lhs_lo, bit), 1)
		end

		remainder_lo = remainder_lo + incoming

		if raw_compare_u64(remainder_lo, remainder_hi, rhs_lo, rhs_hi) >= 0 then
			remainder_lo, remainder_hi = raw_subtract_u64(remainder_lo, remainder_hi, rhs_lo, rhs_hi)

			if bit >= 32 then
				quotient_hi = quotient_hi + 2 ^ (bit - 32)
			else
				quotient_lo = quotient_lo + 2 ^ bit
			end
		end
	end

	return into_bits_i64(quotient_lo, quotient_hi)
end

-- SECTION divide_s64
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
-- NEEDS raw_unsigned_divide_u64
-- NEEDS subtract_i64
local function rt_divide_s64(lhs, rhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	if rhs_lo == 0 and rhs_hi == 0 then
		error("integer divide by zero")
	end

	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local lhs_negative = lhs_hi >= 0x80000000
	local rhs_negative = rhs_hi >= 0x80000000

	if lhs_lo == 0 and lhs_hi == 0x80000000 and rhs_lo == 0xFFFFFFFF and rhs_hi == 0xFFFFFFFF then
		error("integer overflow")
	end

	if lhs_negative then
		lhs = rt_subtract_i64(into_bits_i64(0, 0), lhs)
	end

	if rhs_negative then
		rhs = rt_subtract_i64(into_bits_i64(0, 0), rhs)
	end

	local packed = raw_unsigned_divide_u64(lhs, rhs)

	if lhs_negative ~= rhs_negative then
		return rt_subtract_i64(into_bits_i64(0, 0), packed)
	end

	return packed
end

-- SECTION divide_u64
-- NEEDS from_bits_i64
-- NEEDS raw_unsigned_divide_u64
local function rt_divide_u64(lhs, rhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	if rhs_lo == 0 and rhs_hi == 0 then
		error("integer divide by zero")
	end

	return raw_unsigned_divide_u64(lhs, rhs)
end

-- SECTION remainder_s64
-- NEEDS divide_s64
-- NEEDS multiply_i64
-- NEEDS subtract_i64
local function rt_remainder_s64(lhs, rhs)
	return rt_subtract_i64(lhs, rt_multiply_i64(rt_divide_s64(lhs, rhs), rhs))
end

-- SECTION remainder_u64
-- NEEDS divide_u64
-- NEEDS multiply_i64
-- NEEDS subtract_i64
local function rt_remainder_u64(lhs, rhs)
	return rt_subtract_i64(lhs, rt_multiply_i64(rt_divide_u64(lhs, rhs), rhs))
end

-- SECTION and_i64
-- NEEDS bit32_and
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_and_i64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	return into_bits_i64(bit32_and(lhs_lo, rhs_lo), bit32_and(lhs_hi, rhs_hi))
end

-- SECTION or_i64
-- NEEDS bit32_or
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_or_i64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	return into_bits_i64(bit32_or(lhs_lo, rhs_lo), bit32_or(lhs_hi, rhs_hi))
end

-- SECTION exclusive_or_i64
-- NEEDS bit32_xor
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_exclusive_or_i64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	return into_bits_i64(bit32_xor(lhs_lo, rhs_lo), bit32_xor(lhs_hi, rhs_hi))
end

-- SECTION shift_left_i64
-- NEEDS bit32_and
-- NEEDS bit32_lshift
-- NEEDS bit32_or
-- NEEDS bit32_rshift
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_shift_left_i64(lhs, rhs)
	if type(rhs) == "table" then
		rhs, _ = from_bits_i64(rhs)
	end

	rhs = bit32_and(rhs, 0x3F)

	local lo, hi = from_bits_i64(lhs)

	if rhs == 0 then
		return into_bits_i64(lo, hi)
	end

	if rhs < 32 then
		local carry = bit32_rshift(lo, 32 - rhs)

		return into_bits_i64(bit32_lshift(lo, rhs), bit32_or(bit32_lshift(hi, rhs), carry))
	end

	if rhs == 32 then
		return into_bits_i64(0, lo)
	end

	return into_bits_i64(0, bit32_lshift(lo, rhs - 32))
end

-- SECTION shift_right_s64
-- NEEDS bit32_and
-- NEEDS bit32_arshift
-- NEEDS bit32_lshift
-- NEEDS bit32_or
-- NEEDS bit32_rshift
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_shift_right_s64(lhs, rhs)
	if type(rhs) == "table" then
		rhs, _ = from_bits_i64(rhs)
	end

	rhs = bit32_and(rhs, 0x3F)

	local lo, hi = from_bits_i64(lhs)
	local sign_fill = hi >= 0x80000000 and 0xFFFFFFFF or 0

	if rhs == 0 then
		return into_bits_i64(lo, hi)
	end

	if rhs < 32 then
		local carry = bit32_lshift(hi, 32 - rhs)

		return into_bits_i64(bit32_or(bit32_rshift(lo, rhs), carry), bit32_arshift(hi, rhs))
	end

	if rhs == 32 then
		return into_bits_i64(hi, sign_fill)
	end

	return into_bits_i64(bit32_arshift(hi, rhs - 32), sign_fill)
end

-- SECTION shift_right_u64
-- NEEDS bit32_and
-- NEEDS bit32_lshift
-- NEEDS bit32_or
-- NEEDS bit32_rshift
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
local function rt_shift_right_u64(lhs, rhs)
	if type(rhs) == "table" then
		rhs, _ = from_bits_i64(rhs)
	end

	rhs = bit32_and(rhs, 0x3F)

	local lo, hi = from_bits_i64(lhs)

	if rhs == 0 then
		return into_bits_i64(lo, hi)
	end

	if rhs < 32 then
		local carry = bit32_lshift(hi, 32 - rhs)

		return into_bits_i64(bit32_or(bit32_rshift(lo, rhs), carry), bit32_rshift(hi, rhs))
	end

	if rhs == 32 then
		return into_bits_i64(hi, 0)
	end

	return into_bits_i64(bit32_rshift(hi, rhs - 32), 0)
end

-- SECTION rotate_left_i64
-- NEEDS bit32_and
-- NEEDS or_i64
-- NEEDS shift_left_i64
-- NEEDS shift_right_u64
local function rt_rotate_left_i64(lhs, rhs)
	if type(rhs) == "table" then
		rhs, _ = from_bits_i64(rhs)
	end

	rhs = bit32_and(rhs, 0x3F)

	if rhs == 0 then
		return lhs
	end

	return rt_or_i64(rt_shift_left_i64(lhs, rhs), rt_shift_right_u64(lhs, 64 - rhs))
end

-- SECTION rotate_right_i64
-- NEEDS bit32_and
-- NEEDS or_i64
-- NEEDS shift_left_i64
-- NEEDS shift_right_u64
local function rt_rotate_right_i64(lhs, rhs)
	if type(rhs) == "table" then
		rhs, _ = from_bits_i64(rhs)
	end

	rhs = bit32_and(rhs, 0x3F)

	if rhs == 0 then
		return lhs
	end

	return rt_or_i64(rt_shift_right_u64(lhs, rhs), rt_shift_left_i64(lhs, 64 - rhs))
end

-- SECTION equal_i64
-- NEEDS from_bits_i64
local function rt_equal_i64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	return lhs_lo == rhs_lo and lhs_hi == rhs_hi
end

-- SECTION not_equal_i64
-- NEEDS equal_i64
local function rt_not_equal_i64(lhs, rhs)
	return not rt_equal_i64(lhs, rhs)
end

-- SECTION less_than_s64
-- NEEDS from_bits_i64
local function rt_less_than_s64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)
	local lhs_negative = lhs_hi >= 0x80000000
	local rhs_negative = rhs_hi >= 0x80000000

	if lhs_negative ~= rhs_negative then
		return lhs_negative
	end

	if lhs_hi ~= rhs_hi then
		return lhs_hi < rhs_hi
	end

	return lhs_lo < rhs_lo
end

-- SECTION less_than_u64
-- NEEDS from_bits_i64
local function rt_less_than_u64(lhs, rhs)
	local lhs_lo, lhs_hi = from_bits_i64(lhs)
	local rhs_lo, rhs_hi = from_bits_i64(rhs)

	if lhs_hi ~= rhs_hi then
		return lhs_hi < rhs_hi
	end

	return lhs_lo < rhs_lo
end

-- SECTION greater_than_s64
-- NEEDS less_than_s64
local function rt_greater_than_s64(lhs, rhs)
	return rt_less_than_s64(rhs, lhs)
end

-- SECTION greater_than_u64
-- NEEDS less_than_u64
local function rt_greater_than_u64(lhs, rhs)
	return rt_less_than_u64(rhs, lhs)
end

-- SECTION less_than_equal_s64
-- NEEDS greater_than_s64
local function rt_less_than_equal_s64(lhs, rhs)
	return not rt_greater_than_s64(lhs, rhs)
end

-- SECTION less_than_equal_u64
-- NEEDS greater_than_u64
local function rt_less_than_equal_u64(lhs, rhs)
	return not rt_greater_than_u64(lhs, rhs)
end

-- SECTION greater_than_equal_s64
-- NEEDS less_than_s64
local function rt_greater_than_equal_s64(lhs, rhs)
	return not rt_less_than_s64(lhs, rhs)
end

-- SECTION greater_than_equal_u64
-- NEEDS less_than_u64
local function rt_greater_than_equal_u64(lhs, rhs)
	return not rt_less_than_u64(lhs, rhs)
end

-- SECTION narrow_i64
-- NEEDS from_bits_i64
local function rt_narrow_i64(source)
	local lo, _ = from_bits_i64(source)

	return lo
end

-- SECTION extend_s8_to_i64
-- NEEDS into_bits_i64
local function rt_extend_s8_to_i64(source)
	if source >= 0x80 then
		source = source - 0x100
	end

	if source < 0 then
		return into_bits_i64(source, 0xFFFFFFFF)
	end

	return into_bits_i64(source, 0)
end

-- SECTION extend_s16_to_i64
-- NEEDS into_bits_i64
local function rt_extend_s16_to_i64(source)
	if source >= 0x8000 then
		source = source - 0x10000
	end

	if source < 0 then
		return into_bits_i64(source, 0xFFFFFFFF)
	end

	return into_bits_i64(source, 0)
end

-- SECTION extend_s32_to_i64
-- NEEDS into_bits_i64
local function rt_extend_s32_to_i64(source)
	if type(source) == "table" then
		source = source[1]
	end

	if source >= 0x80000000 then
		return into_bits_i64(source, 0xFFFFFFFF)
	end

	return into_bits_i64(source, 0)
end

-- SECTION convert_s64_to_f32
-- NEEDS convert_s64_to_f64
-- NEEDS into_bits_f32
local function rt_convert_s64_to_f32(source)
	return into_bits_f32(rt_convert_s64_to_f64(source))
end

-- SECTION convert_u64_to_f32
-- NEEDS convert_u64_to_f64
-- NEEDS into_bits_f32
local function rt_convert_u64_to_f32(source)
	return into_bits_f32(rt_convert_u64_to_f64(source))
end

-- SECTION convert_s64_to_f64
-- NEEDS from_bits_i64
-- NEEDS into_bits_i64
-- NEEDS subtract_i64
local function rt_convert_s64_to_f64(source)
	local lo, hi = from_bits_i64(source)

	if hi >= 0x80000000 then
		source = rt_subtract_i64(into_bits_i64(0, 0), source)
		lo, hi = from_bits_i64(source)

		return -(hi * 4294967296.0 + lo)
	end

	return hi * 4294967296.0 + lo
end

-- SECTION convert_u64_to_f64
-- NEEDS from_bits_i64
local function rt_convert_u64_to_f64(source)
	local lo, hi = from_bits_i64(source)

	return hi * 4294967296.0 + lo
end

-- SECTION transmute_i64_to_f64
-- NEEDS from_bits_f64
-- NEEDS from_bits_i64
local function rt_transmute_i64_to_f64(source)
	local lo, hi = from_bits_i64(source)

	return from_bits_f64(lo, hi)
end
