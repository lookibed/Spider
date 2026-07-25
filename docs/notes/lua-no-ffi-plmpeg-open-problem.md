# `lua-no-ffi` `real-world-plmpeg` Open Problem

This note captures the current unfinished work around:

- [tests/manual/real-world-plmpeg](/D:/Backups/Spider/tests/manual/real-world-plmpeg/README.md)

## Current Goal

The practical goal is to make the plain-Lua host path for `pl_mpeg` reliable on large raw MPEG-1 video inputs and user-provided streams.

## What Was Re-Checked

The older statement "1920x1080 frame 0 does not decode" was re-tested and does not reproduce now.

Current practical checks:

- `1280x720` raw `.m1v`: frame 0 decode succeeds
- `1920x1080` raw `.m1v`: frame 0 decode succeeds
- width/height/rgb size are correctly populated for both

The current fixture is already green for:

- the canonical embedded `96x64` raw MPEG-1 clip
- the plain-Lua host smoke on that canonical clip
- a generated `1280x720` raw `.m1v` sample

## Current Problem

The previous "Full HD frame 0 decode failure" is resolved in practice. The remaining behavior difference is narrower: some short external `.m1v` streams do not provide frame index `7` through the current helper path.

What is confirmed in practice now:

- `plmpeg_host_decode_frame(0)` succeeds for generated `1280x720` and `1920x1080` `.m1v`
- for some generated short ffmpeg streams, `plmpeg_host_decode_frame(7)` returns `0`
- canonical fixture `sample.m1v` still decodes frame 7 successfully
- a generated `1920x1080` 5-second stream decodes frame 0 and frame 7 successfully
- this means large resolution alone is not the blocker

That means the remaining failure is **not** explained by:

- a simple "1080p is unsupported" limit
- host file ingestion
- the old `8 MB` heap cap

The failure currently looks like a **stream-shape-specific decode boundary** in the current host helper strategy.

## Strongest Current Hypothesis

The most likely current cause is one of these:

- behavior differences between stream types (for example B-frame/reordering behavior in user-generated ffmpeg `.m1v`)
- current helper assumptions in `decode_frame_rgb(...)` / `plm_video_decode(...)` path for arbitrary external streams
- possible off-by-one/frame-flush behavior at the tail of short raw streams

This is currently considered more likely than:

- generic memory exhaustion
- host adapter I/O issues
- a pure "resolution too high" condition

## Practical Reproduction

The current practical reproduction shape is:

1. Generate `1280x720` and `1920x1080` raw MPEG-1 samples (8 frames)
2. Run [host_main.lua](/D:/Backups/Spider/tests/manual/real-world-plmpeg/host_main.lua:1)
3. Observe frame 0 decode succeeds on both
4. Observe frame 7 can fail on generated streams while canonical sample frame 7 succeeds

Observed behavior:

- generated `1280x720` / `1920x1080`
  - frame 0: success
  - frame 7: may return unavailable
- canonical `sample.m1v`
  - frame 0: success
  - frame 7: success

## Next Useful Debug Step

The next debugging pass should not focus on heap size.

The next useful step (optional now, because host smoke has fallback behavior) is to localize where external streams diverge from canonical sample behavior:

- decoded frame count seen by host helpers for each stream
- whether failing streams rely on B-frame reorder/tail flush behavior not covered by current helper assumptions
- first point where `plm_video_decode(...)` returns `NULL` for generated streams

## Important Boundary

This note is specifically about the **plain-Lua `lua-no-ffi` host helper behavior on external raw `.m1v` streams**.

The practical host smoke workflow is now resilient: it tries frame `7` and falls back to `6..1` for short streams.

A newer comparison fixture also exists now:

- [tests/manual/real-world-plmpeg-stream](/D:/Backups/Spider/tests/manual/real-world-plmpeg-stream/README.md)
- [Tools/WasmtimeHostRunner](/D:/Backups/Spider/Tools/WasmtimeHostRunner/src/main.rs:1)

That stream-oriented branch does not close every `pl_mpeg` question, but it does show that sequential host extraction can already reach `100` frames on `fixtures/fhd_5s_testsrc2.m1v`. The baseline `--all-frames` host path also reaches `100` now after host reset was added, but it remains significantly slower for large frame counts because it still re-decodes each requested frame from stream start.

The new `wasmtime` host runner now shows the same broad shape:

- baseline `100`-frame Full HD host workflow with writes: about `42518.67 ms`
- stream `100`-frame Full HD host workflow with writes: about `1960.14 ms`

That is important because it means the stream branch's advantage is not only caused by `lua-no-ffi`; the baseline helper strategy is also much heavier under a native wasm runtime.

It does **not** change the already confirmed status that:

- the canonical raw MPEG-1 parity fixture is green
- the narrower `pl_mpeg` decode-only fixture matches `wasmtime`
- `1920x1080` frame 0 decode is currently reproducible through the host path
