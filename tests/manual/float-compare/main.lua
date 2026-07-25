local wasm_module_loader = dofile("tests/manual/float-compare/generated/float_hash.lua")

local iterations = tonumber(arg[1]) or 2048
local wasm = wasm_module_loader()

local f32_result = wasm.hash_f32(iterations)
local f64_result = wasm.hash_f64(iterations)
local combined = bit.bxor(f32_result, f64_result)

print("Result (F32): " .. tostring(f32_result))
print("Result (F64): " .. tostring(f64_result))
print("Result (Combined): " .. tostring(combined))
