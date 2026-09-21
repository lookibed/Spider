-- SECTION count_ones_i64
-- NEEDS bit_and
-- NEEDS bit_rshift
local function rt_count_ones_i64(source)
	source = source - bit_and(bit_rshift(source, 1LL), 0x5555555555555555LL)
	source = bit_and(source, 0x3333333333333333LL) + bit_and(bit_rshift(source, 2LL), 0x3333333333333333LL)
	source = bit_and(source + bit_rshift(source, 4LL), 0x0F0F0F0F0F0F0F0FLL)
	source = source + bit_rshift(source, 8LL)
	source = source + bit_rshift(source, 16LL)
	source = source + bit_rshift(source, 32LL)
	source = bit_and(source, 0x000000000000007FLL)

	return source
end

-- SECTION leading_zeroes_i64
-- NEEDS bit_lshift
-- NEEDS bit_rshift
local function rt_leading_zeroes_i64(source)
	if source == 0LL then
		return 64LL
	end

	local result = 0LL

	if bit_rshift(source, 32LL) == 0LL then
		source = bit_lshift(source, 32LL)
		result = result + 32LL
	end

	if bit_rshift(source, 48LL) == 0LL then
		source = bit_lshift(source, 16LL)
		result = result + 16LL
	end

	if bit_rshift(source, 56LL) == 0LL then
		source = bit_lshift(source, 8LL)
		result = result + 8LL
	end

	if bit_rshift(source, 60LL) == 0LL then
		source = bit_lshift(source, 4LL)
		result = result + 4LL
	end

	if bit_rshift(source, 62LL) == 0LL then
		source = bit_lshift(source, 2LL)
		result = result + 2LL
	end

	if bit_rshift(source, 63LL) == 0LL then
		result = result + 1LL
	end

	return result
end

-- SECTION trailing_zeroes_i64
-- NEEDS bit_lshift
-- NEEDS bit_rshift
local function rt_trailing_zeroes_i64(source)
	if source == 0LL then
		return 64LL
	end

	local result = 0LL

	if bit_lshift(source, 32LL) == 0LL then
		source = bit_rshift(source, 32LL)
		result = result + 32LL
	end

	if bit_lshift(source, 48LL) == 0LL then
		source = bit_rshift(source, 16LL)
		result = result + 16LL
	end

	if bit_lshift(source, 56LL) == 0LL then
		source = bit_rshift(source, 8LL)
		result = result + 8LL
	end

	if bit_lshift(source, 60LL) == 0LL then
		source = bit_rshift(source, 4LL)
		result = result + 4LL
	end

	if bit_lshift(source, 62LL) == 0LL then
		source = bit_rshift(source, 2LL)
		result = result + 2LL
	end

	if bit_lshift(source, 63LL) == 0LL then
		result = result + 1LL
	end

	return result
end

-- SECTION add_i64
local function rt_add_i64(lhs, rhs)
	return lhs + rhs
end

-- SECTION subtract_i64
local function rt_subtract_i64(lhs, rhs)
	return lhs - rhs
end

-- SECTION multiply_i64
local function rt_multiply_i64(lhs, rhs)
	return lhs * rhs
end

-- SECTION divide_s64
local function rt_divide_s64(lhs, rhs)
	if lhs == 0x8000000000000000LL and rhs == 0xFFFFFFFFFFFFFFFFLL then
		error("integer overflow")
	elseif rhs == 0LL then
		error("integer divide by zero")
	end

	return lhs / rhs
end

-- SECTION divide_u64
-- NEEDS ffi_cast
-- NEEDS i64_type
-- NEEDS u64_type
local function rt_divide_u64(lhs, rhs)
	if rhs == 0 then
		error("integer divide by zero")
	end

	lhs = ffi_cast(u64_type, lhs)
	rhs = ffi_cast(u64_type, rhs)

	local result = lhs / rhs

	result = ffi_cast(i64_type, result)

	return result
end

-- SECTION remainder_s64
local function rt_remainder_s64(lhs, rhs)
	if rhs == 0 then
		error("integer divide by zero")
	end

	return lhs % rhs
end

-- SECTION remainder_u64
-- NEEDS ffi_cast
-- NEEDS i64_type
-- NEEDS u64_type
local function rt_remainder_u64(lhs, rhs)
	if rhs == 0 then
		error("integer divide by zero")
	end

	lhs = ffi_cast(u64_type, lhs)
	rhs = ffi_cast(u64_type, rhs)

	local result = lhs % rhs

	result = ffi_cast(i64_type, result)

	return result
end

-- SECTION and_i64
-- NEEDS bit
local rt_and_i64 = bit.band

-- SECTION or_i64
-- NEEDS bit
local rt_or_i64 = bit.bor

-- SECTION exclusive_or_i64
-- NEEDS bit
local rt_exclusive_or_i64 = bit.bxor

-- SECTION shift_left_i64
-- NEEDS bit_and
-- NEEDS bit_lshift
local function rt_shift_left_i64(lhs, rhs)
	rhs = bit_and(rhs, 0x3F)

	local result = bit_lshift(lhs, rhs)

	return result
end

-- SECTION shift_right_s64
-- NEEDS bit_and
-- NEEDS bit_arshift
local function rt_shift_right_s64(lhs, rhs)
	rhs = bit_and(rhs, 0x3F)

	local result = bit_arshift(lhs, rhs)

	return result
end

-- SECTION shift_right_u64
-- NEEDS bit_and
-- NEEDS bit_rshift
local function rt_shift_right_u64(lhs, rhs)
	rhs = bit_and(rhs, 0x3F)

	local result = bit_rshift(lhs, rhs)

	return result
end

-- SECTION rotate_left_i64
-- NEEDS bit_lrotate
local function rt_rotate_left_i64(lhs, rhs)
	local result = bit_lrotate(lhs, rhs)

	return result
end

-- SECTION rotate_right_i64
-- NEEDS bit_rrotate
local function rt_rotate_right_i64(lhs, rhs)
	local result = bit_rrotate(lhs, rhs)

	return result
end

-- SECTION equal_i64
local function rt_equal_i64(lhs, rhs)
	return lhs == rhs
end

-- SECTION not_equal_i64
local function rt_not_equal_i64(lhs, rhs)
	return lhs ~= rhs
end

-- SECTION less_than_s64
local function rt_less_than_s64(lhs, rhs)
	return lhs < rhs
end

-- SECTION less_than_u64
-- NEEDS ffi_cast
-- NEEDS u64_type
local function rt_less_than_u64(lhs, rhs)
	lhs = ffi_cast(u64_type, lhs)
	rhs = ffi_cast(u64_type, rhs)

	return lhs < rhs
end

-- SECTION greater_than_s64
local function rt_greater_than_s64(lhs, rhs)
	return lhs > rhs
end

-- SECTION greater_than_u64
-- NEEDS ffi_cast
-- NEEDS u64_type
local function rt_greater_than_u64(lhs, rhs)
	lhs = ffi_cast(u64_type, lhs)
	rhs = ffi_cast(u64_type, rhs)

	return lhs > rhs
end

-- SECTION less_than_equal_s64
local function rt_less_than_equal_s64(lhs, rhs)
	return lhs <= rhs
end

-- SECTION less_than_equal_u64
-- NEEDS ffi_cast
-- NEEDS u64_type
local function rt_less_than_equal_u64(lhs, rhs)
	lhs = ffi_cast(u64_type, lhs)
	rhs = ffi_cast(u64_type, rhs)

	return lhs <= rhs
end

-- SECTION greater_than_equal_s64
local function rt_greater_than_equal_s64(lhs, rhs)
	return lhs >= rhs
end

-- SECTION greater_than_equal_u64
-- NEEDS ffi_cast
-- NEEDS u64_type
local function rt_greater_than_equal_u64(lhs, rhs)
	lhs = ffi_cast(u64_type, lhs)
	rhs = ffi_cast(u64_type, rhs)

	return lhs >= rhs
end

-- SECTION narrow_i64
-- NEEDS bit
local rt_narrow_i64 = bit.tobit

-- SECTION extend_s8_to_i64
-- NEEDS bit_and
local function rt_extend_s8_to_i64(source)
	source = bit_and(source, 0xFFLL)

	if source >= 0x80LL then
		source = source - 0x100LL
	end

	return source
end

-- SECTION extend_s16_to_i64
-- NEEDS bit_and
local function rt_extend_s16_to_i64(source)
	source = bit_and(source, 0xFFFFLL)

	if source >= 0x8000LL then
		source = source - 0x10000LL
	end

	return source
end

-- SECTION extend_s32_to_i64
-- NEEDS bit_and
local function rt_extend_s32_to_i64(source)
	source = bit_and(source, 0xFFFFFFFFLL)

	if source >= 0x80000000LL then
		source = source - 0x100000000LL
	end

	return source
end

-- SECTION odd_rounded_u64
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
local function odd_rounded_u64(source)
	-- LuaJIT turns a 64-bit integer into a `float` by way of a `double`, which
	-- rounds twice and is miscompiled outright once the high bit is set.
	-- Rounding to odd at 53 bits makes the `double` a faithful stand-in, so the
	-- `double` to `float` store stays the only rounding that is ever applied.
	if source < 0x20000000000000ULL then
		return tonumber(source)
	end

	local value = source
	local shift = 0

	if value >= 0x2000000000000000ULL then
		value = bit_rshift(value, 8)
		shift = shift + 8
	end

	if value >= 0x200000000000000ULL then
		value = bit_rshift(value, 4)
		shift = shift + 4
	end

	if value >= 0x80000000000000ULL then
		value = bit_rshift(value, 2)
		shift = shift + 2
	end

	if value >= 0x40000000000000ULL then
		value = bit_rshift(value, 1)
		shift = shift + 1
	end

	shift = shift + 1
	value = bit_rshift(source, shift)

	if bit_lshift(value, shift) ~= source then
		value = bit_or(value, 1ULL)
	end

	return tonumber(value) * (2 ^ shift)
end

-- SECTION convert_s64_to_f32
-- NEEDS bit_or
-- NEEDS ffi_cast
-- NEEDS odd_rounded_u64
-- NEEDS transmute_n32
-- NEEDS u64_type
local function rt_convert_s64_to_f32(source)
	local negative = source < 0LL

	if negative then
		source = -source
	end

	TRANSMUTE_N32.f32 = odd_rounded_u64(ffi_cast(u64_type, source))

	local result = TRANSMUTE_N32.i32

	if negative then
		result = bit_or(result, 0x80000000)
	end

	return result
end

-- SECTION convert_u64_to_f32
-- NEEDS ffi_cast
-- NEEDS odd_rounded_u64
-- NEEDS transmute_n32
-- NEEDS u64_type
local function rt_convert_u64_to_f32(source)
	source = ffi_cast(u64_type, source)

	TRANSMUTE_N32.f32 = odd_rounded_u64(source)

	return TRANSMUTE_N32.i32
end

-- SECTION convert_s64_to_f64
-- NEEDS transmute_n64
local function rt_convert_s64_to_f64(source)
	TRANSMUTE_N64.f64 = source

	return TRANSMUTE_N64.i64
end

-- SECTION convert_u64_to_f64
-- NEEDS bit_and
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS ffi_cast
-- NEEDS i64_type
-- NEEDS transmute_n64
-- NEEDS u64_type
local function rt_convert_u64_to_f64(source)
	source = ffi_cast(u64_type, source)

	if source < 0x8000000000000000ULL then
		TRANSMUTE_N64.f64 = tonumber(ffi_cast(i64_type, source))
	else
		-- LuaJIT's `uint64 -> double` drops the low bits once a trace compiles
		-- it. Halving the value keeps it inside `int64_t`, and the sticky low
		-- bit keeps the rounding decision, so doubling back is exact.
		local halved = bit_or(bit_rshift(source, 1), bit_and(source, 1ULL))

		TRANSMUTE_N64.f64 = tonumber(ffi_cast(i64_type, halved)) * 2
	end

	return TRANSMUTE_N64.i64
end

-- SECTION transmute_i64_to_f64
local function rt_transmute_i64_to_f64(source)
	return source
end
