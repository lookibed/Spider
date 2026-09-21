# `lua-no-ffi` Known Bugs

This note records concrete `lua-no-ffi` implementation bugs with a clear
reproduction story, and their status. Broad architectural limits live in
[problem_lua_limits.md](problem_lua_limits.md).

The authoritative regression check is the conformance suite for this target:

```bash
cargo test -p conformance --test luanoffi
```

## Fixed

### Reference locals were default-initialized to `0` instead of `nil`

- Area: `Targets/LuaNoFFI/Printer/src/expression.rs` (`fmt_locals`).
- `fmt_locals()` printed `local a, b = 0, 0`, but `ref.null` is `nil` and an
  `i64` zero is `into_bits_i64(0, 0)`, so the blanket `0` was wrong for two of
  the five value types.
- The lifter already seeds every WebAssembly local with an explicit typed
  constant (`basic_block_lifter.rs`, `set_local_types`), so the printer now
  declares registers without an initializer, exactly like the LuaJIT target.

### Large-module spill heuristic undercounted LuaJIT locals

- Area: `Targets/LuaNoFFI/Printer/src/statement.rs`
  (`use_table_backed_module_locals`).
- The count now includes `environment`, `excess_stack`, `export` and
  `stack_top` (when the function has a slow stack) and compares against the
  real limit of 200 active locals.

### Boolean-to-integer conversion had the wrong precedence

- Area: `Targets/LuaNoFFI/Printer/src/expression.rs` and
  `Targets/LuaJIT/Printer/src/expression.rs` (`BooleanToInteger`).
- The printer emitted `(cond and 1) or 0`. Inside a larger expression such as
  `x - (cond and 1) or 0` Lua parses this as `(x - (cond and 1)) or 0`, which
  is `x - false` when the condition is false: `attempt to perform arithmetic on
  a boolean value`. This crashed `real-world-miniz` and `real-world-lodepng`
  and dates back to the first LuaJIT target. It now prints `(cond and 1 or 0)`.

### Partially in-bounds 8-byte accesses wrote or read half a value

- Area: `runtime/core/memory.lua` (`rt_store_i64`, `rt_load_i64`),
  `runtime/builtin/buffer.lua` (`buffer_write_f64`, `buffer_read_f64`).
- `i64.store` at address `-1` wrote its high half at address `3` before the
  low half trapped, corrupting memory (`memory_trap.wast`). Every 8-byte access
  now checks the whole range with `buffer_check` before touching a byte.

### Out-of-bounds loads and stores did not trap

- Area: `runtime/builtin/buffer.lua`.
- Loads past the end produced `nil` arithmetic errors, negative addresses read
  from the end of the base string (`string.byte(s, -1)`), and stores past the
  end silently landed in the overlay table. Every `buffer_*` accessor now
  bounds-checks against the logical length and raises
  `out of bounds memory access`.

### `memory.copy` was not a `memmove`

- Area: `runtime/builtin/buffer.lua` (`buffer_copy`).
- Overlapping copies with `destination > source` inside one memory clobbered
  the source bytes. The copy now runs backwards in that case, and both ranges
  are bounds-checked before anything is written.

### `memory.grow` copied the whole memory and mis-handled wrapped sizes

- Area: `runtime/core/memory.lua` (`rt_memory_grow`), `buffer.lua`.
- Growing allocated a fresh buffer and copied every byte through the overlay,
  which timed out `memory_grow.wast` (800 pages). The byte count arrives from
  an `i32` multiply and could be negative after wrapping. Buffers now carry a
  logical length (`__n`) that `buffer_resize` bumps in O(1); sizes are
  re-interpreted as unsigned and anything at or above 2 GiB fails with `-1`.

### `data.drop` left a bare table behind

- Area: `runtime/core/memory.lua` (`rt_memory_drop`).
- The dropped segment became `{}` without the buffer metatable and without a
  length, so any later access crashed inside `string.byte`. It is now an empty
  buffer.

### `bit32_*` sections depended on an undeclared `bit`

- Area: `runtime/builtin/bit32.lua`.
- The sections used the `bit` library without `-- NEEDS bit`, and only worked
  because LuaJIT exposes `bit` as a global. Every section now declares the
  dependency. The prelude printer additionally imports every mentioned helper,
  so a missing `NEEDS` can no longer produce a silent global lookup.

### Inline helpers bypassed the runtime table

- Area: `Targets/LuaNoFFI/Printer/src/library/names_finder.rs`,
  `statement.rs` (`runtime_binding_name`).
- `bit32_or` (inline `i32` add/sub) and `buffer_read_u32` (inline `i32` load)
  were printed directly but reported as `add_i32`/`load_i32`, leaving dead
  `rt_add_i32`/`rt_load_i32` bindings and keeping the real helpers as extra
  upvalues. The names finder now reports the helpers that are actually
  printed.

### The generated tree ended with `return module`

- Area: `Targets/{LuaJIT,LuaNoFFI}/Printer/src/statement.rs`,
  `CLI/src/targets/*.rs`.
- The printer emitted `return module` itself, which broke every conformance
  test (the harness wraps the module in `do ... end`). The `return` now comes
  from the CLI wrapper.

## Known limitations (not bugs to fix in the runtime)

- NaN payloads are not observable: `into_bits_f64` cannot extract payload
  bits from a Lua number without FFI, so every NaN canonicalizes to
  `0x7FF8000000000000`. `f64.wast` reports these as failures.
- Memories are limited to 2 GiB because byte offsets are kept as `i32`
  values on every path.
