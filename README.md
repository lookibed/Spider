# Spider

Spider is a compiler that translates WebAssembly binaries into Lua-family source files:

- `luau`
- `lua-jit`
- `lua-no-ffi`
- `json`

The current project story is simple:

- `lua-no-ffi` is now a real working target, not a side experiment.
- Spider is measured on full translated real-world fixtures, not toy snippets.
- The old LuaJIT limits around `upvalue`, `scope`, and giant generated closures are no longer treated as "original language limits we must accept"; they are compiler problems that Spider now attacks directly.
- The legacy `ffi` path still exists, and Windows support for that route was also extended through a machine-instructions-based implementation path.

## Short measurement table

Full numbers live in [docs/notes/lua-no-ffi-measurements.md](docs/notes/lua-no-ffi-measurements.md). This is the reduced front-page table.

| Fixture | Workload | Wasmtime | `lua-no-ffi` | `lua-jit` / host note | Size signal |
| --- | --- | ---: | ---: | ---: | --- |
| `real-world-binjgb` | canonical `frame_limit = 16` | `486.18 ms` | `4091.13 ms` | see full measurements | see full size table |
| `real-world-binjgb-host-all` | `--all-frames 16` | `188.04 ms` | `10707.79 ms` | see full measurements | host workflow row in full table |
| `real-world-plmpeg-host-all` | `--all-frames 12` on canonical sample | see full measurements | see full measurements | compare against `plmpeg-stream` in full table | host comparison lives in measurements |
| `real-world-plmpeg-stream-host-all` | `--all-frames 12` streaming path | see full measurements | see full measurements | compare against non-stream host path | host comparison lives in measurements |
| `real-world-h264bsd-mp4` | canonical MP4 probe set | see full measurements | see full measurements | control target in full table | see full size table |
| `real-world-libjpeg-turbo-mjpeg` | canonical MJPEG probe set / host-all | see full measurements | see full measurements | control target in full table | see full size table |
| `self-hosting-luanoffi-builder` | generated module snapshot | n/a | current generated `lua-no-ffi` loads past previous top-level blocker | `lua-jit` still has a deep upvalue case | `.wasm`: `165,494 B`, generated `lua-no-ffi`: `2,176,834 B` |

This is not the full matrix. The complete runtime and size tables, including more fixtures and the detailed comparisons against the old path, are in [docs/notes/lua-no-ffi-measurements.md](docs/notes/lua-no-ffi-measurements.md).

## What Spider is selling now

Spider should be read as a compiler that is proving a stronger claim than before:

1. Wasm can be lowered into plain Lua-family code without making `ffi` the center of gravity.
2. The `lua-no-ffi` target is already strong enough to stand on real translated workloads.
3. The project is actively beating back the historic failure modes of the original model: scope pressure, upvalue limits, and oversized closure-heavy code shape.

## `lua-no-ffi` is the main target

The new center of gravity is `lua-no-ffi`.

- It is benchmarked directly against the older `lua-jit` / `ffi` route.
- It is the path where backend work is currently paying off.
- It is the path that makes Spider meaningfully more portable and less dependent on host `ffi` behavior.

Read these first:

- [Notes Index](docs/notes/README.md)
- [Lua No FFI Overview](docs/notes/lua-no-ffi-overview.md)
- [Lua No FFI Measurements](docs/notes/lua-no-ffi-measurements.md)
- [Windows FFI Machine Instructions](docs/notes/windows-ffi-machine-instructions.md)

## Ten strong translated projects / fixtures

Spider is already being pushed on a broad translated workload set. Important examples:

1. [tests/manual/real-world-plmpeg](tests/manual/real-world-plmpeg/README.md)
2. [tests/manual/real-world-plmpeg-stream](tests/manual/real-world-plmpeg-stream/README.md)
3. [tests/manual/real-world-h264bsd-mp4](tests/manual/real-world-h264bsd-mp4/README.md)
4. [tests/manual/real-world-libjpeg-turbo](tests/manual/real-world-libjpeg-turbo/README.md)
5. [tests/manual/real-world-libjpeg-turbo-mjpeg](tests/manual/real-world-libjpeg-turbo-mjpeg/README.md)
6. [tests/manual/real-world-binjgb](tests/manual/real-world-binjgb/README.md)
7. [tests/manual/self-hosting-luanoffi-builder](tests/manual/self-hosting-luanoffi-builder/README.md)
8. [tests/manual/real-world-lodepng](tests/manual/real-world-lodepng/README.md)
9. [tests/manual/real-world-miniz](tests/manual/real-world-miniz/README.md)
10. [tests/manual/real-world-tinyexpr](tests/manual/real-world-tinyexpr/README.md)

This is the point of the repository now: not "can it compile a tiny wasm," but "how far can the backend go on real translated systems?"

## What changed versus the old Spider story

The old easy reading was:

- generate Lua
- rely on `ffi`
- accept original LuaJIT limits as fixed

The current reading should be:

- push `lua-no-ffi` as a first-class working target
- compare it on real fixtures against the old path
- reshape generated code when LuaJIT limits become the bottleneck
- keep the classic `ffi` route alive, including Windows support, but stop pretending it is the only serious route

## Important notes

If you want the current state quickly, read these in order:

1. [docs/notes/lua-no-ffi-overview.md](docs/notes/lua-no-ffi-overview.md)
2. [docs/notes/lua-no-ffi-measurements.md](docs/notes/lua-no-ffi-measurements.md)
3. [tests/manual/self-hosting-luanoffi-builder/README.md](tests/manual/self-hosting-luanoffi-builder/README.md)

If you want current open edges instead of the success story:

- [docs/notes/lua-no-ffi-plmpeg-open-problem.md](docs/notes/lua-no-ffi-plmpeg-open-problem.md)
- [docs/notes/lua-no-ffi-smollm2-open-problem.md](docs/notes/lua-no-ffi-smollm2-open-problem.md)

## Targets

### `lua-no-ffi`

This is the headline target.

- Reduced dependence on host `ffi`
- Measured on real fixtures
- Target-side work against `upvalue` and `scope` limits

### `lua-jit`

This remains useful as the legacy fast path and as a comparison target.

### `luau`

This remains the Luau-oriented route.

### `json`

This remains the structural/debug output target.

## Repository layout

```text
Spider/
├── CLI/                    # Command-line interface
├── Conformance/            # Conformance tests
├── IR/                     # Intermediate Representation
├── Sources/                # Source lifters / frontends
├── Targets/                # Output targets
├── Tools/                  # Helper tooling
├── docs/notes/             # Measurements, status notes, open problems
└── tests/manual/           # Real-world manual fixtures
```

## Build

```bash
cargo build --release
```

## Run

```bash
./target/release/spider-cli.exe input.wasm -t lua-no-ffi
./target/release/spider-cli.exe input.wasm -t lua-jit
./target/release/spider-cli.exe input.wasm -t luau
./target/release/spider-cli.exe input.wasm -t json
```

## Tests

```bash
cargo test
cargo test -p conformance --test luajit
cargo test -p conformance --test luau
```
