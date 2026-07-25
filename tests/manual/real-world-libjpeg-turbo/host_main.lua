local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_jpeg_path = arg[2] or (script_dir .. "/fixtures/sample.jpg")
local generated_module_path = script_dir .. "/generated/libjpeg_turbo.lua"

if target == "lua-jit" then
	error("host_main.lua currently targets lua-no-ffi only")
end

local function read_file(path)
	local file = assert(io.open(path, "rb"))
	local data = assert(file:read("*a"))
	assert(file:close())
	return data
end

local function write_file(path, bytes)
	local file = assert(io.open(path, "wb"))
	assert(file:write(bytes))
	assert(file:close())
end

local function ensure_directory(path)
	local normalized = path:gsub("/", "\\")
	os.execute(('if not exist "%s" mkdir "%s"'):format(normalized, normalized))
end

local function write_bytes(memory, offset, bytes)
	for index = 1, #bytes do
		memory[offset + index] = string.byte(bytes, index)
	end
end

local function read_bytes(memory, offset, length)
	local out = {}
	for index = 1, length do
		out[index] = string.char(memory[offset + index])
	end
	return table.concat(out)
end

local function basename_without_extension(path)
	local normalized = path:gsub("\\", "/")
	local name = normalized:match("([^/]+)$") or normalized
	return (name:gsub("%.[^.]+$", ""))
end

local function ppm_bytes(width, height, rgb_bytes)
	local header = ("P6\n%d %d\n255\n"):format(width, height)
	return header .. rgb_bytes
end

local wasm_module_loader = assert(dofile(generated_module_path))
local wasm = assert(wasm_module_loader())
local memory = wasm.memory[1]
local jpeg_bytes = read_file(input_jpeg_path)
local output_dir = script_dir .. "/generated/frames"
local output_base = basename_without_extension(input_jpeg_path)

ensure_directory(output_dir)

assert(wasm.libjpeg_turbo_host_reset() == 1, "host reset failed")

local input_ptr = wasm.libjpeg_turbo_host_alloc(#jpeg_bytes)
assert(input_ptr ~= 0, "input allocation failed")
write_bytes(memory, input_ptr, jpeg_bytes)
assert(wasm.libjpeg_turbo_host_load(input_ptr, #jpeg_bytes) == 1, "host load failed")
assert(wasm.libjpeg_turbo_host_decode() == 1, "decode failed")

local width = wasm.libjpeg_turbo_host_get_width()
local height = wasm.libjpeg_turbo_host_get_height()
local components = wasm.libjpeg_turbo_host_get_components()
local rgb_ptr = wasm.libjpeg_turbo_host_get_rgb_ptr()
local rgb_size = wasm.libjpeg_turbo_host_get_rgb_size()
local rgb_bytes = read_bytes(memory, rgb_ptr, rgb_size)
local output_path = output_dir .. "/" .. output_base .. ".ppm"

write_file(output_path, ppm_bytes(width, height, rgb_bytes))

print(("Input: %s"):format(input_jpeg_path))
print(("Output: %s"):format(output_path))
print(("Width: %d"):format(width))
print(("Height: %d"):format(height))
print(("Components: %d"):format(components))
print(("RGB Size: %d"):format(rgb_size))
