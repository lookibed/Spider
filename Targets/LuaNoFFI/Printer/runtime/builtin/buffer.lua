-- SECTION buffer
local buffer = {}

-- SECTION buffer_meta
local buffer_meta = {
	__index = function(t, k)
		if type(k) ~= "number" or k < 1 then
			return nil
		end

		local dirty = rawget(t, "__d")

		if dirty then
			local v = rawget(dirty, k)

			if v ~= nil then
				return v
			end
		end

		local s = rawget(t, "__s")

		return string.byte(s, k)
	end,
	__newindex = function(t, k, v)
		if type(k) ~= "number" or k < 1 then
			return
		end

		local dirty = rawget(t, "__d")

		if not dirty then
			dirty = {}
			rawset(t, "__d", dirty)
		end

		rawset(dirty, k, v)
	end,
	__len = function(t)
		return #rawget(t, "__s")
	end
}

-- SECTION transmute_buffer
local TRANSMUTE_BUFFER = {}

-- SECTION transmute_n32
local TRANSMUTE_N32 = {}

-- SECTION transmute_n64
local TRANSMUTE_N64 = {}

-- SECTION ensure_dirty
local function ensure_dirty(buf)
	if not rawget(buf, "__d") then
		rawset(buf, "__d", {})
	end
end

-- SECTION buffer_byte
-- NEEDS buffer_create
local function buffer_byte(buf, offset)
	local dirty = rawget(buf, "__d")

	if dirty then
		local v = rawget(dirty, offset)

		if v ~= nil then
			return v
		end
	end

	local s = rawget(buf, "__s")

	return string.byte(s, offset)
end

-- SECTION buffer_create
-- NEEDS buffer_meta
local function buffer_create(size)
	local t = setmetatable({}, buffer_meta)

	rawset(t, "__s", string.rep("\0", size))

	return t
end

-- SECTION buffer_len
local function buffer_len(buf)
	return #buf
end

-- SECTION buffer_copy
-- NEEDS buffer_byte
-- NEEDS ensure_dirty
local function buffer_copy(dest, dest_offset, src, offset, size)
	if size == 0 then
		return
	end

	ensure_dirty(dest)

	for i = 0, size - 1 do
		local idx = offset + i + 1

		dest[dest_offset + i + 1] = buffer_byte(src, idx)
	end
end

-- SECTION buffer_fill
-- NEEDS ensure_dirty
local function buffer_fill(buf, offset, value, size)
	ensure_dirty(buf)

	value = value % 256

	for i = 1, size do
		buf[offset + i] = value
	end
end

-- SECTION buffer_read_i8
-- NEEDS buffer_byte
local function buffer_read_i8(buf, offset)
	local value = buffer_byte(buf, offset + 1)

	if value >= 128 then
		return value - 256
	end

	return value
end

-- SECTION buffer_read_u8
-- NEEDS buffer_byte
local function buffer_read_u8(buf, offset)
	return buffer_byte(buf, offset + 1)
end

-- SECTION buffer_read_i16
-- NEEDS buffer_byte
local function buffer_read_i16(buf, offset)
	local value = buffer_byte(buf, offset + 1) + buffer_byte(buf, offset + 2) * 256

	if value >= 32768 then
		return value - 65536
	end

	return value
end

-- SECTION buffer_read_u16
-- NEEDS buffer_byte
local function buffer_read_u16(buf, offset)
	return buffer_byte(buf, offset + 1) + buffer_byte(buf, offset + 2) * 256
end

-- SECTION buffer_read_i32
-- NEEDS buffer_byte
local function buffer_read_i32(buf, offset)
	local value = buffer_byte(buf, offset + 1)
		+ buffer_byte(buf, offset + 2) * 256
		+ buffer_byte(buf, offset + 3) * 65536
		+ buffer_byte(buf, offset + 4) * 16777216

	if value >= 2147483648 then
		return value - 4294967296
	end

	return value
end

-- SECTION buffer_read_u32
-- NEEDS buffer_byte
local function buffer_read_u32(buf, offset)
	local dirty = rawget(buf, "__d")

	if dirty then
		local o = offset + 1
		local v1 = rawget(dirty, o)
		local v2 = rawget(dirty, o + 1)
		local v3 = rawget(dirty, o + 2)
		local v4 = rawget(dirty, o + 3)

		if v1 ~= nil and v2 ~= nil and v3 ~= nil and v4 ~= nil then
			return (v1 + v2 * 256 + v3 * 65536 + v4 * 16777216) % 4294967296
		end
	end

	return (buffer_byte(buf, offset + 1)
		+ buffer_byte(buf, offset + 2) * 256
		+ buffer_byte(buf, offset + 3) * 65536
		+ buffer_byte(buf, offset + 4) * 16777216) % 4294967296
end

-- SECTION buffer_read_f32
-- NEEDS buffer_read_u32
-- NEEDS from_bits_f32
local function buffer_read_f32(buf, offset)
	return from_bits_f32(buffer_read_u32(buf, offset))
end

-- SECTION buffer_read_f64
-- NEEDS buffer_read_u32
-- NEEDS from_bits_f64
local function buffer_read_f64(buf, offset)
	local lo = buffer_read_u32(buf, offset)
	local hi = buffer_read_u32(buf, offset + 4)

	return from_bits_f64(lo, hi)
end

-- SECTION buffer_write_u8
-- NEEDS ensure_dirty
local function buffer_write_u8(buf, offset, value)
	buf[offset + 1] = value % 256
end

-- SECTION buffer_write_u16
-- NEEDS ensure_dirty
local function buffer_write_u16(buf, offset, value)
	buf[offset + 1] = value % 256
	buf[offset + 2] = math.floor(value / 256) % 256
end

-- SECTION buffer_write_u32
-- NEEDS ensure_dirty
local function buffer_write_u32(buf, offset, value)
	value = value % 4294967296

	buf[offset + 1] = value % 256
	buf[offset + 2] = math.floor(value / 256) % 256
	buf[offset + 3] = math.floor(value / 65536) % 256
	buf[offset + 4] = math.floor(value / 16777216) % 256
end

-- SECTION buffer_write_f32
-- NEEDS buffer_write_u32
-- NEEDS into_bits_f32
local function buffer_write_f32(buf, offset, value)
	buffer_write_u32(buf, offset, into_bits_f32(value))
end

-- SECTION buffer_write_f64
-- NEEDS buffer_write_u32
-- NEEDS into_bits_f64
local function buffer_write_f64(buf, offset, value)
	local lo, hi = into_bits_f64(value)

	buffer_write_u32(buf, offset, lo)
	buffer_write_u32(buf, offset + 4, hi)
end

-- SECTION buffer_writestring
-- NEEDS ensure_dirty
local function buffer_writestring(buf, offset, str)
	ensure_dirty(buf)

	for i = 1, #str do
		buf[offset + i] = string.byte(str, i)
	end
end

-- SECTION from_bits_i64
local function from_bits_i64(source)
	return source[1], source[2]
end

-- SECTION into_bits_i64
local function into_bits_i64(lo, hi)
	return { lo % 4294967296, hi % 4294967296 }
end

-- SECTION from_bits_f32
local function from_bits_f32(source)
	if source < 0 then
		source = source + 4294967296
	end

	local sign = source >= 0x80000000
	local exponent = math.floor((source % 0x80000000) / 0x800000)
	local mantissa = source % 0x800000

	if exponent == 0 then
		if mantissa == 0 then
			if sign then
				return -0.0
			end

			return 0.0
		end

		local result = mantissa * 2 ^ -149

		if sign then
			return -result
		end

		return result
	end

	if exponent == 0xFF then
		if mantissa == 0 then
			if sign then
				return -math.huge
			end

			return math.huge
		end

		return 0 / 0
	end

	local result = (1 + mantissa / 0x800000) * 2 ^ (exponent - 127)

	if sign then
		return -result
	end

	return result
end

-- SECTION into_bits_f32
local function into_bits_f32(source)
	local function round_to_even(value)
		local floor_value = math.floor(value)
		local fraction = value - floor_value

		if fraction > 0.5 then
			return floor_value + 1
		end

		if fraction < 0.5 then
			return floor_value
		end

		if floor_value % 2 == 0 then
			return floor_value
		end

		return floor_value + 1
	end

	if source ~= source then
		return 0x7FC00000
	end

	if source == math.huge then
		return 0x7F800000
	end

	if source == -math.huge then
		return 0xFF800000
	end

	local sign_bit = 0

	if source < 0 or 1 / source < 0 then
		sign_bit = 0x80000000
		source = -source
	end

	if source == 0 then
		if sign_bit >= 2147483648 then
			return sign_bit - 4294967296
		end

		return sign_bit
	end

	local mantissa, exponent = math.frexp(source)

	if exponent > 127 then
		local result = sign_bit + 0x7F800000

		if result >= 2147483648 then
			return result - 4294967296
		end

		return result
	end

	if exponent < -125 then
		local subnormal = round_to_even(source * 2 ^ 149)

		if subnormal >= 0x800000 then
			local result = sign_bit + 0x00800000

			if result >= 2147483648 then
				return result - 4294967296
			end

			return result
		end

		local result = sign_bit + subnormal

		if result >= 2147483648 then
			return result - 4294967296
		end

		return result
	end

	exponent = exponent + 126
	mantissa = round_to_even((mantissa * 2 - 1) * 0x800000)

	if mantissa >= 0x800000 then
		mantissa = 0
		exponent = exponent + 1

		if exponent >= 0xFF then
			local overflow = sign_bit + 0x7F800000

			if overflow >= 2147483648 then
				return overflow - 4294967296
			end

			return overflow
		end
	end

	local result = sign_bit + exponent * 0x800000 + mantissa

	if result >= 2147483648 then
		return result - 4294967296
	end

	return result
end

-- SECTION from_bits_f64
local function from_bits_f64(lo, hi)
	lo = lo % 4294967296
	hi = hi % 4294967296

	local sign = hi >= 0x80000000
	local exponent = math.floor((hi % 0x80000000) / 0x100000)
	local mantissa_high = hi % 0x100000
	local mantissa = mantissa_high * 4294967296.0 + lo

	if exponent == 0 then
		if mantissa == 0 then
			if sign then
				return -0.0
			end

			return 0.0
		end

		local result = mantissa * 2 ^ -1074

		if sign then
			return -result
		end

		return result
	end

	if exponent == 0x7FF then
		if mantissa == 0 then
			if sign then
				return -math.huge
			end

			return math.huge
		end

		return 0 / 0
	end

	local result = (1 + mantissa / 4503599627370496.0) * 2 ^ (exponent - 1023)

	if sign then
		return -result
	end

	return result
end

-- SECTION into_bits_f64
local function into_bits_f64(source)
	if source ~= source then
		return 0, 0x7FF80000
	end

	if source == math.huge then
		return 0, 0x7FF00000
	end

	if source == -math.huge then
		return 0, 0xFFF00000
	end

	local sign_bit = 0

	if source < 0 or 1 / source < 0 then
		sign_bit = 0x80000000
		source = -source
	end

	if source == 0 then
		return 0, sign_bit
	end

	local mantissa, exponent = math.frexp(source)

	exponent = exponent + 1022

	if exponent >= 0x7FF then
		return 0, sign_bit + 0x7FF00000
	end

	if exponent <= 0 then
		mantissa = math.floor(mantissa * 2 ^ (exponent + 52))

		local hi = sign_bit + math.floor(mantissa / 4294967296.0)
		local lo = mantissa % 4294967296.0

		return lo % 4294967296, hi % 4294967296
	end

	mantissa = math.floor((mantissa - 0.5) * 2 ^ 53)

	local hi = sign_bit + exponent * 0x100000 + math.floor(mantissa / 4294967296.0)
	local lo = mantissa % 4294967296.0

	return lo % 4294967296, hi % 4294967296
end
