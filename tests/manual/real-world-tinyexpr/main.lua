local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local generated_module_path = script_dir .. "/generated/tinyexpr.lua"

local iterations = tonumber(arg[1] or "256")

local wasm_module_loader = dofile(generated_module_path)
local wasm = wasm_module_loader()

print(("Result (Hash): %d"):format(wasm.tinyexpr_hash(iterations)))
print(("Result (Error): %d"):format(wasm.tinyexpr_error_code()))
