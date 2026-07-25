local wasm_module_loader = dofile("tests/manual/hash-compare/generated/hash_loop.lua")

local seed = tonumber(arg[1]) or 123456789
local iterations = tonumber(arg[2]) or 200000

local wasm = wasm_module_loader()
local result = wasm.hash_loop(seed, iterations)

print("Result (Hash): " .. tostring(result))
