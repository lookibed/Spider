-- SECTION memory_type
-- In LuaNoFFI, we use a table-based approach instead of buffer
-- Memory = { data_table, maximum }

-- SECTION memory_new
-- NEEDS buffer_create
-- NEEDS buffer_writestring
local function rt_memory_new(initializer, minimum, maximum)
	local data = buffer_create(minimum)

	for offset, content in pairs(initializer) do
		buffer_writestring(data, offset, content)
	end

	return { data, maximum = maximum }
end

-- SECTION load_i32_from_s8
-- NEEDS buffer_read_i8
local function rt_load_i32_from_s8(source, offset)
	local result = buffer_read_i8(source[1], offset)

	return result
end

-- SECTION load_i32_from_u8
-- NEEDS buffer_read_u8
local function rt_load_i32_from_u8(source, offset)
	local result = buffer_read_u8(source[1], offset)

	return result
end

-- SECTION load_i32_from_s16
-- NEEDS buffer_read_i16
local function rt_load_i32_from_s16(source, offset)
	local result = buffer_read_i16(source[1], offset)

	return result
end

-- SECTION load_i32_from_u16
-- NEEDS buffer_read_u16
local function rt_load_i32_from_u16(source, offset)
	local result = buffer_read_u16(source[1], offset)

	return result
end

-- SECTION load_i32
-- NEEDS buffer_read_u32
local function rt_load_i32(source, offset)
	local result = buffer_read_u32(source[1], offset)

	return result
end

-- SECTION load_i64_from_s8
-- NEEDS buffer_read_i8
-- NEEDS into_bits_i64
local function rt_load_i64_from_s8(source, offset)
	local val = buffer_read_i8(source[1], offset)

	if val >= 0 then
		return into_bits_i64(val, 0)
	else
		return into_bits_i64(val + 0x100000000, 0xFFFFFFFF)
	end
end

-- SECTION load_i64_from_u8
-- NEEDS buffer_read_u8
-- NEEDS into_bits_i64
local function rt_load_i64_from_u8(source, offset)
	local val = buffer_read_u8(source[1], offset)

	return into_bits_i64(val, 0)
end

-- SECTION load_i64_from_s16
-- NEEDS buffer_read_i16
-- NEEDS into_bits_i64
local function rt_load_i64_from_s16(source, offset)
	local val = buffer_read_i16(source[1], offset)

	if val >= 0 then
		return into_bits_i64(val, 0)
	else
		return into_bits_i64(val + 0x100000000, 0xFFFFFFFF)
	end
end

-- SECTION load_i64_from_u16
-- NEEDS buffer_read_u16
-- NEEDS into_bits_i64
local function rt_load_i64_from_u16(source, offset)
	local val = buffer_read_u16(source[1], offset)

	return into_bits_i64(val, 0)
end

-- SECTION load_i64_from_s32
-- NEEDS buffer_read_i32
-- NEEDS into_bits_i64
local function rt_load_i64_from_s32(source, offset)
	local val = buffer_read_i32(source[1], offset)

	if val >= 0 then
		return into_bits_i64(val, 0)
	else
		return into_bits_i64(val + 0x100000000, 0xFFFFFFFF)
	end
end

-- SECTION load_i64_from_u32
-- NEEDS buffer_read_u32
-- NEEDS into_bits_i64
local function rt_load_i64_from_u32(source, offset)
	local val = buffer_read_u32(source[1], offset)

	return into_bits_i64(val, 0)
end

-- SECTION load_i64
-- NEEDS buffer_read_u32
-- NEEDS into_bits_i64
local function rt_load_i64(source, offset)
	local memory = source[1]
	local lo = buffer_read_u32(memory, offset)
	local hi = buffer_read_u32(memory, offset + 4)

	return into_bits_i64(lo, hi)
end

-- SECTION load_f32
-- NEEDS buffer_read_u32
local function rt_load_f32(source, offset)
	return buffer_read_u32(source[1], offset)
end

-- SECTION load_f64
-- NEEDS buffer_read_f64
local function rt_load_f64(source, offset)
	return buffer_read_f64(source[1], offset)
end

-- SECTION store_i32_into_i8
-- NEEDS buffer_write_u8
local function rt_store_i32_into_i8(destination, offset, source)
	buffer_write_u8(destination[1], offset, source)
end

-- SECTION store_i32_into_i16
-- NEEDS buffer_write_u16
local function rt_store_i32_into_i16(destination, offset, source)
	buffer_write_u16(destination[1], offset, source)
end

-- SECTION store_i32
-- NEEDS buffer_write_u32
local function rt_store_i32(destination, offset, source)
	buffer_write_u32(destination[1], offset, source)
end

-- SECTION store_i64_into_i8
-- NEEDS buffer_write_u8
-- NEEDS from_bits_i64
local function rt_store_i64_into_i8(destination, offset, source)
	local lo = from_bits_i64(source)

	buffer_write_u8(destination[1], offset, lo)
end

-- SECTION store_i64_into_i16
-- NEEDS buffer_write_u16
-- NEEDS from_bits_i64
local function rt_store_i64_into_i16(destination, offset, source)
	local lo = from_bits_i64(source)

	buffer_write_u16(destination[1], offset, lo)
end

-- SECTION store_i64_into_i32
-- NEEDS buffer_write_u32
-- NEEDS from_bits_i64
local function rt_store_i64_into_i32(destination, offset, source)
	local lo = from_bits_i64(source)

	buffer_write_u32(destination[1], offset, lo)
end

-- SECTION store_i64
-- NEEDS buffer_write_u32
-- NEEDS from_bits_i64
local function rt_store_i64(destination, offset, source)
	local lo, hi = from_bits_i64(source)

	buffer_write_u32(destination[1], offset + 4, hi)
	buffer_write_u32(destination[1], offset, lo)
end

-- SECTION store_f32
-- NEEDS buffer_write_u32
local function rt_store_f32(destination, offset, source)
	buffer_write_u32(destination[1], offset, source)
end

-- SECTION store_f64
-- NEEDS buffer_write_f64
local function rt_store_f64(destination, offset, source)
	buffer_write_f64(destination[1], offset, source)
end

-- SECTION memory_size
-- NEEDS buffer_len
local function rt_memory_size(source)
	return buffer_len(source[1])
end

-- SECTION memory_grow
-- NEEDS buffer_copy
-- NEEDS buffer_create
-- NEEDS buffer_len
local function rt_memory_grow(destination, size)
	local old = buffer_len(destination[1])
	local new = old + size

	if new > destination.maximum then
		return -1
	end

	local new_buf = buffer_create(new)
	buffer_copy(new_buf, 0, destination[1], 0, old)

	destination[1] = new_buf

	return old
end

-- SECTION memory_fill
-- NEEDS buffer_fill
local function rt_memory_fill(destination, offset, value, size)
	buffer_fill(destination[1], offset, value, size)
end

-- SECTION memory_copy
-- NEEDS buffer_copy
-- NEEDS buffer_len
local function rt_memory_copy(destination, offset_1, source, offset_2, size)
	buffer_copy(destination[1], offset_1, source[1], offset_2, size)
end

-- SECTION memory_drop
local function rt_memory_drop(destination)
	destination[1] = {}
	destination.maximum = 0
end
