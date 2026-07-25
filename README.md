# Spider

> **This is a fork of [SovereignSatellite/Spider](https://github.com/SovereignSatellite/Spider).**
> The key addition over upstream is the **`lua-no-ffi`** target: pure-Lua code generation without FFI, enabling compiled wasm modules to run in environments where FFI is unavailable (sandboxed LuaJIT, PUC-Rio Lua 5.1/5.2).
> See [`docs/notes/lua-no-ffi-status.md`](docs/notes/lua-no-ffi-status.md) for details.

Spider is an experimental compiler based on WebAssembly semantics and the Regionalized Value State Dependence Graph research. It compiles `.wasm` binaries to Luau or LuaJIT source files.

## Manual Testing

Manual smoke/debug artifacts live outside the repository root:

- `tests/manual/fixtures/` for input `.wasm` samples
- `tests/manual/generated/` for generated Lua output
- `tests/manual/main.lua` for the LuaJIT harness
- `tests/manual/hash-compare/` for the reproducible `wasmtime` vs `lua-no-ffi` integer hash comparison
- `tests/manual/float-compare/` for `f32` and `f64` comparison fixtures against `wasmtime`
- `tests/manual/i64-compare/` for `i64` corner-case fixtures against `wasmtime`
- `tests/manual/real-world-tinyexpr/` for a real GitHub-project repro using upstream `TinyExpr`
- `tests/manual/real-world-miniz/` for a real GitHub-project repro using upstream `miniz`
- `tests/manual/real-world-miniz-full/` for the in-memory ZIP/archive layer of upstream `miniz`
- `tests/manual/real-world-miniz-file/` for the file-oriented ZIP convenience surface of upstream `miniz` via a virtual-`stdio` shim
- `tests/manual/real-archive-secret/` for a real external `secretik.zip` smoke test read through LuaJIT stdlib plus `miniz`
- `tests/manual/real-world-chipmunk/` for a real GitHub-project repro using upstream `Chipmunk2D`
- `tests/manual/chipmunk-profile/` for workload-by-workload `Chipmunk2D` profiling across `wasmtime`, `lua-no-ffi`, and `lua-jit`
- `tests/manual/real-world-lodepng/` for a real GitHub-project repro using upstream `LodePNG`, including a plain-Lua host-adapter visual PNG smoke test
- `tests/manual/real-world-libjpeg-turbo/` for a real GitHub-project repro using upstream `libjpeg-turbo`, currently green on the standalone JPEG decode path for `lua-no-ffi`
- `tests/manual/real-world-libjpeg-turbo-mjpeg/` for a real GitHub-project repro using upstream `libjpeg-turbo` on a green MJPEG elementary-stream decode path with `--frame` and `--all-frames` host modes
- `tests/manual/real-world-binjgb/` for a real GitHub-project repro using upstream `binjgb` on a green Game Boy Color framebuffer path driven by `cgb-acid2` plus scripted startup input
- `tests/manual/real-world-h264bsd-mp4/` for a real GitHub-project repro combining upstream `minimp4` and `h264bsd` on a constrained baseline-profile `MP4 + H.264/AVC` decode path
- `tests/manual/real-world-plmpeg/` for a real GitHub-project repro using upstream `pl_mpeg`, currently green on the raw MPEG-1 video decode path for `lua-no-ffi`
- `tests/manual/real-world-plmpeg-stream/` for the stream-oriented `pl_mpeg` comparison fixture with sequential frame decode and frame outputs under `generated/frames/`
- `Tools/WasmtimeHostRunner/` for a symmetric `wasmtime` host runner used for the current `pl_mpeg`, `h264bsd-mp4`, `libjpeg-turbo-mjpeg`, and `binjgb` host-side media/emulator comparisons
- `docs/notes/lua-no-ffi-status.md` for the current readiness assessment and project-fit criteria
- `docs/notes/lua-no-ffi-measurements.md` for size/runtime measurements across the current manual fixtures
- `docs/notes/lua-no-ffi-chipmunk-profile.md` for the hotspot breakdown behind the `Chipmunk2D` slowdown
- `docs/notes/lua-no-ffi-library-porting-philosophy.md` for the recommended porting model for library cores and host adapters

Example workflow:

```sh
$ .\target\release\spider-cli.exe tests/manual/fixtures/test_pure.wasm -t lua-no-ffi | Out-File -Encoding utf8 tests/manual/generated/test.lua
$ luajit tests/manual/main.lua
```

## Install

Prebuilt binaries for Windows, Linux, and macOS are available in the "Releases" tab. Alternatively, build and install from source:

```sh
$ cargo install --git "https://github.com/SovereignSatellite/Spider"
$ spider-cli --help
```
