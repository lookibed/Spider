# `lua-no-ffi` Measurements

This note captures rough practical measurements for the current manual `lua-no-ffi` fixtures.

The goal is not microbenchmark precision. These numbers are meant to answer practical questions:

- how much source/output growth do we see from C to generated Lua
- how large is generated Lua compared with the final `.wasm`
- how far behind `wasmtime` is `lua-no-ffi` on the same fixture

Last refreshed: `2026-04-22`

> **`2026-09-21`: the runtime table below predates the packed-word memory transition and is no
> longer current for `lua-no-ffi`.** Linear memory moved from a byte overlay to a packed array of
> 32-bit words with a signed load contract, and the `binary32` conversions dropped `math.frexp`.
> The size table is still accurate, but every runtime figure is now pessimistic —
> `chipmunk_hash_scene(600)` alone improves `9.4x`. See [§11 of the transition
> results](lua-no-ffi-performance-hypotheses.md#11-transition-results) for the full A/B, and the
> dated row set below for the fixtures that were re-measured.

## Method

- Source counts use the compiled C inputs for each fixture, not every file in the upstream repo.
- Timings are rough wall-clock averages from the local Windows machine.
- Each timing average is based on `3` runs.
- Timings include process startup and module load/parse cost.

That last point matters a lot for `lua-no-ffi`, because parse/load time is part of the real cost of using generated Lua.

## Size Table

| Fixture | Compiled C lines | Compiled C bytes | `.wasm` bytes | Lua lines | Lua bytes | Lua/C lines | Lua/C bytes | Lua/`.wasm` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `hash-compare` | `22` | `603` | `400` | `106` | `3091` | `4.82x` | `5.13x` | `7.73x` |
| `float-compare` | `45` | `1239` | `897` | `386` | `11387` | `8.58x` | `9.19x` | `12.69x` |
| `i64-compare` | `338` | `11523` | `2435` | `649` | `25011` | `1.92x` | `2.17x` | `10.27x` |
| `real-world-tinyexpr` | `1224` | `41260` | `14548` | `6334` | `209019` | `5.17x` | `5.07x` | `14.37x` |
| `real-world-miniz` | `2946` | `150680` | `34930` | `11139` | `444763` | `3.78x` | `2.95x` | `12.73x` |
| `real-world-miniz-full` | `7200` | `370986` | `54142` | `19888` | `821481` | `2.76x` | `2.21x` | `15.17x` |
| `real-world-miniz-file` | `7453` | `378944` | `65079` | `24533` | `1013693` | `3.29x` | `2.68x` | `15.58x` |
| `real-archive-secret` | `7072` | `367460` | `24449` | `11133` | `429754` | `1.57x` | `1.17x` | `17.58x` |
| `real-world-chipmunk` | `8565` | `277429` | `56514` | `13872` | `625988` | `1.62x` | `2.26x` | `11.08x` |
| `real-world-lodepng` | `7837` | `334459` | `115716` | `33785` | `1476360` | `4.31x` | `4.41x` | `12.76x` |
| `real-world-libjpeg-turbo` | `13724` | `599842` | `351224` | `73242` | `3592440` | `5.34x` | `5.99x` | `10.23x` |
| `real-world-libjpeg-turbo-mjpeg` | `13865` | `603517` | `375047` | `73846` | `3678957` | `5.33x` | `6.10x` | `9.81x` |
| `real-world-binjgb` | `5686` | `204392` | `134905` | `34198` | `1576674` | `6.01x` | `7.71x` | `11.69x` |
| `real-world-h264bsd-mp4` | `1327` | `35146` | `165414` | `50800` | `2184930` | `38.28x` | `62.17x` | `13.21x` |
| `real-world-plmpeg` | `427` | `13023` | `50003` | `8546` | `388922` | `20.01x` | `29.86x` | `7.78x` |
| `real-world-plmpeg-stream` | `501` | `15150` | `50910` | `8777` | `397052` | `17.52x` | `26.21x` | `7.80x` |

## Runtime Table

| Fixture | Compared operation | `wasmtime` avg | `lua-no-ffi` avg | Slowdown |
| --- | --- | ---: | ---: | ---: |
| `hash-compare` | `hash_loop(123456789, 200000)` | `31.04 ms` | `16.55 ms` | `0.53x` |
| `float-compare` | `hash_f32(2048)` + `hash_f64(2048)` | `30.47 ms` | `33.46 ms` | `1.10x` |
| `i64-compare` | `hash_i64_mix(512)` + `hash_i64_div(512)` | `42.58 ms` | `26.92 ms` | `0.63x` |
| `real-world-tinyexpr` | `tinyexpr_hash(256)` + `tinyexpr_error_code()` | `48.31 ms` | `50.84 ms` | `1.05x` |
| `real-world-miniz` | `miniz_roundtrip_hash(6)` | `32.88 ms` | `78.18 ms` | `2.38x` |
| `real-world-miniz-full` | `miniz_full_hash(6)` | `38.40 ms` | `220.20 ms` | `5.73x` |
| `real-world-miniz-file` | `miniz_file_hash(6)` | `40.97 ms` | `420.68 ms` | `10.27x` |
| `real-archive-secret` | `main.lua` real ZIP smoke test | `n/a` | `39.05 ms` | `n/a` |
| `real-world-chipmunk` | `chipmunk_hash_scene(600)` | `37.40 ms` | `25866.50 ms` | `691.62x` |
| `real-world-lodepng` | `variant = 0` full probe set | `186.10 ms` | `557.32 ms` | `2.99x` |
| `real-world-lodepng-host` | `host_main.lua` real PNG smoke | `n/a` | `653.08 ms` | `n/a` |
| `real-world-libjpeg-turbo` | full JPEG probe set | `648.30 ms` | `2150.98 ms` | `3.32x` |
| `real-world-libjpeg-turbo-host` | `host_main.lua` canonical JPEG smoke | `n/a` | `406.21 ms` | `n/a` |
| `real-world-libjpeg-turbo-mjpeg` | `frame_limit = 12` full MJPEG probe set | `102.57 ms` | `3845.82 ms` | `37.49x` |
| `real-world-libjpeg-turbo-mjpeg-host` | `host_main.lua` canonical MJPEG smoke | `n/a` | `618.02 ms` | `n/a` |
| `real-world-libjpeg-turbo-mjpeg-host-all` | `host_main.lua --all-frames 12` on `fixtures/sample.mjpg` | `92.18 ms` | `870.81 ms` | `9.45x` |
| `real-world-binjgb` | `frame_limit = 16` full GBC probe set | `486.18 ms` | `4091.13 ms` | `8.42x` |
| `real-world-binjgb-host` | `host_main.lua` canonical GBC smoke | `n/a` | `2388.40 ms` | `n/a` |
| `real-world-binjgb-host-all` | `host_main.lua --all-frames 16` on `fixtures/cgb-acid2.gbc` | `188.04 ms` | `10707.79 ms` | `56.94x` |
| `real-world-h264bsd-mp4` | `frame_limit = 8` full probe set | `526.91 ms` | `7544.49 ms` | `14.32x` |
| `real-world-h264bsd-mp4-host` | `host_main.lua` canonical MP4 smoke | `n/a` | `2326.19 ms` | `n/a` |
| `real-world-h264bsd-mp4-host-all` | `host_main.lua --all-frames 12` on `fixtures/sample.mp4` | `78.56 ms` | `14775.48 ms` | `188.08x` |
| `real-world-plmpeg` | `frame_limit = 8` full probe set | `319.91 ms` | `6884.42 ms` | `21.52x` |
| `real-world-plmpeg-stream` | `frame_limit = 8` full probe set | `319.38 ms` | `6789.22 ms` | `21.26x` |
| `real-world-plmpeg-host-all` | `host_main.lua --all-frames 12` on `fixtures/sample.m1v` | `66.33 ms` | `1800.14 ms` | `27.14x` |
| `real-world-plmpeg-stream-host-all` | `host_stream_main.lua 12` on `fixtures/sample.m1v` | `40.38 ms` | `1168.06 ms` | `28.93x` |
| `real-world-plmpeg-host` | `host_main.lua --all-frames 100` on `fixtures/fhd_5s_testsrc2.m1v` | `42518.67 ms` | `860533.80 ms` | `20.24x` |
| `real-world-plmpeg-stream-host` | `host_stream_main.lua 100` on `fixtures/fhd_5s_testsrc2.m1v` | `1960.14 ms` | `51550.41 ms` | `26.30x` |

## Runtime Table, `2026-09-21` Packed-Word Update

Re-measured on Linux (WSL2), `LuaJIT 2.1.0-beta3`, against a build of commit `aa08225` — the
immediate predecessor of the transition — in a separate target directory. Variants were installed
round-robin, minimum of five runs each, and the installed module was re-checked against a variant
marker before and after every timing.

These are **not** comparable with the table above: that one is a Windows machine, `3`-run averages,
and in several cases different iteration counts. Compare `before` with `after` inside this table only.

In-process kernels — module loaded once, export warmed, minimum `os.clock` of five calls:

| Fixture | Compared operation | before | after | speed-up |
| --- | --- | ---: | ---: | ---: |
| `real-world-chipmunk` | `chipmunk_hash_scene(60)` | `959.1 ms` | `15.6 ms` | `61.3x` |
| `real-world-chipmunk` | `chipmunk_hash_scene(600)` | `29 681 ms` | `3 147 ms` | `9.43x` |
| `real-world-lodepng` | `lodepng_roundtrip_hash(0)` | `140.8 ms` | `29.7 ms` | `4.73x` |
| `real-world-binjgb` | `binjgb_decode_hash(16)` | `2 219.0 ms` | `597.6 ms` | `3.71x` |
| `real-world-tinyexpr` | `tinyexpr_hash(256)` | `4.07 ms` | `2.55 ms` | `1.59x` |
| `real-world-miniz` | `miniz_roundtrip_hash(6)` | `0.077 ms` | `0.085 ms` | `0.90x` |

`chipmunk_hash_scene(600)` is the workload this note records above at `691x` slower than `wasmtime`.
Against the same `37.40 ms` anchor it is now about `84x`. The `tinyexpr` and `miniz` kernels run in
`4 ms` and `80 µs` and are at the timing floor; treat them as "`1.6x`–`3.5x`" and "no change".

Whole process, including startup and module load/parse, which is the cost a user actually pays:

| Fixture | Command | before | after | speed-up | RSS before | RSS after |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `real-world-chipmunk` | `main.lua lua-no-ffi 60` | `5.45 s` | `0.35 s` | `15.57x` | `16.1 MB` | `21.8 MB` |
| `chipmunk-profile` | `main.lua` | `5.36 s` | `0.64 s` | `8.37x` | `17.4 MB` | `25.2 MB` |
| `real-world-binjgb` | `main.lua lua-no-ffi 16` | `6.62 s` | `1.63 s` | `4.06x` | `26.2 MB` | `291.8 MB` |
| `real-world-miniz` | `main.lua` | `0.10 s` | `0.03 s` | `3.33x` | `12.5 MB` | `5.6 MB` |
| `real-world-lodepng` | `main.lua lua-no-ffi 0` | `0.54 s` | `0.19 s` | `2.84x` | `20.8 MB` | `42.4 MB` |
| `real-world-lodepng` | `main.lua lua-no-ffi 1` | `0.66 s` | `0.24 s` | `2.75x` | `24.3 MB` | `45.6 MB` |
| `self-hosting-luanoffi-builder` | `main.lua lua-no-ffi` | `0.16 s` | `0.08 s` | `2.00x` | `8.3 MB` | `18.9 MB` |
| `real-world-gltf-rs` | `main.lua` | `0.10 s` | `0.09 s` | `1.11x` | `9.9 MB` | `24.9 MB` |
| `real-world-tinyexpr` | `main.lua 200000` | `0.54 s` | `0.50 s` | `1.08x` | `6.1 MB` | `6.4 MB` |

Three caveats worth carrying forward:

- **Memory moves in both directions.** A word array costs a flat `2.00x` of the *declared* linear
  memory, whatever fraction of it is touched. `miniz` declares little and writes it densely, so it
  now uses `0.45x` the RSS; `binjgb` declares `64 MiB` and touches a fraction of it, so it uses
  `11.1x`. The `binjgb` figure is the one open regression from the transition.
- **Small fixtures are startup-bound.** `tinyexpr` at `200 000` iterations still spends most of its
  half second loading a `229 KB` Lua module, which is why its whole-process row reads `1.08x` while
  its kernel row reads `1.59x`.
- **Size is essentially unchanged.** Every module grows by the same `~5 KB` of runtime library text:
  `+0.1%` to `+2.1%` for the `22` modules above `200 KB`, and up to `+35.7%` for `hash_loop.lua`,
  which is `7.5 KB` in total. The size table above still stands.

## Notes Per Fixture

### Small comparison fixtures

`hash-compare`, `float-compare`, and `i64-compare` are tiny standalone kernels. On these, startup noise is a large part of total runtime, so `lua-no-ffi` can look surprisingly close to `wasmtime`, and sometimes even faster in wall-clock terms.

That does **not** mean generated Lua is inherently faster. It means these fixtures are too small for process startup noise to disappear into the workload.

### `real-world-tinyexpr`

`TinyExpr` stays close to `wasmtime` in this measurement set:

- parser/evaluator logic is real
- module size is moderate
- the workload is still much lighter than the archive-heavy or physics-heavy cases

### `real-world-miniz`

The `miniz` family shows the most useful current middle ground:

- codec-only `miniz` is still within about `2x`
- archive-heavy `miniz_full` rises to about `5.43x`
- file-style `miniz_file` rises further to about `9.17x`

This is a good picture of how the portability cost grows as the library surface gets broader and more stateful.

### `real-archive-secret`

This fixture is host-integrated:

- the real ZIP is provided through LuaJIT `io.open(..., "rb")`
- there is no directly equivalent one-command `wasmtime --invoke ...` timing

It is still valuable as a real smoke test, but it is not as clean a parity benchmark as the purely exported-function cases.

### `real-world-chipmunk`

`Chipmunk2D` is currently the clearest warning sign in the measurement set:

- parity is correct
- generated Lua is still loadable after the printer-side local-spill fix
- but pure-Lua runtime cost on a long-running stateful physics workload is extremely high

This is the first current fixture that makes the performance boundary of `lua-no-ffi` impossible to ignore.

### `real-world-lodepng`

`LodePNG` now adds a useful image-codec point between `miniz` and `chipmunk`:

- the core `variant = 0` probe set lands at about `2.99x` slower than `wasmtime`
- generated Lua is large: `33785` lines and `1476360` bytes from a `115716` byte `.wasm`
- there is also a practical plain-Lua host smoke path for real PNG files

The host smoke is intentionally listed separately because it is not a symmetric `wasmtime --invoke ...` case:

- it reads a real PNG from disk with Lua file I/O
- moves bytes through the host adapter
- writes real output PNGs back to disk

That makes it a good practical workflow measurement, but not a pure engine-to-engine benchmark.

### `real-world-libjpeg-turbo`

`real-world-libjpeg-turbo` now adds a first green `JPEG` codec point:

- the canonical fixture decodes a real upstream `sample.jpg` through `libjpeg-turbo` into `RGB24`
- parity is green on the decoded-byte probe set, not on encoded JPEG identity
- generated Lua is large but still below the `h264bsd-mp4` point: `73242` lines and `3592440` bytes from a `351224` byte `.wasm`
- the full probe set lands at about `3.32x` slower than `wasmtime`

The host smoke is intentionally listed separately:

- it reads a real `.jpg` from disk through plain Lua file I/O
- it decodes in wasm and writes a real `PPM` under `generated/frames/`
- this is a useful practical image workflow measurement, but not a symmetric host-runner comparison yet

This fixture should currently be read as a `JPEG`/`MJPEG-class` stepping stone:

- the codec core is now validated through `libjpeg-turbo`
- but there is still no separate MJPEG container or stream fixture in this branch

### `real-world-libjpeg-turbo-mjpeg`

`real-world-libjpeg-turbo-mjpeg` is now the first green `MJPEG`-style multi-frame fixture built on the same upstream codec core:

- the canonical input is a tiny `12`-frame `sample.mjpg` elementary stream made from concatenated JPEG frames
- parity is green on decoded `RGB24` frame bytes, folded across the stream rather than on encoded stream identity
- generated Lua is only slightly larger than the JPEG-only branch: `73846` lines and `3678957` bytes from a `375047` byte `.wasm`
- the full `frame_limit = 12` probe set currently lands at about `37.49x` slower than `wasmtime`

The host smoke is intentionally listed separately:

- it reads a real `.mjpg` through plain Lua file I/O
- it supports the same practical manual modes we used on the video fixtures: default smoke, `--frame N`, and `--all-frames [max]`
- it writes real decoded `PPM` frames under `generated/frames/`
- the canonical `--all-frames 12` pass currently averages about `92.18 ms` in the symmetric `wasmtime` host runner versus `870.81 ms` in the current Lua host script, about `9.45x` slower

This makes the split between the two `libjpeg-turbo` fixtures useful:

- `real-world-libjpeg-turbo` stays the narrower single-image JPEG codec point
- `real-world-libjpeg-turbo-mjpeg` adds the first sequential multi-frame `MJPEG` path without bringing in a heavier video container stack

### `real-world-binjgb`

`real-world-binjgb` is now the first green emulator fixture in the set:

- it drives upstream `binjgb` on `cgb-acid2` with fixed scripted startup input so the canonical path reaches the real post-start visual test image rather than the idle `Press A` screen
- parity is defined on packed `RGB555`-class framebuffer bytes folded across frames `0..15`
- generated Lua lands in the middle of the current large-fixture range: `34198` lines and `1576674` bytes from a `134905` byte `.wasm`
- the full `frame_limit = 16` probe set currently lands at about `8.42x` slower than `wasmtime`

The host smoke is intentionally listed separately:

- it reads a real `.gbc` ROM through plain Lua file I/O
- it supports strict canonical smoke, `--frame N`, and `--all-frames [max]`
- it writes real decoded `PPM` frames under `generated/frames/`
- the canonical `--all-frames 16` pass currently averages about `188.04 ms` in the symmetric `wasmtime` host runner versus `10707.79 ms` in the current Lua host script, about `56.94x` slower

There is one important implementation nuance here:

- upstream `binjgb` exposes an `RGBA` framebuffer and built-in post-boot initialization, not a public boot-ROM loading API plus native `RGB555` framebuffer export
- the fixture therefore derives the packed `RGB555` parity surface from upstream `RGBA` output while keeping the boot-ROM source asset in-tree as an explicit reference input rather than an active runtime dependency

### `real-world-h264bsd-mp4`

`real-world-h264bsd-mp4` is the first green `MP4 + H.264/AVC` fixture in the set:

- it combines `minimp4` demux with `h264bsd` decode on a constrained baseline-profile canonical clip
- parity is green on decoded `YUV420` frame data, not encoded-bytes identity
- generated Lua is much larger than the MPEG-1 `pl_mpeg` fixtures: `50800` lines and `2184930` bytes from a `165414` byte `.wasm`
- runtime cost is still practical enough for a correctness fixture, but clearly above the earlier video point at about `14.32x` slower than `wasmtime`

The host smoke is intentionally listed separately because it is not a symmetric `wasmtime --invoke ...` case:

- it reads a real `.mp4` from disk with Lua file I/O
- decodes frame `0` and then `7` with fallback
- converts `YUV420` planes to RGB in Lua
- writes real `PPM` frames under `generated/frames/`

The new `--all-frames [max]` host mode is recorded separately too:

- on the canonical `12`-frame clip, `--all-frames 12` averages about `14775.48 ms`
- the symmetric `wasmtime` runner reaches the same `12`-frame workflow in about `78.56 ms`
- this is much slower than the default smoke path because the current baseline runner re-runs `decode_frame(index)` from the start for each requested frame

### `real-world-plmpeg`

`pl_mpeg` is now the first green video-decode parity fixture for `lua-no-ffi`:

- the canonical clip is a tiny raw MPEG-1 video sample (`sample.m1v`)
- `wasmtime` and `lua-no-ffi` now agree on the full `frame_limit = 8` probe set
- the plain-Lua host adapter also writes real decoded `PPM` frames to disk

This makes `pl_mpeg` a useful midpoint between image codecs like `LodePNG` and much scarier future targets like `libvpx`: it is a real video decoder, but still small enough to validate end-to-end today.

### `real-world-plmpeg-stream`

`real-world-plmpeg-stream` is the stateful comparison branch for the same upstream codec:

- it keeps the same canonical parity probes as `real-world-plmpeg`
- it adds a `begin -> decode_next -> end` host path
- it writes frames under `generated/frames/` so repeated runs stay easier to compare

The most important practical comparison on the current Full HD `5s` sample is:

- baseline `host_main.lua --all-frames 100` now completes all `100` frames in about `860533.80 ms`
- stream `host_stream_main.lua 100` completes the same `100` frames in about `51550.41 ms`
- symmetric `wasmtime` host runner numbers are now available for the same workflow:
  - baseline `100` frames with writes: about `42518.67 ms`
  - stream `100` frames with writes: about `1960.14 ms`

The baseline path is now correct on this workload, but it remains much slower because each requested frame is decoded from the beginning of the stream again after a host reset.

On the smaller canonical `sample.m1v`, the same comparison is now also recorded in a more directly comparable shape against the other codec host-all rows:

- baseline `host_main.lua --all-frames 12` averages about `66.33 ms` in the symmetric `wasmtime` runner versus `1800.14 ms` in `lua-no-ffi`
- stream `host_stream_main.lua 12` averages about `40.38 ms` in the symmetric `wasmtime` runner versus `1168.06 ms` in `lua-no-ffi`
- both paths currently decode `11` available frames on this sample when asked for `12`, so these rows are still apples-to-apples with each other even though the stream is shorter than the requested cap

So the honest comparison is:

- baseline and stream both complete `100` frames on this workload
- stream is much faster in total wall-clock time because it keeps decoder state and advances sequentially
- normalized by decoded frames, stream is still much better for this case (`~515.50 ms/frame` vs `~8605.34 ms/frame`, about `16.69x` better)
- the same algorithmic gap is visible under `wasmtime` too (`~19.60 ms/frame` vs `~425.19 ms/frame`, about `21.69x` better), which shows that this difference is not just a `lua-no-ffi` artifact

## Practical Takeaways

- Generated Lua is consistently much larger than the final `.wasm`.
- Small synthetic fixtures are useful for semantics, but misleading for performance expectations.
- `TinyExpr` and core `miniz` are still in a practically usable range.
- Broader archive/file surfaces get expensive faster.
- `LodePNG` sits in the middle: expensive enough to notice, but nowhere near the `Chipmunk2D` cliff.
- `real-world-libjpeg-turbo-mjpeg` is a much harsher multi-frame codec workload than the JPEG-only branch, even though both ride on the same upstream decode core.
- `real-world-h264bsd-mp4` is the new H.264/MP4 midpoint: clearly heavier than `LodePNG`, but still far from the `Chipmunk2D` cliff and already useful as a real codec parity fixture.
- `pl_mpeg` is now a real correctness win and a useful first video performance point, but it still measures only the narrowed raw-video path, not full MPEG-PS demux or a modern codec stack.
- `real-world-plmpeg-stream` gives a better foundation for sequential multi-frame host extraction, and the new `wasmtime` host runner shows that its win over the baseline path is mostly algorithmic rather than Lua-specific.
- Long-running stateful float workloads like `Chipmunk2D` are currently correctness wins, not performance wins.

The honest summary is:

`lua-no-ffi` is now strong enough to validate real upstream libraries for correctness, but the performance profile still depends heavily on workload shape, and stateful float-heavy simulations are currently very expensive.

## Runtime Table, `2026-09-23` Linux re-measurement

A fresh three-way run of the fixtures from the Runtime Table above, on Linux (WSL2, 16 cores),
against commit `816091a` (packed-word memory runtime). `wasmtime-cli 24.0.1`, `LuaJIT 2.1.0-beta3`.
The CLI was built in a private target directory and every `lua-no-ffi` and `lua-jit` module was
regenerated from the fixture's `.wasm` into a scratch copy of the fixture layout; the fresh
`lua-no-ffi` output is byte-identical to the checked-in `generated/*.lua` for every fixture.
Every result matched `wasmtime` bit for bit (both Lua targets, wherever they load).

Load average: `0.05` before the series; the one-minute figure rose to `2.8` at its peak during the
run, which is the measurement itself (`wasmtime -C cache=n` compiles with parallel Cranelift
threads), and was back under `1.0` at the end.

How each column was taken:

- **Whole process** — `/usr/bin/time`, minimum of five runs. `wasmtime` is
  `wasmtime run -C cache=n --invoke <export> <file.wasm> <args>`; for a multi-export operation it is
  the **sum** of one process per export (minimum of five each), which is how the Windows table was
  taken. So `wasmtime` pays module compilation once per export: `~10 ms` for `hash_loop.wasm`,
  `~50 ms` for the `libjpeg-turbo` modules, and `46.5 ms × 16` for the self-hosting fixture. The Lua
  side is one `luajit` process that loads the generated module once and calls the same exports once.
- **Kernel** — the Lua side is `os.clock()` around the export calls only, inside a driver that loads
  the module once, warms the operation up once, and takes the minimum of five. The instance is
  reused when repeated calls return the same result. Rows marked † get a fresh instance for every
  timed call because a second call in the same instance changes the result (the `miniz` bump
  heap) or because `main.lua` builds one instance per probe (both `libjpeg-turbo` fixtures). A
  fresh instance costs a re-trace, because traces are specialised to closure identity: `lodepng`
  runs in `167 ms` fresh against `97 ms` reused, and `selfhost` in `34 ms` against `15 ms`.
  **The `wasmtime` column is an approximation.** It is the whole-process time of a precompiled
  module (`wasmtime compile`, then `run --allow-precompiled`, minimum of fifteen) minus the same
  module invoked with a non-existent export (`6.2`–`6.5 ms`), summed over the exports. Under `1 ms`
  it is inside the noise, so it is shown as `< 1 ms` and the ratio as a lower bound.
- **Max RSS** — `%M` from `/usr/bin/time`, largest of the five whole-process runs.
- **Traces** — `luajit -jv` over one whole-process run: traces started and `TRACE ---` aborts.

The old Windows column is the slowdown from the Runtime Table above: Windows, three-run averages,
whole-process, pre-transition runtime. It compares directly only with the whole-process column
here. In the kernel table it is context only, because the old figures were dominated by startup
on the small fixtures.

`lua-jit` fails to load on nine of the fifteen rows (eight fixtures) with `function at line N has more than 60
upvalues`: `tinyexpr`, `miniz-full`, `miniz-file`, `chipmunk`, `libjpeg-turbo`, `libjpeg-turbo-mjpeg`,
self-hosting, and `gltf-rs`. `wasmtime` cannot run `gltf-rs` from the CLI: it needs the host to copy
the `.glb` into linear memory before the call.

#### Whole process (`/usr/bin/time`, minimum of five)

| Fixture | Compared operation | `wasmtime` | `lua-no-ffi` | `lua-jit` | no-ffi / `wasmtime` | old Windows slowdown |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `hash-compare` | `hash_loop(123456789, 200000)` | `10.0 ms` | `2.83 ms` | `2.46 ms` | `0.28x` | `0.53x` |
| `float-compare` | `hash_f32(2048) + hash_f64(2048)` | `19.8 ms` (2 procs) | `10.8 ms` | `23.9 ms` | `0.55x` | `1.10x` |
| `i64-compare` | `hash_i64_mix(512) + hash_i64_div(512)` | `22.0 ms` (2 procs) | `7.34 ms` | `2.69 ms` | `0.33x` | `0.63x` |
| `real-world-tinyexpr` | `tinyexpr_hash(256) + tinyexpr_error_code()` | `29.2 ms` (2 procs) | `15.6 ms` | fails to load | `0.54x` | `1.05x` |
| `real-world-miniz` | `miniz_roundtrip_hash(6)` | `25.5 ms` | `28.6 ms` | `35.9 ms` | `1.12x` | `2.38x` |
| `real-world-miniz-full` | `miniz_full_hash(6)` | `28.3 ms` | `40.4 ms` | fails to load | `1.43x` | `5.73x` |
| `real-world-miniz-file` | `miniz_file_hash(6)` | `28.7 ms` | `75.6 ms` | fails to load | `2.63x` | `10.27x` |
| `real-world-chipmunk` | `chipmunk_hash_scene(600)` | `22.0 ms` | `2 449 ms` | fails to load | `111.15x` | `691.62x` |
| `real-world-chipmunk` | `chipmunk_hash_scene(60)` | `20.6 ms` | `66.5 ms` | fails to load | `3.23x` | n/a |
| `real-world-lodepng` | `variant = 0 full probe set` (5 exports) | `151 ms` (5 procs) | `153 ms` | `93.6 ms` | `1.01x` | `2.99x` |
| `real-world-libjpeg-turbo` | `full JPEG probe set` (6 exports) | `306 ms` (6 procs) | `675 ms` | fails to load | `2.21x` | `3.32x` |
| `real-world-libjpeg-turbo-mjpeg` | `frame_limit = 12 full probe set` (8 exports) | `412 ms` (8 procs) | `1 356 ms` | fails to load | `3.29x` | `37.49x` |
| `real-world-binjgb` | `frame_limit = 16 full probe set` (6 exports) | `258 ms` (6 procs) | `1 599 ms` | `837 ms` | `6.20x` | `8.42x` |
| `self-hosting-luanoffi-builder` | `full probe set` (3 cases, 16 exports) | `720 ms` (16 procs) | `69.8 ms` | fails to load | `0.10x` | n/a |
| `real-world-gltf-rs` | `gltf_compute_hash on fixtures/Box.glb` | n/a | `86.5 ms` | fails to load | n/a | n/a |

#### In-process kernel (compared operation only)

| Fixture | Compared operation | `wasmtime` (approx.) | `lua-no-ffi` | `lua-jit` | no-ffi / `wasmtime` | old Windows slowdown |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `hash-compare` | `hash_loop(123456789, 200000)` | `< 1 ms` | `0.44 ms` | `0.44 ms` | noise | `0.53x` |
| `float-compare` | `hash_f32(2048) + hash_f64(2048)` | `< 1 ms` | `0.39 ms` | `0.15 ms` | noise | `1.10x` |
| `i64-compare` | `hash_i64_mix(512) + hash_i64_div(512)` | `< 1 ms` | `0.82 ms` | `0.02 ms` | noise | `0.63x` |
| `real-world-tinyexpr` | `tinyexpr_hash(256) + tinyexpr_error_code()` | `< 1 ms` | `1.56 ms` | fails to load | `> 1.6x` | `1.05x` |
| `real-world-miniz` | `miniz_roundtrip_hash(6)` | `< 1 ms` | `8.48 ms` † | `1.52 ms` | `> 8.5x` | `2.38x` |
| `real-world-miniz-full` | `miniz_full_hash(6)` | `< 1 ms` | `8.44 ms` | fails to load | `> 8.4x` | `5.73x` |
| `real-world-miniz-file` | `miniz_file_hash(6)` | `< 1 ms` | `22.9 ms` | fails to load | `> 22.9x` | `10.27x` |
| `real-world-chipmunk` | `chipmunk_hash_scene(600)` | `2.72 ms` | `2 543 ms` | fails to load | `936.47x` | `691.62x` |
| `real-world-chipmunk` | `chipmunk_hash_scene(60)` | `< 1 ms` | `10.5 ms` | fails to load | `> 10.5x` | n/a |
| `real-world-lodepng` | `variant = 0 full probe set` (5 exports) | `3.33 ms` | `127 ms` | `19.7 ms` | `38.10x` | `2.99x` |
| `real-world-libjpeg-turbo` | `full JPEG probe set` (6 exports) | `2.16 ms` | `263 ms` † | fails to load | `122.15x` | `3.32x` |
| `real-world-libjpeg-turbo-mjpeg` | `frame_limit = 12 full probe set` (8 exports) | `5.42 ms` | `954 ms` † | fails to load | `175.77x` | `37.49x` |
| `real-world-binjgb` | `frame_limit = 16 full probe set` (6 exports) | `29.3 ms` | `1 062 ms` | `759 ms` | `36.21x` | `8.42x` |
| `self-hosting-luanoffi-builder` | `full probe set` (3 cases, 16 exports) | `2.59 ms` | `12.3 ms` | fails to load | `4.77x` | n/a |
| `real-world-gltf-rs` | `gltf_compute_hash on fixtures/Box.glb` | n/a | `8.73 ms` | fails to load | n/a | n/a |

#### Max RSS (whole process)

| Fixture | Compared operation | `wasmtime` | `lua-no-ffi` | `lua-jit` | no-ffi / `wasmtime` |
| --- | --- | ---: | ---: | ---: | ---: |
| `hash-compare` | `hash_loop(123456789, 200000)` | `19.6 MB` | `2.6 MB` | `2.5 MB` | `0.13x` |
| `float-compare` | `hash_f32(2048) + hash_f64(2048)` | `20.1 MB` | `3.2 MB` | `2.9 MB` | `0.16x` |
| `i64-compare` | `hash_i64_mix(512) + hash_i64_div(512)` | `21.4 MB` | `3.4 MB` | `2.8 MB` | `0.16x` |
| `real-world-tinyexpr` | `tinyexpr_hash(256) + tinyexpr_error_code()` | `25.1 MB` | `4.5 MB` | fails to load | `0.18x` |
| `real-world-miniz` | `miniz_roundtrip_hash(6)` | `30.5 MB` | `5.4 MB` | `4.4 MB` | `0.18x` |
| `real-world-miniz-full` | `miniz_full_hash(6)` | `36.7 MB` | `20.2 MB` | fails to load | `0.55x` |
| `real-world-miniz-file` | `miniz_file_hash(6)` | `39.3 MB` | `45.0 MB` | fails to load | `1.15x` |
| `real-world-chipmunk` | `chipmunk_hash_scene(600)` | `29.0 MB` | `25.2 MB` | fails to load | `0.87x` |
| `real-world-chipmunk` | `chipmunk_hash_scene(60)` | `28.9 MB` | `17.6 MB` | fails to load | `0.61x` |
| `real-world-lodepng` | `variant = 0 full probe set` (5 exports) | `41.4 MB` | `41.9 MB` | `23.4 MB` | `1.01x` |
| `real-world-libjpeg-turbo` | `full JPEG probe set` (6 exports) | `48.6 MB` | `139.2 MB` | fails to load | `2.86x` |
| `real-world-libjpeg-turbo-mjpeg` | `frame_limit = 12 full probe set` (8 exports) | `49.0 MB` | `201.4 MB` | fails to load | `4.11x` |
| `real-world-binjgb` | `frame_limit = 16 full probe set` (6 exports) | `38.8 MB` | `281.5 MB` | `79.1 MB` | `7.25x` |
| `self-hosting-luanoffi-builder` | `full probe set` (3 cases, 16 exports) | `43.6 MB` | `18.5 MB` | fails to load | `0.42x` |
| `real-world-gltf-rs` | `gltf_compute_hash on fixtures/Box.glb` | n/a | `24.0 MB` | fails to load | n/a |

#### Generated size and JIT trace health (`luajit -jv`, one whole run)

| Fixture | `.wasm` bytes | `lua-no-ffi` bytes | `lua-jit` bytes | no-ffi traces / aborts | `lua-jit` traces / aborts | top no-ffi abort reasons |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `hash-compare` | `400` | `10182` | `4612` | `5 / 0` | `4 / 0` | — |
| `float-compare` | `897` | `23794` | `17443` | `49 / 34` | `28 / 27` | loop unroll limit reached ×32; leaving loop in root trace ×2 |
| `i64-compare` | `2435` | `36854` | `19104` | `74 / 10` | `12 / 0` | loop unroll limit reached ×10 |
| `real-world-tinyexpr` | `14548` | `229325` | `198858` | `118 / 47` | fails to load | loop unroll limit reached ×12; call unroll limit reached ×12; inner loop in root trace ×11 |
| `real-world-miniz` | `34930` | `459004` | `434665` | `101 / 117` | `89 / 60` | loop unroll limit reached ×84; leaving loop in root trace ×26; inner loop in root trace ×7 |
| `real-world-miniz-full` | `54142` | `834407` | `795668` | `141 / 65` | fails to load | loop unroll limit reached ×36; leaving loop in root trace ×21; inner loop in root trace ×8 |
| `real-world-miniz-file` | `65079` | `1022685` | `981759` | `208 / 128` | fails to load | loop unroll limit reached ×81; leaving loop in root trace ×34; inner loop in root trace ×12 |
| `real-world-chipmunk` (`600`) | `56514` | `632100` | `595106` | `18103 / 11575` | fails to load | loop unroll limit reached ×9053; inner loop in root trace ×1179; leaving loop in root trace ×820 |
| `real-world-chipmunk` (`60`) | `56514` | `632100` | `595106` | `570 / 372` | fails to load | loop unroll limit reached ×309; leaving loop in root trace ×30; inner loop in root trace ×27 |
| `real-world-lodepng` | `115716` | `1478703` | `1435117` | `979 / 478` | `431 / 1372` | loop unroll limit reached ×242; too many snapshots ×92; leaving loop in root trace ×65 |
| `real-world-libjpeg-turbo` | `351224` | `3625308` | `3516777` | `1138 / 752` | fails to load | loop unroll limit reached ×297; NYI: register coalescing too complex ×251; inner loop in root trace ×102 |
| `real-world-libjpeg-turbo-mjpeg` | `375047` | `3711775` | `3603056` | `4464 / 1964` | fails to load | loop unroll limit reached ×1082; inner loop in root trace ×418; leaving loop in root trace ×204 |
| `real-world-binjgb` | `135932` | `1618090` | `1571457` | `4074 / 8651` | `1509 / 7247` | NYI: register coalescing too complex ×7130; loop unroll limit reached ×1216; blacklisted ×112 |
| `self-hosting-luanoffi-builder` | `171389` | `2068990` | `1995751` | `163 / 167` | fails to load | loop unroll limit reached ×122; inner loop in root trace ×27; leaving loop in root trace ×16 |
| `real-world-gltf-rs` | `552966` | `8014955` | `7921514` | `94 / 100` | fails to load | loop unroll limit reached ×80; leaving loop in root trace ×10; inner loop in root trace ×7 |


The biggest remaining gaps, ranked by kernel slowdown against `wasmtime`:

1. `chipmunk_hash_scene(600)` — `~940x` kernel and `111x` whole process, down from `692x` whole
   process on the old table. The trace log explains it: `18 103` traces, `11 575` aborts, `9 053`
   of them `loop unroll limit reached`. At `60` steps the same code runs `> 10x` slower
   (`3.2x` whole process), so the cost is in the long, steady simulation phase and not in load.
2. `libjpeg-turbo-mjpeg`, `frame_limit = 12` — `~176x` kernel †, `3.3x` whole process (old `37.5x`).
   The probe set decodes the stream three times, each in a fresh instance. On a reused instance
   one warm `decode_hash(12)` takes about `235 ms`.
3. `libjpeg-turbo` — `~122x` kernel †, `2.2x` whole process. `251` aborts are
   `NYI: register coalescing too complex`, which usually points to too many live values in one trace.
4. `lodepng`, `variant = 0` — `~38x` kernel, `1.0x` whole process. `lua-jit` runs the same kernel in
   `19.7 ms` against `127 ms`, so most of this gap is the cost of the packed-word memory and not of
   the control flow.
5. `binjgb`, `frame_limit = 16` — `~36x` kernel, `6.2x` whole process, and `7.3x` the RSS
   (`281 MB`, which is `2x` of the `64 MiB` declared memory plus tables). `7 130` of its `8 651`
   aborts are `NYI: register coalescing too complex`. `lua-jit` is only `1.4x` faster here, so this
   one is trace-shape bound more than memory-representation bound.
6. `miniz-file` — `> 23x` kernel, `2.6x` whole process.

Everything below that is within `~10x` in kernel and within `3.3x` in whole process. Whole
process looks much kinder than the kernel figures because `wasmtime -C cache=n` spends `10`–`50 ms`
per process compiling. For short workloads that compile time outweighs the Lua interpreter;
for anything longer than a few hundred milliseconds of real work the kernel column is the one that
predicts behaviour.
