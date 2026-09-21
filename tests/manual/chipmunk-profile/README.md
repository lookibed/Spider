# Chipmunk2D Profiling Breakdown

This fixture breaks the `Chipmunk2D` slowdown question into smaller workload classes so we can compare:

- `wasmtime`
- Spider `lua-no-ffi`
- Spider `lua-jit`

The goal is not just parity. The goal is to identify which class of work explodes in pure Lua:

- memory-heavy state mutation
- expensive float/math helper usage
- branch-heavy state updates
- simple physics stepping
- collision stepping
- full collision + constraint stepping

Exports:

- `profile_memory_walk(i32) -> i32`
- `profile_math_shim(i32) -> i32`
- `profile_branch_state(i32) -> i32`
- `profile_space_freefall(i32) -> i32`
- `profile_space_collision(i32) -> i32`
- `profile_space_full(i32) -> i32`

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
```

```powershell
$chipmunkSources = Get-ChildItem tests/manual/real-world-chipmunk/upstream/src/*.c | Where-Object { $_.Name -notin @('cpHastySpace.c', 'cpMarch.c', 'cpPolyline.c', 'cpSpaceDebug.c') } | ForEach-Object { $_.FullName }
D:\Backups\WASI\wasi-sdk-24.0\bin\wasm32-wasi-clang.exe -DNDEBUG -DCP_USE_DOUBLES=1 -Oz -nostdlib -ffunction-sections -fdata-sections -Itests/manual/real-world-chipmunk/upstream/include -Wl,--gc-sections -Wl,--no-entry -Wl,--export=profile_memory_walk -Wl,--export=profile_math_shim -Wl,--export=profile_branch_state -Wl,--export=profile_space_freefall -Wl,--export=profile_space_collision -Wl,--export=profile_space_full tests/manual/chipmunk-profile/src/module.c tests/manual/chipmunk-profile/src/shim.c $chipmunkSources -o tests/manual/chipmunk-profile/generated/chipmunk_profile.wasm
```

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\chipmunk-profile\generated\chipmunk_profile.wasm -t lua-no-ffi > tests\manual\chipmunk-profile\generated\chipmunk_profile.lua"
cmd /c "target\release\spider-cli.exe tests\manual\chipmunk-profile\generated\chipmunk_profile.wasm -t lua-jit > tests\manual\chipmunk-profile\generated\chipmunk_profile_jit.lua"
```

```powershell
luajit tests/manual/chipmunk-profile/main.lua lua-no-ffi 400 400 400 120
luajit tests/manual/chipmunk-profile/main.lua lua-jit 400 400 400 120
```

## Default Inputs

- `memory_iterations = 400`
- `math_iterations = 400`
- `branch_iterations = 400`
- `scene_iterations = 120`

These defaults are chosen to keep all three targets runnable while still showing the relative shape of the slowdown.

## Notes

- The all-in-one profiling wasm is useful for parity and convenience, but the timing comparison in [lua-no-ffi-chipmunk-profile.md](../../docs/notes/lua-no-ffi-chipmunk-profile.md) was taken from single-export benchmark modules.
- That was necessary because an earlier combined profiling module exceeded the current `lua-jit` target's structural load limits, which would have blurred runtime cost with code-shape limits.
