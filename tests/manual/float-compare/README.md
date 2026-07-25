# Float Compare

This manual scenario compares Spider's `lua-no-ffi` output against `wasmtime` for float-heavy wasm code.

Exports:

- `hash_f32(i32 iterations) -> i32`
- `hash_f64(i32 iterations) -> i32`

Default input:

- `iterations = 2048`

Build the standalone non-WASI wasm module:

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\clang.exe --% --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export=hash_f32 -Wl,--export=hash_f64 -Wl,--allow-undefined tests/manual/float-compare/src/module.c -o tests/manual/float-compare/generated/float_hash.wasm
```

Run in Wasmtime:

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke hash_f32 tests/manual/float-compare/generated/float_hash.wasm 2048
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke hash_f64 tests/manual/float-compare/generated/float_hash.wasm 2048
```

Current Wasmtime baseline for `iterations = 2048`:

```text
hash_f32 = 206320613
hash_f64 = -736305322
combined = -665785165
```

Generate `lua-no-ffi` output:

```powershell
$lines = .\target\release\spider-cli.exe tests/manual/float-compare/generated/float_hash.wasm -t lua-no-ffi
$text = [string]::Join([Environment]::NewLine, $lines)
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path "tests/manual/float-compare/generated/float_hash.lua"), $text, $encoding)
```

Run in LuaJIT:

```powershell
luajit tests/manual/float-compare/main.lua 2048
```

Current `lua-no-ffi` result for `iterations = 2048`:

```text
Result (F32): 206320613
Result (F64): -736305322
Result (Combined): -665785165
```

Regression ladder:

```text
iterations=1
iterations=8
iterations=16
iterations=2048
all currently match between wasmtime and lua-no-ffi
```
