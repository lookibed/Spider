# PL_MPEG Real-World Comparison

This fixture uses the upstream [`pl_mpeg`](https://github.com/phoboslab/pl_mpeg) repository as the first real-world video codec case for `lua-no-ffi`.

The wasm module is currently built as a standalone non-WASI decode-only **raw MPEG-1 video** module:
- upstream `pl_mpeg.h` is used from `upstream/`
- `src/pl_mpeg.c` provides the single-file implementation build
- `src/shim.c` provides a simple standalone heap and libc-style memory helpers with a `64 MB` fixed heap
- `src/module.c` embeds a canonical `sample.m1v` clip and exports:
  - `plmpeg_decode_hash(i32 frame_limit) -> i32`
  - `plmpeg_probe_width() -> i32`
  - `plmpeg_probe_height() -> i32`
  - `plmpeg_probe_frame_count(i32 frame_limit) -> i32`
  - `plmpeg_probe_first_frame_hash() -> i32`
  - `plmpeg_probe_last_frame_hash(i32 frame_limit) -> i32`
- the same module also exposes a plain-Lua host adapter path for real raw `.m1v` files:
  - `plmpeg_host_alloc(i32) -> i32`
  - `plmpeg_host_reset() -> i32`
  - `plmpeg_host_load(i32 bytes_ptr, i32 bytes_len) -> i32`
  - `plmpeg_host_decode_frame(i32 frame_index) -> i32`
  - `plmpeg_host_get_rgb_ptr() -> i32`
  - `plmpeg_host_get_rgb_size() -> i32`
  - `plmpeg_host_get_width() -> i32`
  - `plmpeg_host_get_height() -> i32`

The committed canonical clip is:
- `96x64`
- `12` frames
- raw MPEG-1 video in `sample.m1v`
- generated deterministically from `ffmpeg`'s `testsrc2`

There is also a sidecar `sample.mpg` in `fixtures/` that keeps the MPEG-PS container around as a future demux regression input, but the current parity fixture is intentionally narrowed to the raw video path.

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
cargo build --release -p wasmtime-host-runner
```

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\clang.exe --% --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export-all -Itests/manual/real-world-plmpeg/include -Itests/manual/real-world-plmpeg/upstream tests/manual/real-world-plmpeg/src/module.c tests/manual/real-world-plmpeg/src/shim.c tests/manual/real-world-plmpeg/src/pl_mpeg.c -o tests/manual/real-world-plmpeg/generated/plmpeg.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_decode_hash tests/manual/real-world-plmpeg/generated/plmpeg.wasm 8
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_width tests/manual/real-world-plmpeg/generated/plmpeg.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_height tests/manual/real-world-plmpeg/generated/plmpeg.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_frame_count tests/manual/real-world-plmpeg/generated/plmpeg.wasm 8
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_first_frame_hash tests/manual/real-world-plmpeg/generated/plmpeg.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_last_frame_hash tests/manual/real-world-plmpeg/generated/plmpeg.wasm 8
```

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\real-world-plmpeg\generated\plmpeg.wasm -t lua-no-ffi > tests\manual\real-world-plmpeg\generated\plmpeg.lua"
cmd /c "target\release\spider-cli.exe tests\manual\real-world-plmpeg\generated\plmpeg.wasm -t lua-jit > tests\manual\real-world-plmpeg\generated\plmpeg_jit.lua"
```

```powershell
luajit tests/manual/real-world-plmpeg/main.lua lua-no-ffi 8
luajit tests/manual/real-world-plmpeg/main.lua lua-jit 8
```

## External Host Adapter Visual Test

This fixture also includes a real file-based smoke test through plain Lua file APIs:
- reads a real raw `.m1v` file from disk with `io.open(..., "rb")`
- copies the bytes into wasm memory
- decodes frame `0`
- tries to decode frame `7`, and falls back to the highest available frame down to `1`
- writes each decoded RGB frame to a `P6` `.ppm` file

The host adapter script is:
- [host_main.lua](../../tests/manual/real-world-plmpeg/host_main.lua#L1)

Run it like this:

```powershell
luajit tests/manual/real-world-plmpeg/host_main.lua lua-no-ffi
```

Or with your own raw `.m1v`:

```powershell
luajit tests/manual/real-world-plmpeg/host_main.lua lua-no-ffi path\to\your.m1v
```

Example with the local fixture copy:

```powershell
luajit tests/manual/real-world-plmpeg/host_main.lua lua-no-ffi tests/manual/real-world-plmpeg/fixtures/test.m1v
```

Decode one specific frame:

```powershell
luajit tests/manual/real-world-plmpeg/host_main.lua lua-no-ffi path\to\your.m1v --frame 42
```

Decode all available frames (optionally with a safety limit):

```powershell
luajit tests/manual/real-world-plmpeg/host_main.lua lua-no-ffi path\to\your.m1v --all-frames
luajit tests/manual/real-world-plmpeg/host_main.lua lua-no-ffi path\to\your.m1v --all-frames 500
```

Expected outputs:
- `tests/manual/real-world-plmpeg/generated/frames/sample_frame000.ppm`
- `tests/manual/real-world-plmpeg/generated/frames/sample_frame007.ppm` (or `frame006..frame001` fallback for short external streams)

This path intentionally uses ordinary Lua file APIs only. No `ffi` is required on the host side.

## Wasmtime Host Runner

For symmetric host-in-the-loop comparisons against `lua-no-ffi`, use:

- [Tools/WasmtimeHostRunner](../../Tools/WasmtimeHostRunner/src/main.rs#L1)

This runner is still intentionally fixture-specific:

- it currently knows concrete `plmpeg_*` export names
- it lives under `Tools/`, but it should be read as a practical comparison utility for this fixture family, not as a finished universal Spider host-runner abstraction
- that tradeoff is acceptable for now because it gives a reproducible `wasmtime` workflow that matches the Lua host scripts closely enough to compare baseline vs stream behavior honestly

Baseline host workflow:

```powershell
target\release\wasmtime-host-runner.exe --mode baseline --wasm tests\manual\real-world-plmpeg\generated\plmpeg.wasm --input tests\manual\real-world-plmpeg\fixtures\fhd_5s_testsrc2.m1v --frames 100
```

With frame writes for a workflow that matches `host_main.lua` more closely:

```powershell
target\release\wasmtime-host-runner.exe --mode baseline --wasm tests\manual\real-world-plmpeg\generated\plmpeg.wasm --input tests\manual\real-world-plmpeg\fixtures\fhd_5s_testsrc2.m1v --frames 100 --output-dir tests\manual\real-world-plmpeg\generated\frames_wasmtime
```

Current rough `wasmtime` result on `fixtures/fhd_5s_testsrc2.m1v` with frame writes:

- `100` frames decoded
- about `42518.67 ms` total
- about `425.19 ms/frame`

## Useful Manual Commands

Convert generated `.ppm` frames to `.png` for quick visual inspection:

```powershell
ffmpeg -y -i .\tests\manual\real-world-plmpeg\generated\frames\fhd_5s_testsrc2_frame000.ppm .\tests\manual\real-world-plmpeg\generated\frames\fhd_5s_testsrc2_frame000.png
ffmpeg -y -i .\tests\manual\real-world-plmpeg\generated\frames\fhd_5s_testsrc2_frame007.ppm .\tests\manual\real-world-plmpeg\generated\frames\fhd_5s_testsrc2_frame007.png
```

Build raw MPEG-1 `.m1v` from your own input video:

```powershell
ffmpeg -y -i "D:\path\to\your_input.mp4" -vf "scale=1920:1080,fps=25" -t 5 -c:v mpeg1video -q:v 5 -an ".\tests\manual\real-world-plmpeg\fixtures\my_5s_1080p.m1v"
```

Generate a deterministic test clip without an input file:

```powershell
ffmpeg -y -f lavfi -i testsrc2=size=1920x1080:rate=25 -t 5 -c:v mpeg1video -q:v 5 -an ".\tests\manual\real-world-plmpeg\fixtures\my_testsrc_5s.m1v"
```

Run the `lua-no-ffi` host decode smoke on your generated `.m1v`:

```powershell
luajit .\tests\manual\real-world-plmpeg\host_main.lua lua-no-ffi .\tests\manual\real-world-plmpeg\fixtures\my_5s_1080p.m1v
```

Or run the bundled larger sample directly:

```powershell
luajit .\tests\manual\real-world-plmpeg\host_main.lua lua-no-ffi .\tests\manual\real-world-plmpeg\fixtures\test.m1v --all-frames 100
```

Compare the same `100`-frame Full HD workflow in `wasmtime`:

```powershell
target\release\wasmtime-host-runner.exe --mode baseline --wasm tests\manual\real-world-plmpeg\generated\plmpeg.wasm --input tests\manual\real-world-plmpeg\fixtures\fhd_5s_testsrc2.m1v --frames 100 --output-dir tests\manual\real-world-plmpeg\generated\frames_wasmtime
```

## Current Result

Confirmed `wasmtime` outputs on the canonical `frame_limit = 8` run:

- `DecodeHash = -1675151828`
- `Width = 96`
- `Height = 64`
- `FrameCount = 8`
- `FirstFrameHash = 1251253572`
- `LastFrameHash = 1609960924`

Current `lua-no-ffi` status:

- `DecodeHash = -1675151828`
- `Width = 96`
- `Height = 64`
- `FrameCount = 8`
- `FirstFrameHash = 1251253572`
- `LastFrameHash = 1609960924`

That now matches the canonical `wasmtime` probe set on the narrowed raw MPEG-1 video path.

Current host-adapter status:

- `host_main.lua` is green for the canonical raw `.m1v` sample
- it writes:
  - `tests/manual/real-world-plmpeg/generated/frames/sample_frame000.ppm`
  - `tests/manual/real-world-plmpeg/generated/frames/sample_frame007.ppm`
- both outputs come from plain Lua file I/O with no `ffi`
- a generated `1280x720` raw MPEG-1 sample decodes frame 0 successfully through the same path
- a generated `1920x1080` raw MPEG-1 sample also decodes frame 0 successfully
- a generated `1920x1080` 5-second sample decodes frame 0 and frame 7 successfully
- some short external streams still do not expose frame index `7`; the host script now falls back to `frame006..frame001` automatically
- symmetric `wasmtime` host measurement is now available too through `wasmtime-host-runner`
- on `fixtures/fhd_5s_testsrc2.m1v`, the baseline host workflow reaches `100` frames in about `42518.67 ms` under `wasmtime`

Current `lua-jit` control status:

- the module generates successfully
- the generated `lua-jit` target currently fails to load because the emitted module exceeds LuaJIT's `60 upvalues` limit

So `pl_mpeg` is now a **decode-only parity win for `lua-no-ffi`** on raw MPEG-1 video, while the broader container path and the current `lua-jit` target still remain open issues.
