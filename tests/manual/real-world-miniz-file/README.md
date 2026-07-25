# Miniz File-API Comparison

This fixture pushes `miniz` past the memory-only archive workflow and through its file-oriented ZIP convenience APIs.

It still does not depend on native OS files or FFI. Instead:

- upstream `miniz` file APIs are used unchanged
- a tiny virtual-`stdio` shim is provided under `src/shim.c`
- local headers in `include/` override `stdio.h` and `sys/stat.h` just enough for the wasm build

That means this fixture exercises a much fuller `miniz` surface while keeping the host model deterministic and portable.

The workload:

- seeds three source files into a virtual filesystem
- creates `out/archive.zip` using `mz_zip_writer_init_file()`
- adds three files via `mz_zip_writer_add_file()`
- finalizes the archive
- appends a fourth file with `mz_zip_add_mem_to_archive_file_in_place()`
- reopens the archive via `mz_zip_reader_init_file()`
- extracts files via `mz_zip_reader_extract_file_to_file()`
- extracts the appended file with `mz_zip_extract_archive_file_to_heap()`
- validates hashes and archive metadata

Exports:

- `miniz_file_hash(i32) -> i32`
- `miniz_file_probe_num_files(i32) -> i32`
- `miniz_file_probe_archive_size(i32) -> i32`
- `miniz_file_probe_extract_hash(i32) -> i32`
- `miniz_file_probe_in_place(i32) -> i32`

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\wasm32-wasi-clang.exe --% -I tests/manual/real-world-miniz-file/include -DNDEBUG -DMINIZ_NO_TIME -O2 -nostdlib -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--no-entry -Wl,--export=miniz_file_hash -Wl,--export=miniz_file_probe_num_files -Wl,--export=miniz_file_probe_archive_size -Wl,--export=miniz_file_probe_extract_hash -Wl,--export=miniz_file_probe_in_place tests/manual/real-world-miniz-file/src/module.c tests/manual/real-world-miniz-file/src/shim.c tests/manual/real-world-miniz/upstream/miniz.c tests/manual/real-world-miniz/upstream/miniz_tdef.c tests/manual/real-world-miniz/upstream/miniz_tinfl.c tests/manual/real-world-miniz/upstream/miniz_zip.c -o tests/manual/real-world-miniz-file/generated/miniz_file.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_file_hash tests/manual/real-world-miniz-file/generated/miniz_file.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_file_probe_num_files tests/manual/real-world-miniz-file/generated/miniz_file.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_file_probe_archive_size tests/manual/real-world-miniz-file/generated/miniz_file.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_file_probe_extract_hash tests/manual/real-world-miniz-file/generated/miniz_file.wasm 6
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke miniz_file_probe_in_place tests/manual/real-world-miniz-file/generated/miniz_file.wasm 6
```

```powershell
cmd /c "cargo run -q -p spider-cli -- tests\manual\real-world-miniz-file\generated\miniz_file.wasm -t lua-no-ffi > tests\manual\real-world-miniz-file\generated\miniz_file.lua"
```

```powershell
luajit tests/manual/real-world-miniz-file/main.lua 6
```

## Goal

This fixture is meant to answer the next practical question after the memory-backed `miniz` archive case:

Can `Spider -> lua-no-ffi` still match `wasmtime` once the library starts leaning on its convenience file-style surface, even when that surface is being adapted through a thin portability shim?

## Current Result

Current confirmed outputs with `level = 6`:

- `wasmtime`
  - `miniz_file_hash(6) = -138697996`
  - `miniz_file_probe_num_files(6) = 4`
  - `miniz_file_probe_archive_size(6) = 3473`
  - `miniz_file_probe_extract_hash(6) = 1747784103`
  - `miniz_file_probe_in_place(6) = 1`
- `lua-no-ffi`
  - `Result (Hash): -138697996`
  - `Result (Files): 4`
  - `Result (ArchiveSize): 3473`
  - `Result (ExtractHash): 1747784103`
  - `Result (InPlace): 1`

## What This Fixture Actually Shows

This is the first `miniz` fixture in the repo that intentionally goes through the file-oriented convenience API surface instead of stopping at memory-only archive helpers.

It still does not emulate a real operating system inside `lua-no-ffi`.

Instead, it validates a more realistic "full library cycle" through:

- upstream file-style API calls
- a thin virtual-`stdio` portability shim
- parity against `wasmtime`

That makes it a better measure of how far Spider can carry a real library once the host boundary is adapted instead of ignored.
