# LuaJIT Hard Limits Blocking Large Spider Modules

This note documents two LuaJIT runtime limits that currently block Spider-generated modules above a certain size threshold. Both limits are built into the LuaJIT VM and cannot be raised without modifying LuaJIT itself.

---

## 1. 60 Upvalues Per Function

### Root Cause

LuaJIT imposes a hard limit of **60 upvalues per function**. An upvalue is a variable captured from an outer lexical scope by an inner closure. Spider generates nested function closures where wasm-level functions capture shared module state and runtime bindings from their enclosing scopes.

### How Spider Hits This

In generated Lua, each wasm-level function becomes a `Scoped` closure:

```lua
(function()
    local loc_1_ = loc_outer_1_   -- upvalue 1
    local loc_2_ = loc_outer_2_   -- upvalue 2
    -- ... up to N upvalues
    return (function(...)
        -- inner wasm function body
    end)
end)()
```

Each local captured from the outer scope counts as one upvalue. Large wasm modules with many nested functions and many shared variables can easily exceed 60.

### Current Workaround: Packed Scoped Dependencies

**File:** `Targets/LuaNoFFI/Printer/src/expression.rs` (line 18)

```rust
const PACKED_SCOPED_DEPENDENCIES_THRESHOLD: usize = 48;
```

When a scoped function has 48 or more captured dependencies, Spider collapses them into a single table upvalue:

```lua
(function()
    local __spider_scoped_dependencies = { dep_1, dep_2, ..., dep_N }
    return (function(...)
        local dep_1 = __spider_scoped_dependencies[1]  -- table access, not upvalue
        local dep_2 = __spider_scoped_dependencies[2]
        -- ...
    end)
end)()
```

This reduces N upvalues to 1 (the `__spider_scoped_dependencies` table).

### Where It Still Fails

The threshold of 48 leaves a 12-slot gap below the 60 limit. A function that has:
- 48 packed dependencies (1 table upvalue)
- Plus its own function parameter + locals
- Plus additional captured variables from even-deeper scopes

can theoretically compound past 60. More critically, **the `lua-jit` target's module wrapper** directly captures runtime helper bindings as upvalues without any packing — there is no table-backed spill mechanism for the lua-jit module function itself.

### Reproduction

| Fixture | Wasm KB | Lua lines | Error |
|---|---|---|---|
| `plmpeg-stream` (lua-jit) | 51 | 8,890 | `function has more than 60 upvalues` |
| `gltf-rs` (lua-jit) | 540 | 190,865 | `function has more than 60 upvalues` |
| `wasm3` (lua-jit) | 90 | 30,418 | `function has more than 60 upvalues` |

All three fail at module load time — the LuaJIT parser rejects the function before any execution.

---

## 2. 200 Local Variables Per Function

### Root Cause

LuaJIT imposes a hard limit of **200 local variables per function** (including the function's parameters). Spider's `lua-no-ffi` target declares all wasm-level locals plus runtime helper bindings as local variables in the `module()` function body:

```lua
local function module(environment_0_)
    local excess_stack = { top = 0 }
    local rt_add_i32 = runtime.rt_add_i32
    local rt_load_i32 = runtime.rt_load_i32
    -- ... one local per runtime helper
    local loc_0_, loc_1_, loc_2_ = 0, 0, 0
    -- ... one local per wasm local variable
    -- ... up to N total
    local export = { ... }
    return export
end
```

### Current Workaround: Table-Backed Module Locals

**File:** `Targets/LuaNoFFI/Printer/src/statement.rs` (lines 215-217)

```rust
fn use_table_backed_module_locals(printer: &LuaNoFFIPrinter, locals: &[Name]) -> bool {
    locals.len() + printer.runtime_names().len() + 2 >= 200
}
```

When this returns true, wasm locals are moved from direct declarations into a `module_locals` table:

```lua
local module_locals = {}
for i = 1, 200 do
    module_locals[i] = 0
end
-- Each wasm local becomes a table access:
-- loc_0_ -> module_locals[1]
-- loc_1_ -> module_locals[2]
```

This brings wasm local count from N to 1 (the `module_locals` table itself).

### Bug #2: Heuristic Undercount

**Documented in:** `docs/notes/lua-no-ffi-known-bugs.md` (lines 47-95)

The heuristic `locals.len() + runtime_names.len() + 2` is missing several locals that are always present in the generated output:

| Local variable | Present when | Heuristic counts? |
|---|---|---|
| `environment_0_` (parameter) | Always | ❌ |
| `excess_stack` | Always | ❌ |
| `export` | Always | ❌ |
| `stack_top` | `stack > 0` | ❌ |

**Correct formula:**
```
actual_locals = 1 (environment) + 1 (excess_stack) + runtime_names.len()
              + (stack > 0 ? 1 : 0) + locals.len() + 1 (export)
```

**Concrete breakage**: with 197 wasm locals, 0 runtime helpers, and stack > 0:
- Heuristic: `197 + 0 + 2 = 199 < 200` → **no spill**
- Actual: `197 + 0 + 3 + 1 = 201 > 200` → **exceeds limit!**

### Resolved: The Runtime Prelude No Longer Uses Chunk Locals

The `wasm3` failure above was reported as `main function has more than 200
local variables`, which is the **main chunk**, not `module()`. Every runtime
section used to be printed as a chunk level `local function ...` / `local x =
...`, so a large module needed one chunk local per helper; `wasm3` reached 208
of them and `binjgb` was close behind.

**File:** `Targets/LuaNoFFI/Printer/src/library/printer.rs`

Each section is now printed inside its own `do ... end` block and publishes the
locals it declares in a single chunk level `runtime` table:

```lua
local runtime = {}

do -- SECTION truncate_f32
	local from_bits_f32, into_bits_f32, math_modf = runtime.from_bits_f32, runtime.into_bits_f32, runtime.math_modf
local function rt_truncate_f32(source)
	-- ...
end
	runtime.rt_truncate_f32 = rt_truncate_f32
end

local function module(environment_0_)
	local rt_truncate_f32 = runtime.rt_truncate_f32
	-- ...
end
```

The chunk therefore holds `runtime` plus `module` no matter how many sections
are emitted, while calls between helpers still go through block locals, i.e.
plain upvalues, rather than table lookups. A block holds its imports plus its
own declarations; the widest built-in section needs nine (`raw_unsigned_divide_u64`),
and the printer asserts that no block exceeds 190.

The imports of a block are every name an earlier section declared that the body
mentions, which is a superset of its `-- NEEDS` list; sections that forgot a
`-- NEEDS` line (`truncate_f32` → `math_modf`, `saturate_f64_to_s64` →
`subtract_i64`) used to depend on some other section pulling the dependency in,
and now resolve on their own.

Code printed after the prelude that refers to a section local by name — the
conformance harness does this with `environment`, `named` and `selected` — has
to bind it again through `Printer::print_bindings`, and mutable state shared
between a section and the chunk has to be a table field or a global.

### Separate Per-Function Spill (LocalAllocator)

The Builder has its own **per-inner-function** spill mechanism in `Targets/LuaNoFFI/Builder/src/local_allocator/local_provider.rs` (lines 7-9):

```rust
const MAX_LOCAL_VARIABLES: usize = 197;
```

When an inner wasm function exceeds 197 fast locals, the allocator spills them to `Local::Slow { offset }` — the `excess_stack` table. This is a **different** mechanism from the module-level `module_locals` spill. The `locals` vector in the tree only contains `Local::Fast` entries, so `locals.len()` correctly represents the fast-local count for the 200-limit heuristic. The error is purely in the `+ 2` accounting.

### Reproduction

| Fixture | Wasm KB | Lua lines | Generated locals | Error |
|---|---|---|---|---|
| `wasm3` (lua-no-ffi) | 90 | 30,800 | 2,368 | `main function has more than 200 local variables` |

The wasm3 module generates 2,368 local variables — far above 200. The spill heuristic should trigger, but because of the undercount bug, it doesn't. The load error itself came from the prelude rather than from `module()`, and is resolved by the section scoping above; `wasm3` and `binjgb` now load.

---

## Summary

| Limit | Value | Affected targets | Workaround | Workaround gap |
|---|---|---|---|---|
| Upvalues per function | 60 | lua-jit, lua-no-ffi | Packed scoped (threshold 48) | Module wrapper has no packing; threshold leaves 12-slot margin |
| Locals per function | 200 | lua-no-ffi | `module_locals` table spill | Heuristic undercounts by 3-4 (Bug #2) |
| Locals in the main chunk | 200 | lua-no-ffi | One `do ... end` block per runtime section, definitions shared through the `runtime` table | None known |

Both limits are architectural — they reflect Spider's strategy of emitting all variables as Lua locals in a single function body. A fundamental rethinking (e.g., splitting the module function into multiple sub-functions, or moving runtime bindings to a separate table) would be needed to fully resolve these limits for arbitrarily large wasm modules.

### Related

- `docs/notes/lua-no-ffi-known-bugs.md` — Bug #2 documented with reproduction steps
- `docs/notes/lua-no-ffi-status.md` — mentions "Large modules can still expose structural generator/runtime limits"
