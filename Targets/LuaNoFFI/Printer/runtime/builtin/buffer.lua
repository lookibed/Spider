-- SECTION buffer
-- A buffer is a table with three raw fields:
--   `__n`: the logical byte length,
--   `__s`: an immutable base image (a Lua string, possibly shorter than `__n`;
--          bytes past its end read as zero),
--   `__d`: an optional overlay table of written bytes keyed by 1-based index.
local buffer = {}

-- SECTION buffer_trap
local function buffer_trap()
	error("out of bounds memory access", 2)
end

-- SECTION buffer_meta
local buffer_meta = {
	__index = function(t, k)
		if type(k) ~= "number" or k < 1 or k > rawget(t, "__n") then
			return nil
		end

		local dirty = rawget(t, "__d")

		if dirty then
			local v = rawget(dirty, k)

			if v ~= nil then
				return v
			end
		end

		return string.byte(rawget(t, "__s"), k) or 0
	end,
	__newindex = function(t, k, v)
		if type(k) ~= "number" or k < 1 or k > rawget(t, "__n") then
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
		return rawget(t, "__n")
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
	local dirty = rawget(buf, "__d")

	if not dirty then
		dirty = {}
		rawset(buf, "__d", dirty)
	end

	return dirty
end

-- SECTION buffer_byte
-- NEEDS buffer_trap
-- Reads the byte at `base + offset`, where `base` is the address a WebAssembly
-- access computed and `offset` the static offset of the instruction. A negative
-- `base` is out of bounds for every memory we support, and `base + offset` is
-- computed in doubles so it never wraps.
local function buffer_byte(buf, base, offset)
	local index = base + offset

	if base < 0 or index >= rawget(buf, "__n") then
		buffer_trap()
	end

	local dirty = rawget(buf, "__d")

	if dirty then
		local v = dirty[index + 1]

		if v ~= nil then
			return v
		end
	end

	return string.byte(rawget(buf, "__s"), index + 1) or 0
end

-- SECTION buffer_create
-- NEEDS buffer_meta
local function buffer_create(size)
	local t = setmetatable({}, buffer_meta)

	rawset(t, "__s", "")
	rawset(t, "__n", size)

	return t
end

-- SECTION buffer_len
local function buffer_len(buf)
	return rawget(buf, "__n")
end

-- SECTION buffer_check
-- NEEDS buffer_trap
-- Traps unless the whole range `[base + offset, base + offset + size)` lies
-- inside `buf`. Multi-word accesses must call this first so a partially
-- in-bounds access never writes or reads anything.
local function buffer_check(buf, base, offset, size)
	if base < 0 or base + offset + size > rawget(buf, "__n") then
		buffer_trap()
	end
end

-- SECTION buffer_resize
local function buffer_resize(buf, size)
	rawset(buf, "__n", size)
end

-- SECTION buffer_copy
-- NEEDS buffer_trap
-- NEEDS ensure_dirty
local function buffer_copy(dest, dest_offset, src, offset, size)
	if
		size < 0
		or dest_offset < 0
		or offset < 0
		or dest_offset + size > rawget(dest, "__n")
		or offset + size > rawget(src, "__n")
	then
		buffer_trap()
	end

	if size == 0 then
		return
	end

	local dest_d = ensure_dirty(dest)
	local src_d = rawget(src, "__d")
	local src_s = rawget(src, "__s")

	if dest == src and dest_offset > offset then
		for i = size - 1, 0, -1 do
			local from = offset + i + 1
			local v = src_d[from]

			if v == nil then
				v = string.byte(src_s, from) or 0
			end

			dest_d[dest_offset + i + 1] = v
		end

		return
	end

	if src_d then
		for i = 0, size - 1 do
			local from = offset + i + 1
			local v = src_d[from]

			if v == nil then
				v = string.byte(src_s, from) or 0
			end

			dest_d[dest_offset + i + 1] = v
		end
	else
		for i = 0, size - 1 do
			dest_d[dest_offset + i + 1] = string.byte(src_s, offset + i + 1) or 0
		end
	end
end

-- SECTION buffer_fill
-- NEEDS buffer_trap
-- NEEDS ensure_dirty
local function buffer_fill(buf, offset, value, size)
	if size < 0 or offset < 0 or offset + size > rawget(buf, "__n") then
		buffer_trap()
	end

	if size == 0 then
		return
	end

	local dirty = ensure_dirty(buf)

	value = value % 256

	for i = offset + 1, offset + size do
		dirty[i] = value
	end
end

-- SECTION buffer_read_i8
-- NEEDS buffer_byte
local function buffer_read_i8(buf, base, offset)
	local value = buffer_byte(buf, base, offset)

	if value >= 128 then
		return value - 256
	end

	return value
end

-- SECTION buffer_read_u8
-- NEEDS buffer_byte
local function buffer_read_u8(buf, base, offset)
	return buffer_byte(buf, base, offset)
end

-- SECTION buffer_read_u16
-- NEEDS buffer_trap
local function buffer_read_u16(buf, base, offset)
	local index = base + offset

	if base < 0 or index + 2 > rawget(buf, "__n") then
		buffer_trap()
	end

	local o = index + 1
	local s = rawget(buf, "__s")
	local dirty = rawget(buf, "__d")

	if dirty then
		local v1 = dirty[o]
		local v2 = dirty[o + 1]

		if v1 == nil then
			v1 = string.byte(s, o) or 0
		end

		if v2 == nil then
			v2 = string.byte(s, o + 1) or 0
		end

		return v1 + v2 * 256
	end

	if o + 1 > #s then
		return (string.byte(s, o) or 0) + (string.byte(s, o + 1) or 0) * 256
	end

	local v1, v2 = string.byte(s, o, o + 1)

	return v1 + v2 * 256
end

-- SECTION buffer_read_i16
-- NEEDS buffer_read_u16
local function buffer_read_i16(buf, base, offset)
	local value = buffer_read_u16(buf, base, offset)

	if value >= 32768 then
		return value - 65536
	end

	return value
end

-- SECTION buffer_read_u32
-- NEEDS buffer_trap
local function buffer_read_u32(buf, base, offset)
	local index = base + offset

	if base < 0 or index + 4 > rawget(buf, "__n") then
		buffer_trap()
	end

	local o = index + 1
	local s = rawget(buf, "__s")
	local dirty = rawget(buf, "__d")

	if dirty then
		local v1 = dirty[o]
		local v2 = dirty[o + 1]
		local v3 = dirty[o + 2]
		local v4 = dirty[o + 3]

		if v1 == nil then
			v1 = string.byte(s, o) or 0
		end

		if v2 == nil then
			v2 = string.byte(s, o + 1) or 0
		end

		if v3 == nil then
			v3 = string.byte(s, o + 2) or 0
		end

		if v4 == nil then
			v4 = string.byte(s, o + 3) or 0
		end

		return v1 + v2 * 256 + v3 * 65536 + v4 * 16777216
	end

	if o + 3 > #s then
		return (string.byte(s, o) or 0)
			+ (string.byte(s, o + 1) or 0) * 256
			+ (string.byte(s, o + 2) or 0) * 65536
			+ (string.byte(s, o + 3) or 0) * 16777216
	end

	local v1, v2, v3, v4 = string.byte(s, o, o + 3)

	return v1 + v2 * 256 + v3 * 65536 + v4 * 16777216
end

-- SECTION buffer_read_i32
-- NEEDS buffer_read_u32
local function buffer_read_i32(buf, base, offset)
	local value = buffer_read_u32(buf, base, offset)

	if value >= 2147483648 then
		return value - 4294967296
	end

	return value
end

-- SECTION buffer_read_f32
-- NEEDS buffer_read_u32
-- NEEDS from_bits_f32
local function buffer_read_f32(buf, base, offset)
	return from_bits_f32(buffer_read_u32(buf, base, offset))
end

-- SECTION buffer_read_f64
-- NEEDS buffer_check
-- NEEDS buffer_read_u32
-- NEEDS from_bits_f64
local function buffer_read_f64(buf, base, offset)
	buffer_check(buf, base, offset, 8)

	local lo = buffer_read_u32(buf, base, offset)
	local hi = buffer_read_u32(buf, base, offset + 4)

	return from_bits_f64(lo, hi)
end

-- SECTION buffer_write_u8
-- NEEDS buffer_trap
-- NEEDS ensure_dirty
local function buffer_write_u8(buf, base, offset, value)
	local index = base + offset

	if base < 0 or index + 1 > rawget(buf, "__n") then
		buffer_trap()
	end

	local dirty = ensure_dirty(buf)

	dirty[index + 1] = value % 256
end

-- SECTION buffer_write_u16
-- NEEDS buffer_trap
-- NEEDS ensure_dirty
local function buffer_write_u16(buf, base, offset, value)
	local index = base + offset

	if base < 0 or index + 2 > rawget(buf, "__n") then
		buffer_trap()
	end

	local dirty = ensure_dirty(buf)

	value = value % 65536

	dirty[index + 1] = value % 256
	dirty[index + 2] = math.floor(value / 256)
end

-- SECTION buffer_write_u32
-- NEEDS buffer_trap
-- NEEDS ensure_dirty
local function buffer_write_u32(buf, base, offset, value)
	local index = base + offset

	if base < 0 or index + 4 > rawget(buf, "__n") then
		buffer_trap()
	end

	local dirty = ensure_dirty(buf)

	value = value % 4294967296

	dirty[index + 1] = value % 256
	dirty[index + 2] = math.floor(value / 256) % 256
	dirty[index + 3] = math.floor(value / 65536) % 256
	dirty[index + 4] = math.floor(value / 16777216)
end

-- SECTION buffer_write_f32
-- NEEDS buffer_write_u32
-- NEEDS into_bits_f32
local function buffer_write_f32(buf, base, offset, value)
	buffer_write_u32(buf, base, offset, into_bits_f32(value))
end

-- SECTION buffer_write_f64
-- NEEDS buffer_check
-- NEEDS buffer_write_u32
-- NEEDS into_bits_f64
local function buffer_write_f64(buf, base, offset, value)
	buffer_check(buf, base, offset, 8)

	local lo, hi = into_bits_f64(value)

	buffer_write_u32(buf, base, offset, lo)
	buffer_write_u32(buf, base, offset + 4, hi)
end

-- SECTION buffer_writestring
-- NEEDS buffer_trap
-- NEEDS ensure_dirty
local function buffer_writestring(buf, offset, str)
	local size = #str

	if offset < 0 or offset + size > rawget(buf, "__n") then
		buffer_trap()
	end

	if size == 0 then
		return
	end

	local dirty = ensure_dirty(buf)

	for i = 1, size do
		dirty[offset + i] = string.byte(str, i)
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

	if exponent > 128 then
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
