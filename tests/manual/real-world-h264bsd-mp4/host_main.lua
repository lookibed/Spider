local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_mp4_path = arg[2] or (script_dir .. "/fixtures/sample.mp4")
local mode = arg[3]
local custom_frame_index = mode == "--frame" and tonumber(arg[4]) or nil
local all_frames_limit = mode == "--all-frames" and tonumber(arg[4]) or nil
local generated_module_path = script_dir .. "/generated/h264mp4.lua"

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

local function clamp_byte(value)
	if value < 0 then
		return 0
	end

	if value > 255 then
		return 255
	end

	return value
end

local function yuv420_to_rgb_bytes(width, height, y_bytes, u_bytes, v_bytes)
	local rgb = {}
	local uv_width = math.floor(width / 2)
	local rgb_index = 1

	for y = 0, height - 1 do
		local y_row = y * width
		local uv_row = math.floor(y / 2) * uv_width

		for x = 0, width - 1 do
			local y_value = string.byte(y_bytes, y_row + x + 1)
			local uv_index = uv_row + math.floor(x / 2) + 1
			local cb = string.byte(u_bytes, uv_index) - 128
			local cr = string.byte(v_bytes, uv_index) - 128
			local c = y_value
			local r = clamp_byte(math.floor(c + 1.402 * cr + 0.5))
			local g = clamp_byte(math.floor(c - 0.344136 * cb - 0.714136 * cr + 0.5))
			local b = clamp_byte(math.floor(c + 1.772 * cb + 0.5))

			rgb[rgb_index] = string.char(r)
			rgb[rgb_index + 1] = string.char(g)
			rgb[rgb_index + 2] = string.char(b)
			rgb_index = rgb_index + 3
		end
	end

	return table.concat(rgb)
end

local function ppm_bytes(width, height, rgb_bytes)
	local header = ("P6\n%d %d\n255\n"):format(width, height)
	return header .. rgb_bytes
end

local function decode_frame(wasm, memory, mp4_bytes, frame_index)
	assert(wasm.h264mp4_host_reset() == 1, "host reset failed")

	local input_ptr = wasm.h264mp4_host_alloc(#mp4_bytes)
	assert(input_ptr ~= 0, "input allocation failed")
	write_bytes(memory, input_ptr, mp4_bytes)
	assert(wasm.h264mp4_host_load(input_ptr, #mp4_bytes) == 1, "host load failed")
	assert(wasm.h264mp4_host_decode_frame(frame_index) == 1, ("decode frame %d failed"):format(frame_index))

	local width = wasm.h264mp4_host_get_width()
	local height = wasm.h264mp4_host_get_height()
	local y_ptr = wasm.h264mp4_host_get_y_ptr()
	local u_ptr = wasm.h264mp4_host_get_u_ptr()
	local v_ptr = wasm.h264mp4_host_get_v_ptr()
	local y_size = wasm.h264mp4_host_get_y_size()
	local u_size = wasm.h264mp4_host_get_u_size()
	local v_size = wasm.h264mp4_host_get_v_size()
	local y_bytes = read_bytes(memory, y_ptr, y_size)
	local u_bytes = read_bytes(memory, u_ptr, u_size)
	local v_bytes = read_bytes(memory, v_ptr, v_size)
	local rgb_bytes = yuv420_to_rgb_bytes(width, height, y_bytes, u_bytes, v_bytes)

	return {
		frame_index = frame_index,
		width = width,
		height = height,
		y_size = y_size,
		u_size = u_size,
		v_size = v_size,
		rgb_bytes = rgb_bytes,
	}
end

local function decode_secondary_frame(wasm, memory, mp4_bytes, preferred_index)
	local index = preferred_index
	while index >= 1 do
		local ok, frame = pcall(function()
			return decode_frame(wasm, memory, mp4_bytes, index)
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

local function decode_all_frames(wasm, memory, mp4_bytes, max_frames, output_dir, output_base)
	local decoded = 0
	local width = 0
	local height = 0
	local y_size = 0
	local u_size = 0
	local v_size = 0
	local index = 0

	while index < max_frames do
		local ok, frame = pcall(function()
			return decode_frame(wasm, memory, mp4_bytes, index)
		end)
		if not ok then
			break
		end

		write_frame(output_dir, output_base, frame)
		decoded = decoded + 1
		width = frame.width
		height = frame.height
		y_size = frame.y_size
		u_size = frame.u_size
		v_size = frame.v_size
		index = index + 1
	end

	return {
		decoded = decoded,
		width = width,
		height = height,
		y_size = y_size,
		u_size = u_size,
		v_size = v_size,
	}
end

local wasm_module_loader = dofile(generated_module_path)
assert(type(wasm_module_loader) == "function", "generated module did not return a loader")
local wasm = wasm_module_loader()
local memory = wasm.memory[1]
local mp4_bytes = read_file(input_mp4_path)
local output_dir = script_dir .. "/generated/frames"
local output_base = basename_without_extension(input_mp4_path)

ensure_directory(output_dir)

print(("Input: %s"):format(input_mp4_path))

if mode == "--frame" then
	assert(custom_frame_index and custom_frame_index >= 0, "for --frame pass non-negative index as 4th argument")
	local frame = decode_frame(wasm, memory, mp4_bytes, custom_frame_index)
	local path = write_frame(output_dir, output_base, frame)
	print(("Frame %d: %s"):format(frame.frame_index, path))
	print(("Width: %d"):format(frame.width))
	print(("Height: %d"):format(frame.height))
	print(("Y Size: %d"):format(frame.y_size))
	print(("U Size: %d"):format(frame.u_size))
	print(("V Size: %d"):format(frame.v_size))
elseif mode == "--all-frames" then
	assert((not all_frames_limit) or all_frames_limit > 0, "for --all-frames pass a positive max count as 4th argument")
	local result = decode_all_frames(wasm, memory, mp4_bytes, all_frames_limit or 1000000, output_dir, output_base)
	assert(result.decoded > 0, "no frames decoded")
	print(("Decoded Frames: %d"):format(result.decoded))
	print(("Width: %d"):format(result.width))
	print(("Height: %d"):format(result.height))
	print(("Y Size: %d"):format(result.y_size))
	print(("U Size: %d"):format(result.u_size))
	print(("V Size: %d"):format(result.v_size))
else
	local first = decode_frame(wasm, memory, mp4_bytes, 0)
	local first_path = write_frame(output_dir, output_base, first)
	print(("Frame 0: %s"):format(first_path))
	print(("Width: %d"):format(first.width))
	print(("Height: %d"):format(first.height))
	print(("Y Size: %d"):format(first.y_size))
	print(("U Size: %d"):format(first.u_size))
	print(("V Size: %d"):format(first.v_size))

	local secondary = decode_secondary_frame(wasm, memory, mp4_bytes, 7)
	if secondary then
		local secondary_path = write_frame(output_dir, output_base, secondary)
		print(("Frame %d: %s"):format(secondary.frame_index, secondary_path))
	else
		print("Frame 7..1: unavailable")
	end
end
