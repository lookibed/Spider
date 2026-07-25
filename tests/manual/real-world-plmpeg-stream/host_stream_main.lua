local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_mpg_path = arg[2] or (script_dir .. "/fixtures/sample.m1v")
local max_frames = tonumber(arg[3]) or 240
local generated_module_path = script_dir .. "/generated/plmpeg.lua"

if target == "lua-jit" then
	error("host_stream_main.lua currently targets lua-no-ffi only")
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

local function write_frame(output_dir, output_base, frame_index, width, height, rgb_bytes)
	local path = output_dir .. "/" .. output_base .. ("_stream_frame%03d.ppm"):format(frame_index)
	write_file(path, ppm_bytes(width, height, rgb_bytes))
	return path
end

local wasm_module_loader = dofile(generated_module_path)
assert(type(wasm_module_loader) == "function", "generated module did not return a loader")
local wasm = wasm_module_loader()
local memory = wasm.memory[1]
local mpg_bytes = read_file(input_mpg_path)
local output_dir = script_dir .. "/generated/frames"
local output_base = basename_without_extension(input_mpg_path)
local input_ptr = wasm.plmpeg_host_alloc(#mpg_bytes)

ensure_directory(output_dir)

assert(max_frames > 0, "max_frames should be positive")
assert(input_ptr ~= 0, "input allocation failed")
write_bytes(memory, input_ptr, mpg_bytes)
assert(wasm.plmpeg_host_load(input_ptr, #mpg_bytes) == 1, "host load failed")
assert(wasm.plmpeg_host_stream_begin() == 1, "stream begin failed")

print(("Input: %s"):format(input_mpg_path))

local decoded_frames = 0
local first_width = 0
local first_height = 0
local first_rgb_size = 0

while decoded_frames < max_frames do
	if wasm.plmpeg_host_stream_decode_next() ~= 1 then
		break
	end

	local frame_index = wasm.plmpeg_host_stream_get_frame_index()
	local width = wasm.plmpeg_host_get_width()
	local height = wasm.plmpeg_host_get_height()
	local rgb_ptr = wasm.plmpeg_host_get_rgb_ptr()
	local rgb_size = wasm.plmpeg_host_get_rgb_size()
	local rgb_bytes = read_bytes(memory, rgb_ptr, rgb_size)
	local path = write_frame(output_dir, output_base, frame_index, width, height, rgb_bytes)

	if decoded_frames == 0 then
		first_width = width
		first_height = height
		first_rgb_size = rgb_size
	end

	print(("Frame %d: %s"):format(frame_index, path))
	decoded_frames = decoded_frames + 1
end

wasm.plmpeg_host_stream_end()

assert(decoded_frames > 0, "no frames decoded in stream mode")
print(("Decoded Frames: %d"):format(decoded_frames))
print(("Width: %d"):format(first_width))
print(("Height: %d"):format(first_height))
print(("RGB Size: %d"):format(first_rgb_size))
