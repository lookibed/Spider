local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*)[/\\][^/\\]+$") or "."
local generated_module_path = script_dir .. "/generated/miniz_file.lua"

local level = tonumber(arg[1] or "6")

local function as_i32(value)
    if value >= 0x80000000 then
        return value - 0x100000000
    end

    return value
end

local wasm_module_loader = dofile(generated_module_path)
local wasm = wasm_module_loader()

print(("Result (Hash): %d"):format(as_i32(wasm.miniz_file_hash(level))))
print(("Result (Files): %d"):format(as_i32(wasm.miniz_file_probe_num_files(level))))
print(("Result (ArchiveSize): %d"):format(as_i32(wasm.miniz_file_probe_archive_size(level))))
print(("Result (ExtractHash): %d"):format(as_i32(wasm.miniz_file_probe_extract_hash(level))))
print(("Result (InPlace): %d"):format(as_i32(wasm.miniz_file_probe_in_place(level))))
