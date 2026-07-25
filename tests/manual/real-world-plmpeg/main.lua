local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local frame_limit = tonumber(arg[2] or "8")
local generated_module_path = script_dir .. "/generated/plmpeg.lua"

if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/plmpeg_jit.lua"
end

local wasm_module_loader = dofile(generated_module_path)

local function to_signed32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end

	return value
end

local function with_wasm(callback)
	local wasm = wasm_module_loader()
	return callback(wasm)
end

print(("Result (DecodeHash): %d"):format(to_signed32(with_wasm(function(wasm)
	return wasm.plmpeg_decode_hash(frame_limit)
end))))
print(("Result (Width): %d"):format(to_signed32(with_wasm(function(wasm)
	return wasm.plmpeg_probe_width()
end))))
print(("Result (Height): %d"):format(to_signed32(with_wasm(function(wasm)
	return wasm.plmpeg_probe_height()
end))))
print(("Result (FrameCount): %d"):format(to_signed32(with_wasm(function(wasm)
	return wasm.plmpeg_probe_frame_count(frame_limit)
end))))
print(("Result (FirstFrameHash): %d"):format(to_signed32(with_wasm(function(wasm)
	return wasm.plmpeg_probe_first_frame_hash()
end))))
print(("Result (LastFrameHash): %d"):format(to_signed32(with_wasm(function(wasm)
	return wasm.plmpeg_probe_last_frame_hash(frame_limit)
end))))
