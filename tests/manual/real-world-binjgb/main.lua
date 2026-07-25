local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local frame_limit = tonumber(arg[2]) or 16

local generated_module_path = script_dir .. "/generated/binjgb.lua"
if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/binjgb_jit.lua"
end

local function i32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end
	return value
end

local wasm_module_loader = assert(dofile(generated_module_path))
local wasm = assert(wasm_module_loader())

print(("Result (DecodeHash): %d"):format(i32(wasm.binjgb_decode_hash(frame_limit))))
print(("Result (Width): %d"):format(wasm.binjgb_probe_width()))
print(("Result (Height): %d"):format(wasm.binjgb_probe_height()))
print(("Result (FrameCount): %d"):format(wasm.binjgb_probe_frame_count(frame_limit)))
print(("Result (FirstFrameHash): %d"):format(i32(wasm.binjgb_probe_first_frame_hash())))
print(("Result (LastFrameHash): %d"):format(i32(wasm.binjgb_probe_last_frame_hash(frame_limit))))
