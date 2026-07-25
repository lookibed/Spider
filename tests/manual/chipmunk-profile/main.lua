local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local generated_module_path = script_dir .. "/generated/chipmunk_profile.lua"

if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/chipmunk_profile_jit.lua"
end

local function to_signed32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end

	return value
end

local memory_iterations = tonumber(arg[2] or "400")
local math_iterations = tonumber(arg[3] or "400")
local branch_iterations = tonumber(arg[4] or "400")
local scene_iterations = tonumber(arg[5] or "120")

local wasm_module_loader = dofile(generated_module_path)
local wasm = wasm_module_loader()

print(("Memory: %d"):format(to_signed32(wasm.profile_memory_walk(memory_iterations))))
print(("Math: %d"):format(to_signed32(wasm.profile_math_shim(math_iterations))))
print(("Branch: %d"):format(to_signed32(wasm.profile_branch_state(branch_iterations))))
print(("Freefall: %d"):format(to_signed32(wasm.profile_space_freefall(scene_iterations))))
print(("Collision: %d"):format(to_signed32(wasm.profile_space_collision(scene_iterations))))
print(("Full: %d"):format(to_signed32(wasm.profile_space_full(scene_iterations))))
