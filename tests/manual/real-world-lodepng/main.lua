local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local variant = tonumber(arg[2] or "0")
local generated_module_path = script_dir .. "/generated/lodepng.lua"

if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/lodepng_jit.lua"
end

local wasm_module_loader = dofile(generated_module_path)
local wasm = wasm_module_loader()

local function to_signed32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end

	return value
end

print(("Result (Roundtrip): %d"):format(to_signed32(wasm.lodepng_roundtrip_hash(variant))))
print(("Result (EncodedSize): %d"):format(to_signed32(wasm.lodepng_probe_encoded_size(variant))))
print(("Result (DecodeHash): %d"):format(to_signed32(wasm.lodepng_probe_decode_hash(variant))))
print(("Result (InputHash): %d"):format(to_signed32(wasm.lodepng_probe_input_hash(variant))))
print(("Result (PngHash): %d"):format(to_signed32(wasm.lodepng_probe_png_hash(variant))))
