local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local iterations = tonumber(arg[2] or "600")
local generated_module_path = script_dir .. "/generated/chipmunk.lua"

if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/chipmunk_jit.lua"
end

local wasm_module_loader = dofile(generated_module_path)
local wasm = wasm_module_loader()

local function to_signed32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end

	return value
end

print(("Result (Hash): %d"):format(to_signed32(wasm.chipmunk_hash_scene(iterations))))
print(("Result (Variant): %d"):format(to_signed32(wasm.chipmunk_hash_scene_variant(iterations))))
print(("Probe (Body0X): %d"):format(to_signed32(wasm.chipmunk_probe_body_x(0, iterations))))
print(("Probe (Body1Y): %d"):format(to_signed32(wasm.chipmunk_probe_body_y(1, iterations))))
print(("Probe (Body2Angle): %d"):format(to_signed32(wasm.chipmunk_probe_angle(2, iterations))))
