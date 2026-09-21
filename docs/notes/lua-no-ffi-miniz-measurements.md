# `lua-no-ffi` `miniz` Measurements

This note captures rough practical measurements for Spider's `lua-no-ffi` target on the `miniz` fixtures currently checked into the repository.

The goal is not microbenchmark precision. These numbers are meant to answer a practical question:

"How much source/output size growth do we see when porting `miniz` through Spider, and how far behind `wasmtime` is `lua-no-ffi` on the same feature slice?"

## Scope

The measurements below cover:

- [tests/manual/real-world-miniz](../../tests/manual/real-world-miniz/README.md)
- [tests/manual/real-world-miniz-full](../../tests/manual/real-world-miniz-full/README.md)
- [tests/manual/real-world-miniz-file](../../tests/manual/real-world-miniz-file/README.md)
- [tests/manual/real-archive-secret](../../tests/manual/real-archive-secret/README.md)

The first three are the most apples-to-apples for `wasmtime` vs `lua-no-ffi`.

The `real-archive-secret` case is different:

- it uses a real external `secretik.zip`
- it is driven through LuaJIT host I/O
- it is currently validated through the iterative `miniz` extract path
- it does not have the same one-command `wasmtime --invoke ...` timing shape as the other fixtures

## Source And Output Size

### `real-world-miniz`

- C input total: `3448` lines, `179585` bytes
- `.wasm`: `34930` bytes
- generated Lua: `11139` lines, `444763` bytes
- line growth vs C: `3.23x`
- byte growth vs C: `2.48x`
- Lua size vs `.wasm`: `12.73x`

This fixture is the core compression/decompression path:

- `mz_compress2()`
- `mz_uncompress()`
- `mz_crc32()`
- `mz_adler32()`

### `real-world-miniz-full`

- C input total: `8061` lines, `427087` bytes
- `.wasm`: `54142` bytes
- generated Lua: `19888` lines, `821481` bytes
- line growth vs C: `2.47x`
- byte growth vs C: `1.92x`
- Lua size vs `.wasm`: `15.17x`

This fixture extends into the in-memory ZIP/archive surface of upstream `miniz`.

### `real-world-miniz-file`

- C input total: `8335` lines, `435716` bytes
- `.wasm`: `65079` bytes
- generated Lua: `24533` lines, `1013693` bytes
- line growth vs C: `2.94x`
- byte growth vs C: `2.33x`
- Lua size vs `.wasm`: `15.58x`

This is the file-style ZIP surface over a virtual-`stdio` adapter.

### `real-archive-secret`

- C input total: `7933` lines, `423561` bytes
- `.wasm`: `24449` bytes
- generated Lua: `11133` lines, `429754` bytes
- line growth vs C: `1.40x`
- byte growth vs C: `1.01x`
- Lua size vs `.wasm`: `17.58x`

This fixture is smaller as a generated module because it only keeps the narrow feature slice needed to ingest one real external archive and extract one known file.

It still pulls in a large amount of upstream `miniz` source at build time, but dead-code elimination drops much more aggressively here than in the broader `miniz_full` and `miniz_file` fixtures.

## Runtime Timing

These timings are rough wall-clock measurements from the local Windows machine, not rigorous benchmarks.

Each number is the average of 3 runs and includes process startup plus module load/parse cost.

That matters for `lua-no-ffi`, because generated Lua parse/load time is part of the practical cost.

### `real-world-miniz`

Operation compared:

- `wasmtime --invoke miniz_roundtrip_hash ... 6`
- `luajit tests/manual/real-world-miniz/main.lua 6`

Results:

- `wasmtime`: `50.13 ms` average
- `lua-no-ffi`: `111.37 ms` average
- slowdown: `2.22x`

Samples:

- `wasmtime`: `80.45 / 30.80 / 39.14 ms`
- `lua-no-ffi`: `148.92 / 97.00 / 88.17 ms`

### `real-world-miniz-file`

Operation compared:

- `wasmtime --invoke miniz_file_hash ... 6`
- `luajit tests/manual/real-world-miniz-file/main.lua 6`

Results:

- `wasmtime`: `58.46 ms` average
- `lua-no-ffi`: `456.80 ms` average
- slowdown: `7.81x`

Samples:

- `wasmtime`: `89.38 / 42.25 / 43.76 ms`
- `lua-no-ffi`: `547.52 / 438.36 / 384.53 ms`

### `real-archive-secret`

Operation measured:

- `luajit tests/manual/real-archive-secret/main.lua`

Results:

- `lua-no-ffi`: `54.07 ms` average

Samples:

- `83.03 / 36.60 / 42.59 ms`

There is no directly equivalent single-command `wasmtime` timing here yet, because this fixture's real ZIP is supplied through the Lua host via `io.open(..., "rb")`.

So this case is useful as a practical smoke test, but not as a clean `wasmtime` parity timing benchmark.

## Practical Takeaways

The current `miniz` data suggests:

- Spider-to-`lua-no-ffi` output growth is real and substantial
- generated Lua size tends to land around `2x-3x` the source C by bytes, and much larger than the final `.wasm`
- for the core codec slice, `lua-no-ffi` is slower than `wasmtime`, but still within the same broad order of magnitude
- for the broader file-style surface, the slowdown grows significantly
- module load/parse cost is part of the real price of `lua-no-ffi`, not just steady-state execution

The honest summary is:

`miniz` is already usable through Spider and `lua-no-ffi`, but the portability win comes with visible size and runtime overhead, especially once the host-facing archive/file surface gets larger.
