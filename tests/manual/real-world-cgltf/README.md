# cgltf Real-World Comparison

This fixture uses the upstream [`cgltf`](https://github.com/jkuhlmann/cgltf) single-header C99 library as a glTF 2.0 / GLB parser for `lua-no-ffi`.

The wasm module is intentionally built as a standalone non-WASI module:
- upstream `cgltf.h` is used directly from `upstream/`
- `src/shim.c` provides a minimal standalone runtime: heap allocator, string functions, string-to-number conversion so the module has no host imports
- `src/module.c` exports parity probes (against an embedded `RiggedSimple.glb`) and host-adapter exports for parsing external `.glb` files from Lua memory

The committed canonical sample is:
- `RiggedSimple.glb` from [KhronosGroup glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets)
- 2 meshes, 2 animations, 6 nodes, 1 skin

## Canonical Commands

From the repository root:

```powershell
cargo build --release -p spider-cli
cargo build --release -p wasmtime-host-runner
```

### Native Reference (etalon)

```powershell
cmd /c "call ""C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"" > nul && cl /O2 /Itests\manual\real-world-cgltf\upstream tests\manual\real-world-cgltf\src\reference.c /Fe:tests\manual\real-world-cgltf\generated\reference.exe"
```

```powershell
tests\manual\real-world-cgltf\generated\reference.exe tests\manual\real-world-cgltf\fixtures\RiggedSimple.glb
```

### wasm Build

```powershell
D:\Backups\WASI\wasi-sdk-24.0\bin\clang.exe --% --target=wasm32 -Os -nostdlib -Wl,--no-entry -Wl,--export=cgltf_host_alloc -Wl,--export=cgltf_host_load -Wl,--export=cgltf_host_parse -Wl,--export=cgltf_host_free -Wl,--export=cgltf_compute_hash -Wl,--export=cgltf_host_get_mesh_count -Wl,--export=cgltf_host_get_animation_count -Wl,--export=cgltf_host_get_node_count -Wl,--export=cgltf_host_get_skin_count -Wl,--export=cgltf_host_get_scene_count -Wl,--export=cgltf_host_get_animation_name_len -Wl,--export=cgltf_host_get_animation_name -Wl,--export=cgltf_host_get_animation_channel_count -Wl,--export=cgltf_host_get_mesh_name_len -Wl,--export=cgltf_host_get_mesh_name -Wl,--export=cgltf_host_get_node_name_len -Wl,--export=cgltf_host_get_node_name -Wl,--export=cgltf_host_get_node_has_mesh -Wl,--export=cgltf_host_get_node_has_skin -Wl,--export=cgltf_host_get_node_local_transform -Wl,--export=cgltf_host_get_node_world_transform -Wl,--allow-undefined -DNDEBUG -Itests/manual/real-world-cgltf/include -Itests/manual/real-world-cgltf/upstream tests/manual/real-world-cgltf/src/module.c tests/manual/real-world-cgltf/src/shim.c -o tests/manual/real-world-cgltf/generated/cgltf.wasm
```

```powershell
cmd /c "target\release\spider-cli.exe tests\manual\real-world-cgltf\generated\cgltf.wasm -t lua-no-ffi > tests\manual\real-world-cgltf\generated\cgltf.lua"
```

### Parity Test (wasmtime + lua)

```powershell
# wasmtime host runner
target\release\wasmtime-host-runner.exe --fixture cgltf --wasm tests\manual\real-world-cgltf\generated\cgltf.wasm --input tests\manual\real-world-cgltf\fixtures\RiggedSimple.glb

# Lua host adapter
luajit tests\manual\real-world-cgltf\main.lua lua-no-ffi
```

## Expected Result

All three paths (native reference, wasmtime, lua-no-ffi) produce identical output on `fixtures/RiggedSimple.glb`:

```
Result (Hash): -834878637
Result (MeshCount): 1
Result (AnimationCount): 1
Result (NodeCount): 5
Result (SkinCount): 1
Result (SceneCount): 1
Result (AnimationChannelCount0): 3
Result (MeshName0): Cylinder
Result (Node0): Z_UP
Result (Node1): Armature
Result (Node2): Cylinder MESH SKIN
Result (Node3): Bone
Result (Node4): Bone.001
```

## Known Limitations

- `cgltf` defaults `FILE*`-based file reading for buffer/external-image URIs. This fixture uses memory-only parsing (`cgltf_parse`), so `.gltf` files with external buffer URIs will not load. `.glb` files with inline data are fully supported.
- `cgltf_write.h` is not included (writer not needed for this fixture).
- `strtod` implementation in `shim.c` handles basic format; edge cases (inf/nan/hex floats) may diverge from libc `strtod`.
