# Miniz Full-Surface Comparison

This fixture extends the earlier `miniz` codec-only case into the in-memory ZIP/archive layer.

It intentionally does not use `stdio` or FFI. Instead, it exercises `miniz`'s higher-level archive surface through:

- `mz_zip_writer_init_heap()`
- `mz_zip_writer_add_mem()`
- `mz_zip_writer_finalize_heap_archive()`
- `mz_zip_reader_init_mem()`
- `mz_zip_reader_get_num_files()`
- `mz_zip_reader_locate_file()`
- `mz_zip_reader_file_stat()`
- `mz_zip_reader_extract_to_mem()`
- `mz_zip_validate_archive()`

This makes it a much better test of `miniz`'s "periphery" without depending on native file APIs.

The wasm module is built as a standalone non-WASI module:

- upstream `miniz.c`, `miniz_tdef.c`, `miniz_tinfl.c`, `miniz_zip.c`, and headers are used from `../real-world-miniz/upstream/`
- `src/shim.c` provides the local allocator, memory helpers, and `strlen()`
- `src/module.c` builds an in-memory ZIP archive containing three deterministic files, then reads it back and verifies the archive

Exports:

- `miniz_full_hash(i32) -> i32`
- `miniz_full_probe_num_files(i32) -> i32`
- `miniz_full_probe_archive_size(i32) -> i32`
- `miniz_full_probe_locate_mix(i32) -> i32`
- `miniz_full_probe_extract_hash(i32) -> i32`
- `miniz_full_probe_validate(i32) -> i32`

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\wasm32-wasi-clang.exe --% -DNDEBUG -DMINIZ_NO_STDIO -DMINIZ_NO_TIME -O2 -nostdlib -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--no-entry -Wl,--export=miniz_full_hash -Wl,--export=miniz_full_probe_num_files -Wl,--export=miniz_full_probe_archive_size -Wl,--export=miniz_full_probe_locate_mix -Wl,--export=miniz_full_probe_extract_hash -Wl,--export=miniz_full_probe_validate tests/manual/real-world-miniz-full/src/module.c tests/manual/real-world-miniz-full/src/shim.c tests/manual/real-world-miniz/upstream/miniz.c tests/manual/real-world-miniz/upstream/miniz_tdef.c tests/manual/real-world-miniz/upstream/miniz_tinfl.c tests/manual/real-world-miniz/upstream/miniz_zip.c -o tests/manual/real-world-miniz-full/generated/miniz_full.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_full_hash tests/manual/real-world-miniz-full/generated/miniz_full.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_full_probe_num_files tests/manual/real-world-miniz-full/generated/miniz_full.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_full_probe_archive_size tests/manual/real-world-miniz-full/generated/miniz_full.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_full_probe_locate_mix tests/manual/real-world-miniz-full/generated/miniz_full.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_full_probe_extract_hash tests/manual/real-world-miniz-full/generated/miniz_full.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_full_probe_validate tests/manual/real-world-miniz-full/generated/miniz_full.wasm 6
```

```powershell
cmd /c "cargo run -q -p spider-cli -- tests\manual\real-world-miniz-full\generated\miniz_full.wasm -t lua-no-ffi > tests\manual\real-world-miniz-full\generated\miniz_full.lua"
```

```powershell
luajit tests/manual/real-world-miniz-full/main.lua 6
```

## Goal

The target is exact parity between:

- `wasmtime --invoke miniz_full_hash ...`
- `luajit tests/manual/real-world-miniz-full/main.lua ...`

This fixture is meant to answer a more ambitious question than the codec-only `miniz` case:

Can `lua-no-ffi` carry not just the compression core, but also the archive-management layer of a real upstream library when the host boundary stays memory-backed and explicit?

## Current Result

Current confirmed outputs with `level = 6`:

- `wasmtime`
  - `miniz_full_hash(6) = -2109846306`
  - `miniz_full_probe_num_files(6) = 3`
  - `miniz_full_probe_archive_size(6) = 3200`
  - `miniz_full_probe_locate_mix(6) = 258`
  - `miniz_full_probe_extract_hash(6) = 1129688585`
  - `miniz_full_probe_validate(6) = 1`
- `lua-no-ffi`
  - `Result (Hash): -2109846306`
  - `Result (Files): 3`
  - `Result (ArchiveSize): 3200`
  - `Result (LocateMix): 258`
  - `Result (ExtractHash): 1129688585`
  - `Result (Validate): 1`

## Runtime Gaps That This Fixture Exposed

This expanded `miniz` case exposed two real `lua-no-ffi` issues beyond the earlier codec-only fixture:

- Fast Lua locals were being declared as `nil`, which is wrong for numeric wasm locals that should default to zero.
- `rt_extend_s32_to_i64()` needed to tolerate already-widened `i64` table values, because this archive-heavy workload hit a lowering pattern where sign-extension arrived through `rt_widen_i32(...)`.

Fixing those gaps was enough to bring the ZIP/archive fixture into parity with `wasmtime`.
