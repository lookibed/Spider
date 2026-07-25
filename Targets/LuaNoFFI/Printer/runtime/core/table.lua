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
local function rt_table_get(source, offset)
	assert(offset < source.minimum, "out of bounds table access")

	return source[offset]
end

-- SECTION table_set
local function rt_table_set(destination, offset, source)
	assert(offset < destination.minimum, "out of bounds table access")

	destination[offset] = source
end

-- SECTION table_size
local function rt_table_size(source)
	return source.minimum
end

-- SECTION table_grow
local function rt_table_grow(destination, source, size)
	local old = destination.minimum
	local new = old + size

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
local function rt_table_fill(destination, offset, source, size)
	assert(offset + size <= destination.minimum, "out of bounds table access")

	for i = 0, size - 1 do
		destination[offset + i] = source
	end
end

-- SECTION table_copy
local function rt_table_copy(destination, offset_1, source, offset_2, size)
	assert(offset_1 + size <= destination.minimum, "out of bounds table access")
	assert(offset_2 + size <= source.minimum, "out of bounds table access")

	for i = 0, size - 1 do
		destination[offset_1 + i] = source[offset_2 + i]
	end
end

-- SECTION table_drop
local function rt_table_drop(destination)
	destination.minimum = 0
	destination.maximum = 0
end
