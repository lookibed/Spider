# BINJGB Real-World Comparison

This fixture uses the upstream [`binji/binjgb`](https://github.com/binji/binjgb) repository as the first `GB/GBC` emulator case for `lua-no-ffi`.

The current v1 shape is intentionally narrow:

- upstream core: `binjgb`
- target mode: `Game Boy Color`
- canonical ROM: `fixtures/cgb-acid2.gbc`
- canonical startup uses a fixed scripted input path that presses `A` on frames `8..9`
- parity is defined on a packed `RGB555`-style framebuffer derived from the upstream `RGBA` framebuffer with `CGB_COLOR_CURVE_NONE`
- host visual output is `PPM`

The fixture now also supports external/manual startup presets for non-canonical ROMs:

- `acid2`
- `tetris-start`
- `tetris-start-then-a`
- `none`

Important upstream contract note:

- `binjgb` publicly exposes an `RGBA` framebuffer, not a raw internal boot-ROM-driven CGB pixel buffer
- it also initializes the emulator from its own post-boot state and does not expose a boot-ROM loading API
- this fixture therefore follows the real upstream contract: it uses `binjgb`'s built-in post-boot initialization and derives a packed `15-bit` framebuffer for parity

The fixture still includes open-source SameBoy CGB boot ROM source assets under `fixtures/bootrom-source/` as a documented reference, but they are not wired into the `binjgb` runtime path because upstream does not provide a boot-ROM loading surface.

## Files

- `src/module.c` wraps the emulator into a standalone wasm fixture
- `src/shim.c` provides a simple standalone heap and libc-style helpers
- `tools/embed_asset.ps1` converts the canonical ROM into a generated C header
- `main.lua` runs strict parity probes
- `host_main.lua` is the plain-Lua host smoke runner

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
cargo build --release -p wasmtime-host-runner
```

Generate the embedded ROM header:

```powershell
powershell -ExecutionPolicy Bypass -File tests/manual/real-world-binjgb/tools/embed_asset.ps1 -InputPath tests/manual/real-world-binjgb/fixtures/cgb-acid2.gbc -OutputPath tests/manual/real-world-binjgb/generated/cgb_acid2_data.h -SymbolName cgb_acid2_data
```

Build the standalone wasm:

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\clang.exe --% --target=wasm32 -O2 -D__wasm__ -nostdlib -Wl,--no-entry -Wl,--export-all -Itests/manual/real-world-binjgb/include -Itests/manual/real-world-binjgb/generated -Itests/manual/real-world-binjgb/upstream/src tests/manual/real-world-binjgb/src/module.c tests/manual/real-world-binjgb/src/shim.c tests/manual/real-world-binjgb/upstream/src/common.c tests/manual/real-world-binjgb/upstream/src/emulator.c tests/manual/real-world-binjgb/upstream/src/joypad.c -o tests/manual/real-world-binjgb/generated/binjgb.wasm
```

Probe with `wasmtime`:

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke binjgb_decode_hash tests/manual/real-world-binjgb/generated/binjgb.wasm 16
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke binjgb_probe_width tests/manual/real-world-binjgb/generated/binjgb.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke binjgb_probe_height tests/manual/real-world-binjgb/generated/binjgb.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke binjgb_probe_frame_count tests/manual/real-world-binjgb/generated/binjgb.wasm 16
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke binjgb_probe_first_frame_hash tests/manual/real-world-binjgb/generated/binjgb.wasm
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke binjgb_probe_last_frame_hash tests/manual/real-world-binjgb/generated/binjgb.wasm 16
```

Generate `lua-no-ffi` output:

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\real-world-binjgb\generated\binjgb.wasm -t lua-no-ffi > tests\manual\real-world-binjgb\generated\binjgb.lua"
```

Run the canonical Lua harness:

```powershell
luajit tests/manual/real-world-binjgb/main.lua lua-no-ffi 16
```

## Wasmtime Host Runner

For a symmetric host-in-the-loop comparison against the Lua host script, use:

- [Tools/WasmtimeHostRunner](/D:/Backups/Spider/Tools/WasmtimeHostRunner/src/main.rs:1)

```powershell
target\release\wasmtime-host-runner.exe --fixture gbc --mode baseline --wasm tests\manual\real-world-binjgb\generated\binjgb.wasm --input tests\manual\real-world-binjgb\fixtures\cgb-acid2.gbc --frames 16 --output-dir tests\manual\real-world-binjgb\generated\frames_wasmtime
```

Current rough `wasmtime` result on the canonical `16`-frame host-all workflow with frame writes:

- `16` frames decoded
- about `188.04 ms` total
- `RGB Size: 69120`

## External Host Adapter Visual Test

The host runner:

- reads a real `.gbc` ROM from disk with `io.open(..., "rb")`
- copies the bytes into wasm memory
- asks the module to render frames using the canonical scripted startup input
- reads the packed `RGB555`-style framebuffer back out
- converts it to `RGB24` in Lua
- writes `P6` `.ppm` frames under `generated/frames/`

For canonical `cgb-acid2`, the default preset is `acid2`.

For external ROMs:

- filenames matching `tetris*.gb` or `tetris*.gbc` default to `tetris-start`
- everything else defaults to `none`

Run it like this:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi
```

Or on your own `.gbc`:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\your.gbc
```

Force a startup preset:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\your.gbc --preset acid2
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\your.gb --preset tetris-start
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\your.gb --preset tetris-start-then-a
```

Manual button controls:

- `--buttons-mask <mask>` applies a constant bitmask on every frame
- `--script "<entry;entry;...>"` applies frame-range button masks
- script entry forms:
  - `start-end:MASK`
  - `frame:MASK`
- `MASK` may be:
  - numeric (`8`, `0x08`, `136`)
  - symbolic tokens combined by `,`, `+`, or `|` (for example `START`, `A`, `START+A`)
- supported symbols: `A`, `B`, `SELECT`, `START`, `RIGHT`, `LEFT`, `UP`, `DOWN`

Example:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\rom.gb --preset none --script "480-481:START;520-521:A"
```

Decode one exact frame:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi tests/manual/real-world-binjgb/fixtures/cgb-acid2.gbc --frame 15
```

Decode every available frame up to a cap:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi tests/manual/real-world-binjgb/fixtures/cgb-acid2.gbc --all-frames 16
```

Default smoke outputs:

- `tests/manual/real-world-binjgb/generated/frames/cgb-acid2_frame000.ppm`
- `tests/manual/real-world-binjgb/generated/frames/cgb-acid2_frame015.ppm`

Convert generated `.ppm` frames to `.png` for quick visual inspection:

```powershell
ffmpeg -y -i D:\Backups\Spider\tests\manual\real-world-binjgb\generated\frames\cgb-acid2_frame000.ppm D:\Backups\Spider\tests\manual\real-world-binjgb\generated\frames\cgb-acid2_frame000.png
ffmpeg -y -i D:\Backups\Spider\tests\manual\real-world-binjgb\generated\frames\cgb-acid2_frame015.ppm D:\Backups\Spider\tests\manual\real-world-binjgb\generated\frames\cgb-acid2_frame015.png
```

## External `Tetris` Smoke

`Tetris` is intentionally supported as an external/manual smoke workflow only:

- no commercial ROM bytes are embedded or committed in this fixture
- `cgb-acid2` remains the only canonical parity ROM
- the current `Tetris` path is best understood as a `DMG` compatibility smoke through `binjgb`

Recommended first run on a user-supplied ROM:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\Tetris.gb --preset tetris-start
```

Exact useful menu/start frame:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\Tetris.gb --preset tetris-start --frame 700
```

One practical game-field frame:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\Tetris.gb --preset none --script "520-620:START;700-710:START;920-930:START" --frame 1100
```

If a specific dump needs one extra menu confirmation after `START`, use:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\Tetris.gb --preset tetris-start-then-a --frame 700
```

For exact startup timing experiments on external dumps, use script ranges:

```powershell
luajit tests/manual/real-world-binjgb/host_main.lua lua-no-ffi path\to\Tetris.gb --preset none --frame 575 --script "500-501:START;532-533:START;564-565:A"
```

Current scripted timings are:

- `tetris-start`: hold `START` in windows `520..620`, `700..710`, and `920..930`
- `tetris-start-then-a`: same `START` windows plus `A` in `960..965`

## Current Result

This fixture is now green on its narrowed v1 scope:

- `wasmtime` and `lua-no-ffi` match on the canonical `frame_limit = 16` probe set
- `host_main.lua` writes real decoded `PPM` frames for `cgb-acid2.gbc`
- frame `15` reaches the real post-start acid2 image rather than the initial `Press A` screen

Canonical values:

- `DecodeHash = -1323964910`
- `Width = 160`
- `Height = 144`
- `FrameCount = 16`
- `FirstFrameHash = 1015431621`
- `LastFrameHash = 838717591`

Current scope remains intentionally narrow:

- `binjgb` post-boot CGB path only
- no audio
- no interactive input model beyond named startup presets plus the existing manual button-mask API
- parity defined on packed `RGB555`-style framebuffer bytes derived from upstream `RGBA`
- boot ROM source is included as a reference asset, but upstream does not expose boot-ROM loading and the fixture therefore uses `binjgb`'s built-in post-boot initialization
