local script_path = (... and debug.getinfo(1, "S").source:sub(2)) or arg[0]
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local target = arg[1] or "lua-no-ffi"
local generated_module_path = script_dir .. "/generated/wasm3.lua"

if target == "lua-jit" then
	generated_module_path = script_dir .. "/generated/wasm3_jit.lua"
end

local function read_file(path)
	local f = assert(io.open(path, "rb"))
	local d = assert(f:read("*a"))
	f:close()
	return d
end

local test_wasm = read_file(script_dir .. "/fixtures/test42.wasm")
print(("Test wasm: %d bytes"):format(#test_wasm))

local m = dofile(generated_module_path)
local w = m()

local f = function(name)
	local buf = w.wasm3_host_alloc(#test_wasm)
	assert(buf ~= 0, "alloc failed")
	if target == "lua-jit" then
		local ffi = require("ffi")
		ffi.copy(ffi.cast("uint8_t *", w.memory.data) + buf, test_wasm, #test_wasm)
	else
		for i = 1, #test_wasm do w.memory[1][buf + i] = string.byte(test_wasm, i) end
	end
	assert(w.wasm3_host_load_wasm(buf, #test_wasm) == 1, "load_wasm failed")
	
	local name_buf = w.wasm3_host_alloc(#name)
	for i = 1, #name do w.memory[1][name_buf + i] = string.byte(name, i) end
	local s = os.clock()
	local ok = w.wasm3_host_run(name_buf, #name)
	local t = os.clock() - s
	
	if ok == 1 then
		local result = w.wasm3_host_get_result()
		print(("%s: result=%d time=%.3fs"):format(name, result, t))
		return result
	else
		print(("%s: ERROR code=%d time=%.3fs"):format(name, ok, t))
		return nil
	end
end

f("test")
w.wasm3_host_free()
