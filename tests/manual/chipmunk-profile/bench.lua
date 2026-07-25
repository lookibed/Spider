local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."

local target = arg[1] or "lua-no-ffi"
local module_base = arg[2] or "memory_walk"
local export_name = arg[3] or "profile_memory_walk"
local iterations = tonumber(arg[4] or "400")

local generated_module_path = script_dir .. "/generated/" .. module_base .. ".lua"
if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/" .. module_base .. "_jit.lua"
end

local function to_signed32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end

	return value
end

local wasm_module_loader = dofile(generated_module_path)
local wasm = wasm_module_loader()
print(to_signed32(wasm[export_name](iterations)))
