local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_glb_path = arg[2] or (script_dir .. "/fixtures/RiggedSimple.glb")
local mode = arg[3] or "--default"
local mode_arg = arg[4]
local generated_module_path = script_dir .. "/generated/cgltf.lua"

if target == "lua-jit" then
	error("host_main.lua currently targets lua-no-ffi only")
end

local function read_file(path)
	local file = assert(io.open(path, "rb"))
	local data = assert(file:read("*a"))
	assert(file:close())
	return data
end

local function write_bytes(memory, offset, bytes)
	for index = 1, #bytes do
		memory[offset + index] = string.byte(bytes, index)
	end
end

local function read_string(memory, offset, length)
	local out = {}
	for index = 1, length do
		out[index] = string.char(memory[offset + index])
	end
	return table.concat(out)
end

local function read_float(memory, offset)
	local b1 = memory[offset + 1]
	local b2 = memory[offset + 2]
	local b3 = memory[offset + 3]
	local b4 = memory[offset + 4]
	local bits = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
	-- Convert f32 bits to Lua number
	local sign = 1
	local exponent = 0
	local mantissa = 0
	if bits >= 2147483648 then
		sign = -1
		bits = bits - 2147483648
	end
	exponent = math.floor(bits / 8388608)
	mantissa = bits % 8388608
	if exponent == 0 then
		return sign * math.ldexp(mantissa, -149)
	elseif exponent == 255 then
		return mantissa == 0 and (sign * math.huge) or (0 / 0)
	else
		return sign * math.ldexp(1 + mantissa / 8388608, exponent - 127)
	end
end

local function print_node(wasm, memory, index)
	local name_len = wasm.cgltf_host_get_node_name_len(index)
	local name = ""
	if name_len > 0 then
		local buf = wasm.cgltf_host_alloc(name_len + 1)
		wasm.cgltf_host_get_node_name(index, buf, name_len + 1)
		name = read_string(memory, buf, name_len)
	end

	local has_mesh = wasm.cgltf_host_get_node_has_mesh(index) == 1
	local has_skin = wasm.cgltf_host_get_node_has_skin(index) == 1
	local flags = ""
	if has_mesh then flags = flags .. " MESH" end
	if has_skin then flags = flags .. " SKIN" end
	print(("  Node %d: %s%s"):format(index, name, flags))
end

local function print_animation(wasm, memory, index)
	local name_len = wasm.cgltf_host_get_animation_name_len(index)
	local name = ""
	if name_len > 0 then
		local buf = wasm.cgltf_host_alloc(name_len + 1)
		wasm.cgltf_host_get_animation_name(index, buf, name_len + 1)
		name = read_string(memory, buf, name_len)
	end
	local channels = wasm.cgltf_host_get_animation_channel_count(index)
	print(("  Animation %d: %s (%d channels)"):format(index, name, channels))
end

local wasm_module_loader = dofile(generated_module_path)
assert(type(wasm_module_loader) == "function", "generated module did not return a loader")
local wasm = wasm_module_loader()
local memory = wasm.memory[1]
local glb_bytes = read_file(input_glb_path)

print(("Input: %s (%d bytes)"):format(input_glb_path, #glb_bytes))

local buf = wasm.cgltf_host_alloc(#glb_bytes)
assert(buf ~= 0, "allocation failed")
write_bytes(memory, buf, glb_bytes)
assert(wasm.cgltf_host_load(buf, #glb_bytes) == 1, "host load failed")
assert(wasm.cgltf_host_parse() == 1, "host parse failed")

local mesh_count = wasm.cgltf_host_get_mesh_count()
local anim_count = wasm.cgltf_host_get_animation_count()
local node_count = wasm.cgltf_host_get_node_count()
local skin_count = wasm.cgltf_host_get_skin_count()

print(("Meshes: %d"):format(mesh_count))
print(("Animations: %d"):format(anim_count))
print(("Nodes: %d"):format(node_count))
print(("Skins: %d"):format(skin_count))

for i = 0, node_count - 1 do
	print_node(wasm, memory, i)
end

for i = 0, anim_count - 1 do
	print_animation(wasm, memory, i)
end

wasm.cgltf_host_free()
print("Done.")
