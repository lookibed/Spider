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
local function rt_round_up_f32(source)
	source = from_bits_f32(source)
	source = math.ceil(source)
	source = into_bits_f32(source)

	return source
end

-- SECTION round_down_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_round_down_f32(source)
	source = from_bits_f32(source)
	source = math.floor(source)
	source = into_bits_f32(source)

	return source
end

-- SECTION truncate_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_truncate_f32(source)
	source = from_bits_f32(source)
	source = math_modf(source)
	source = into_bits_f32(source)

	return source
end

-- SECTION nearest_f32
-- NEEDS from_bits_f32
-- NEEDS into_bits_f32
local function rt_nearest_f32(source)
	source = from_bits_f32(source)
	source = math.floor(source + 0.5)
	source = into_bits_f32(source)

	return source
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
local function rt_minimum_f32(lhs, rhs)
	if from_bits_f32(lhs) < from_bits_f32(rhs) then return lhs else return rhs end
end

-- SECTION maximum_f32
-- NEEDS from_bits_f32
local function rt_maximum_f32(lhs, rhs)
	if from_bits_f32(lhs) > from_bits_f32(rhs) then return lhs else return rhs end
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
local function rt_saturate_f32_to_s32(source)
	source = from_bits_f32(source)

	if source >= 2147483648.0 then
		return 0x7FFFFFFF
	elseif source < -2147483648.0 then
		return -2147483648
	elseif source >= 0 then
		return math.floor(source + 0.5)
	else
		return math.ceil(source - 0.5)
	end
end

-- SECTION truncate_f32_to_s32
-- NEEDS from_bits_f32
local function rt_truncate_f32_to_s32(source)
	source = from_bits_f32(source)

	if source >= 2147483648.0 or source < -2147483648.0 then
		error("integer overflow")
	elseif source >= 0 then
		return math.floor(source)
	else
		return math.ceil(source)
	end
end

-- SECTION saturate_f32_to_u32
-- NEEDS from_bits_f32
local function rt_saturate_f32_to_u32(source)
	source = from_bits_f32(source)

	if source >= 4294967296.0 then
		return 0xFFFFFFFF
	elseif source < 0 then
		return 0
	else
		return math.floor(source + 0.5)
	end
end

-- SECTION truncate_f32_to_u32
-- NEEDS from_bits_f32
local function rt_truncate_f32_to_u32(source)
	source = from_bits_f32(source)

	if source >= 4294967296.0 or source < 0 then
		error("integer overflow")
	else
		return math.floor(source)
	end
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
