# `lua-no-ffi` Known Bugs

This note records concrete `lua-no-ffi` bugs that were identified during review of the current uncommitted changes and are worth preserving for future fixes.

These are not broad architectural concerns; they are discrete implementation issues with a clear reproduction story.

## 1. Reference Locals Are Default-Initialized To `0` Instead Of `nil`

Affected area:

- [Targets/LuaNoFFI/Printer/src/expression.rs](/D:/Backups/Spider/Targets/LuaNoFFI/Printer/src/expression.rs:67)

Problem summary:

- `fmt_locals()` now initializes all locals to `0`
- `lua-no-ffi` models `ref.null` as `nil`
- WebAssembly reference locals are initialized to null by default
- this means freshly declared reference locals now start with the wrong value in generated Lua

Why this is a real bug:

- the WebAssembly lifter already preserves reference types:
  - [Sources/WebAssembly/Lifter/src/function_lifter.rs](/D:/Backups/Spider/Sources/WebAssembly/Lifter/src/function_lifter.rs:18)
  - [Sources/WebAssembly/Lifter/src/control_flow_lifter/basic_block_lifter.rs](/D:/Backups/Spider/Sources/WebAssembly/Lifter/src/control_flow_lifter/basic_block_lifter.rs:70)
- the `lua-no-ffi` printer already treats null references as `nil`:
  - [Targets/LuaNoFFI/Printer/src/expression.rs](/D:/Backups/Spider/Targets/LuaNoFFI/Printer/src/expression.rs:687)
- so the new `0` initialization creates a direct semantic mismatch for reference locals

Reproducibility:

- high
- this should reproduce on a wasm module that:
  1. declares an `externref` or `funcref` local
  2. reads it before any explicit assignment
  3. checks it through `ref.is_null` or equivalent control flow

Expected effect:

- generated Lua will observe a non-null value where wasm semantics require null
- branches depending on reference-local default state can diverge immediately

Current status:

- confirmed as a semantic mismatch by code-path inspection
- not yet fixed

## 2. Large-Module Spill Heuristic Still Undercounts LuaJIT Locals

Affected area:

- [Targets/LuaNoFFI/Printer/src/statement.rs](/D:/Backups/Spider/Targets/LuaNoFFI/Printer/src/statement.rs:215)

Problem summary:

- `use_table_backed_module_locals()` currently decides whether to spill locals with:
  - `locals.len() + printer.runtime_names().len() + 2 >= 200`
- but `module(...)` has more local names than that count includes

Names currently missing from the heuristic:

- the `environment` parameter
- `excess_stack`
- `export`
- `stack_top` when stack space is used

Why this is a real bug:

- the new spill logic was introduced specifically to stay under LuaJIT's local-variable limit
- near the threshold, the current accounting can still choose the non-spill path even though the printed `module()` function exceeds the real local count limit
- that means the "large module" fix is incomplete for boundary cases

Reproducibility:

- high
- this should reproduce on modules close to the LuaJIT local limit, especially when:
  - `locals.len()` is near `197-199`
  - stack space is non-zero
  - runtime helper bindings are also present

Concrete example:

- with `197` wasm locals, `0` runtime helpers, and non-zero stack:
  - heuristic count is `199`
  - actual printed local count is higher once `environment`, `excess_stack`, `stack_top`, and `export` are included
- this can still push generated `module()` over the LuaJIT limit

Expected effect:

- generated Lua may still fail to load on some large near-threshold modules
- the failure mode is the same class of large-module breakage that the spill feature was intended to prevent

Current status:

- confirmed by direct local-count accounting against the printed `module()` shape
- not yet fixed
