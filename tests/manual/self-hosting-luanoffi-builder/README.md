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

The crate is a workspace member and `rust-toolchain.toml` already pins the
`wasm32-unknown-unknown` target, so no extra `rustup target add` is needed.

Build the wrapper crate and copy the artifact into `generated`:

```bash
cargo build --manifest-path tests/manual/self-hosting-luanoffi-builder/Cargo.toml \
	--target wasm32-unknown-unknown --release

cp target/wasm32-unknown-unknown/release/self_hosting_luanoffi_builder.wasm \
	tests/manual/self-hosting-luanoffi-builder/generated/self_hosting_luanoffi_builder.wasm
```

Generate `lua-no-ffi` from the wasm:

```bash
cargo build --release -p spider-cli

./target/release/spider-cli \
	tests/manual/self-hosting-luanoffi-builder/generated/self_hosting_luanoffi_builder.wasm \
	-t lua-no-ffi \
	> tests/manual/self-hosting-luanoffi-builder/generated/self_hosting_luanoffi_builder.lua
```

## Run

Run the generated `lua-no-ffi` module under `luajit`, from the repository root:

```bash
luajit tests/manual/self-hosting-luanoffi-builder/main.lua lua-no-ffi
```

## Verified output

Verified on Linux with `rustc 1.98.1`, `luajit 2.1.0-beta3` and
`wasmtime-cli 24.0.1`. The `lua-no-ffi` run prints exactly:

```text
Result (CaseCount): 3
Case 0 (Locals): 1
Case 0 (Stack): 0
Case 0 (Exports): 1
Case 0 (CodeHash): 1183502082
Case 0 (TreeHash): 1193852273
Case 1 (Locals): 3
Case 1 (Stack): 0
Case 1 (Exports): 1
Case 1 (CodeHash): -1661873899
Case 1 (TreeHash): -472748772
Case 2 (Locals): 2
Case 2 (Stack): 0
Case 2 (Exports): 1
Case 2 (CodeHash): -1794148870
Case 2 (TreeHash): 693920941
```

Every value above is bit-identical to the `wasmtime` baseline below.

## Wasmtime baseline

`--invoke` must be passed *before* the module path; `wasmtime 24` otherwise
treats it as a module argument and silently prints nothing. The local cache
directory is also broken in this environment, hence `-C cache=n`.

```bash
WASM=tests/manual/self-hosting-luanoffi-builder/generated/self_hosting_luanoffi_builder.wasm

wasmtime run -C cache=n --invoke builder_case_count "$WASM"

for case in 0 1 2; do
	for probe in builder_probe_locals builder_probe_stack builder_probe_exports \
		builder_probe_code_hash builder_run_case_hash; do
		echo "case $case $probe = $(wasmtime run -C cache=n --invoke "$probe" "$WASM" "$case")"
	done
done
```

Reference values:

| probe                     | case 0     | case 1      | case 2      |
| ------------------------- | ---------- | ----------- | ----------- |
| `builder_probe_locals`    | 1          | 3           | 2           |
| `builder_probe_stack`     | 0          | 0           | 0           |
| `builder_probe_exports`   | 1          | 1           | 1           |
| `builder_probe_code_hash` | 1183502082 | -1661873899 | -1794148870 |
| `builder_run_case_hash`   | 1193852273 | -472748772  | 693920941   |

`builder_case_count` returns `3`.

The module imports nothing and needs no WASI, so any plain WebAssembly host
works as a second opinion, for example `node`:

```bash
node -e 'const fs=require("fs");const e=new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(process.argv[1])),{}).exports;console.log(e.builder_probe_code_hash(0))' \
	tests/manual/self-hosting-luanoffi-builder/generated/self_hosting_luanoffi_builder.wasm
```

## Notes

- The fixture keeps hashing local and structural. It does not depend on `luanoffi-printer`.
- The wrapper crate uses a hybrid profile: host builds stay ergonomic, while `wasm32` builds use `no_std + alloc` with a fixture-local bump allocator to keep the emitted wasm narrower.
- Approximate artifact sizes: `.wasm` is `171,389` bytes, generated `lua-no-ffi` is about `2.09` MB and generated `lua-jit` about `2.00` MB. The Lua sizes move with printer changes.
- `lua-no-ffi` loads and runs cleanly under LuaJIT; the module hoists spilled module-level cells into `excess_stack`, so it stays under both the 200-local and the 60-upvalue limits.
- `lua-jit` still fails to load with `function ... has more than 60 upvalues`. In that target the module-level cells are plain locals, so the `(function() ... end)()` wrapper around a packed scoped function captures every dependency as an upvalue. `main.lua` therefore rejects `lua-jit` for now.
