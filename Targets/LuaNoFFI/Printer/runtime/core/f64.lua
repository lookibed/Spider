-- SECTION absolute_f64
local function rt_absolute_f64(source)
	return math.abs(source)
end

-- SECTION negate_f64
local function rt_negate_f64(source)
	return -source
end

-- SECTION square_root_f64
-- NEEDS math_sqrt
local function rt_square_root_f64(source)
	return math_sqrt(source)
end

-- SECTION round_up_f64
-- NEEDS math_ceil
local function rt_round_up_f64(source)
	return math_ceil(source)
end

-- SECTION round_down_f64
-- NEEDS math_floor
local function rt_round_down_f64(source)
	return math_floor(source)
end

-- SECTION truncate_f64
-- NEEDS math_modf
local function rt_truncate_f64(source)
	return math_modf(source)
end

-- SECTION nearest_f64
-- NEEDS math_ceil
-- NEEDS math_floor
local function rt_nearest_f64(source)
	if source >= 0 then
		return math_floor(source + 0.5)
	end

	return math_ceil(source - 0.5)
end

-- SECTION add_f64
local function rt_add_f64(lhs, rhs)
	return lhs + rhs
end

-- SECTION subtract_f64
local function rt_subtract_f64(lhs, rhs)
	return lhs - rhs
end

-- SECTION multiply_f64
local function rt_multiply_f64(lhs, rhs)
	return lhs * rhs
end

-- SECTION divide_f64
local function rt_divide_f64(lhs, rhs)
	return lhs / rhs
end

-- SECTION minimum_f64
local function rt_minimum_f64(lhs, rhs)
	if lhs < rhs then
		return lhs
	end

	return rhs
end

-- SECTION maximum_f64
local function rt_maximum_f64(lhs, rhs)
	if lhs > rhs then
		return lhs
	end

	return rhs
end

-- SECTION copy_sign_f64
-- NEEDS math_abs
local function rt_copy_sign_f64(lhs, rhs)
	if rhs >= 0 then
		return math_abs(lhs)
	end

	return -math_abs(lhs)
end

-- SECTION equal_f64
local function rt_equal_f64(lhs, rhs)
	return lhs == rhs
end

-- SECTION not_equal_f64
local function rt_not_equal_f64(lhs, rhs)
	return lhs ~= rhs
end

-- SECTION less_than_f64
local function rt_less_than_f64(lhs, rhs)
	return lhs < rhs
end

-- SECTION greater_than_f64
local function rt_greater_than_f64(lhs, rhs)
	return lhs > rhs
end

-- SECTION less_than_equal_f64
local function rt_less_than_equal_f64(lhs, rhs)
	return lhs <= rhs
end

-- SECTION greater_than_equal_f64
local function rt_greater_than_equal_f64(lhs, rhs)
	return lhs >= rhs
end

-- SECTION narrow_f64
local function rt_narrow_f64(source)
	return source
end

-- SECTION saturate_f64_to_s32
local function rt_saturate_f64_to_s32(source)
	if source >= 2147483648.0 then
		return 0x7FFFFFFF
	end

	if source < -2147483648.0 then
		return -2147483648
	end

	if source >= 0 then
		return math.floor(source + 0.5)
	end

	return math.ceil(source - 0.5)
end

-- SECTION truncate_f64_to_s32
local function rt_truncate_f64_to_s32(source)
	if source >= 2147483648.0 or source < -2147483648.0 then
		error("integer overflow")
	end

	if source >= 0 then
		return math.floor(source)
	end

	return math.ceil(source)
end

-- SECTION saturate_f64_to_u32
local function rt_saturate_f64_to_u32(source)
	if source >= 4294967296.0 then
		return 0xFFFFFFFF
	end

	if source < 0 then
		return 0
	end

	return math.floor(source + 0.5)
end

-- SECTION truncate_f64_to_u32
local function rt_truncate_f64_to_u32(source)
	if source >= 4294967296.0 or source < 0 then
		error("integer overflow")
	end

	return math.floor(source)
end

-- SECTION saturate_f64_to_s64
-- NEEDS into_bits_i64
local function rt_saturate_f64_to_s64(source)
	if source ~= source then
		return into_bits_i64(0, 0)
	end

	if source >= 9223372036854775808.0 then
		return into_bits_i64(0xFFFFFFFF, 0x7FFFFFFF)
	end

	if source <= -9223372036854775808.0 then
		return into_bits_i64(0, 0x80000000)
	end

	if source < 0 then
		source = math.ceil(source)
		local positive = -source
		local hi = math.floor(positive / 4294967296.0)
		local lo = positive - hi * 4294967296.0

		return rt_subtract_i64(into_bits_i64(0, 0), into_bits_i64(lo, hi))
	end

	source = math.floor(source)

	return into_bits_i64(source % 4294967296.0, math.floor(source / 4294967296.0))
end

-- SECTION truncate_f64_to_s64
-- NEEDS saturate_f64_to_s64
local function rt_truncate_f64_to_s64(source)
	if source >= 9223372036854775808.0 or source < -9223372036854775808.0 then
		error("integer overflow")
	end

	return rt_saturate_f64_to_s64(source)
end

-- SECTION saturate_f64_to_u64
-- NEEDS into_bits_i64
local function rt_saturate_f64_to_u64(source)
	if source ~= source or source <= 0 then
		return into_bits_i64(0, 0)
	end

	if source >= 18446744073709551616.0 then
		return into_bits_i64(0xFFFFFFFF, 0xFFFFFFFF)
	end

	source = math.floor(source)

	return into_bits_i64(source % 4294967296.0, math.floor(source / 4294967296.0))
end

-- SECTION truncate_f64_to_u64
-- NEEDS saturate_f64_to_u64
local function rt_truncate_f64_to_u64(source)
	if source >= 18446744073709551616.0 or source < 0 then
		error("integer overflow")
	end

	return rt_saturate_f64_to_u64(source)
end

-- SECTION transmute_f64_to_i64
-- NEEDS into_bits_f64
-- NEEDS into_bits_i64
local function rt_transmute_f64_to_i64(source)
	local lo, hi = into_bits_f64(source)

	return into_bits_i64(lo, hi)
end
