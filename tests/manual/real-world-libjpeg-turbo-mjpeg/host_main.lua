local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_mjpeg_path = arg[2] or (script_dir .. "/fixtures/sample.mjpg")
local mode = arg[3]
local custom_frame_index = mode == "--frame" and tonumber(arg[4]) or nil
local all_frames_limit = mode == "--all-frames" and tonumber(arg[4]) or nil
local generated_module_path = script_dir .. "/generated/libjpeg_turbo_mjpeg.lua"

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

local function decode_frame(wasm, memory, mjpeg_bytes, frame_index)
	assert(wasm.libjpeg_turbo_mjpeg_host_reset() == 1, "host reset failed")

	local input_ptr = wasm.libjpeg_turbo_mjpeg_host_alloc(#mjpeg_bytes)
	assert(input_ptr ~= 0, "input allocation failed")
	write_bytes(memory, input_ptr, mjpeg_bytes)
	assert(wasm.libjpeg_turbo_mjpeg_host_load(input_ptr, #mjpeg_bytes) == 1, "host load failed")
	assert(wasm.libjpeg_turbo_mjpeg_host_decode_frame(frame_index) == 1, ("decode frame %d failed"):format(frame_index))

	local width = wasm.libjpeg_turbo_mjpeg_host_get_width()
	local height = wasm.libjpeg_turbo_mjpeg_host_get_height()
	local components = wasm.libjpeg_turbo_mjpeg_host_get_components()
	local rgb_ptr = wasm.libjpeg_turbo_mjpeg_host_get_rgb_ptr()
	local rgb_size = wasm.libjpeg_turbo_mjpeg_host_get_rgb_size()
	local rgb_bytes = read_bytes(memory, rgb_ptr, rgb_size)

	return {
		frame_index = frame_index,
		width = width,
		height = height,
		components = components,
		rgb_size = rgb_size,
		rgb_bytes = rgb_bytes,
	}
end

local function decode_secondary_frame(wasm, memory, mjpeg_bytes, preferred_index)
	local index = preferred_index
	while index >= 1 do
		local ok, frame = pcall(function()
			return decode_frame(wasm, memory, mjpeg_bytes, index)
		end)
		if ok then
			return frame
		end
		index = index - 1
	end
	return nil
end

local function write_frame(output_dir, output_base, frame)
	local path = output_dir .. "/" .. output_base .. ("_frame%03d.ppm"):format(frame.frame_index)
	write_file(path, ppm_bytes(frame.width, frame.height, frame.rgb_bytes))
	return path
end

local function decode_all_frames(wasm, memory, mjpeg_bytes, max_frames, output_dir, output_base)
	local decoded = 0
	local width = 0
	local height = 0
	local components = 0
	local rgb_size = 0
	local index = 0

	while index < max_frames do
		local ok, frame = pcall(function()
			return decode_frame(wasm, memory, mjpeg_bytes, index)
		end)
		if not ok then
			break
		end

		write_frame(output_dir, output_base, frame)
		decoded = decoded + 1
		width = frame.width
		height = frame.height
		components = frame.components
		rgb_size = frame.rgb_size
		index = index + 1
	end

	return {
		decoded = decoded,
		width = width,
		height = height,
		components = components,
		rgb_size = rgb_size,
	}
end

local wasm_module_loader = assert(dofile(generated_module_path))
local wasm = assert(wasm_module_loader())
local memory = wasm.memory[1]
local mjpeg_bytes = read_file(input_mjpeg_path)
local output_dir = script_dir .. "/generated/frames"
local output_base = basename_without_extension(input_mjpeg_path)

ensure_directory(output_dir)

print(("Input: %s"):format(input_mjpeg_path))

if mode == "--frame" then
	assert(custom_frame_index and custom_frame_index >= 0, "for --frame pass non-negative index as 4th argument")
	local frame = decode_frame(wasm, memory, mjpeg_bytes, custom_frame_index)
	local path = write_frame(output_dir, output_base, frame)
	print(("Frame %d: %s"):format(frame.frame_index, path))
	print(("Width: %d"):format(frame.width))
	print(("Height: %d"):format(frame.height))
	print(("Components: %d"):format(frame.components))
	print(("RGB Size: %d"):format(frame.rgb_size))
elseif mode == "--all-frames" then
	assert((not all_frames_limit) or all_frames_limit > 0, "for --all-frames pass a positive max count as 4th argument")
	local result = decode_all_frames(wasm, memory, mjpeg_bytes, all_frames_limit or 1000000, output_dir, output_base)
	assert(result.decoded > 0, "no frames decoded")
	print(("Decoded Frames: %d"):format(result.decoded))
	print(("Width: %d"):format(result.width))
	print(("Height: %d"):format(result.height))
	print(("Components: %d"):format(result.components))
	print(("RGB Size: %d"):format(result.rgb_size))
else
	local first = decode_frame(wasm, memory, mjpeg_bytes, 0)
	local first_path = write_frame(output_dir, output_base, first)
	print(("Frame 0: %s"):format(first_path))
	print(("Width: %d"):format(first.width))
	print(("Height: %d"):format(first.height))
	print(("Components: %d"):format(first.components))
	print(("RGB Size: %d"):format(first.rgb_size))

	local secondary = decode_secondary_frame(wasm, memory, mjpeg_bytes, 7)
	if secondary then
		local secondary_path = write_frame(output_dir, output_base, secondary)
		print(("Frame %d: %s"):format(secondary.frame_index, secondary_path))
	else
		print("Frame 7..1: unavailable")
	end
end
