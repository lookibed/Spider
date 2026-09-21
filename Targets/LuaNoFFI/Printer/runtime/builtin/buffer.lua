-- SECTION buffer
-- A memory image is a table with two raw fields:
--   `__n`: the logical byte length,
--   `__w`: a dense array of packed 32-bit words, indexed from one, each holding
--          the `bit.tobit` (signed) form of four little endian bytes.
--
-- Byte `a` lives in word `bit.rshift(a, 2) + 1` at bit offset
-- `bit.lshift(bit.band(a, 3), 3)`, which is the little endian layout
-- WebAssembly specifies. The word array is always two slots longer than the
-- length strictly needs, so an unaligned access that straddles the final word
-- still finds a slot to read.
--
-- Every 32-bit read returns the signed `bit.tobit` form, which is the single
-- `i32` representation the whole runtime uses; no load is ever fixed up
-- afterwards. Reads narrower than a word stay unsigned (`0 .. 255`,
-- `0 .. 65535`), which is also a valid `i32` because those values are positive.
local buffer = {}

-- SECTION buffer_trap
local function buffer_trap()
	error("out of bounds memory access", 2)
end

-- SECTION buffer_new_table
-- Allocates a table with room for `size` array slots.
--
-- `table.new` is a `LuaJIT` extension, so it is loaded through `pcall`; a host
-- without it still works, and only pays for growing the array part instead.
local buffer_new_table
do
	local loaded, allocator = pcall(require, "table.new")

	if loaded and type(allocator) == "function" then
		buffer_new_table = allocator
	else
		buffer_new_table = function()
			return {}
		end
	end
end

-- SECTION buffer_meta
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS bit_xor
-- Exposes the packed words as a one based byte array. Host code outside the
-- generated module reads and writes linear memory through this view, so the
-- indices it takes are byte addresses plus one.
local buffer_meta = {
	__index = function(t, k)
		if type(k) ~= "number" or k < 1 or k > t.__n then
			return nil
		end

		local address = k - 1

		return bit_and(bit_rshift(t.__w[bit_rshift(address, 2) + 1], bit_lshift(bit_and(address, 3), 3)), 255)
	end,
	__newindex = function(t, k, v)
		if type(k) ~= "number" or k < 1 or k > t.__n then
			return
		end

		local address = k - 1
		local words = t.__w
		local index = bit_rshift(address, 2) + 1
		local shift = bit_lshift(bit_and(address, 3), 3)

		words[index] =
			bit_or(bit_and(words[index], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(bit_and(v, 255), shift))
	end,
	__len = function(t)
		return t.__n
	end
}

-- SECTION transmute_buffer
local TRANSMUTE_BUFFER = {}

-- SECTION transmute_n32
local TRANSMUTE_N32 = {}

-- SECTION transmute_n64
local TRANSMUTE_N64 = {}

-- SECTION buffer_byte
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_rshift
-- NEEDS buffer_trap
-- Reads the byte at `base + offset`, where `base` is the address a WebAssembly
-- access computed and `offset` the static offset of the instruction. A negative
-- `base` is out of bounds for every memory we support, and `base + offset` is
-- computed in doubles so it never wraps.
local function buffer_byte(buf, base, offset)
	local index = base + offset

	if base < 0 or index >= buf.__n then
		buffer_trap()
	end

	return bit_and(bit_rshift(buf.__w[bit_rshift(index, 2) + 1], bit_lshift(bit_and(index, 3), 3)), 255)
end

-- SECTION buffer_create
-- NEEDS buffer_meta
-- NEEDS buffer_new_table
-- NEEDS math_floor
local function buffer_create(size)
	local count = math_floor(size / 4) + 2
	local words = buffer_new_table(count, 0)

	for index = 1, count do
		words[index] = 0
	end

	return setmetatable({ __n = size, __w = words }, buffer_meta)
end

-- SECTION buffer_len
local function buffer_len(buf)
	return buf.__n
end

-- SECTION buffer_check
-- NEEDS buffer_trap
-- Traps unless the whole range `[base + offset, base + offset + size)` lies
-- inside `buf`. Multi-word accesses must call this first so a partially
-- in-bounds access never writes or reads anything.
local function buffer_check(buf, base, offset, size)
	if base < 0 or base + offset + size > buf.__n then
		buffer_trap()
	end
end

-- SECTION buffer_resize
-- NEEDS math_floor
-- Grows the word array to cover `size` bytes and only then publishes the new
-- length, so a failed allocation leaves the memory exactly as it was.
local function buffer_resize(buf, size)
	local words = buf.__w
	local old = math_floor(buf.__n / 4) + 2
	local new = math_floor(size / 4) + 2

	for index = old + 1, new do
		words[index] = 0
	end

	rawset(buf, "__n", size)
end

-- SECTION buffer_copy
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS bit_xor
-- NEEDS buffer_trap
-- Moves `size` bytes, with `memmove` semantics when the two ranges overlap.
--
-- The fast path copies whole words and needs the two addresses to share their
-- alignment; it also needs the copy to run forwards, which an overlap only
-- allows when the destination is at or below the source.
local function buffer_copy(dest, dest_offset, src, offset, size)
	if
		size < 0
		or dest_offset < 0
		or offset < 0
		or dest_offset + size > dest.__n
		or offset + size > src.__n
	then
		buffer_trap()
	end

	if size == 0 then
		return
	end

	local dest_words = dest.__w
	local src_words = src.__w
	local backwards = dest == src and dest_offset > offset

	if not backwards and bit_and(bit_xor(dest_offset, offset), 3) == 0 then
		local head = bit_and(-dest_offset, 3)

		if head > size then
			head = size
		end

		for k = 0, head - 1 do
			local from = offset + k
			local to = dest_offset + k
			local value = bit_and(bit_rshift(src_words[bit_rshift(from, 2) + 1], bit_lshift(bit_and(from, 3), 3)), 255)
			local index = bit_rshift(to, 2) + 1
			local shift = bit_lshift(bit_and(to, 3), 3)

			dest_words[index] =
				bit_or(bit_and(dest_words[index], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(value, shift))
		end

		local count = bit_rshift(size - head, 2)
		local to_index = bit_rshift(dest_offset + head, 2)
		local from_index = bit_rshift(offset + head, 2)

		for k = 1, count do
			dest_words[to_index + k] = src_words[from_index + k]
		end

		for k = head + count * 4, size - 1 do
			local from = offset + k
			local to = dest_offset + k
			local value = bit_and(bit_rshift(src_words[bit_rshift(from, 2) + 1], bit_lshift(bit_and(from, 3), 3)), 255)
			local index = bit_rshift(to, 2) + 1
			local shift = bit_lshift(bit_and(to, 3), 3)

			dest_words[index] =
				bit_or(bit_and(dest_words[index], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(value, shift))
		end

		return
	end

	local first = 0
	local last = size - 1
	local step = 1

	if backwards then
		first = size - 1
		last = 0
		step = -1
	end

	for k = first, last, step do
		local from = offset + k
		local to = dest_offset + k
		local value = bit_and(bit_rshift(src_words[bit_rshift(from, 2) + 1], bit_lshift(bit_and(from, 3), 3)), 255)
		local index = bit_rshift(to, 2) + 1
		local shift = bit_lshift(bit_and(to, 3), 3)

		dest_words[index] =
			bit_or(bit_and(dest_words[index], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(value, shift))
	end
end

-- SECTION buffer_fill
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS bit_tobit
-- NEEDS bit_xor
-- NEEDS buffer_trap
local function buffer_fill(buf, offset, value, size)
	if size < 0 or offset < 0 or offset + size > buf.__n then
		buffer_trap()
	end

	if size == 0 then
		return
	end

	local words = buf.__w
	local byte = bit_and(value, 255)
	local word = bit_tobit(byte * 16843009)
	local address = offset
	local last = offset + size

	while address < last and bit_and(address, 3) ~= 0 do
		local index = bit_rshift(address, 2) + 1
		local shift = bit_lshift(bit_and(address, 3), 3)

		words[index] = bit_or(bit_and(words[index], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(byte, shift))
		address = address + 1
	end

	while address + 4 <= last do
		words[bit_rshift(address, 2) + 1] = word
		address = address + 4
	end

	while address < last do
		local index = bit_rshift(address, 2) + 1
		local shift = bit_lshift(bit_and(address, 3), 3)

		words[index] = bit_or(bit_and(words[index], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(byte, shift))
		address = address + 1
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
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS buffer_trap
local function buffer_read_u16(buf, base, offset)
	local index = base + offset

	if base < 0 or index + 2 > buf.__n then
		buffer_trap()
	end

	local words = buf.__w
	local slot = bit_rshift(index, 2) + 1
	local shift = bit_lshift(bit_and(index, 3), 3)

	if shift == 24 then
		return bit_or(bit_rshift(words[slot], 24), bit_lshift(bit_and(words[slot + 1], 255), 8))
	end

	return bit_and(bit_rshift(words[slot], shift), 65535)
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

-- SECTION buffer_read_i32
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS buffer_trap
-- Returns the signed `bit.tobit` form of the word at the address, which is the
-- form every other `i32` in the runtime already has.
local function buffer_read_i32(buf, base, offset)
	local index = base + offset

	if base < 0 or index + 4 > buf.__n then
		buffer_trap()
	end

	local words = buf.__w
	local slot = bit_rshift(index, 2) + 1
	local shift = bit_lshift(bit_and(index, 3), 3)

	if shift == 0 then
		return words[slot]
	end

	return bit_or(bit_rshift(words[slot], shift), bit_lshift(words[slot + 1], 32 - shift))
end

-- SECTION buffer_read_f32
-- NEEDS buffer_read_i32
-- NEEDS from_bits_f32
local function buffer_read_f32(buf, base, offset)
	return from_bits_f32(buffer_read_i32(buf, base, offset))
end

-- SECTION buffer_read_f64
-- NEEDS buffer_check
-- NEEDS buffer_read_i32
-- NEEDS from_bits_f64
local function buffer_read_f64(buf, base, offset)
	buffer_check(buf, base, offset, 8)

	local lo = buffer_read_i32(buf, base, offset)
	local hi = buffer_read_i32(buf, base, offset + 4)

	return from_bits_f64(lo, hi)
end

-- SECTION buffer_write_u8
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS bit_xor
-- NEEDS buffer_trap
local function buffer_write_u8(buf, base, offset, value)
	local index = base + offset

	if base < 0 or index + 1 > buf.__n then
		buffer_trap()
	end

	local words = buf.__w
	local slot = bit_rshift(index, 2) + 1
	local shift = bit_lshift(bit_and(index, 3), 3)

	words[slot] =
		bit_or(bit_and(words[slot], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(bit_and(value, 255), shift))
end

-- SECTION buffer_write_u16
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS bit_xor
-- NEEDS buffer_trap
local function buffer_write_u16(buf, base, offset, value)
	local index = base + offset

	if base < 0 or index + 2 > buf.__n then
		buffer_trap()
	end

	local words = buf.__w
	local slot = bit_rshift(index, 2) + 1
	local shift = bit_lshift(bit_and(index, 3), 3)
	local half = bit_and(value, 65535)

	if shift == 24 then
		words[slot] = bit_or(bit_and(words[slot], 0xFFFFFF), bit_lshift(half, 24))
		words[slot + 1] = bit_or(bit_and(words[slot + 1], -256), bit_rshift(half, 8))

		return
	end

	words[slot] = bit_or(bit_and(words[slot], bit_xor(bit_lshift(65535, shift), -1)), bit_lshift(half, shift))
end

-- SECTION buffer_write_i32
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS bit_tobit
-- NEEDS bit_xor
-- NEEDS buffer_trap
-- Accepts either sign of a 32-bit value; the word array always stores the
-- `bit.tobit` form.
local function buffer_write_i32(buf, base, offset, value)
	local index = base + offset

	if base < 0 or index + 4 > buf.__n then
		buffer_trap()
	end

	local words = buf.__w
	local slot = bit_rshift(index, 2) + 1
	local shift = bit_lshift(bit_and(index, 3), 3)
	local word = bit_tobit(value)

	if shift == 0 then
		words[slot] = word

		return
	end

	local high = bit_lshift(-1, shift)
	local low = bit_xor(high, -1)

	words[slot] = bit_or(bit_and(words[slot], low), bit_and(bit_lshift(word, shift), high))
	words[slot + 1] = bit_or(bit_and(words[slot + 1], high), bit_and(bit_rshift(word, 32 - shift), low))
end

-- SECTION buffer_write_f32
-- NEEDS buffer_write_i32
-- NEEDS into_bits_f32
local function buffer_write_f32(buf, base, offset, value)
	buffer_write_i32(buf, base, offset, into_bits_f32(value))
end

-- SECTION buffer_write_f64
-- NEEDS buffer_check
-- NEEDS buffer_write_i32
-- NEEDS into_bits_f64
local function buffer_write_f64(buf, base, offset, value)
	buffer_check(buf, base, offset, 8)

	local lo, hi = into_bits_f64(value)

	buffer_write_i32(buf, base, offset, lo)
	buffer_write_i32(buf, base, offset + 4, hi)
end

-- SECTION buffer_writestring
-- NEEDS bit_and
-- NEEDS bit_lshift
-- NEEDS bit_or
-- NEEDS bit_rshift
-- NEEDS bit_xor
-- NEEDS buffer_trap
-- Writes a data segment. The middle of the segment lands one whole word at a
-- time, which is what makes module start-up cheap for large segments.
local function buffer_writestring(buf, offset, str)
	local size = #str

	if offset < 0 or offset + size > buf.__n then
		buffer_trap()
	end

	if size == 0 then
		return
	end

	local string_byte = string.byte
	local words = buf.__w
	local head = bit_and(-offset, 3)

	if head > size then
		head = size
	end

	for k = 1, head do
		local address = offset + k - 1
		local slot = bit_rshift(address, 2) + 1
		local shift = bit_lshift(bit_and(address, 3), 3)

		words[slot] =
			bit_or(bit_and(words[slot], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(string_byte(str, k), shift))
	end

	local count = bit_rshift(size - head, 2)
	local base = bit_rshift(offset + head, 2)

	for k = 1, count do
		local position = head + k * 4 - 3
		local b1, b2, b3, b4 = string_byte(str, position, position + 3)

		words[base + k] = bit_or(b1, bit_lshift(b2, 8), bit_lshift(b3, 16), bit_lshift(b4, 24))
	end

	for k = head + count * 4 + 1, size do
		local address = offset + k - 1
		local slot = bit_rshift(address, 2) + 1
		local shift = bit_lshift(bit_and(address, 3), 3)

		words[slot] =
			bit_or(bit_and(words[slot], bit_xor(bit_lshift(255, shift), -1)), bit_lshift(string_byte(str, k), shift))
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

-- SECTION f32_constants
-- Constants shared by the `binary32` conversions.
--
-- `F32_POWERS[k + 150]` is `2 ^ k` for every `k` in `-149 .. 128`. It is built
-- by exact doubling and halving, so no `pow` call and no rounding is involved,
-- and it replaces the `2 ^ exponent` expressions the conversions would
-- otherwise evaluate on every call.
--
-- `SPLIT_F32` is the Veltkamp split factor `2 ^ 29 + 1`: for a finite double of
-- `binary32` magnitude, `c = x * SPLIT_F32` followed by `c - (c - x)` is the
-- correctly rounded `binary32` value of `x`. That replaces `math.frexp`, which
-- the `LuaJIT` tracer cannot compile and which therefore split a trace on every
-- conversion.
--
-- `SUB_MAGIC_F32` is `1.5 * 2 ^ 52 * 2 ^ -149`; adding and subtracting it
-- rounds a value to a multiple of the smallest subnormal with the same
-- round-half-to-even rule. `OVERFLOW_F32` is the first double that rounds up to
-- infinity, and `SCALE_F32` turns a rounded subnormal into its integer
-- mantissa.
local F32_POWERS = {}
local SPLIT_F32 = 2 ^ 29 + 1
local MIN_NORMAL_F32 = 2 ^ -126
local SUB_MAGIC_F32 = 1.5 * 2 ^ -97
local OVERFLOW_F32 = 2 ^ 128 - 2 ^ 103
local SCALE_F32 = 2 ^ 149
do
	local value = 1.0

	for k = 0, 128 do
		F32_POWERS[k + 150] = value
		value = value * 2
	end

	value = 1.0

	for k = -1, -149, -1 do
		value = value / 2
		F32_POWERS[k + 150] = value
	end
end

-- SECTION from_bits_f32
-- NEEDS bit_and
-- NEEDS bit_rshift
-- NEEDS f32_constants
-- NEEDS math_huge
-- Turns a `binary32` bit pattern into a double. The pattern may carry either
-- sign, since `bit.rshift` normalises it first.
local function from_bits_f32(source)
	local exponent = bit_and(bit_rshift(source, 23), 0xFF)
	local mantissa = bit_and(source, 0x7FFFFF)
	local result

	if exponent == 0xFF then
		if mantissa ~= 0 then
			return 0 / 0
		end

		result = math_huge
	elseif exponent == 0 then
		-- `2 ^ -149` scaled, which is exact for every subnormal mantissa.
		result = mantissa * F32_POWERS[1]
	else
		-- `(2 ^ 23 + mantissa) * 2 ^ (exponent - 150)`, and `exponent - 150`
		-- lands at table index `exponent`.
		result = (mantissa + 0x800000) * F32_POWERS[exponent]
	end

	if bit_and(bit_rshift(source, 31), 1) ~= 0 then
		return -result
	end

	return result
end

-- SECTION into_bits_f32
-- NEEDS f32_constants
-- NEEDS math_floor
-- NEEDS math_log
-- Rounds a double to `binary32` and returns its bit pattern, signed so that it
-- matches every other `i32` the runtime produces.
--
-- The rounding is a Veltkamp split rather than `math.frexp`, and the exponent
-- comes from a logarithm corrected by at most one step, so the whole function
-- compiles into a trace.
local function into_bits_f32(source)
	if source ~= source then
		return 0x7FC00000
	end

	local sign_bit = 0

	if source < 0 or 1 / source < 0 then
		sign_bit = 0x80000000
		source = -source
	end

	local result

	if source >= OVERFLOW_F32 then
		result = sign_bit + 0x7F800000
	elseif source < MIN_NORMAL_F32 then
		-- Subnormal or zero. The magic add rounds to a multiple of `2 ^ -149`,
		-- and scaling that back is exact. A value that rounds up to `2 ^ -126`
		-- yields a mantissa of `0x800000`, which is already the encoding of the
		-- smallest normal.
		result = sign_bit + ((source + SUB_MAGIC_F32) - SUB_MAGIC_F32) * SCALE_F32
	else
		local split = source * SPLIT_F32
		local rounded = split - (split - source)
		local exponent = math_floor(math_log(rounded) * 1.4426950408889634)
		local scale = F32_POWERS[exponent + 150]

		-- The logarithm is only accurate to within one exponent, so correct it.
		if rounded < scale then
			exponent = exponent - 1
			scale = F32_POWERS[exponent + 150]
		elseif rounded >= scale + scale then
			exponent = exponent + 1
			scale = F32_POWERS[exponent + 150]
		end

		-- Dividing by a power of two is exact, and the rounded value is already
		-- a `binary32`, so the mantissa comes out as an exact integer.
		result = sign_bit + (exponent + 127) * 0x800000 + (rounded / scale - 1) * 0x800000
	end

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
