# I64 Compare

This manual scenario compares Spider's `lua-no-ffi` output against `wasmtime` for `i64`-heavy wasm code.

Exports:

- `hash_i64_mix(i32 iterations) -> i32`
- `hash_i64_div(i32 iterations) -> i32`

Default input:

- `iterations = 512`

Build the standalone non-WASI wasm module:

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\clang.exe --% --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export=hash_i64_mix -Wl,--export=hash_i64_div -Wl,--export=probe_div_s64 -Wl,--export=probe_rem_s64 -Wl,--export=probe_div_u64 -Wl,--export=probe_rem_u64 -Wl,--allow-undefined tests/manual/i64-compare/src/module.c -o tests/manual/i64-compare/generated/i64_hash.wasm
```

Run in Wasmtime:

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke hash_i64_mix tests/manual/i64-compare/generated/i64_hash.wasm 512
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke hash_i64_div tests/manual/i64-compare/generated/i64_hash.wasm 512
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke probe_div_s64 tests/manual/i64-compare/generated/i64_hash.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke probe_rem_s64 tests/manual/i64-compare/generated/i64_hash.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke probe_div_u64 tests/manual/i64-compare/generated/i64_hash.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke probe_rem_u64 tests/manual/i64-compare/generated/i64_hash.wasm
```

Current Wasmtime baseline for `iterations = 512`:

```text
hash_i64_mix = -921783428
hash_i64_div = -1398093681
combined = 1705278451
probe_div_s64 = 674596155
probe_rem_s64 = 0
probe_div_u64 = 1290282190
probe_rem_u64 = 0
```

Generate `lua-no-ffi` output:

```powershell
cmd /c "cargo run -q -p spider-cli -- tests\manual\i64-compare\generated\i64_hash.wasm -t lua-no-ffi > tests\manual\i64-compare\generated\i64_hash.lua"
```

Run in LuaJIT:

```powershell
luajit tests/manual/i64-compare/main.lua 512
```

Current `lua-no-ffi` result for `iterations = 512`:

```text
Result (Mix): -921783428
Result (Div): -1398093681
Result (Combined): 1705278451
```

Regression ladder:

```text
iterations=1   => mix matches, div matches
iterations=16  => mix matches, div matches
iterations=512 => mix matches, div matches
```

Root cause that was fixed:

- `rt_less_than_s64` in [Targets/LuaNoFFI/Printer/runtime/core/i64.lua](/D:/Backups/Spider/Targets/LuaNoFFI/Printer/runtime/core/i64.lua:474) used the `hi ^ 0x80000000` trick and then compared the result as a signed Lua number.
- In LuaJIT's `bit` library, `bit.bxor` returns a signed 32-bit number, so negative `i64` values could compare incorrectly against zero.
- That flipped the `if (signed_state < 0)` branch inside `hash_i64_div`, which corrupted the hash even though the underlying `i64 div/rem` arithmetic was already correct.
