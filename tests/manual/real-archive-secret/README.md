# Real Archive Secret Test

This fixture uses a real ZIP file on disk:

- [secretik.zip](../../tests/manual/real-archive-secret/fixtures/secretik.zip)

Inside it there is one file:

- `secretik.txt`

Expected contents:

- `Hi Bebra 2026!`

The LuaJIT harness:

- reads the real archive using `io.open(..., "rb")`
- copies the archive bytes into wasm memory
- calls a `miniz`-based wasm export that locates and extracts `secretik.txt`
- reads the extracted bytes back out of wasm memory
- verifies the text against the expected string

The canonical path uses the iterative `miniz` extractor. That is intentional: under `lua-no-ffi` the direct `extract_to_mem/extract_to_heap` path currently hits a false CRC failure on this external ZIP even though the decompressed bytes are correct. The iterative path is currently the known-good real-archive route.

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\wasm32-wasi-clang.exe --% -DNDEBUG -DMINIZ_NO_STDIO -DMINIZ_NO_TIME -O2 -nostdlib -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--no-entry -Wl,--export=miniz_secret_reset -Wl,--export=miniz_secret_alloc -Wl,--export=miniz_secret_expected_length -Wl,--export=miniz_secret_extract_message -Wl,--export=miniz_secret_extract_message_iter -Wl,--export=miniz_secret_extract_message_direct -Wl,--export=miniz_secret_probe_expected_crc32 -Wl,--export=miniz_secret_probe_buffer_crc32 -Wl,--export=miniz_secret_probe_file_crc32 -Wl,--export=miniz_secret_matches_expected tests/manual/real-archive-secret/src/module.c tests/manual/real-archive-secret/src/shim.c tests/manual/real-world-miniz/upstream/miniz.c tests/manual/real-world-miniz/upstream/miniz_tdef.c tests/manual/real-world-miniz/upstream/miniz_tinfl.c tests/manual/real-world-miniz/upstream/miniz_zip.c -o tests/manual/real-archive-secret/generated/secret_reader.wasm
```

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\real-archive-secret\generated\secret_reader.wasm -t lua-no-ffi > tests\manual\real-archive-secret\generated\secret_reader.lua"
```

```powershell
luajit tests/manual/real-archive-secret/main.lua
```

## Goal

This is a practical smoke test on a real archive file instead of a synthetic in-memory archive builder.
