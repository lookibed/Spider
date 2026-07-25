local wasm_module_loader = dofile("tests/manual/i64-compare/generated/i64_hash.lua")

local iterations = tonumber(arg[1]) or 512
local wasm = wasm_module_loader()

local mix_result = wasm.hash_i64_mix(iterations)
local div_result = wasm.hash_i64_div(iterations)
local combined = bit.bxor(mix_result, div_result)

print("Result (Mix): " .. tostring(mix_result))
print("Result (Div): " .. tostring(div_result))
print("Result (Combined): " .. tostring(combined))
