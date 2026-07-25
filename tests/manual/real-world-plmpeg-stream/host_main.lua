local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_mpg_path = arg[2] or (script_dir .. "/fixtures/sample.m1v")
local mode = arg[3] or "--default"
local mode_arg = arg[4]
local generated_module_path = script_dir .. "/generated/plmpeg.lua"

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

local function decode_frame(wasm, memory, mpg_bytes, frame_index)
	local input_ptr = wasm.plmpeg_host_alloc(#mpg_bytes)
	assert(input_ptr ~= 0, "input allocation failed")
	write_bytes(memory, input_ptr, mpg_bytes)
	assert(wasm.plmpeg_host_load(input_ptr, #mpg_bytes) == 1, "host load failed")
	assert(wasm.plmpeg_host_decode_frame(frame_index) == 1, ("decode frame %d failed"):format(frame_index))

	local width = wasm.plmpeg_host_get_width()
	local height = wasm.plmpeg_host_get_height()
	local rgb_ptr = wasm.plmpeg_host_get_rgb_ptr()
	local rgb_size = wasm.plmpeg_host_get_rgb_size()

	return {
		frame_index = frame_index,
		width = width,
		height = height,
		rgb_size = rgb_size,
		rgb_bytes = read_bytes(memory, rgb_ptr, rgb_size),
	}
end

local function decode_secondary_frame(wasm, memory, mpg_bytes, preferred_index)
	local index = preferred_index
	while index >= 1 do
		local ok, frame = pcall(function()
			return decode_frame(wasm, memory, mpg_bytes, index)
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

local function decode_all_frames(wasm, memory, mpg_bytes, max_frames)
	local frames = {}
	local index = 0

	while index < max_frames do
		local ok, frame = pcall(function()
			return decode_frame(wasm, memory, mpg_bytes, index)
		end)
		if not ok then
			break
		end

		frames[#frames + 1] = frame
		index = index + 1
	end

	return frames
end

local wasm_module_loader = dofile(generated_module_path)
assert(type(wasm_module_loader) == "function", "generated module did not return a loader")
local wasm = wasm_module_loader()
local memory = wasm.memory[1]
local mpg_bytes = read_file(input_mpg_path)
local output_dir = script_dir .. "/generated"
local output_base = basename_without_extension(input_mpg_path)
local custom_frame_index = tonumber(mode_arg)
local all_frames_limit = tonumber(mode_arg) or 240

print(("Input: %s"):format(input_mpg_path))

if mode == "--frame" then
	assert(custom_frame_index and custom_frame_index >= 0, "for --frame pass non-negative index as 4th argument")
	local frame = decode_frame(wasm, memory, mpg_bytes, custom_frame_index)
	local path = write_frame(output_dir, output_base, frame)
	print(("Frame %d: %s"):format(frame.frame_index, path))
	print(("Width: %d"):format(frame.width))
	print(("Height: %d"):format(frame.height))
	print(("RGB Size: %d"):format(frame.rgb_size))
elseif mode == "--all-frames" then
	local frames = decode_all_frames(wasm, memory, mpg_bytes, all_frames_limit)
	assert(#frames > 0, "no frames decoded")
	print(("Decoded Frames: %d"):format(#frames))
	print(("Width: %d"):format(frames[1].width))
	print(("Height: %d"):format(frames[1].height))
	print(("RGB Size: %d"):format(frames[1].rgb_size))
	for index = 1, #frames do
		local frame = frames[index]
		local path = write_frame(output_dir, output_base, frame)
		print(("Frame %d: %s"):format(frame.frame_index, path))
	end
else
	local first = decode_frame(wasm, memory, mpg_bytes, 0)
	local first_path = write_frame(output_dir, output_base, first)
	print(("Frame 0: %s"):format(first_path))
	print(("Width: %d"):format(first.width))
	print(("Height: %d"):format(first.height))
	print(("RGB Size: %d"):format(first.rgb_size))

	local secondary = decode_secondary_frame(wasm, memory, mpg_bytes, 7)
	if secondary then
		local secondary_path = write_frame(output_dir, output_base, secondary)
		print(("Frame %d: %s"):format(secondary.frame_index, secondary_path))
	else
		print("Frame 7..1: unavailable")
	end
end
