# real-world-libjpeg-turbo-mjpeg

`libjpeg-turbo`-based MJPEG elementary-stream fixture for Spider `lua-no-ffi`.

Current scope:
- upstream codec core: `libjpeg-turbo`
- canonical input: `fixtures/sample.mjpg`
- stream shape: concatenated JPEG frames (`MJPEG` elementary stream)
- core parity: parse frames, decode to `RGB24`, and hash decoded frame bytes
- host smoke: read a real `.mjpg`, decode one frame or many frames, and write `PPM`

## Files

- `src/module.c` - MJPEG frame parser + JPEG decode exports
- `src/shim.c` - tiny allocator and libc surface
- `src/sample_mjpeg_data.h` - embedded canonical MJPEG bytes
- `main.lua` - parity probe runner
- `host_main.lua` - plain-Lua host runner with `--frame` and `--all-frames`
- `fixtures/sample.mjpg` - canonical MJPEG stream

## Build

Use the same `libjpeg-turbo` source set as the JPEG fixture, but swap in this fixture's `module.c`/`shim.c` and output path:

```powershell
clang --% --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export-all -Wl,--export-memory -Wl,--initial-memory=33554432 -Wl,--max-memory=33554432 -I tests/manual/real-world-libjpeg-turbo-mjpeg/include -I tests/manual/real-world-libjpeg-turbo/upstream/src tests/manual/real-world-libjpeg-turbo-mjpeg/src/module.c tests/manual/real-world-libjpeg-turbo-mjpeg/src/shim.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdapimin.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdapistd-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdapistd-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdapistd-16.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdatasrc.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdcoefct-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdcoefct-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdcolor-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdcolor-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdcolor-16.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jddctmgr-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jddctmgr-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jddiffct-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jddiffct-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jddiffct-16.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdhuff.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdicc.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdinput.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdlhuff.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdlossls-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdlossls-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdlossls-16.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdmainct-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdmainct-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdmainct-16.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdmarker.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdmaster.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdmerge-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdmerge-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdphuff.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdpostct-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdpostct-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdpostct-16.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdsample-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdsample-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jdsample-16.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdtrans.c tests/manual/real-world-libjpeg-turbo/upstream/src/jerror.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jidctflt-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jidctflt-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jidctfst-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jidctfst-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jidctint-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jidctint-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jidctred-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jidctred-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/jmemmgr.c tests/manual/real-world-libjpeg-turbo/upstream/src/jmemnobs.c tests/manual/real-world-libjpeg-turbo/upstream/src/jpeg_nbits.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jquant1-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jquant1-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jquant2-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jquant2-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jutils-8.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jutils-12.c tests/manual/real-world-libjpeg-turbo/upstream/src/wrapper/jutils-16.c tests/manual/real-world-libjpeg-turbo/upstream/src/jcomapi.c tests/manual/real-world-libjpeg-turbo/upstream/src/jaricom.c tests/manual/real-world-libjpeg-turbo/upstream/src/jdarith.c -o tests/manual/real-world-libjpeg-turbo-mjpeg/generated/libjpeg_turbo_mjpeg.wasm
```

Generate `lua-no-ffi`:

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\real-world-libjpeg-turbo-mjpeg\generated\libjpeg_turbo_mjpeg.wasm -t lua-no-ffi > tests\manual\real-world-libjpeg-turbo-mjpeg\generated\libjpeg_turbo_mjpeg.lua"
```

## Parity Smoke

```powershell
wasmtime run -C cache=n --invoke libjpeg_turbo_mjpeg_decode_hash tests/manual/real-world-libjpeg-turbo-mjpeg/generated/libjpeg_turbo_mjpeg.wasm 12
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/main.lua lua-no-ffi 12
```

Current canonical results:

- `DecodeHash = -598443464`
- `Width = 96`
- `Height = 64`
- `Components = 3`
- `FrameCount = 12`
- `FirstFrameHash = -924446984`
- `LastFrameHash = 1556833302`
- `InputHash = 755618084`

## Host Smoke

Default smoke:

```powershell
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi tests/manual/real-world-libjpeg-turbo-mjpeg/fixtures/sample.mjpg
```

Specific frame:

```powershell
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi tests/manual/real-world-libjpeg-turbo-mjpeg/fixtures/sample.mjpg --frame 7
```

All frames:

```powershell
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi tests/manual/real-world-libjpeg-turbo-mjpeg/fixtures/sample.mjpg --all-frames
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi tests/manual/real-world-libjpeg-turbo-mjpeg/fixtures/sample.mjpg --all-frames 12
```

Current host behavior:

- default smoke writes `sample_frame000.ppm` and `sample_frame007.ppm`
- `--frame 7` writes only `sample_frame007.ppm`
- `--all-frames 12` writes `12` frames under `generated/frames/`

## Test Your Own Video

If you already have an `.mjpg` or raw MJPEG elementary stream, run it directly:

```powershell
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi D:\path\to\your_video.mjpg
```

Specific frame:

```powershell
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi D:\path\to\your_video.mjpg --frame 12
```

All frames:

```powershell
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi D:\path\to\your_video.mjpg --all-frames
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi D:\path\to\your_video.mjpg --all-frames 100
```

If your source is a normal video file like `.mp4`, `.mov`, or `.avi`, first convert it to an MJPEG elementary stream:

```powershell
ffmpeg -y -i "D:\path\to\your_input.mp4" -vf "fps=12,scale=960:540" -t 5 -c:v mjpeg -q:v 4 -an -f mjpeg "D:\Backups\Spider\tests\manual\real-world-libjpeg-turbo-mjpeg\fixtures\your_video.mjpg"
```

Then run it:

```powershell
luajit tests/manual/real-world-libjpeg-turbo-mjpeg/host_main.lua lua-no-ffi D:\Backups\Spider\tests\manual\real-world-libjpeg-turbo-mjpeg\fixtures\your_video.mjpg
```

The decoded frames are written under:

- `tests/manual/real-world-libjpeg-turbo-mjpeg/generated/frames/`

To view a decoded frame in a regular image viewer, convert `PPM` to `PNG`:

```powershell
ffmpeg -y -i D:\Backups\Spider\tests\manual\real-world-libjpeg-turbo-mjpeg\generated\frames\your_video_frame000.ppm D:\Backups\Spider\tests\manual\real-world-libjpeg-turbo-mjpeg\generated\frames\your_video_frame000.png
```
