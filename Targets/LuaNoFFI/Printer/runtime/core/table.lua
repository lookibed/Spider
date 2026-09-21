-- SECTION table_new
local function rt_table_new(initializer, minimum, maximum)
	local result = {}

	for offset, element in pairs(initializer) do
		result[offset] = element
	end

	result.minimum = minimum
	result.maximum = maximum

	return result
end

-- SECTION table_get
-- NEEDS force_u32
local function rt_table_get(source, offset)
	offset = force_u32(offset)

	if offset >= source.minimum then
		error("out of bounds table access", 0)
	end

	return source[offset]
end

-- SECTION table_set
-- NEEDS force_u32
local function rt_table_set(destination, offset, source)
	offset = force_u32(offset)

	if offset >= destination.minimum then
		error("out of bounds table access", 0)
	end

	destination[offset] = source
end

-- SECTION table_size
local function rt_table_size(source)
	return source.minimum
end

-- SECTION table_grow
-- NEEDS force_u32
local function rt_table_grow(destination, source, size)
	local old = destination.minimum
	local new = old + force_u32(size)

	if new > destination.maximum then
		return -1
	end

	for offset = old, new - 1 do
		destination[offset] = source
	end

	destination.minimum = new

	return old
end

-- SECTION table_fill
-- NEEDS force_u32
local function rt_table_fill(destination, offset, source, size)
	offset = force_u32(offset)
	size = force_u32(size)

	if offset + size > destination.minimum then
		error("out of bounds table access", 0)
	end

	for i = 0, size - 1 do
		destination[offset + i] = source
	end
end

-- SECTION table_copy
-- NEEDS force_u32
local function rt_table_copy(destination, offset_1, source, offset_2, size)
	offset_1 = force_u32(offset_1)
	offset_2 = force_u32(offset_2)
	size = force_u32(size)

	if offset_1 + size > destination.minimum or offset_2 + size > source.minimum then
		error("out of bounds table access", 0)
	end

	if offset_1 <= offset_2 then
		for i = 0, size - 1 do
			destination[offset_1 + i] = source[offset_2 + i]
		end
	else
		for i = size - 1, 0, -1 do
			destination[offset_1 + i] = source[offset_2 + i]
		end
	end
end

-- SECTION table_drop
local function rt_table_drop(destination)
	for offset = 0, destination.minimum - 1 do
		destination[offset] = nil
	end

	destination.minimum = 0
	destination.maximum = 0
end

-- SECTION function_types
-- An indirect call compares the WebAssembly type of the function it found against the
-- type the call site expects, so every function a module defines registers its key here.
-- The table is weak keyed so an unreachable function value is still collected, and a host
-- function simply has no entry, which leaves it unchecked.
local rt_function_types = setmetatable({}, { __mode = "k" })

-- SECTION function_type
-- NEEDS function_types
local function rt_function_type(source, key)
	rt_function_types[source] = key

	return source
end

-- SECTION table_get_function
-- NEEDS force_u32
-- NEEDS function_types
local function rt_table_get_function(source, offset, expected)
	offset = force_u32(offset)

	if offset >= source.minimum then
		error("undefined element", 0)
	end

	local result = source[offset]

	if result == nil then
		error("uninitialized element", 0)
	end

	local actual = rt_function_types[result]

	if actual ~= nil and actual ~= expected then
		error("indirect call type mismatch", 0)
	end

	return result
end
