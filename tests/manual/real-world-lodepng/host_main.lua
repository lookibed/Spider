local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_png_path = arg[2] or (script_dir .. "/fixtures/host_input.png")

local generated_module_path = script_dir .. "/generated/lodepng.lua"
if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/lodepng_jit.lua"
end
local bitlib = rawget(_G, "bit32") or rawget(_G, "bit")
assert(bitlib and bitlib.bxor, "bit library is required")

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

local function fold_bytes(bytes)
	local hash = 0x811C9DC5
	for index = 1, #bytes do
		hash = bitlib.bxor(hash, string.byte(bytes, index))
		hash = (hash * 16777619) % 4294967296
		hash = ((hash * 32) + math.floor(hash / 134217728)) % 4294967296
	end
	return hash
end

local function to_signed32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end

	return value
end

local function run_pass(wasm, memory, png_bytes, apply_overlay)
	wasm.lodepng_host_reset()

	local input_ptr = wasm.lodepng_host_alloc(#png_bytes)
	assert(input_ptr ~= 0, "input allocation failed")

	write_bytes(memory, input_ptr, png_bytes)
	do
		local decode_err = wasm.lodepng_host_decode_png(input_ptr, #png_bytes)
		assert(decode_err == 0, ("decode failed (%d)"):format(decode_err))
	end

	local width = wasm.lodepng_host_width()
	local height = wasm.lodepng_host_height()
	local decoded_size = wasm.lodepng_host_decoded_size()
	local decoded_ptr = wasm.lodepng_host_decoded_ptr()

	if apply_overlay then
		local overlay_err = wasm.lodepng_host_apply_debug_overlay()
		assert(overlay_err == 0, ("overlay failed (%d)"):format(overlay_err))
	end

	do
		local encode_err = wasm.lodepng_host_encode_decoded()
		assert(encode_err == 0, ("encode failed (%d)"):format(encode_err))
	end

	local encoded_ptr = wasm.lodepng_host_encoded_ptr()
	local encoded_size = wasm.lodepng_host_encoded_size()

	return {
		width = width,
		height = height,
		decoded_size = decoded_size,
		decoded_ptr = decoded_ptr,
		decoded_bytes = read_bytes(memory, decoded_ptr, decoded_size),
		encoded_ptr = encoded_ptr,
		encoded_size = encoded_size,
		encoded_bytes = read_bytes(memory, encoded_ptr, encoded_size),
	}
end

local function decode_only(wasm, memory, png_bytes)
	wasm.lodepng_host_reset()

	local input_ptr = wasm.lodepng_host_alloc(#png_bytes)
	assert(input_ptr ~= 0, "input allocation failed")

	write_bytes(memory, input_ptr, png_bytes)
	do
		local decode_err = wasm.lodepng_host_decode_png(input_ptr, #png_bytes)
		assert(decode_err == 0, ("decode failed (%d)"):format(decode_err))
	end

	local decoded_size = wasm.lodepng_host_decoded_size()
	local decoded_ptr = wasm.lodepng_host_decoded_ptr()

	return {
		width = wasm.lodepng_host_width(),
		height = wasm.lodepng_host_height(),
		decoded_size = decoded_size,
		decoded_ptr = decoded_ptr,
		decoded_bytes = read_bytes(memory, decoded_ptr, decoded_size),
	}
end

local wasm_module_loader = dofile(generated_module_path)
assert(type(wasm_module_loader) == "function", "generated module did not return a loader")
local wasm = wasm_module_loader()
local memory = wasm.memory[1]
local png_bytes = read_file(input_png_path)

local input_decode = run_pass(wasm, memory, png_bytes, false)
local roundtrip = run_pass(wasm, memory, png_bytes, false)
local roundtrip_decode = decode_only(wasm, memory, roundtrip.encoded_bytes)
local overlay = run_pass(wasm, memory, png_bytes, true)

local output_dir = script_dir .. "/generated"
local roundtrip_path = output_dir .. "/host_roundtrip.png"
local overlay_path = output_dir .. "/host_overlay.png"

write_file(roundtrip_path, roundtrip.encoded_bytes)
write_file(overlay_path, overlay.encoded_bytes)

local input_decoded_hash = fold_bytes(input_decode.decoded_bytes)
local roundtrip_decoded_hash = fold_bytes(roundtrip_decode.decoded_bytes)
local overlay_decoded_hash = fold_bytes(overlay.decoded_bytes)
local roundtrip_png_hash = fold_bytes(roundtrip.encoded_bytes)
local overlay_png_hash = fold_bytes(overlay.encoded_bytes)

print(("Input: %s"):format(input_png_path))
print(("Roundtrip PNG: %s"):format(roundtrip_path))
print(("Overlay PNG: %s"):format(overlay_path))
print(("Decoded Width: %d"):format(input_decode.width))
print(("Decoded Height: %d"):format(input_decode.height))
print(("Decoded Size: %d"):format(input_decode.decoded_size))
print(("Input Decoded Hash: %d"):format(to_signed32(input_decoded_hash)))
print(("Roundtrip Decoded Hash: %d"):format(to_signed32(roundtrip_decoded_hash)))
print(("Overlay Decoded Hash: %d"):format(to_signed32(overlay_decoded_hash)))
print(("Roundtrip PNG Hash: %d"):format(to_signed32(roundtrip_png_hash)))
print(("Overlay PNG Hash: %d"):format(to_signed32(overlay_png_hash)))
print(("Roundtrip Size: %d"):format(roundtrip.encoded_size))
print(("Overlay Size: %d"):format(overlay.encoded_size))
print(("Roundtrip Matches Input: %d"):format((input_decode.decoded_bytes == roundtrip_decode.decoded_bytes) and 1 or 0))
