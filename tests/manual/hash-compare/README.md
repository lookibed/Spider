# Hash Compare

This manual scenario compares the same exported wasm function under `wasmtime` and Spider's `lua-no-ffi` target.

Contract:

- Exported function: `hash_loop(i32 seed, i32 iterations) -> i32`
- Default inputs: `seed = 123456789`, `iterations = 200000`

Build the standalone non-WASI wasm module:

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\clang.exe --target=wasm32 -O2 -nostdlib `
  -Wl,--no-entry `
  -Wl,--export=hash_loop `
  -Wl,--allow-undefined `
  tests/manual/hash-compare/src/module.c `
  -o tests/manual/hash-compare/generated/hash_loop.wasm
```

Run the wasm directly in Wasmtime:

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke hash_loop `
  tests/manual/hash-compare/generated/hash_loop.wasm `
  123456789 `
  200000
```

Generate pure LuaJIT-compatible Lua and run it through LuaJIT:

```powershell
$lines = .\target\release\spider-cli.exe tests/manual/hash-compare/generated/hash_loop.wasm -t lua-no-ffi
$text = [string]::Join([Environment]::NewLine, $lines)
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path "tests/manual/hash-compare/generated/hash_loop.lua"), $text, $encoding)

luajit tests/manual/hash-compare/main.lua 123456789 200000
```

Expected result for both engines:

```text
Result (Hash): -1767246609
```

Second regression input pair:

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke hash_loop `
  tests/manual/hash-compare/generated/hash_loop.wasm `
  1 `
  65536

luajit tests/manual/hash-compare/main.lua 1 65536
```

Expected result for both engines:

```text
Result (Hash): 1645510779
```
