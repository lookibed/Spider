# TinyExpr Real-World Comparison

This fixture uses the upstream [`TinyExpr`](https://github.com/codeplea/tinyexpr) repository as a real-world parser/evaluator case for `lua-no-ffi`.

The wasm module is intentionally built as a standalone non-WASI module:
- upstream `tinyexpr.c` and `tinyexpr.h` are used directly from `upstream/`
- `src/shim.c` provides a minimal standalone runtime for allocation, string helpers, `ctype`, and math helpers so the module has no host imports
- `src/module.c` exports two functions:
  - `tinyexpr_hash(i32) -> i32`
  - `tinyexpr_error_code() -> i32`
  - plus probe exports for isolating parser/data/runtime mismatches

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\wasm32-wasi-clang.exe --% -O2 -nostdlib -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--no-entry -Wl,--export=tinyexpr_hash -Wl,--export=tinyexpr_error_code -Wl,--export=tinyexpr_probe_number -Wl,--export=tinyexpr_probe_builtin -Wl,--export=tinyexpr_probe_variable -Wl,--export=tinyexpr_probe_static_builtin -Wl,--export=tinyexpr_probe_compare_flags -Wl,--export=tinyexpr_probe_mini_binary_search -Wl,--export=tinyexpr_probe_builtin_count -Wl,--export=tinyexpr_probe_find_builtin_sqrt -Wl,--export=tinyexpr_probe_find_builtin_abs -Wl,--export=tinyexpr_probe_builtin_sqrt_type -Wl,--export=tinyexpr_probe_builtin_sqrt_name_prefix -Wl,--export=tinyexpr_probe_builtin_sqrt_name_terminator -Wl,--export=tinyexpr_probe_builtin_pointer_delta -Wl,--export=tinyexpr_probe_builtin_address_delta -Wl,--export=tinyexpr_probe_compare_sqrt_to -Wl,--export=tinyexpr_probe_find_builtin_trace_sqrt -Wl,--export=tinyexpr_probe_divide_s32 tests/manual/real-world-tinyexpr/src/module.c tests/manual/real-world-tinyexpr/src/shim.c tests/manual/real-world-tinyexpr/upstream/tinyexpr.c -o tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke tinyexpr_hash tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm 256
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke tinyexpr_error_code tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke tinyexpr_probe_number tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke tinyexpr_probe_builtin tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke tinyexpr_probe_variable tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke tinyexpr_probe_static_builtin tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke tinyexpr_probe_compare_flags tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke tinyexpr_probe_mini_binary_search tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm
```

```powershell
cmd /c "cargo run -q -p spider-cli -- tests\manual\real-world-tinyexpr\generated\tinyexpr.wasm -t lua-no-ffi > tests\manual\real-world-tinyexpr\generated\tinyexpr.lua"
```

```powershell
luajit tests/manual/real-world-tinyexpr/main.lua 256
```

```powershell
@'
local wasm_module_loader = dofile("tests/manual/real-world-tinyexpr/generated/tinyexpr.lua")
local wasm = wasm_module_loader()
print("hash", wasm.tinyexpr_hash(256))
print("err", wasm.tinyexpr_error_code())
print("number", wasm.tinyexpr_probe_number())
print("builtin", wasm.tinyexpr_probe_builtin())
print("variable", wasm.tinyexpr_probe_variable())
print("static_builtin", wasm.tinyexpr_probe_static_builtin())
print("compare", wasm.tinyexpr_probe_compare_flags())
print("mini", wasm.tinyexpr_probe_mini_binary_search())
'@ | luajit -
```

## Current Result

Current confirmed outputs with `iterations = 256`:

- `wasmtime`
  - `tinyexpr_hash(256) = 141480662`
  - `tinyexpr_error_code() = 6`
- `lua-no-ffi`
  - `tinyexpr_hash(256) = 141480662`
  - `tinyexpr_error_code() = 6`

Key probe exports also match:

- `tinyexpr_probe_number() = 12500`
- `tinyexpr_probe_builtin() = 2000`
- `tinyexpr_probe_variable() = 4000`
- `tinyexpr_probe_static_builtin() = 2000`
- `tinyexpr_probe_compare_flags() = 1`
- `tinyexpr_probe_mini_binary_search() = 41`
- `tinyexpr_probe_find_builtin_sqrt() = 21`

## Root Cause That Was Fixed

The real mismatch was not in TinyExpr itself but in `lua-no-ffi` signed `i32` division.

`tinyexpr.c` uses a binary search in `find_builtin()`:

```c
const int i = (imin + ((imax - imin) / 2));
```

Under the broken `lua-no-ffi` runtime, `rt_divide_s32` mis-normalized signed `i32` values through a `bit32_xor(..., 0x80000000)` trick that is unsafe in LuaJIT because `bit` results are signed 32-bit numbers. That made simple cases such as `(24 - 1) / 2` return `0` instead of `11`, so the binary search walked indices `0, 1, 2, 3, 4` instead of `11, 17, 20, 22, 21` and never reached `sqrt`.

After replacing that with explicit `u32 -> signed i32` normalization in `Targets/LuaNoFFI/Printer/runtime/core/i32.lua`, the upstream builtin lookup and the full TinyExpr fixture now match `wasmtime`.
