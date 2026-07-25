# real-world-libjpeg-turbo

`libjpeg-turbo` decode-only fixture for Spider `lua-no-ffi`.

Current scope:
- upstream: `libjpeg-turbo`
- canonical input: `fixtures/sample.jpg`
- core parity: decode embedded JPEG to `RGB24` and hash decoded bytes
- host smoke: read a real `.jpg` with plain Lua, decode in wasm, write `PPM`
- this is the first `JPEG`/`MJPEG-class` fixture for Spider, but v1 intentionally stops at standalone JPEG decode rather than a full MJPEG container path

## Files

- `upstream/` - shallow clone of `libjpeg-turbo`
- `src/module.c` - wasm harness and exports
- `src/shim.c` - tiny allocator and libc surface for standalone build
- `src/sample_jpeg_data.h` - embedded canonical JPEG bytes
- `main.lua` - parity probe runner
- `host_main.lua` - plain-Lua real file smoke
- `fixtures/sample.jpg` - canonical JPEG input
- `generated/` - wasm, generated Lua, and decoded `PPM`

## Build

```powershell
clang --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export-all -Wl,--export=memory -Wl,--initial-memory=33554432 -Wl,--max-memory=33554432 -I tests/manual/real-world-libjpeg-turbo/include -I tests/manual/real-world-libjpeg-turbo/upstream/src tests/manual/real-world-libjpeg-turbo/src/module.c tests/manual/real-world-libjpeg-turbo/src/shim.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdapimin.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdapistd.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdarith.c tests/manual/real-world-libjpeg-turbo/upstream/src/jaricom.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdatasrc.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdcoefct.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdcolor.c tests/manual/real-world-libjpeg-turbo/upstream/src/jddctmgr.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdhuff.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdicc.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdinput.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdmainct.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdmarker.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdmaster.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdmerge.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdphuff.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdpostct.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdsample.c tests/manual/real-world-libjpeg-turbo/upstream/src/jerror.c tests/manual/real-world-libjpeg-turbo/upstream/src/jidctflt.c tests/manual/real-world-libjpeg-turbo/upstream/src/jidctfst.c tests/manual/real-world-libjpeg-turbo/upstream/src/jidctint.c tests/manual/real-world-libjpeg-turbo/upstream/src/jidctred.c tests/manual/real-world-libjpeg-turbo/upstream/src/jmemmgr.c tests/manual/real-world-libjpeg-turbo/upstream/src/jmemnobs.c tests/manual/real-world-libjpeg-turbo/upstream/src/jquant1.c tests/manual/real-world-libjpeg-turbo/upstream/src/jquant2.c tests/manual/real-world-libjpeg-turbo/upstream/src/jcomapi.c tests/manual/real-world-libjpeg-turbo/upstream/src/jutils.c -o tests/manual/real-world-libjpeg-turbo/generated/libjpeg_turbo.wasm
```

Generate `lua-no-ffi`:

```powershell
target\release\spider-cli.exe tests\manual\real-world-libjpeg-turbo\generated\libjpeg_turbo.wasm -t lua-no-ffi > tests\manual\real-world-libjpeg-turbo\generated\libjpeg_turbo.lua
```

## Parity Smoke

`wasmtime`:

```powershell
wasmtime run -C cache=n --invoke libjpeg_turbo_decode_hash tests/manual/real-world-libjpeg-turbo/generated/libjpeg_turbo.wasm
wasmtime run -C cache=n --invoke libjpeg_turbo_probe_width tests/manual/real-world-libjpeg-turbo/generated/libjpeg_turbo.wasm
wasmtime run -C cache=n --invoke libjpeg_turbo_probe_height tests/manual/real-world-libjpeg-turbo/generated/libjpeg_turbo.wasm
```

`lua-no-ffi`:

```powershell
luajit tests/manual/real-world-libjpeg-turbo/main.lua lua-no-ffi
```

Current canonical results:

- `DecodeHash = 950757193`
- `Width = 227`
- `Height = 149`
- `Components = 3`
- `InputHash = 1227945443`
- `RgbSize = 101469`

## Host Smoke

Canonical sample:

```powershell
luajit tests/manual/real-world-libjpeg-turbo/host_main.lua lua-no-ffi tests/manual/real-world-libjpeg-turbo/fixtures/sample.jpg
```

Your own JPEG:

```powershell
luajit tests/manual/real-world-libjpeg-turbo/host_main.lua lua-no-ffi D:\path\to\your.jpg
```

Output:

- `generated/frames/<basename>.ppm`

Convert to PNG for quick viewing:

```powershell
ffmpeg -y -i tests/manual/real-world-libjpeg-turbo/generated/frames/sample.ppm tests/manual/real-world-libjpeg-turbo/generated/frames/sample.png
```

## Current Notes

- this fixture is green on the canonical `sample.jpg` parity path for `wasmtime` and `lua-no-ffi`
- the plain-Lua host adapter is green for real `.jpg` inputs and writes inspectable `PPM` output
- `MJPEG` is not yet represented as a container fixture here; for now, this is the codec-core stepping stone for that class of workloads
