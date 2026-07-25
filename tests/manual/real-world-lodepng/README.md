# LodePNG Real-World Comparison

This fixture uses the upstream [`LodePNG`](https://github.com/lvandeve/lodepng) repository as a real-world image codec case for `lua-no-ffi`.

The wasm module is built as a standalone non-WASI memory-only codec module:
- upstream `lodepng.h` and `lodepng.cpp` are used from `upstream/`
- `src/lodepng.c` includes upstream `lodepng.cpp` in C mode
- `src/shim.c` provides standalone heap and libc memory helpers with a `16 MB` fixed heap for manual host smoke tests
- `src/module.c` exports:
  - `lodepng_roundtrip_hash(i32) -> i32`
  - `lodepng_probe_encoded_size(i32) -> i32`
  - `lodepng_probe_decode_hash(i32) -> i32`
  - `lodepng_probe_input_hash(i32) -> i32`
  - `lodepng_probe_png_hash(i32) -> i32`

The workload:
- fills a deterministic RGBA image
- encodes it to PNG bytes with upstream `lodepng_encode32`
- decodes the produced PNG with upstream `lodepng_decode32`
- verifies exact RGBA byte parity
- hashes decoded pixels and encoded PNG bytes into an `i32`

`variant = 0` uses a `40x28` image. `variant = 1` uses a `53x37` image.

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\clang.exe --% --target=wasm32 -O2 -nostdlib -Itests/manual/real-world-lodepng/include -x c -DLODEPNG_NO_COMPILE_DISK -DLODEPNG_NO_COMPILE_CPP -Wl,--no-entry -Wl,--export-all tests/manual/real-world-lodepng/src/module.c tests/manual/real-world-lodepng/src/shim.c tests/manual/real-world-lodepng/src/lodepng.c -o tests/manual/real-world-lodepng/generated/lodepng.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke lodepng_roundtrip_hash tests/manual/real-world-lodepng/generated/lodepng.wasm 0
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke lodepng_probe_encoded_size tests/manual/real-world-lodepng/generated/lodepng.wasm 0
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke lodepng_probe_decode_hash tests/manual/real-world-lodepng/generated/lodepng.wasm 0
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke lodepng_probe_input_hash tests/manual/real-world-lodepng/generated/lodepng.wasm 0
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke lodepng_probe_png_hash tests/manual/real-world-lodepng/generated/lodepng.wasm 0
```

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\real-world-lodepng\generated\lodepng.wasm -t lua-no-ffi > tests\manual\real-world-lodepng\generated\lodepng.lua"
cmd /c "target\release\spider-cli.exe tests\manual\real-world-lodepng\generated\lodepng.wasm -t lua-jit > tests\manual\real-world-lodepng\generated\lodepng_jit.lua"
```

```powershell
luajit tests/manual/real-world-lodepng/main.lua lua-no-ffi 0
luajit tests/manual/real-world-lodepng/main.lua lua-no-ffi 1
```

## External Host Adapter Visual Test

This fixture also includes a real file-based smoke test through a thin host adapter written in plain Lua stdlib style:
- reads a real PNG from disk with `io.open(..., "rb")`
- copies PNG bytes into wasm memory
- lets upstream `LodePNG` decode and re-encode inside wasm
- writes real output PNGs back to disk with `io.open(..., "wb")`
- verifies that the decoded roundtrip pixels still match the original decoded pixels

The host adapter script is:
- [host_main.lua](/D:/Backups/Spider/tests/manual/real-world-lodepng/host_main.lua:1)
- [grayscale_main.lua](/D:/Backups/Spider/tests/manual/real-world-lodepng/grayscale_main.lua:1)

The default real input image is:
- [host_input.png](/D:/Backups/Spider/tests/manual/real-world-lodepng/fixtures/host_input.png)

Run it like this:

```powershell
luajit tests/manual/real-world-lodepng/host_main.lua lua-no-ffi
```

Or with a custom real image:

```powershell
luajit tests/manual/real-world-lodepng/host_main.lua lua-no-ffi tests/manual/real-world-lodepng/fixtures/host_input.png
```

Expected outputs:
- `tests/manual/real-world-lodepng/generated/host_roundtrip.png`
- `tests/manual/real-world-lodepng/generated/host_overlay.png`

Expected success signal:
- `Roundtrip Matches Input: 1`

This path intentionally uses ordinary Lua file APIs and string/byte manipulation only. No `ffi` is required on the host side.
For practical manual use it re-encodes through the dedicated `lodepng_host_encode_decoded()` export, which now uses a conservative no-LZ77/no-compression host path. That keeps real-file smoke and grayscale output usable even though the core parity fixture still exposes an encoder divergence in the normal upstream encode path.

## Arbitrary PNG To Grayscale

There is also a one-shot helper for manual testing with your own PNG files:

```powershell
luajit tests/manual/real-world-lodepng/grayscale_main.lua lua-no-ffi path\to\your.png
```

By default it writes:

- `path\to\your_gray.png`

You can also provide an explicit output path:

```powershell
luajit tests/manual/real-world-lodepng/grayscale_main.lua lua-no-ffi path\to\your.png path\to\custom_gray.png
```

This helper:
- reads the input PNG with plain Lua file I/O
- decodes it inside wasm through upstream `LodePNG`
- applies grayscale inside the wasm module
- re-encodes it through upstream `LodePNG`
- saves the resulting PNG back to disk

This path is now confirmed on a real `504x417` PNG produced by Paint:
- decode succeeds
- grayscale succeeds
- the resulting `_gray.png` is written back to disk through plain Lua I/O

## Expected Goal

The target is exact parity between:
- `wasmtime --invoke ...`
- `lua-no-ffi`

This fixture exists to stress:
- PNG encode/decode core
- real codec memory traffic
- filter/deflate-style internal loops
- image-sized buffer churn without OS/file dependencies

## Current Result

Confirmed `wasmtime` outputs:

- `variant = 0`
  - `Roundtrip = -1680879972`
  - `EncodedSize = 3870`
  - `DecodeHash = -2110661857`
  - `InputHash = -2110663679`
  - `PngHash = 79205344`
- `variant = 1`
  - `Roundtrip = -998874337`
  - `EncodedSize = 6518`
  - `DecodeHash = 496467531`
  - `InputHash = 496461629`
  - `PngHash = -1526580224`

Current `lua-no-ffi` status:

- `variant = 0` matches `wasmtime` on `Roundtrip`, `EncodedSize`, `DecodeHash`, and `InputHash`
- `variant = 0` differs on `PngHash`, which means the encoder can emit different PNG bytes while still decoding back to the same pixels
- `variant = 1` does not currently match `wasmtime`
  - `Roundtrip = -998874351`
  - `EncodedSize = 6520`
  - `DecodeHash = 496467525`
  - `InputHash = 496461629`
  - `PngHash = -530733477`

That means the current `LodePNG` regression starts after raw image generation and inside the encoder path, not in the deterministic input image builder.

At the same time, the separate plain-Lua host adapter path is currently green for practical manual use:

- real PNG ingestion from disk works
- decoded-pixel roundtrip verification works
- grayscale export to `*_gray.png` works
- the practical host path uses the dedicated conservative host encode mode rather than the parity-stressing core encode path
