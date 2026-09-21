-- SECTION absolute_f64
-- NEEDS math_abs
local function rt_absolute_f64(source)
	return math_abs(source)
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
	local result = math_ceil(source)

	return result
end

-- SECTION round_down_f64
-- NEEDS math_floor
local function rt_round_down_f64(source)
	local result = math_floor(source)

	return result
end

-- SECTION truncate_f64
-- NEEDS math_modf
local function rt_truncate_f64(source)
	local result = math_modf(source)

	return result
end

-- SECTION nearest_f64
-- NEEDS math_abs
-- NEEDS math_modf
local function rt_nearest_f64(source)
	local rounded, remainder = math_modf(source)

	remainder = math_abs(remainder)

	if remainder > 0.5 or (remainder == 0.5 and rounded % 2 ~= 0) then
		if source < 0 then
			rounded = rounded - 1
		else
			rounded = rounded + 1
		end
	end

	return rounded
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
	if lhs ~= lhs or rhs ~= rhs then
		return 0 / 0
	end

	if lhs == 0 and rhs == 0 then
		if 1 / lhs < 0 then
			return lhs
		end

		return rhs
	end

	if lhs < rhs then
		return lhs
	end

	return rhs
end

-- SECTION maximum_f64
local function rt_maximum_f64(lhs, rhs)
	if lhs ~= lhs or rhs ~= rhs then
		return 0 / 0
	end

	if lhs == 0 and rhs == 0 then
		if 1 / lhs > 0 then
			return lhs
		end

		return rhs
	end

	if lhs > rhs then
		return lhs
	end

	return rhs
end

-- SECTION copy_sign_f64
-- NEEDS math_abs
local function rt_copy_sign_f64(lhs, rhs)
	if rhs < 0 or (rhs == 0 and 1 / rhs < 0) then
		return -math_abs(lhs)
	end

	return math_abs(lhs)
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
-- NEEDS into_bits_f32
local function rt_narrow_f64(source)
	return into_bits_f32(source)
end

-- SECTION saturate_f64_to_s32
-- NEEDS force_i32
-- NEEDS math_modf
local function rt_saturate_f64_to_s32(source)
	if source ~= source then
		return 0
	end

	if source >= 2147483648.0 then
		return force_i32(0x7FFFFFFF)
	end

	if source <= -2147483648.0 then
		return force_i32(-2147483648)
	end

	source = math_modf(source)

	return force_i32(source)
end

-- SECTION truncate_f64_to_s32
-- NEEDS force_i32
-- NEEDS math_modf
local function rt_truncate_f64_to_s32(source)
	source = math_modf(source)

	if source >= 2147483648.0 or source < -2147483648.0 then
		error("integer overflow")
	elseif source ~= source then
		error("invalid conversion to integer")
	end

	return force_i32(source)
end

-- SECTION saturate_f64_to_u32
-- NEEDS force_i32
-- NEEDS math_modf
local function rt_saturate_f64_to_u32(source)
	if source ~= source then
		return 0
	end

	if source >= 4294967296.0 then
		return force_i32(0xFFFFFFFF)
	end

	if source <= 0 then
		return 0
	end

	source = math_modf(source)

	return force_i32(source)
end

-- SECTION truncate_f64_to_u32
-- NEEDS force_i32
-- NEEDS math_modf
local function rt_truncate_f64_to_u32(source)
	source = math_modf(source)

	if source >= 4294967296.0 or source < 0 then
		error("integer overflow")
	elseif source ~= source then
		error("invalid conversion to integer")
	end

	return force_i32(source)
end

-- SECTION saturate_f64_to_s64
-- NEEDS into_bits_i64
-- NEEDS math_floor
-- NEEDS math_modf
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

	source = math_modf(source)

	local negative = source < 0

	if negative then
		source = -source
	end

	local hi = math_floor(source / 4294967296.0)
	local lo = source - hi * 4294967296.0

	if negative then
		lo = -lo
		hi = -hi

		if lo ~= 0 then
			lo = lo + 4294967296.0
			hi = hi - 1
		end
	end

	return into_bits_i64(lo, hi)
end

-- SECTION truncate_f64_to_s64
-- NEEDS math_modf
-- NEEDS saturate_f64_to_s64
local function rt_truncate_f64_to_s64(source)
	source = math_modf(source)

	if source >= 9223372036854775808.0 or source < -9223372036854775808.0 then
		error("integer overflow")
	elseif source ~= source then
		error("invalid conversion to integer")
	end

	return rt_saturate_f64_to_s64(source)
end

-- SECTION saturate_f64_to_u64
-- NEEDS into_bits_i64
-- NEEDS math_floor
-- NEEDS math_modf
local function rt_saturate_f64_to_u64(source)
	if source ~= source or source <= 0 then
		return into_bits_i64(0, 0)
	end

	if source >= 18446744073709551616.0 then
		return into_bits_i64(0xFFFFFFFF, 0xFFFFFFFF)
	end

	source = math_modf(source)

	local hi = math_floor(source / 4294967296.0)
	local lo = source - hi * 4294967296.0

	return into_bits_i64(lo, hi)
end

-- SECTION truncate_f64_to_u64
-- NEEDS math_modf
-- NEEDS saturate_f64_to_u64
local function rt_truncate_f64_to_u64(source)
	source = math_modf(source)

	if source >= 18446744073709551616.0 or source < 0 then
		error("integer overflow")
	elseif source ~= source then
		error("invalid conversion to integer")
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
