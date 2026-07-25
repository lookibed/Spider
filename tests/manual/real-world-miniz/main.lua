local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local generated_module_path = script_dir .. "/generated/miniz.lua"

local level = tonumber(arg[1] or "6")

local wasm_module_loader = dofile(generated_module_path)
local wasm = wasm_module_loader()

print(("Result (Hash): %d"):format(wasm.miniz_roundtrip_hash(level)))
print(("Result (Size): %d"):format(wasm.miniz_probe_compressed_size(level)))
print(("Result (CRC32): %d"):format(wasm.miniz_probe_crc32()))
print(("Result (Adler32): %d"):format(wasm.miniz_probe_adler32()))
print(("Result (Fold): %d"):format(wasm.miniz_probe_fold_hash()))
