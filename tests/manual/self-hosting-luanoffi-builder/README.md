# Self-Hosting `luanoffi-builder`

This fixture is the first narrow self-hosting experiment for Spider:

- Rust wrapper crate -> `wasm32-unknown-unknown`
- compiled by `spider-cli` to `lua-no-ffi`
- executed by `luajit`
- parity defined on deterministic `LuaNoFFITree` probes and hashes

Scope for v1:

- `ir-graph`
- `luanoffi-tree`
- `luanoffi-builder`

Out of scope:

- full `Spider`
- `luanoffi-printer`
- dynamic IR input formats

## Embedded cases

The wrapper crate embeds 3 fixed graph constructors:

- `case 0`: arithmetic-only export
- `case 1`: global round-trip with stateful builder code
- `case 2`: `Gamma` if-else that produces non-trivial control-flow code

## Build

If the wasm target is missing, install it first:

```powershell
rustup target add wasm32-unknown-unknown
```

Build the wrapper crate:

```powershell
cargo build --manifest-path .\tests\manual\self-hosting-luanoffi-builder\Cargo.toml --target wasm32-unknown-unknown --release
```

Copy the produced wasm into `generated`:

```powershell
Copy-Item .\tests\manual\self-hosting-luanoffi-builder\target\wasm32-unknown-unknown\release\self_hosting_luanoffi_builder.wasm .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.wasm
```

Generate `lua-no-ffi` from the wasm:

```powershell
.\target\release\spider-cli.exe .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.wasm -t lua-no-ffi > .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.lua
```

## Run

Run the generated `lua-no-ffi` module under `luajit`:

```powershell
luajit .\tests\manual\self-hosting-luanoffi-builder\main.lua lua-no-ffi
```

Expected output shape:

```text
Result (CaseCount): 3
Case 0 (Locals): ...
Case 0 (Stack): ...
Case 0 (Exports): ...
Case 0 (CodeHash): ...
Case 0 (TreeHash): ...
...
```

## Wasmtime baseline

Run the wasm directly with `wasmtime`:

```powershell
wasmtime -C cache=n .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.wasm --invoke builder_case_count
wasmtime -C cache=n .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.wasm --invoke builder_probe_locals 0
wasmtime -C cache=n .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.wasm --invoke builder_probe_stack 0
wasmtime -C cache=n .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.wasm --invoke builder_probe_exports 0
wasmtime -C cache=n .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.wasm --invoke builder_probe_code_hash 0
wasmtime -C cache=n .\tests\manual\self-hosting-luanoffi-builder\generated\self_hosting_luanoffi_builder.wasm --invoke builder_run_case_hash 0
```

Repeat the probe calls for cases `1` and `2` and require exact equality with the values printed by `main.lua`.

## Notes

- The fixture keeps hashing local and structural. It does not depend on `luanoffi-printer`.
- The wrapper crate now uses a hybrid profile: host builds stay ergonomic, while `wasm32` builds use `no_std + alloc` with a fixture-local bump allocator to keep the emitted wasm narrower.
- In this environment, `wasmtime` needed `-C cache=n` because its default cache directory was broken locally.
- Current blocker after a verified wasm build:
  - both generated targets, `lua-no-ffi` and `lua-jit`, still fail to load under LuaJIT with `function ... has more than 60 upvalues`
  - after moving the wrapper to `no_std` on wasm, the artifact sizes improved only modestly: `.wasm` is `165,494` bytes, generated `lua-no-ffi` is `2,163,187` bytes, generated `lua-jit` is `2,104,007` bytes
  - this means the next meaningful step is target-side reduction of captured upvalues or a still narrower wasm code shape
