# `lua-no-ffi` Status

This note summarizes the current readiness of Spider's `lua-no-ffi` target as of the latest manual validation work under:

- [tests/manual/hash-compare](../../tests/manual/hash-compare/README.md)
- [tests/manual/float-compare](../../tests/manual/float-compare/README.md)
- [tests/manual/i64-compare](../../tests/manual/i64-compare/README.md)
- [tests/manual/real-world-tinyexpr](../../tests/manual/real-world-tinyexpr/README.md)
- [tests/manual/real-world-miniz](../../tests/manual/real-world-miniz/README.md)
- [tests/manual/real-world-miniz-full](../../tests/manual/real-world-miniz-full/README.md)
- [tests/manual/real-world-miniz-file](../../tests/manual/real-world-miniz-file/README.md)
- [tests/manual/real-archive-secret](../../tests/manual/real-archive-secret/README.md)
- [tests/manual/real-world-chipmunk](../../tests/manual/real-world-chipmunk/README.md)
- [tests/manual/real-world-lodepng](../../tests/manual/real-world-lodepng/README.md)
- [tests/manual/real-world-libjpeg-turbo](../../tests/manual/real-world-libjpeg-turbo/README.md)
- [tests/manual/real-world-libjpeg-turbo-mjpeg](../../tests/manual/real-world-libjpeg-turbo-mjpeg/README.md)
- [tests/manual/real-world-binjgb](../../tests/manual/real-world-binjgb/README.md)
- [tests/manual/real-world-h264bsd-mp4](../../tests/manual/real-world-h264bsd-mp4/README.md)
- [tests/manual/real-world-plmpeg](../../tests/manual/real-world-plmpeg/README.md)
- [tests/manual/real-world-plmpeg-stream](../../tests/manual/real-world-plmpeg-stream/README.md)

Related measurement note:

- [docs/notes/lua-no-ffi-measurements.md](../../docs/notes/lua-no-ffi-measurements.md)
- [docs/notes/lua-no-ffi-chipmunk-profile.md](../../docs/notes/lua-no-ffi-chipmunk-profile.md)
- [docs/notes/lua-no-ffi-known-bugs.md](../../docs/notes/lua-no-ffi-known-bugs.md)
- [docs/notes/lua-no-ffi-plmpeg-open-problem.md](../../docs/notes/lua-no-ffi-plmpeg-open-problem.md)

## Overall Readiness

Current status: `usable experimental`, now backed by the WebAssembly spec
conformance suite instead of manual comparison alone.

Conformance (`cargo test -p conformance --test luanoffi`, 78 spec `.wast`
files x 4 LuaJIT variants, run on Linux with LuaJIT 2.1.0-beta3):

- `lua-no-ffi`: 280 / 312 cases pass. Every remaining failure is a NaN
  sign or payload assertion (`address`, `conversions`, `f64_bitwise`,
  `float_exprs`, `float_literals`, `float_memory`, `float_misc`, `select`):
  `f64` is a native Lua number and LuaJIT cannot observe a NaN's sign or
  payload without FFI, so those bits are unrecoverable by design.
- `lua-jit` (the FFI target, same suite via `--test luajit`): 312 / 312.

Real-world parity against `wasmtime` 24.0.1: `tinyexpr`, `miniz` and
`lodepng` (both variants, all five probes) match bit-for-bit. Every fixture
`.wasm` in `tests/manual` compiles and loads under LuaJIT except
`real-world-gltf-rs` (a generated function still exceeds 60 upvalues).

Suggested readiness score:

- Architecture and target wiring: `7/10`
- Runtime section contract: `7/10`
- `i32` and control-flow confidence: `9/10`
- `f32` and `f64` confidence: `7/10`
- `i64` confidence: `6/10`
- Broad wasm program compatibility: `5/10`
- Manual debugging usefulness: `9/10`

## Size And Runtime Snapshot

Representative points from the current measurement set:

- small semantic fixtures can look deceptively cheap: `hash-compare` is `22` compiled C lines -> `106` Lua lines and does not show a meaningful slowdown over `wasmtime` in wall-clock terms
- medium real-world library slices stay usable: `real-world-miniz` is `2946` compiled C lines -> `11139` Lua lines, `34930` byte `.wasm` -> `444763` byte Lua, and about `2.38x` slower than `wasmtime`
- broader archive/file surfaces get expensive faster: `real-world-miniz-file` reaches about `10.27x` slowdown with `24533` Lua lines and a `1013693` byte generated module
- `real-world-lodepng` now gives a useful image-codec midpoint: `7837` compiled C lines -> `33785` Lua lines, `115716` byte `.wasm` -> `1476360` byte Lua, and about `2.99x` slowdown on the `variant = 0` core probe set
- `real-world-libjpeg-turbo` now adds a first green `JPEG` codec point: `13724` compiled C lines -> `73242` Lua lines, `351224` byte `.wasm` -> `3592440` byte Lua, and about `3.32x` slowdown on the full canonical probe set
- `real-world-libjpeg-turbo-mjpeg` now adds a first green `MJPEG` multi-frame point: `13865` compiled C lines -> `73846` Lua lines, `375047` byte `.wasm` -> `3678957` byte Lua, and about `37.49x` slowdown on the canonical `12`-frame probe set
- `real-world-libjpeg-turbo-mjpeg` now also has a symmetric `wasmtime` host path for `--all-frames 12`, landing at about `92.18 ms` versus `870.81 ms` for the current Lua host script
- `real-world-binjgb` now adds a first green Game Boy Color emulator point: `5686` compiled C lines -> `34198` Lua lines, `134905` byte `.wasm` -> `1576674` byte Lua, and about `8.42x` slowdown on the canonical `16`-frame `cgb-acid2` framebuffer probe set
- `real-world-binjgb` also now has a symmetric `wasmtime` host path for `--all-frames 16`, landing at about `188.04 ms` versus `10707.79 ms` for the current Lua host script
- `real-world-h264bsd-mp4` now adds a first green `MP4 + H.264/AVC` point: `1327` compiled C lines -> `50800` Lua lines, `165414` byte `.wasm` -> `2184930` byte Lua, and about `14.32x` slowdown on the constrained baseline-profile `frame_limit = 8` probe set
- `real-world-plmpeg` and `real-world-plmpeg-stream` now form a useful video pair: both are green on the canonical raw MPEG-1 probe set, while the stream branch adds sequential `decode_next` host extraction for multi-frame comparisons
- `real-world-h264bsd-mp4` now also has a symmetric `wasmtime` host path through the same runner, and on the canonical `12`-frame all-frames workflow it lands at about `78.56 ms` versus `14775.48 ms` for the current Lua host script
- the new `wasmtime` host runner makes those host-side `pl_mpeg` comparisons symmetric too: on `100` Full HD frames with writes, baseline is about `42518.67 ms` and stream about `1960.14 ms`, so the big stream win is clearly not only a `lua-no-ffi` artifact
- `real-archive-secret` stays a good practical smoke test for real ZIP ingestion through Lua host I/O, but it is not a clean symmetric `wasmtime` timing case
- `real-world-chipmunk` is the clearest current performance boundary: parity is correct, but `chipmunk_hash_scene(600)` is still about `691.62x` slower than `wasmtime`
- the chipmunk profile breakdown suggests the real cliff starts at collision processing and grows again with constraints, rather than being explained by isolated math-only or memory-only costs

Full measurement details live in:

- [docs/notes/lua-no-ffi-measurements.md](../../docs/notes/lua-no-ffi-measurements.md)

## What Is Confirmed Working

The following areas have direct manual parity checks against `wasmtime`:

- Pure `i32` arithmetic and control flow
- Loop-heavy integer hashing
- `f32` arithmetic/conversion paths used by the float fixture
- `f64` arithmetic/conversion paths used by the float fixture
- `i64` multiply, divide, remainder, shifts, rotates, and signed branching used by the `i64` fixture
- Real upstream parser/evaluator code through `TinyExpr`
- Real upstream compression/decompression code through `miniz`
- Real upstream in-memory ZIP/archive management through `miniz`
- Real upstream file-oriented ZIP convenience APIs through `miniz` with a virtual-`stdio` adapter
- Real external ZIP ingestion through LuaJIT `io.open(..., "rb")` plus `miniz` iterative extraction
- Real upstream physics-core stepping through `Chipmunk2D`
- Real PNG file ingestion plus roundtrip/visual output through plain-Lua host I/O with `LodePNG`
- Real PNG grayscale rewrite to `*_gray.png` through plain-Lua host I/O with `LodePNG`
- Real upstream JPEG decode through `libjpeg-turbo`
- Real JPEG file ingestion plus decoded `PPM` output through plain-Lua host I/O with `libjpeg-turbo`
- Real upstream MJPEG elementary-stream decode through `libjpeg-turbo`
- Real MJPEG file ingestion plus decoded `PPM` frame output through plain-Lua host I/O with `libjpeg-turbo`
- Real upstream Game Boy Color emulation through `binjgb` on a scripted `cgb-acid2` visual-test path
- Real `.gbc` ROM ingestion plus decoded `PPM` framebuffer output through plain-Lua host I/O with `binjgb`
- Real upstream MP4 demux plus H.264 decode through `minimp4 + h264bsd` on a constrained baseline-profile clip
- Real MP4 file ingestion plus decoded `PPM` frame output through plain-Lua host I/O with `minimp4 + h264bsd`
- Pure LuaJIT 2.1 runtime with no FFI
- Lua 5.1-compatible source generation using the `bit` library only

- Real upstream raw MPEG-1 video decode through `pl_mpeg` on the narrowed decode-only path

## Supported Project Criteria

The following wasm/C projects are currently reasonable candidates for `lua-no-ffi`:

- Standalone non-WASI `.wasm` modules
- Modules exposed through exported functions instead of a host OS environment
- Projects compiled from plain C with no libc-heavy assumptions
- Deterministic numeric kernels
- Integer-heavy logic
- Moderate float usage with normal arithmetic, comparisons, and truncation paths
- Moderate `i64` usage where correctness matters more than speed
- Small and medium manual regression fixtures
- Debug repro cases where parity is checked against `wasmtime`

Good examples:

- Hashing kernels
- Compression-like inner loops without syscalls
- Small simulation/math kernels
- Physics-core libraries with deterministic fixed-step simulation and no rendering layer
- Signal/image kernels that do not depend on host APIs
- Regression fixtures built specifically to compare Spider output against `wasmtime`
- Real upstream library cores with host glue stripped or replaced by local adapters
- Real upstream library surfaces that extend past the pure codec core but still keep the host boundary memory-backed
- Real upstream library surfaces that lean on file-style APIs, as long as the host boundary is explicitly adapted

## Conditionally Supported Project Criteria

These project shapes may work, but should currently be treated as "test first, trust later":

- Float-heavy code with many edge-case conversions
- `i64`-heavy business logic or codecs
- Memory-heavy kernels with frequent loads/stores across multiple element widths
- Large loops where runtime cost matters
- Projects with multiple exports and nontrivial state threading
- C modules that rely on compiler lowering patterns not yet covered by the manual fixtures

For these, the right process is:

1. build the `.wasm`
2. compare against `wasmtime`
3. keep the repro fixture if anything drifts

## Not Supported or Not Yet Trustworthy

The following categories should currently be considered unsupported, incomplete, or too risky to promise:

- WASI host programs as a productized target
- Syscalls, filesystem, environment, clock, and other OS-facing behavior
- Arbitrary third-party wasm binaries with no parity check
- Full conformance-level coverage across the wasm spec
- Performance-sensitive workloads where pure-Lua speed is critical
- Large real-world applications compiled from C/C++ and expected to "just work"
- Anything that depends on exact NaN payload behavior unless verified case-by-case
- Any workflow that assumes `lua-no-ffi` already has the same maturity as the FFI-backed `lua-jit` target

## Practical Criteria For C Sources

A C project is a good fit for `lua-no-ffi` if most of the following are true:

- It builds to a standalone wasm module without WASI requirements
- It exports functions directly
- It does not require libc I/O
- It does not allocate through an external runtime that expects a full host environment
- Its correctness can be checked from numeric return values or deterministic buffers
- It can be compared against `wasmtime`

A C project is a bad fit right now if several of the following are true:

- It expects `main()` plus a WASI environment
- It uses file I/O, process APIs, time, or randomness from the host
- It is very large and pointer-heavy
- It relies on broad undefined-behavior-sensitive compiler output
- It needs high throughput
- It is difficult to validate against a trusted engine

## Main Risks Still Open

The biggest remaining risks are:

- Missing coverage outside the current manual parity fixtures
- Float edge cases not yet expanded into a broader regression set
- `i64` corner cases beyond the current divide/multiply/branch fixture
- Memory semantics under more complex real programs
- Host-bound library layers that still need explicit adapter design outside the wasm core
- Performance of pure-Lua execution on larger modules
- The current `real-world-libjpeg-turbo` win is intentionally narrow: standalone JPEG decode only, no separate MJPEG container/stream workflow yet, and parity defined on decoded `RGB24` bytes
- The current `real-world-libjpeg-turbo-mjpeg` win is intentionally narrow too: raw MJPEG elementary streams only, no AVI/MOV/container demux layer yet, and parity defined on decoded `RGB24` frame bytes rather than container fidelity
- The current `real-world-binjgb` win is intentionally narrow too: one scripted `cgb-acid2` visual-test ROM, parity defined on a packed `RGB555`-class framebuffer surface derived from upstream `RGBA`, and canonical startup still tied to upstream post-boot initialization because `binjgb` does not expose a public boot-ROM loading API
- The current `real-world-h264bsd-mp4` win is intentionally narrow: constrained baseline-profile MP4 only, no audio, no generalized streaming API, and parity defined on decoded `YUV420` output rather than container-level fidelity
- MPEG-PS/container demux through `pl_mpeg` is still unproven: the current green fixture is narrowed to raw MPEG-1 video, while the sidecar `.mpg` container path remains future work
- External-stream `pl_mpeg` host behavior is mostly practical now: frame 0 decode works for generated `1280x720` and `1920x1080` raw `.m1v`, and a generated `1920x1080` 5-second stream reaches frame 7; short streams that do not expose index `7` are now handled by host fallback (`7 -> ... -> 1`)
- The baseline `real-world-plmpeg` `--all-frames` host path no longer stops at `2` frames on `fixtures/fhd_5s_testsrc2.m1v`; after adding host reset between frame decodes it completes `100` frames too, but it is still dramatically slower than `real-world-plmpeg-stream` because it re-decodes from stream start for every requested frame
- `Tools/WasmtimeHostRunner` now confirms the same shape on `wasmtime`: the stream branch is still much faster than baseline on the same `100`-frame Full HD workflow, which points to an algorithmic difference more than a Lua-only runtime problem
- A remaining false CRC failure in the direct `miniz` non-wrapping `extract_to_mem/extract_to_heap` path on at least one external ZIP, even though the decompressed bytes are correct and the iterative extract path matches
- Large modules can still expose structural generator/runtime limits, though `lua-no-ffi` now handles at least one such case by spilling oversized top-level local sets into a table-backed representation
- Two concrete uncommitted bugs are now tracked separately in [docs/notes/lua-no-ffi-known-bugs.md](../../docs/notes/lua-no-ffi-known-bugs.md): reference-local default initialization and a near-threshold undercount in the LuaJIT local spill heuristic

## Recommended Usage

Use `lua-no-ffi` today for:

- manual debugging
- parity experiments
- controlled regression fixtures
- small and medium standalone wasm modules

Do not present it yet as:

- a drop-in replacement for the FFI-backed target
- a broad compatibility target for arbitrary wasm
- a high-performance backend

## Recommended Acceptance Gate

Before trusting a new wasm/C project on `lua-no-ffi`, check all of the following:

- `spider-cli -t lua-no-ffi` generates without panic
- generated Lua contains no FFI usage
- the module runs under LuaJIT 2.1
- result matches `wasmtime`
- if floats or `i64` are important, add a dedicated manual fixture for that case

## Current Bottom Line

`lua-no-ffi` is now real enough to use for serious debugging and controlled standalone modules.

It is not yet broad-coverage or production-ready.

The current honest claim is:

"Pure LuaJIT without FFI works for validated standalone wasm modules, and numeric parity is now demonstrated on targeted `i32`, `f32/f64`, and `i64` comparison fixtures."

That claim is now reinforced by parity on two real upstream library cores:

- `TinyExpr` for parser/evaluator logic
- `miniz` for compression/decompression buffer logic

It is now also reinforced by parity on a real upstream stateful physics-core fixture:

- `Chipmunk2D` for long-running float, collision, and constraint stepping

It is also reinforced by parity on a broader `miniz` archive fixture:

- memory-backed ZIP writer/reader/stat/locate/extract/validate behavior through `miniz_zip`

And now by parity on a file-style `miniz` fixture:

- writer/read/extract/in-place-update convenience APIs through `miniz_zip` over a virtual-`stdio` shim

And it now has a new real-world PNG codec regression fixture:

- `LodePNG`, where `variant = 0` is largely green but `variant = 1` still exposes a `lua-no-ffi` encoder divergence after input generation
- the practical plain-Lua `LodePNG` host path is still useful anyway, because its dedicated host export now uses a conservative no-LZ77 encode mode for real-file roundtrip and grayscale smoke tests

It also now has a real external host-adapter visual smoke test on `LodePNG`:

- a real PNG file is read through plain Lua file APIs, decoded in wasm, re-encoded back to disk, and verified to preserve decoded pixels on the roundtrip path

And now a first real `JPEG` codec parity fixture:

- `libjpeg-turbo`, narrowed to standalone JPEG decode, where `lua-no-ffi` now matches `wasmtime` on decoded `RGB24` probes and also writes real decoded `PPM` output through a plain-Lua host adapter

And now a first real `MJPEG` parity fixture:

- `libjpeg-turbo-mjpeg`, narrowed to concatenated-JPEG elementary streams, where `lua-no-ffi` now matches `wasmtime` on decoded `RGB24` multi-frame probes and also writes real decoded `PPM` frames through a plain-Lua host adapter with `--frame` and `--all-frames`

And now a first real emulator parity fixture:

- `binjgb`, narrowed to a scripted `cgb-acid2` Game Boy Color visual-test path, where `lua-no-ffi` now matches `wasmtime` on packed framebuffer probes and also writes real decoded `PPM` frames through a plain-Lua host adapter with `--frame` and `--all-frames`

And it now has a first real video-codec parity fixture:

- `pl_mpeg`, narrowed to raw MPEG-1 video decode, where `lua-no-ffi` now matches `wasmtime` on the canonical clip and also writes real decoded `PPM` frames through a plain-Lua host adapter

And now a first real `MP4 + H.264/AVC` parity fixture:

- `minimp4 + h264bsd`, narrowed to a constrained baseline-profile canonical clip, where `lua-no-ffi` now matches `wasmtime` on decoded `YUV420` frame probes and also writes real decoded `PPM` frames through a plain-Lua host adapter
