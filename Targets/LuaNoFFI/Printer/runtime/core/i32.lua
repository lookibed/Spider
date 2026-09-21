-- SECTION count_ones_i32
-- NEEDS bit32_and
-- NEEDS bit32_rshift
local function rt_count_ones_i32(source)
	source = source - bit32_and(bit32_rshift(source, 1), 0x55555555)
	source = bit32_and(source, 0x33333333) + bit32_and(bit32_rshift(source, 2), 0x33333333)
	source = bit32_and(source + bit32_rshift(source, 4), 0x0F0F0F0F)
	source = source + bit32_rshift(source, 8)
	source = bit32_rshift(source, 0) + bit32_rshift(source, 16)
	source = bit32_and(source, 0x0000003F)

	return source
end

-- SECTION leading_zeroes_i32
-- NEEDS bit32_countlz
local rt_leading_zeroes_i32 = bit32_countlz

-- SECTION trailing_zeroes_i32
-- NEEDS bit32_countrz
local rt_trailing_zeroes_i32 = bit32_countrz

-- SECTION add_i32
-- NEEDS bit32_or
local function rt_add_i32(lhs, rhs)
	local result = bit32_or(lhs + rhs, 0)

	return result
end

-- SECTION subtract_i32
-- NEEDS bit32_or
local function rt_subtract_i32(lhs, rhs)
	local result = bit32_or(lhs - rhs, 0)

	return result
end

-- SECTION multiply_i32
-- NEEDS bit32_and
-- NEEDS bit32_lshift
-- NEEDS bit32_or
-- NEEDS bit32_rshift
local function rt_multiply_i32(lhs, rhs)
	local a16 = bit32_rshift(lhs, 16)
	local a00 = bit32_and(lhs, 0xFFFF)
	local b16 = bit32_rshift(rhs, 16)
	local b00 = bit32_and(rhs, 0xFFFF)

	local c00 = a00 * b00
	local c16 = a16 * b00 + a00 * b16

	local result = bit32_or(c00 + bit32_lshift(c16, 16), 0)

	return result
end

-- SECTION force_s32
-- NEEDS force_u32
local function force_s32(source)
	source = force_u32(source)

	if source >= 0x80000000 then
		return source - 0x100000000
	end

	return source
end

-- SECTION divide_s32
-- NEEDS bit32_or
-- NEEDS force_s32
-- NEEDS math_modf
local function rt_divide_s32(lhs, rhs)
	lhs = force_s32(lhs)
	rhs = force_s32(rhs)

	if rhs == 0 then
		error("integer divide by zero")
	elseif lhs == -0x80000000 and rhs == -1 then
		error("integer overflow")
	end

	local result = lhs / rhs

	result = math_modf(result)
	result = bit32_or(result, 0)

	return result
end

-- SECTION divide_u32
-- NEEDS bit32_or
-- NEEDS force_u32
-- NEEDS math_floor
local function rt_divide_u32(lhs, rhs)
	lhs = force_u32(lhs)
	rhs = force_u32(rhs)

	if rhs == 0 then
		error("integer divide by zero")
	end

	local result = math_floor(lhs / rhs)

	result = bit32_or(result, 0)

	return result
end

-- SECTION remainder_s32
-- NEEDS bit32_or
-- NEEDS force_s32
-- NEEDS math_fmod
local function rt_remainder_s32(lhs, rhs)
	lhs = force_s32(lhs)
	rhs = force_s32(rhs)

	if rhs == 0 then
		error("integer divide by zero")
	end

	local result = math_fmod(lhs, rhs)

	result = bit32_or(result, 0)

	return result
end

-- SECTION remainder_u32
-- NEEDS bit32_or
-- NEEDS force_u32
local function rt_remainder_u32(lhs, rhs)
	lhs = force_u32(lhs)
	rhs = force_u32(rhs)

	if rhs == 0 then
		error("integer divide by zero")
	end

	local result = lhs % rhs

	result = bit32_or(result, 0)

	return result
end

-- SECTION and_i32
-- NEEDS bit32_and
local rt_and_i32 = bit32_and

-- SECTION or_i32
-- NEEDS bit32_or
local rt_or_i32 = bit32_or

-- SECTION exclusive_or_i32
-- NEEDS bit32_xor
local rt_exclusive_or_i32 = bit32_xor

-- SECTION shift_left_i32
-- NEEDS bit32_and
-- NEEDS bit32_lshift
local function rt_shift_left_i32(lhs, rhs)
	rhs = bit32_and(rhs, 0x1F)

	local result = bit32_lshift(lhs, rhs)

	return result
end

-- SECTION shift_right_s32
-- NEEDS bit32_and
-- NEEDS bit32_arshift
local function rt_shift_right_s32(lhs, rhs)
	rhs = bit32_and(rhs, 0x1F)

	local result = bit32_arshift(lhs, rhs)

	return result
end

-- SECTION shift_right_u32
-- NEEDS bit32_and
-- NEEDS bit32_rshift
local function rt_shift_right_u32(lhs, rhs)
	rhs = bit32_and(rhs, 0x1F)

	local result = bit32_rshift(lhs, rhs)

	return result
end

-- SECTION rotate_left_i32
-- NEEDS bit32_and
-- NEEDS bit32_lrotate
local function rt_rotate_left_i32(lhs, rhs)
	rhs = bit32_and(rhs, 0x1F)

	local result = bit32_lrotate(lhs, rhs)

	return result
end

-- SECTION rotate_right_i32
-- NEEDS bit32_and
-- NEEDS bit32_rrotate
local function rt_rotate_right_i32(lhs, rhs)
	rhs = bit32_and(rhs, 0x1F)

	local result = bit32_rrotate(lhs, rhs)

	return result
end

-- SECTION equal_i32
-- NEEDS force_i32
local function rt_equal_i32(lhs, rhs)
	return force_i32(lhs) == force_i32(rhs)
end

-- SECTION not_equal_i32
-- NEEDS force_i32
local function rt_not_equal_i32(lhs, rhs)
	return force_i32(lhs) ~= force_i32(rhs)
end

-- SECTION less_than_s32
-- NEEDS force_s32
local function rt_less_than_s32(lhs, rhs)
	lhs = force_s32(lhs)
	rhs = force_s32(rhs)

	return lhs < rhs
end

-- SECTION less_than_u32
-- NEEDS force_u32
local function rt_less_than_u32(lhs, rhs)
	lhs = force_u32(lhs)
	rhs = force_u32(rhs)

	return lhs < rhs
end

-- SECTION greater_than_s32
-- NEEDS force_s32
local function rt_greater_than_s32(lhs, rhs)
	lhs = force_s32(lhs)
	rhs = force_s32(rhs)

	return lhs > rhs
end

-- SECTION greater_than_u32
-- NEEDS force_u32
local function rt_greater_than_u32(lhs, rhs)
	lhs = force_u32(lhs)
	rhs = force_u32(rhs)

	return lhs > rhs
end

-- SECTION less_than_equal_s32
-- NEEDS force_s32
local function rt_less_than_equal_s32(lhs, rhs)
	lhs = force_s32(lhs)
	rhs = force_s32(rhs)

	return lhs <= rhs
end

-- SECTION less_than_equal_u32
-- NEEDS force_u32
local function rt_less_than_equal_u32(lhs, rhs)
	lhs = force_u32(lhs)
	rhs = force_u32(rhs)

	return lhs <= rhs
end

-- SECTION greater_than_equal_s32
-- NEEDS force_s32
local function rt_greater_than_equal_s32(lhs, rhs)
	lhs = force_s32(lhs)
	rhs = force_s32(rhs)

	return lhs >= rhs
end

-- SECTION greater_than_equal_u32
-- NEEDS force_u32
local function rt_greater_than_equal_u32(lhs, rhs)
	lhs = force_u32(lhs)
	rhs = force_u32(rhs)

	return lhs >= rhs
end

-- SECTION widen_i32
-- NEEDS into_bits_i64
local function rt_widen_i32(source)
	source = into_bits_i64(source, 0)

	return source
end

-- SECTION extend_s8_to_i32
-- NEEDS bit32_and
-- NEEDS bit32_or
local function rt_extend_s8_to_i32(source)
	source = bit32_and(source, 0xFF)

	if source >= 0x80 then
		source = bit32_or(source - 0x100, 0)
	end

	return source
end

-- SECTION extend_s16_to_i32
-- NEEDS bit32_and
-- NEEDS bit32_or
local function rt_extend_s16_to_i32(source)
	source = bit32_and(source, 0xFFFF)

	if source >= 0x8000 then
		source = bit32_or(source - 0x10000, 0)
	end

	return source
end

-- SECTION convert_s32_to_f32
-- NEEDS force_s32
-- NEEDS into_bits_f32
local function rt_convert_s32_to_f32(source)
	return into_bits_f32(force_s32(source) + 0.0)
end

-- SECTION convert_u32_to_f32
-- NEEDS force_u32
-- NEEDS into_bits_f32
local function rt_convert_u32_to_f32(source)
	return into_bits_f32(force_u32(source) + 0.0)
end

-- SECTION convert_s32_to_f64
-- NEEDS force_s32
local function rt_convert_s32_to_f64(source)
	return force_s32(source) + 0.0
end

-- SECTION convert_u32_to_f64
-- NEEDS force_u32
local function rt_convert_u32_to_f64(source)
	return force_u32(source) + 0.0
end

-- SECTION transmute_i32_to_f32
local function rt_transmute_i32_to_f32(source)
	return source
end
