-- SECTION absolute_f32
-- NEEDS bit32_and
local function rt_absolute_f32(source)
	source = bit32_and(source, 0x7FFFFFFF)

	return source
end

-- SECTION negate_f32
-- NEEDS bit32_xor
local function rt_negate_f32(source)
	source = bit32_xor(source, 0x80000000)

	return source
end

-- SECTION square_root_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
-- NEEDS math_sqrt
local function rt_square_root_f32(source)
	source = from_bits_f32(source)
	source = math_sqrt(source)
	source = into_bits_f32(source)

	return source
end

-- SECTION round_up_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
-- NEEDS math_ceil
local function rt_round_up_f32(source)
	source = from_bits_f32(source)
	source = math_ceil(source)
	source = into_bits_f32(source)

	return source
end

-- SECTION round_down_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
-- NEEDS math_floor
local function rt_round_down_f32(source)
	source = from_bits_f32(source)
	source = math_floor(source)
	source = into_bits_f32(source)

	return source
end

-- SECTION truncate_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
-- NEEDS math_modf
local function rt_truncate_f32(source)
	source = from_bits_f32(source)
	source = math_modf(source)
	source = into_bits_f32(source)

	return source
end

-- SECTION nearest_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
-- NEEDS math_abs
-- NEEDS math_modf
local function rt_nearest_f32(source)
	local native = from_bits_f32(source)
	local rounded, remainder = math_modf(native)

	remainder = math_abs(remainder)

	if remainder > 0.5 or (remainder == 0.5 and rounded % 2 ~= 0) then
		if native < 0 then
			rounded = rounded - 1
		else
			rounded = rounded + 1
		end
	end

	return into_bits_f32(rounded)
end

-- SECTION add_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_add_f32(lhs, rhs)
	return into_bits_f32(from_bits_f32(lhs) + from_bits_f32(rhs))
end

-- SECTION subtract_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_subtract_f32(lhs, rhs)
	return into_bits_f32(from_bits_f32(lhs) - from_bits_f32(rhs))
end

-- SECTION multiply_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_multiply_f32(lhs, rhs)
	return into_bits_f32(from_bits_f32(lhs) * from_bits_f32(rhs))
end

-- SECTION divide_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_divide_f32(lhs, rhs)
	return into_bits_f32(from_bits_f32(lhs) / from_bits_f32(rhs))
end

-- SECTION minimum_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_minimum_f32(lhs, rhs)
	local lhs_native = from_bits_f32(lhs)
	local rhs_native = from_bits_f32(rhs)

	if lhs_native ~= lhs_native or rhs_native ~= rhs_native then
		return into_bits_f32(0 / 0)
	end

	if lhs_native == 0 and rhs_native == 0 then
		if 1 / lhs_native < 0 then
			return lhs
		end

		return rhs
	end

	if lhs_native < rhs_native then
		return lhs
	end

	return rhs
end

-- SECTION maximum_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_maximum_f32(lhs, rhs)
	local lhs_native = from_bits_f32(lhs)
	local rhs_native = from_bits_f32(rhs)

	if lhs_native ~= lhs_native or rhs_native ~= rhs_native then
		return into_bits_f32(0 / 0)
	end

	if lhs_native == 0 and rhs_native == 0 then
		if 1 / lhs_native > 0 then
			return lhs
		end

		return rhs
	end

	if lhs_native > rhs_native then
		return lhs
	end

	return rhs
end

-- SECTION copy_sign_f32
-- NEEDS bit32_and
-- NEEDS bit32_or
local function rt_copy_sign_f32(lhs, rhs)
	lhs = bit32_and(lhs, 0x7FFFFFFF)
	rhs = bit32_and(rhs, 0x80000000)

	return bit32_or(lhs, rhs)
end

-- SECTION equal_f32
-- NEEDS from_bits_f32
local function rt_equal_f32(lhs, rhs)
	return from_bits_f32(lhs) == from_bits_f32(rhs)
end

-- SECTION not_equal_f32
-- NEEDS from_bits_f32
local function rt_not_equal_f32(lhs, rhs)
	return from_bits_f32(lhs) ~= from_bits_f32(rhs)
end

-- SECTION less_than_f32
-- NEEDS from_bits_f32
local function rt_less_than_f32(lhs, rhs)
	return from_bits_f32(lhs) < from_bits_f32(rhs)
end

-- SECTION greater_than_f32
-- NEEDS from_bits_f32
local function rt_greater_than_f32(lhs, rhs)
	return from_bits_f32(lhs) > from_bits_f32(rhs)
end

-- SECTION less_than_equal_f32
-- NEEDS from_bits_f32
local function rt_less_than_equal_f32(lhs, rhs)
	return from_bits_f32(lhs) <= from_bits_f32(rhs)
end

-- SECTION greater_than_equal_f32
-- NEEDS from_bits_f32
local function rt_greater_than_equal_f32(lhs, rhs)
	return from_bits_f32(lhs) >= from_bits_f32(rhs)
end

-- SECTION widen_f32
-- NEEDS from_bits_f32
local function rt_widen_f32(source)
	return from_bits_f32(source)
end

-- SECTION saturate_f32_to_s32
-- NEEDS from_bits_f32
-- NEEDS saturate_f64_to_s32
local function rt_saturate_f32_to_s32(source)
	return rt_saturate_f64_to_s32(from_bits_f32(source))
end

-- SECTION truncate_f32_to_s32
-- NEEDS from_bits_f32
-- NEEDS truncate_f64_to_s32
local function rt_truncate_f32_to_s32(source)
	return rt_truncate_f64_to_s32(from_bits_f32(source))
end

-- SECTION saturate_f32_to_u32
-- NEEDS from_bits_f32
-- NEEDS saturate_f64_to_u32
local function rt_saturate_f32_to_u32(source)
	return rt_saturate_f64_to_u32(from_bits_f32(source))
end

-- SECTION truncate_f32_to_u32
-- NEEDS from_bits_f32
-- NEEDS truncate_f64_to_u32
local function rt_truncate_f32_to_u32(source)
	return rt_truncate_f64_to_u32(from_bits_f32(source))
end

-- SECTION saturate_f32_to_s64
-- NEEDS from_bits_f32
-- NEEDS saturate_f64_to_s64
local function rt_saturate_f32_to_s64(source)
	return rt_saturate_f64_to_s64(from_bits_f32(source))
end

-- SECTION truncate_f32_to_s64
-- NEEDS from_bits_f32
-- NEEDS truncate_f64_to_s64
local function rt_truncate_f32_to_s64(source)
	return rt_truncate_f64_to_s64(from_bits_f32(source))
end

-- SECTION saturate_f32_to_u64
-- NEEDS from_bits_f32
-- NEEDS saturate_f64_to_u64
local function rt_saturate_f32_to_u64(source)
	return rt_saturate_f64_to_u64(from_bits_f32(source))
end

-- SECTION truncate_f32_to_u64
-- NEEDS from_bits_f32
-- NEEDS truncate_f64_to_u64
local function rt_truncate_f32_to_u64(source)
	return rt_truncate_f64_to_u64(from_bits_f32(source))
end

-- SECTION transmute_f32_to_i32
local function rt_transmute_f32_to_i32(source)
	return source
end
