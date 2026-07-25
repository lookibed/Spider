# Miniz Real-World Comparison

This fixture uses the upstream [`miniz`](https://github.com/richgel999/miniz) repository as a real-world buffer/integer/memory case for `lua-no-ffi`.

The wasm module is built as a standalone non-WASI module:
- upstream `miniz.c` and `miniz.h` are used directly from `upstream/`
- `src/shim.c` provides minimal allocation and memory helpers
- `src/module.c` exports:
  - `miniz_roundtrip_hash(i32) -> i32`
  - `miniz_probe_compressed_size(i32) -> i32`
  - `miniz_probe_crc32() -> i32`
  - `miniz_probe_adler32() -> i32`
  - `miniz_probe_fold_hash() -> i32`
  - `miniz_probe_fold_prefix(i32) -> i32`
  - `miniz_probe_fold_step(i32, i32) -> i32`

The workload:
- fills a deterministic 8192-byte input buffer
- compresses it with `mz_compress2()`
- decompresses it with `mz_uncompress()`
- verifies byte-for-byte roundtrip integrity
- folds the output plus `crc32`/`adler32` into a final hash

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\wasm32-wasi-clang.exe --% -DNDEBUG -DMINIZ_NO_STDIO -DMINIZ_NO_TIME -DMINIZ_NO_ARCHIVE_APIS -O2 -nostdlib -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--no-entry -Wl,--export=miniz_roundtrip_hash -Wl,--export=miniz_probe_compressed_size -Wl,--export=miniz_probe_crc32 -Wl,--export=miniz_probe_adler32 -Wl,--export=miniz_probe_fold_hash -Wl,--export=miniz_probe_fold_prefix -Wl,--export=miniz_probe_fold_step tests/manual/real-world-miniz/src/module.c tests/manual/real-world-miniz/src/shim.c tests/manual/real-world-miniz/upstream/miniz.c tests/manual/real-world-miniz/upstream/miniz_tdef.c tests/manual/real-world-miniz/upstream/miniz_tinfl.c -o tests/manual/real-world-miniz/generated/miniz.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_roundtrip_hash tests/manual/real-world-miniz/generated/miniz.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_probe_compressed_size tests/manual/real-world-miniz/generated/miniz.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_probe_crc32 tests/manual/real-world-miniz/generated/miniz.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_probe_adler32 tests/manual/real-world-miniz/generated/miniz.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_probe_fold_hash tests/manual/real-world-miniz/generated/miniz.wasm
```

```powershell
cmd /c "cargo run -q -p spider-cli -- tests\manual\real-world-miniz\generated\miniz.wasm -t lua-no-ffi > tests\manual\real-world-miniz\generated\miniz.lua"
```

```powershell
luajit tests/manual/real-world-miniz/main.lua 6
```

## Expected Goal

The target is exact parity between:
- `wasmtime --invoke miniz_roundtrip_hash ...`
- `luajit tests/manual/real-world-miniz/main.lua ...`

## Current Result

Current confirmed outputs with `level = 6`:

- `wasmtime`
  - `miniz_roundtrip_hash(6) = 58679047`
  - `miniz_probe_compressed_size(6) = 2152`
  - `miniz_probe_crc32() = 2035028898`
  - `miniz_probe_adler32() = 1263729890`
  - `miniz_probe_fold_hash() = 828487727`
- `lua-no-ffi`
  - `miniz_roundtrip_hash(6) = 58679047`
  - `miniz_probe_compressed_size(6) = 2152`
  - `miniz_probe_crc32() = 2035028898`
  - `miniz_probe_adler32() = 1263729890`
  - `miniz_probe_fold_hash() = 828487727`

## Root Cause That Was Fixed

This fixture initially roundtripped correctly but still disagreed on the final hash. The mismatch was narrowed to the first single-step fold operation:

- `miniz_probe_fold_step(0x811C9DC5, 90)`

That pointed to `lua-no-ffi`'s `rt_multiply_i32` fast path in `Targets/LuaNoFFI/Printer/runtime/core/i32.lua`. The old implementation sometimes multiplied large signed values directly as Lua numbers, which is not reliable for exact `i32` overflow semantics. Replacing it with the exact 16-bit decomposition path for all `i32.mul` calls fixed the `miniz` hash and aligned the whole fixture with `wasmtime`.
