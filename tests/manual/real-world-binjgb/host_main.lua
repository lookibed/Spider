local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_rom_path = arg[2] or (script_dir .. "/fixtures/cgb-acid2.gbc")
local generated_module_path = script_dir .. "/generated/binjgb.lua"

local PRESET_IDS = {
	none = 0,
	acid2 = 1,
	["tetris-start"] = 2,
	["tetris-start-then-a"] = 3,
}

local mode = nil
local custom_frame_index = nil
local all_frames_limit = nil
local preset_name = nil
local buttons_mask_spec = nil
local script_spec = nil

if target == "lua-jit" then
	error("host_main.lua currently targets lua-no-ffi only")
end

do
	local index = 3
	while index <= #arg do
		local value = arg[index]
		if value == "--frame" then
			mode = "--frame"
			custom_frame_index = tonumber(arg[index + 1])
			index = index + 2
		elseif value == "--all-frames" then
			mode = "--all-frames"
			if arg[index + 1] and not tostring(arg[index + 1]):match("^%-%-") then
				all_frames_limit = tonumber(arg[index + 1])
				index = index + 2
			else
				all_frames_limit = nil
				index = index + 1
			end
		elseif value == "--preset" then
			preset_name = arg[index + 1]
			index = index + 2
		elseif value == "--buttons-mask" then
			buttons_mask_spec = arg[index + 1]
			index = index + 2
		elseif value == "--script" then
			script_spec = arg[index + 1]
			index = index + 2
		else
			error(("unknown argument: %s"):format(tostring(value)))
		end
	end
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

local function split_tokens(value, pattern)
	local out = {}
	for token in string.gmatch(value, pattern) do
		if token ~= "" then
			table.insert(out, token)
		end
	end
	return out
end

local BUTTON_BITS = {
	A = 1,
	B = 2,
	SELECT = 4,
	START = 8,
	RIGHT = 16,
	LEFT = 32,
	UP = 64,
	DOWN = 128,
}

local function parse_buttons_mask(spec)
	if not spec or spec == "" then
		return 0
	end

	local numeric = tonumber(spec)
	if numeric then
		if numeric < 0 then
			error("buttons mask must be non-negative")
		end
		return numeric % 256
	end

	local mask = 0
	local normalized = spec:upper():gsub("%s+", "")
	local tokens = split_tokens(normalized, "([^,+|]+)")
	for _, token in ipairs(tokens) do
		local bit = BUTTON_BITS[token]
		if not bit then
			error(("unknown button token in mask: %s"):format(token))
		end
		mask = mask + bit
	end

	return mask % 256
end

local function parse_button_script(spec)
	local entries = {}
	if not spec or spec == "" then
		return entries
	end

	local chunks = split_tokens(spec, "([^;]+)")
	for _, raw_chunk in ipairs(chunks) do
		local chunk = raw_chunk:gsub("%s+", "")
		local range, mask_spec = chunk:match("^([^:]+):(.+)$")
		if not range or not mask_spec then
			error(("invalid script entry '%s' (use start-end:MASK or frame:MASK)"):format(raw_chunk))
		end

		local start_s, end_s = range:match("^(%-?%d+)%-(%-?%d+)$")
		if not start_s then
			start_s = range:match("^(%-?%d+)$")
			end_s = start_s
		end
		if not start_s or not end_s then
			error(("invalid script frame range '%s'"):format(range))
		end

		local start_frame = tonumber(start_s)
		local end_frame = tonumber(end_s)
		if start_frame < 0 or end_frame < start_frame then
			error(("invalid script range '%s'"):format(range))
		end

		table.insert(entries, {
			start_frame = start_frame,
			end_frame = end_frame,
			mask = parse_buttons_mask(mask_spec),
		})
	end

	return entries
end

local function extend_with_tetris_preset_script(entries, preset)
	if preset ~= "tetris-start" and preset ~= "tetris-start-then-a" then
		return entries
	end

	table.insert(entries, { start_frame = 520, end_frame = 620, mask = BUTTON_BITS.START })
	table.insert(entries, { start_frame = 700, end_frame = 710, mask = BUTTON_BITS.START })
	table.insert(entries, { start_frame = 920, end_frame = 930, mask = BUTTON_BITS.START })
	if preset == "tetris-start-then-a" then
		table.insert(entries, { start_frame = 960, end_frame = 965, mask = BUTTON_BITS.A })
	end
	return entries
end

local function select_default_preset(path)
	local basename = basename_without_extension(path):lower()
	if basename == "cgb-acid2" then
		return "acid2", nil
	end
	if basename:match("^tetris") then
		return "tetris-start", nil
	end
	return "none", "auto-detected no startup preset; use --preset for ROM-specific menu flows"
end

local function rgb555_bytes_to_rgb24(bytes)
	local out = {}
	local out_index = 1
	local index = 1

	while index <= #bytes do
		local lo = string.byte(bytes, index)
		local hi = string.byte(bytes, index + 1)
		local pixel = lo + hi * 256
		local r5 = math.floor(pixel / 1024) % 32
		local g5 = math.floor(pixel / 32) % 32
		local b5 = pixel % 32
		out[out_index] = string.char(r5 * 8 + math.floor(r5 / 4))
		out[out_index + 1] = string.char(g5 * 8 + math.floor(g5 / 4))
		out[out_index + 2] = string.char(b5 * 8 + math.floor(b5 / 4))
		out_index = out_index + 3
		index = index + 2
	end

	return table.concat(out)
end

local function ppm_bytes(width, height, rgb_bytes)
	local header = ("P6\n%d %d\n255\n"):format(width, height)
	return header .. rgb_bytes
end

local function decode_frame(wasm, memory, rom_bytes, frame_index, selected_preset, buttons_mask, script_entries)
	assert(wasm.binjgb_host_reset() == 1, "host reset failed")
	local input_ptr = wasm.binjgb_host_alloc(#rom_bytes)
	assert(input_ptr ~= 0, "input allocation failed")
	write_bytes(memory, input_ptr, rom_bytes)
	assert(wasm.binjgb_host_load_rom(input_ptr, #rom_bytes) == 1, "host load failed")
	local preset_id = PRESET_IDS[selected_preset]
	if wasm.binjgb_host_set_input_preset then
		assert(wasm.binjgb_host_set_input_preset(preset_id) == 1, "host preset set failed")
		assert(wasm.binjgb_host_set_buttons(buttons_mask) == 1, "host manual buttons set failed")
	else
		assert(wasm.binjgb_host_set_buttons(preset_id * 256 + buttons_mask) == 1, "host preset fallback set failed")
	end
	if wasm.binjgb_host_clear_button_script and wasm.binjgb_host_add_button_script then
		assert(wasm.binjgb_host_clear_button_script() == 1, "host script clear failed")
		for _, entry in ipairs(script_entries) do
			assert(wasm.binjgb_host_add_button_script(entry.start_frame, entry.end_frame, entry.mask) == 1, "host script add failed")
		end
	end
	assert(wasm.binjgb_host_run_frame(frame_index) == 1, ("decode frame %d failed"):format(frame_index))

	local width = wasm.binjgb_host_get_width()
	local height = wasm.binjgb_host_get_height()
	local framebuffer_ptr = wasm.binjgb_host_get_framebuffer_ptr()
	local framebuffer_size = wasm.binjgb_host_get_framebuffer_size()
	local framebuffer_bytes = read_bytes(memory, framebuffer_ptr, framebuffer_size)
	local rgb_bytes = rgb555_bytes_to_rgb24(framebuffer_bytes)

	return {
		frame_index = frame_index,
		width = width,
		height = height,
		framebuffer_size = framebuffer_size,
		rgb_bytes = rgb_bytes,
	}
end

local function write_frame(output_dir, output_base, frame)
	local path = output_dir .. "/" .. output_base .. ("_frame%03d.ppm"):format(frame.frame_index)
	write_file(path, ppm_bytes(frame.width, frame.height, frame.rgb_bytes))
	return path
end

local function decode_all_frames(wasm, memory, rom_bytes, max_frames, output_dir, output_base, selected_preset, buttons_mask, script_entries)
	local decoded = 0
	local width = 0
	local height = 0
	local framebuffer_size = 0
	local index = 0

	while index < max_frames do
		local ok, frame = pcall(function()
			return decode_frame(wasm, memory, rom_bytes, index, selected_preset, buttons_mask, script_entries)
		end)
		if not ok then
			break
		end

		write_frame(output_dir, output_base, frame)
		decoded = decoded + 1
		width = frame.width
		height = frame.height
		framebuffer_size = frame.framebuffer_size
		index = index + 1
	end

	return {
		decoded = decoded,
		width = width,
		height = height,
		framebuffer_size = framebuffer_size,
	}
end

local wasm_module_loader = assert(dofile(generated_module_path))
local wasm = assert(wasm_module_loader())
local memory = wasm.memory[1]
local rom_bytes = read_file(input_rom_path)
local output_dir = script_dir .. "/generated/frames"
local output_base = basename_without_extension(input_rom_path)
local selected_preset, preset_note = preset_name or select_default_preset(input_rom_path)
local default_late_frame = (selected_preset == "tetris-start" or selected_preset == "tetris-start-then-a") and 900 or 15
local buttons_mask = parse_buttons_mask(buttons_mask_spec)
local script_entries = parse_button_script(script_spec)
if (not script_spec or script_spec == "") then
	script_entries = extend_with_tetris_preset_script(script_entries, selected_preset)
end

assert(PRESET_IDS[selected_preset], ("unknown preset: %s"):format(tostring(selected_preset)))

ensure_directory(output_dir)

print(("Input: %s"):format(input_rom_path))
print(("Preset: %s"):format(selected_preset))
print(("Buttons Mask: %d"):format(buttons_mask))
if #script_entries > 0 then
	print(("Script Entries: %d"):format(#script_entries))
end
if preset_note then
	print(("Note: %s"):format(preset_note))
end

if mode == "--frame" then
	assert(custom_frame_index and custom_frame_index >= 0, "for --frame pass non-negative index as 4th argument")
	local frame = decode_frame(wasm, memory, rom_bytes, custom_frame_index, selected_preset, buttons_mask, script_entries)
	local path = write_frame(output_dir, output_base, frame)
	print(("Frame %d: %s"):format(frame.frame_index, path))
	print(("Width: %d"):format(frame.width))
	print(("Height: %d"):format(frame.height))
	print(("Framebuffer Size: %d"):format(frame.framebuffer_size))
elseif mode == "--all-frames" then
	assert((not all_frames_limit) or all_frames_limit > 0, "for --all-frames pass a positive max count as 4th argument")
	local result = decode_all_frames(wasm, memory, rom_bytes, all_frames_limit or 1000000, output_dir, output_base, selected_preset, buttons_mask, script_entries)
	assert(result.decoded > 0, "no frames decoded")
	print(("Decoded Frames: %d"):format(result.decoded))
	print(("Width: %d"):format(result.width))
	print(("Height: %d"):format(result.height))
	print(("Framebuffer Size: %d"):format(result.framebuffer_size))
else
	local first = decode_frame(wasm, memory, rom_bytes, 0, selected_preset, buttons_mask, script_entries)
	local first_path = write_frame(output_dir, output_base, first)
	print(("Frame 0: %s"):format(first_path))
	print(("Width: %d"):format(first.width))
	print(("Height: %d"):format(first.height))
	print(("Framebuffer Size: %d"):format(first.framebuffer_size))

	local later = decode_frame(wasm, memory, rom_bytes, default_late_frame, selected_preset, buttons_mask, script_entries)
	local later_path = write_frame(output_dir, output_base, later)
	print(("Frame %d: %s"):format(later.frame_index, later_path))
end
