# Chipmunk2D Real-World Comparison

This fixture uses the upstream [`Chipmunk2D`](https://github.com/slembcke/Chipmunk2D) repository as a real-world float/state/control-flow case for `lua-no-ffi`.

The wasm module is built as a standalone non-WASI physics-core module:
- upstream `Chipmunk2D` sources are used directly from `upstream/`
- `src/shim.c` provides heap, memory, sort, math, and diagnostic stubs needed for standalone wasm
- `src/module.c` exports:
  - `chipmunk_hash_scene(i32) -> i32`
  - `chipmunk_hash_scene_variant(i32) -> i32`
  - `chipmunk_probe_body_x(i32, i32) -> i32`
  - `chipmunk_probe_body_y(i32, i32) -> i32`
  - `chipmunk_probe_angle(i32, i32) -> i32`

The workload:
- creates a deterministic `cpSpace`
- adds a ground, a slope, four dynamic bodies, and three constraints
- steps the simulation with fixed `dt = 1/120`
- hashes positions, velocities, angles, and angular velocities into an `i32`

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
$chipmunkSources = Get-ChildItem tests/manual/real-world-chipmunk/upstream/src/*.c | Where-Object { $_.Name -notin @('cpHastySpace.c', 'cpMarch.c', 'cpPolyline.c', 'cpSpaceDebug.c') } | ForEach-Object { $_.FullName }
D:\Backups\WASI\wasi-sdk-24.0\bin\wasm32-wasi-clang.exe -DNDEBUG -DCP_USE_DOUBLES=1 -Oz -nostdlib -ffunction-sections -fdata-sections -Itests/manual/real-world-chipmunk/upstream/include -Wl,--gc-sections -Wl,--no-entry -Wl,--export=chipmunk_hash_scene -Wl,--export=chipmunk_hash_scene_variant -Wl,--export=chipmunk_probe_body_x -Wl,--export=chipmunk_probe_body_y -Wl,--export=chipmunk_probe_angle tests/manual/real-world-chipmunk/src/module.c tests/manual/real-world-chipmunk/src/shim.c $chipmunkSources -o tests/manual/real-world-chipmunk/generated/chipmunk.wasm
```

```powershell
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke chipmunk_hash_scene tests/manual/real-world-chipmunk/generated/chipmunk.wasm 60
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke chipmunk_hash_scene tests/manual/real-world-chipmunk/generated/chipmunk.wasm 600
D:\Backups\wasmtime\wasmtime-v24.0.1\wasmtime.exe -C cache=n --invoke chipmunk_hash_scene_variant tests/manual/real-world-chipmunk/generated/chipmunk.wasm 600
```

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\real-world-chipmunk\generated\chipmunk.wasm -t lua-no-ffi > tests\manual\real-world-chipmunk\generated\chipmunk.lua"
```

```powershell
luajit tests/manual/real-world-chipmunk/main.lua 600
```

## Expected Goal

The target is exact parity between:
- `wasmtime --invoke chipmunk_hash_scene ...`
- `luajit tests/manual/real-world-chipmunk/main.lua ...`

This fixture exists to stress:
- long-running float arithmetic
- body integration and collision response
- constraint solving
- branch-heavy stateful stepping

## Current Result

Current confirmed outputs:

- `wasmtime`
  - `chipmunk_hash_scene(60) = -1855749543`
  - `chipmunk_hash_scene(600) = 792478063`
  - `chipmunk_hash_scene_variant(600) = -455480843`
  - `chipmunk_probe_body_x(0, 600) = -1071644672`
  - `chipmunk_probe_body_y(1, 600) = -216627709`
  - `chipmunk_probe_angle(2, 600) = -343754584`
- `lua-no-ffi`
  - `chipmunk_hash_scene(60) = -1855749543`
  - `chipmunk_hash_scene(600) = 792478063`
  - `chipmunk_hash_scene_variant(600) = -455480843`
  - `chipmunk_probe_body_x(0, 600) = -1071644672`
  - `chipmunk_probe_body_y(1, 600) = -216627709`
  - `chipmunk_probe_angle(2, 600) = -343754584`

## Root Cause That Was Fixed

This fixture initially hit a structural LuaJIT limit before any numeric parity check:

- the generated top-level `module()` function in `lua-no-ffi` exceeded LuaJIT's `200` local-variable limit

The fix was made in the `lua-no-ffi` printer:

- large top-level wasm locals are now spilled into a table-backed `module_locals[...]` representation instead of being emitted as hundreds of real Lua locals

That keeps the generated module loadable under LuaJIT without changing wasm behavior, and it was enough to make the `Chipmunk2D` fixture executable and parity-checkable.
