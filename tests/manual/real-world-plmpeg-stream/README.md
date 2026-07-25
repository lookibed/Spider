# PL_MPEG Real-World Stream Comparison

This fixture is a stream-oriented variant of `real-world-plmpeg`, intended for run-to-run comparison against the baseline host path.

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
  - `plmpeg_host_load(i32 bytes_ptr, i32 bytes_len) -> i32`
  - `plmpeg_host_decode_frame(i32 frame_index) -> i32`
  - `plmpeg_host_get_rgb_ptr() -> i32`
  - `plmpeg_host_get_rgb_size() -> i32`
  - `plmpeg_host_get_width() -> i32`
  - `plmpeg_host_get_height() -> i32`
  - `plmpeg_host_stream_begin() -> i32`
  - `plmpeg_host_stream_decode_next() -> i32`
  - `plmpeg_host_stream_end() -> i32`
  - `plmpeg_host_stream_get_frame_index() -> i32`

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
D:\Backups\WASI\wasi-sdk-24.0\bin\clang.exe --% --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export=plmpeg_decode_hash -Wl,--export=plmpeg_probe_width -Wl,--export=plmpeg_probe_height -Wl,--export=plmpeg_probe_frame_count -Wl,--export=plmpeg_probe_first_frame_hash -Wl,--export=plmpeg_probe_last_frame_hash -Wl,--export=plmpeg_probe_sequence_start_code -Wl,--export=plmpeg_probe_video_has_header -Wl,--export=plmpeg_host_alloc -Wl,--export=plmpeg_host_load -Wl,--export=plmpeg_host_decode_frame -Wl,--export=plmpeg_host_get_rgb_ptr -Wl,--export=plmpeg_host_get_rgb_size -Wl,--export=plmpeg_host_get_width -Wl,--export=plmpeg_host_get_height -Wl,--export=plmpeg_host_probe_video_has_header -Wl,--export=plmpeg_host_probe_width -Wl,--export=plmpeg_host_probe_height -Wl,--export=plmpeg_host_probe_frame_count -Wl,--export=plmpeg_host_stream_begin -Wl,--export=plmpeg_host_stream_decode_next -Wl,--export=plmpeg_host_stream_end -Wl,--export=plmpeg_host_stream_get_frame_index -Wl,--allow-undefined -Itests/manual/real-world-plmpeg-stream/include -Itests/manual/real-world-plmpeg-stream/upstream tests/manual/real-world-plmpeg-stream/src/module.c tests/manual/real-world-plmpeg-stream/src/shim.c tests/manual/real-world-plmpeg-stream/src/pl_mpeg.c -o tests/manual/real-world-plmpeg-stream/generated/plmpeg.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_decode_hash tests/manual/real-world-plmpeg-stream/generated/plmpeg.wasm 8
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_width tests/manual/real-world-plmpeg-stream/generated/plmpeg.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_height tests/manual/real-world-plmpeg-stream/generated/plmpeg.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_frame_count tests/manual/real-world-plmpeg-stream/generated/plmpeg.wasm 8
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_first_frame_hash tests/manual/real-world-plmpeg-stream/generated/plmpeg.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke plmpeg_probe_last_frame_hash tests/manual/real-world-plmpeg-stream/generated/plmpeg.wasm 8
```

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\real-world-plmpeg-stream\generated\plmpeg.wasm -t lua-no-ffi > tests\manual\real-world-plmpeg-stream\generated\plmpeg.lua"
cmd /c "target\release\spider-cli.exe tests\manual\real-world-plmpeg-stream\generated\plmpeg.wasm -t lua-jit > tests\manual\real-world-plmpeg-stream\generated\plmpeg_jit.lua"
```

```powershell
luajit tests/manual/real-world-plmpeg-stream/main.lua lua-no-ffi 8
luajit tests/manual/real-world-plmpeg-stream/main.lua lua-jit 8
```

## External Host Adapter Visual Test

This fixture keeps the baseline `host_main.lua` and adds a stream-oriented runner:
- [host_stream_main.lua](/D:/Backups/Spider/tests/manual/real-world-plmpeg-stream/host_stream_main.lua:1)

This fixture also includes a real file-based smoke test through plain Lua file APIs:
- reads a real raw `.m1v` file from disk with `io.open(..., "rb")`
- copies the bytes into wasm memory
- decodes frame `0`
- tries to decode frame `7`, and falls back to the highest available frame down to `1`
- writes each decoded RGB frame to a `P6` `.ppm` file

The host adapter script is:
- [host_main.lua](/D:/Backups/Spider/tests/manual/real-world-plmpeg-stream/host_main.lua:1)

Run it like this:

```powershell
luajit tests/manual/real-world-plmpeg-stream/host_main.lua lua-no-ffi
```

Or with your own raw `.m1v`:

```powershell
luajit tests/manual/real-world-plmpeg-stream/host_main.lua lua-no-ffi path\to\your.m1v
```

Example with the local fixture copy:

```powershell
luajit tests/manual/real-world-plmpeg-stream/host_main.lua lua-no-ffi tests/manual/real-world-plmpeg-stream/fixtures/test.m1v
```

Stream-mode runner (single load + decode-next loop):

```powershell
luajit tests/manual/real-world-plmpeg-stream/host_stream_main.lua lua-no-ffi
luajit tests/manual/real-world-plmpeg-stream/host_stream_main.lua lua-no-ffi path\to\your.m1v 500
```

Decode one specific frame:

```powershell
luajit tests/manual/real-world-plmpeg-stream/host_main.lua lua-no-ffi path\to\your.m1v --frame 42
```

Decode all available frames (optionally with a safety limit):

```powershell
luajit tests/manual/real-world-plmpeg-stream/host_main.lua lua-no-ffi path\to\your.m1v --all-frames
luajit tests/manual/real-world-plmpeg-stream/host_main.lua lua-no-ffi path\to\your.m1v --all-frames 500
```

## Comparison Runs

Baseline fixture:

```powershell
luajit tests/manual/real-world-plmpeg/host_main.lua lua-no-ffi path\to\your.m1v --all-frames 500
```

Stream fixture:

```powershell
luajit tests/manual/real-world-plmpeg-stream/host_stream_main.lua lua-no-ffi path\to\your.m1v 500
```

The same `100`-frame Full HD stream run in `wasmtime`:

```powershell
target\release\wasmtime-host-runner.exe --mode stream --wasm tests\manual\real-world-plmpeg-stream\generated\plmpeg.wasm --input tests\manual\real-world-plmpeg-stream\fixtures\fhd_5s_testsrc2.m1v --frames 100 --output-dir tests\manual\real-world-plmpeg-stream\generated\frames_wasmtime
```

Expected outputs:
- `tests/manual/real-world-plmpeg-stream/generated/frames/sample_frame000.ppm`
- `tests/manual/real-world-plmpeg-stream/generated/frames/sample_frame007.ppm` (or `frame006..frame001` fallback for short external streams)

This path intentionally uses ordinary Lua file APIs only. No `ffi` is required on the host side.

## Wasmtime Host Runner

The same stream workflow can now be measured under `wasmtime` too:

- [Tools/WasmtimeHostRunner](/D:/Backups/Spider/Tools/WasmtimeHostRunner/src/main.rs:1)

This runner is still intentionally fixture-specific:

- it currently knows concrete `plmpeg_*` export names
- it is useful because it makes the stream-vs-baseline comparison symmetric against `lua-no-ffi`
- but it should still be treated as a pragmatic utility for the current video fixtures, not as a polished general Spider host-runner layer

```powershell
target\release\wasmtime-host-runner.exe --mode stream --wasm tests\manual\real-world-plmpeg-stream\generated\plmpeg.wasm --input tests\manual\real-world-plmpeg-stream\fixtures\fhd_5s_testsrc2.m1v --frames 100
```

With frame writes:

```powershell
target\release\wasmtime-host-runner.exe --mode stream --wasm tests\manual\real-world-plmpeg-stream\generated\plmpeg.wasm --input tests\manual\real-world-plmpeg-stream\fixtures\fhd_5s_testsrc2.m1v --frames 100 --output-dir tests\manual\real-world-plmpeg-stream\generated\frames_wasmtime
```

Current rough `wasmtime` result on `fixtures/fhd_5s_testsrc2.m1v` with frame writes:

- `100` frames decoded
- about `1960.14 ms` total
- about `19.60 ms/frame`

## Useful Manual Commands

Convert generated `.ppm` frames to `.png` for quick visual inspection:

```powershell
ffmpeg -y -i D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\generated\frames\fhd_5s_testsrc2_stream_frame000.ppm D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\generated\frames\fhd_5s_testsrc2_stream_frame000.png
ffmpeg -y -i D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\generated\frames\fhd_5s_testsrc2_stream_frame007.ppm D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\generated\frames\fhd_5s_testsrc2_stream_frame007.png
```

Build raw MPEG-1 `.m1v` from your own input video:

```powershell
ffmpeg -y -i "D:\path\to\your_input.mp4" -vf "scale=1920:1080,fps=25" -t 5 -c:v mpeg1video -q:v 5 -an "D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\fixtures\my_5s_1080p.m1v"
```

Generate a deterministic test clip without an input file:

```powershell
ffmpeg -y -f lavfi -i testsrc2=size=1920x1080:rate=25 -t 5 -c:v mpeg1video -q:v 5 -an "D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\fixtures\my_testsrc_5s.m1v"
```

Run the `lua-no-ffi` host decode smoke on your generated `.m1v`:

```powershell
luajit D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\host_main.lua lua-no-ffi D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\fixtures\my_5s_1080p.m1v
```

And the stream runner on the bundled larger sample:

```powershell
luajit D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\host_stream_main.lua lua-no-ffi D:\Backups\Spider\tests\manual\real-world-plmpeg-stream\fixtures\test.m1v 100
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
  - `tests/manual/real-world-plmpeg-stream/generated/frames/sample_frame000.ppm`
  - `tests/manual/real-world-plmpeg-stream/generated/frames/sample_frame007.ppm`
- both outputs come from plain Lua file I/O with no `ffi`
- a generated `1280x720` raw MPEG-1 sample decodes frame 0 successfully through the same path
- a generated `1920x1080` raw MPEG-1 sample also decodes frame 0 successfully
- a generated `1920x1080` 5-second sample decodes frame 0 and frame 7 successfully
- some short external streams still do not expose frame index `7`; the host script now falls back to `frame006..frame001` automatically
- symmetric `wasmtime` host measurement is now available for the stream workflow too
- on `fixtures/fhd_5s_testsrc2.m1v`, the stream host workflow reaches `100` frames in about `1960.14 ms` under `wasmtime`
- the `wasmtime` baseline vs stream gap stays large too, which confirms that the stream branch's advantage is mostly algorithmic, not only a Lua-specific effect

Current `lua-jit` control status:

- the module generates successfully
- the generated `lua-jit` target currently fails to load because the emitted module exceeds LuaJIT's `60 upvalues` limit

So `pl_mpeg` is now a **decode-only parity win for `lua-no-ffi`** on raw MPEG-1 video, while the broader container path and the current `lua-jit` target still remain open issues.
