local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"

local generated_module_path = script_dir .. "/generated/self_hosting_luanoffi_builder.lua"
if target == "lua-jit" then
	error("main.lua currently targets lua-no-ffi only")
end

local function i32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end
	return value
end

local wasm_module_loader = assert(dofile(generated_module_path))
local wasm = assert(wasm_module_loader())

local case_count = wasm.builder_case_count()
print(("Result (CaseCount): %d"):format(case_count))

for case_id = 0, case_count - 1 do
	print(("Case %d (Locals): %d"):format(case_id, wasm.builder_probe_locals(case_id)))
	print(("Case %d (Stack): %d"):format(case_id, wasm.builder_probe_stack(case_id)))
	print(("Case %d (Exports): %d"):format(case_id, wasm.builder_probe_exports(case_id)))
	print(("Case %d (CodeHash): %d"):format(case_id, i32(wasm.builder_probe_code_hash(case_id))))
	print(("Case %d (TreeHash): %d"):format(case_id, i32(wasm.builder_run_case_hash(case_id))))
end
