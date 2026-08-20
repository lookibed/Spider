local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local input_glb_path = arg[2] or (script_dir .. "/fixtures/Box.glb")
local generated_module_path = script_dir .. "/generated/gltf_rs.lua"

if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/gltf_rs_jit.lua"
end

local function read_file(path)
	local f = assert(io.open(path, "rb"))
	local d = assert(f:read("*a"))
	f:close()
	return d
end

local glb = read_file(input_glb_path)
print(("Input: %s (%d bytes)"):format(input_glb_path, #glb))

local m = dofile(generated_module_path)
local w = m()
local buf = w.gltf_host_alloc(#glb)
assert(buf ~= 0, "alloc failed")

if target == "lua-jit" then
	local ffi = require("ffi")
	ffi.copy(ffi.cast("uint8_t *", w.memory.data) + buf, glb, #glb)
else
	for i = 1, #glb do w.memory[1][buf + i] = string.byte(glb, i) end
end

w.gltf_host_load(buf, #glb)

local s = os.clock()
local hash = w.gltf_compute_hash(buf, #glb)
local t = os.clock() - s

print(("Result (Hash): %d"):format(hash))
print(("Result (Time): %.3fs"):format(t))
