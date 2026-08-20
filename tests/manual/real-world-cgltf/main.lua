local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_glb_path = arg[2] or (script_dir .. "/fixtures/RiggedSimple.glb")
local generated_module_path = script_dir .. "/generated/cgltf.lua"

if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/cgltf_jit.lua"
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

local function to_signed32(value)
	if value >= 2147483648 then
		return value - 4294967296
	end
	return value
end

local wasm_module_loader = dofile(generated_module_path)
assert(type(wasm_module_loader) == "function", "generated module did not return a loader")

local glb_bytes = read_file(input_glb_path)
print(("Input: %s (%d bytes)"):format(input_glb_path, #glb_bytes))

local function run(callback)
	local wasm = wasm_module_loader()
	local memory = wasm.memory[1]
	local buf = wasm.cgltf_host_alloc(#glb_bytes)
	assert(buf ~= 0, "allocation failed")
	write_bytes(memory, buf, glb_bytes)
	assert(wasm.cgltf_host_load(buf, #glb_bytes) == 1, "host load failed")
	assert(wasm.cgltf_host_parse() == 1, "host parse failed")

	local hash = wasm.cgltf_compute_hash(buf, #glb_bytes)
	print(("Result (Hash): %d"):format(hash))
	local result = callback(wasm, memory)
	wasm.cgltf_host_free()
	return result
end

run(function(wasm, memory)
print(("Result (MeshCount): %d"):format(wasm.cgltf_host_get_mesh_count()))
print(("Result (AnimationCount): %d"):format(wasm.cgltf_host_get_animation_count()))
print(("Result (NodeCount): %d"):format(wasm.cgltf_host_get_node_count()))
print(("Result (SkinCount): %d"):format(wasm.cgltf_host_get_skin_count()))
print(("Result (SceneCount): %d"):format(wasm.cgltf_host_get_scene_count()))

for i = 0, wasm.cgltf_host_get_animation_count() - 1 do
	local channels = wasm.cgltf_host_get_animation_channel_count(i)
	print(("Result (AnimationChannelCount%d): %d"):format(i, channels))
end

for i = 0, wasm.cgltf_host_get_mesh_count() - 1 do
	local name_len = wasm.cgltf_host_get_mesh_name_len(i)
	if name_len > 0 then
		local buf = wasm.cgltf_host_alloc(name_len + 1)
		wasm.cgltf_host_get_mesh_name(i, buf, name_len + 1)
		local name = read_string(memory, buf, name_len)
		print(("Result (MeshName%d): %s"):format(i, name))
	end
end

for i = 0, wasm.cgltf_host_get_node_count() - 1 do
	local name_len = wasm.cgltf_host_get_node_name_len(i)
	local name = ""
	if name_len > 0 then
		local buf = wasm.cgltf_host_alloc(name_len + 1)
		wasm.cgltf_host_get_node_name(i, buf, name_len + 1)
		name = read_string(memory, buf, name_len)
	end
	local flags = ""
	if wasm.cgltf_host_get_node_has_mesh(i) == 1 then flags = flags .. " MESH" end
	if wasm.cgltf_host_get_node_has_skin(i) == 1 then flags = flags .. " SKIN" end
	print(("Result (Node%d): %s%s"):format(i, name, flags))
end
end)
