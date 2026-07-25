local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_png_path = assert(arg[2], "input PNG path is required")
local output_png_path = arg[3]

local generated_module_path = script_dir .. "/generated/lodepng.lua"
if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/lodepng_jit.lua"
end

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

local function derive_output_path(path)
	local stem, extension = path:match("^(.*)(%.[^./\\]+)$")
	if stem then
		return stem .. "_gray" .. extension
	end

	return path .. "_gray.png"
end

local wasm_module_loader = dofile(generated_module_path)
assert(type(wasm_module_loader) == "function", "generated module did not return a loader")
local wasm = wasm_module_loader()
local memory = wasm.memory[1]
assert(type(memory) == "table", "this script currently expects table-backed wasm memory")

local png_bytes = read_file(input_png_path)
local input_ptr = wasm.lodepng_host_alloc(#png_bytes)
assert(input_ptr ~= 0, "input allocation failed")

write_bytes(memory, input_ptr, png_bytes)
do
	local decode_err = wasm.lodepng_host_decode_png(input_ptr, #png_bytes)
	assert(decode_err == 0, ("decode failed (%d)"):format(decode_err))
end

do
	local grayscale_err = wasm.lodepng_host_apply_grayscale()
	assert(grayscale_err == 0, ("grayscale failed (%d)"):format(grayscale_err))
end

do
	local encode_err = wasm.lodepng_host_encode_decoded()
	assert(encode_err == 0, ("encode failed (%d)"):format(encode_err))
end

local encoded_ptr = wasm.lodepng_host_encoded_ptr()
local encoded_size = wasm.lodepng_host_encoded_size()
local encoded_bytes = read_bytes(memory, encoded_ptr, encoded_size)

output_png_path = output_png_path or derive_output_path(input_png_path)
write_file(output_png_path, encoded_bytes)

print(("Input: %s"):format(input_png_path))
print(("Output: %s"):format(output_png_path))
print(("Width: %d"):format(wasm.lodepng_host_width()))
print(("Height: %d"):format(wasm.lodepng_host_height()))
print(("Decoded Size: %d"):format(wasm.lodepng_host_decoded_size()))
print(("Encoded Size: %d"):format(encoded_size))
