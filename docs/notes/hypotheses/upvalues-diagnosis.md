# Upvalue Pressure: Diagnosis for `lua-no-ffi` and `lua-jit`

Written: `2026-09-23`. Measured with `LuaJIT 2.1.0-beta3` on Linux (WSL2) against commit `edb7054`.
Every module was regenerated from its `.wasm` with the existing `target/release/spider-cli` (no
`-o`). The fresh `lua-no-ffi` output is byte-identical to the checked-in `generated/<name>.lua` for
all 28 modules. **All 28 checked-in `generated/<name>_jit.lua` files are stale** (dated
`2026-09-21`, from before the latest printer changes), so every `lua-jit` number below comes from the
fresh output, not from the files in the tree.

This note is the measured baseline for the three sibling notes written alongside it
(`upvalues-environment.md`, `upvalues-structure.md`, `upvalues-prior-art.md`). It extends
[lua-no-ffi-upvalue-strategies.md](../lua-no-ffi-upvalue-strategies.md) (§1 there has the model
`upvalues(body) = dependencies + distinct runtime helpers (+1 if excess_stack)`), and it
supersedes the `lua-jit` half of [problem_lua_limits.md](../problem_lua_limits.md).

---

## 0. Summary

1. **`lua-jit` fails to load 15 of 28 modules (11 fixture directories), not 8.** On top of the eight
   in the `2026-09-23` table of `lua-no-ffi-measurements.md`, `h264bsd-mp4`, `plmpeg`, `wasm3` and
   four `chipmunk-profile` modules also fail. In **13 of the 15** the only prototype over 60 is
   `module()` itself, and every one of its upvalues is a chunk-level runtime helper (`rt_*`).
   `module()` needs one upvalue per helper the module names: 61–152.
2. The other two are the ones `lua-no-ffi` had to fix as well: `gltf_rs` (module 90, one scope
   wrapper 83, two bodies 65 and 61) and self-hosting (wrapper 84, module 65).
3. `lua-no-ffi` never goes over. Its module captures one upvalue (`runtime`). Its worst prototype
   is 58 (`gltf_rs`, a packed body). Across 5 379 bodies, **71 % of body upvalues are runtime
   helpers**; the rest are dependency cells. The largest helper count in any one body is **45**
   (`gltf_rs`), which leaves 11 slots under the 56 that packing cannot help with.
4. A text-level emulation of the `lua-no-ffi` mitigations applied to fresh `lua-jit` output makes
   **14 of the 15 load**, with results identical to `lua-no-ffi` wherever they were checked. The
   mitigations are: publish the helpers in one table and rebind them as `module()` locals, then
   spill `module()` locals to a table. Only `gltf_rs` also needs budget-aware packing.
5. Hot helper traffic costs nothing in compiled code today. Helpers are immutable function
   upvalues, and LuaJIT turns them into trace constants: **0 function-typed `ULOAD`s in 1 168
   traces**, sampled from three fixtures. The only upvalue loads left in traces are dependency cells.
   They are tables, which LuaJIT never turns into constants, and all of these loads sit before the
   loop (**0 inside a loop**). Any strategy that moves helpers into a table swaps a free constant
   for a guarded hash load.

---

## 1. Method

### 1.1 Census tool

For each module, a LuaJIT script:

* loads the chunk and walks every prototype through `jit.util.funck`;
* reads `funcinfo(pt).upvalues` and the names from `jit.util.funcuvname(pt, i)`;
* scans the bytecode (`jit.util.funcbc`) to count `UGET` per upvalue name;
* classifies prototypes as `runtime` (before `module`), `module`, `wrapper` (the scope closure that
  receives dependencies), or `body` (the WebAssembly function itself);
* classifies each upvalue name as follows:

| class | how it is recognised |
| --- | --- |
| `helper` | `lua-no-ffi`: a name bound as `local X = runtime.X` in `module()`; `lua-jit`: any chunk-level `local` before `module()` |
| `dep_func` / `dep_global` / `dep_memory` / `dep_table` | a dependency (wrapper parameter or wrapper `local`) whose source `module()` slot is a cell that receives a function, a cell that receives a value, an `rt_memory_new(...)` result or an `rt_table_new(...)` result; aliases (`loc_a = loc_b`) are followed |
| `mod_*` | the same slot classes captured directly from `module()` (only `lua-jit` wrappers do this) |
| `packed` | `__spider_scoped_dependencies` |
| `excess_stack`, `stack_top`, `module_locals`, `environment` | by name |

No upvalue in any of the 56 modules landed in an "other" or "unknown" class.

### 1.2 Counting modules that fail to load

LuaJIT's parser refuses the whole chunk, so `funcinfo` is not available. For those files the tool
rewrites every chunk-level `local` before `module()` into a global assignment. The chunk then loads,
and for each prototype the tool adds back the set of those names referenced as `GGET`/`GSET`
**anywhere in its subtree**. A captured name is an upvalue of every enclosing function, so this
reconstructs the original count exactly.

**Validation:** the tool forced this rewrite on four `lua-jit` modules that do load (`binjgb`,
`lodepng`, `cgltf`, `miniz`) and compared the result with the direct counts. All 942 module,
wrapper and body prototypes matched with 0 differences. The rewritten file is used only for
counting. Running it gives wrong results (§4.2).

`luajit -bl` was not needed: it stops at the first over-limit prototype for the same reason
`loadfile` does.

### 1.3 Where each module first fails (`loadfile`, fresh `lua-jit`)

| module | error |
| --- | --- |
| `tinyexpr_jit` | `function at line 751 has more than 60 upvalues` (= `module`) |
| `miniz_full_jit` / `miniz_file_jit` | line 643 / 647 (`module`) |
| `chipmunk_jit`, `space_{collision,freefall,full}_jit` | line 642 (`module`) |
| `chipmunk_profile_jit` | line 666 (`module`) |
| `libjpeg_turbo_jit`, `libjpeg_turbo_mjpeg_jit` | line 907 (`module`) |
| `h264mp4_jit` | line 741 (`module`) |
| `plmpeg_jit` (not `-stream`) | line 892 (`module`) |
| `wasm3_jit` | line 1841 (`module`) |
| `gltf_rs_jit` | line 1064 (`module`) |
| `self_hosting_luanoffi_builder_jit` | **line 19811 (a scope wrapper)**. It closes before `module` does, so the parser reports it first |

---

## 2. Per-module census

### 2.1 Headline table

`max` is over all prototypes. `helpers≤` is the largest number of distinct runtime helpers named by
any single body. `jit mod` is the upvalue count of `lua-jit`'s `module()`. **Bold** marks a count
over 60.

| module | nf protos | nf mean | nf max | nf body helpers≤ | jit loads | jit mod | jit wrapper max | jit body max | jit protos >60 |
| --- | ---: | ---: | ---: | ---: | :---: | ---: | ---: | ---: | ---: |
| chipmunk-profile.branch_state | 45 | 2.73 | 26 | 24 | yes | 26 | 26 | 25 | 0 |
| chipmunk-profile.chipmunk_profile | 560 | 7.51 | 35 | 24 | **no** | **63** | 28 | 34 | 1 |
| chipmunk-profile.math_shim | 58 | 3.52 | 28 | 22 | yes | 28 | 27 | 26 | 0 |
| chipmunk-profile.memory_walk | 49 | 3.00 | 24 | 22 | yes | 25 | 23 | 22 | 0 |
| chipmunk-profile.space_{collision,freefall,full} | 542 | 7.36 | 35 | 22 | **no** | **61** | 28 | 34 | 1 |
| float-compare.float_hash | 38 | 2.26 | 15 | 15 | yes | 24 | – | 15 | 0 |
| hash-compare.hash_loop | 19 | 1.84 | 7 | 7 | yes | 9 | – | 7 | 0 |
| i64-compare.i64_hash | 53 | 4.23 | 19 | 19 | yes | 23 | – | 18 | 0 |
| real-archive-secret.secret_reader | 158 | 6.06 | 39 | 33 | yes | **60 (at the limit)** | 40 | 39 | 0 |
| binjgb | 395 | 7.31 | 53 | 33 | yes | 59 | 52 | 53 | 0 |
| cgltf | 239 | 6.86 | 57 | 19 | yes | 55 | 57 | 56 | 0 |
| chipmunk | 552 | 7.33 | 32 | 22 | **no** | **61** | 28 | 31 | 1 |
| gltf-rs | 1522 | 11.82 | 58 | **45** | **no** | **90** | **83** | **65** | 4 |
| h264bsd-mp4 | 553 | 9.19 | 48 | 40 | **no** | **69** | 49 | 48 | 1 |
| libjpeg-turbo-mjpeg | 1135 | 9.81 | 51 | 26 | **no** | **63** | 52 | 50 | 1 |
| libjpeg-turbo | 1127 | 9.82 | 51 | 26 | **no** | **63** | 52 | 50 | 1 |
| lodepng | 460 | 7.89 | 56 | 26 | yes | 42 | 40 | 56 | 0 |
| lodepng_diag | 385 | 8.95 | 56 | 26 | yes | 42 | 41 | 56 | 0 |
| miniz-file | 261 | 8.38 | 44 | 33 | **no** | **65** | 45 | 44 | 1 |
| miniz-full | 209 | 7.94 | 43 | 33 | **no** | **64** | 44 | 43 | 1 |
| miniz | 119 | 6.66 | 32 | 28 | yes | 39 | 33 | 32 | 0 |
| plmpeg-stream | 168 | 6.14 | 30 | 26 | yes | 42 | 31 | 30 | 0 |
| plmpeg | 413 | 6.92 | 33 | 27 | **no** | **66** | 34 | 33 | 1 |
| tinyexpr | 225 | 4.89 | 25 | 22 | **no** | **74** | 25 | 24 | 1 |
| wasm3 | 1516 | 8.43 | 34 | 19 | **no** | **152** | 34 | 35 | 1 |
| self-hosting-luanoffi-builder | 575 | 11.30 | 57 | 40 | **no** | **65** | **84** | 54 | 2 |

In `lua-no-ffi`, `module()` has exactly 1 upvalue in every module. The worst `lua-no-ffi`
prototype in each module is always a **body**, never a wrapper. The parameter-passing wrapper
from the strategies study works as intended: a wrapper holds at most `helpers + 1`
(`rt_function_type`).

Corpus, `lua-no-ffi`, 5 379 bodies: mean body upvalues **10.81**; 65 bodies at 40 or more; 23 at
50 or more; max 58. Corpus maximum of all non-helper upvalues in one body: 43 dependencies.

### 2.2 Worst prototypes, with source classes

| module | target | line | kind | uv | helper | dep_func | dep_global | dep_mem | dep_table | other |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| gltf_rs | nf | 42838 | body | 58 | 15 | 39 | 1 | 1 | – | packed 1, excess_stack 1 |
| gltf_rs | nf | 171467 | body | 58 | 30 | 24 | 1 | 1 | – | packed 1, excess_stack 1 |
| gltf_rs | nf | 184674 | body | 50 | **45** | … | | | | the max-helper body |
| gltf_rs | jit | 1064 | module | **90** | 90 | – | – | – | – | – |
| gltf_rs | jit | 175150 | wrapper | **83** | 31 | 49 (mod) | – | 1 (mod) | – | excess_stack 1, stack_top 1 |
| gltf_rs | jit | 48931 | body | **65** | 24 | 39 | 1 | 1 | – | – |
| gltf_rs | jit | 71779 | body | **61** | 25 | 34 | 1 | 1 | – | – |
| self-hosting | nf | 20421 | body | 57 | 40 | 15 | 1 | – | – | packed 1 |
| self-hosting | jit | 19811 | wrapper | **84** | 41 | 40 (mod) | – | 1 (mod) | – | excess_stack 1, stack_top 1 |
| self-hosting | jit | 760 | module | **65** | 65 | – | – | – | – | – |
| cgltf | nf | 5270 | body | 57 | 18 | 36 | 1 | 1 | 1 | – |
| cgltf | jit | 4619 | wrapper | 57 | 18 | 36 (mod) | 1 | 1 | 1 | – |
| lodepng | nf | 20974 | body | 56 | 26 | 28 | 1 | 1 | – | – |
| binjgb | nf | 16579 | body | 53 | 33 | 18 | – | 1 | 1 | – |
| libjpeg-turbo | nf | 41229 | body | 51 | 15 | 34 | – | 1 | 1 | – |
| h264mp4 | nf | 11158 | body | 48 | 40 | 5 | 1 | 1 | 1 | – |
| miniz-file | nf | 22465 | body | 44 | 33 | 8 | 1 | 1 | 1 | – |
| tinyexpr | jit | 751 | module | **74** | 74 | – | – | – | – | – |
| wasm3 | jit | 1841 | module | **152** | 152 | – | – | – | – | – |

The worst bodies come in two shapes:

* **Dependency-dominated.** Mostly calls to sibling functions: `cgltf` has 36 `dep_func`,
  `libjpeg` 34, `gltf_rs` 39.
* **Helper-dominated.** Big switch-like interpreters and codecs: `h264mp4` names 40 helpers,
  `self-hosting` 40, `gltf_rs` 45.

Packing (`Targets/LuaNoFFI/Printer/src/expression.rs:261-286`) only helps the first shape.

### 2.3 Mean upvalue sources per body (`lua-no-ffi`)

`lua-jit` bodies differ by at most 0.5 in the helper column and are identical in the dependency
columns. The difference comes from slightly different helper sets.

| module | body mean | helper | dep_func | dep_global | dep_memory | dep_table | packed / excess_stack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| tinyexpr | 7.50 | 5.83 | 1.19 | 0.09 | 0.37 | 0.01 | – |
| miniz | 11.21 | 8.85 | 1.18 | 0.30 | 0.79 | 0.09 | – |
| miniz-full | 12.48 | 9.65 | 1.43 | 0.32 | 0.83 | 0.25 | – |
| miniz-file | 12.23 | 9.10 | 1.80 | 0.29 | 0.80 | 0.24 | – |
| chipmunk | 9.00 | 6.25 | 1.53 | 0.27 | 0.83 | 0.12 | – |
| lodepng | 9.07 | 6.48 | 1.61 | 0.13 | 0.80 | 0.05 | – |
| cgltf | 10.26 | 6.74 | 2.39 | 0.11 | 0.88 | 0.14 | – |
| binjgb | 8.18 | 6.26 | 1.01 | 0.16 | 0.72 | 0.02 | – |
| h264mp4 | 10.95 | 8.14 | 1.66 | 0.27 | 0.85 | 0.02 | – |
| libjpeg-turbo | 10.52 | 8.72 | 0.39 | 0.13 | 0.90 | 0.38 | – |
| plmpeg | 8.69 | 6.36 | 1.13 | 0.05 | 0.89 | 0.26 | – |
| wasm3 | 10.04 | 7.52 | 0.72 | 0.08 | 0.97 | 0.75 | – |
| secret_reader | 10.45 | 7.90 | 1.48 | 0.24 | 0.64 | 0.19 | – |
| self-hosting | 14.27 | 10.52 | 2.34 | 0.44 | 0.92 | 0.05 | 1 body packed |
| gltf_rs | 15.73 | 8.54 | 5.45 | 0.67 | 0.96 | 0.10 | 5 bodies packed, 2 use `excess_stack` |
| **corpus (5 379 bodies)** | **10.81** | **7.70 (71 %)** | | | | | |

Classes that never show up as a body upvalue: `environment` (no fixture has imports, and the
environment parameter is not used by any body), `module_locals` (sources are evaluated in
`module()` and passed in), and `runtime`. `excess_stack` appears only in the two packed `gltf_rs`
bodies that spill their own locals.

---

## 3. Why `lua-jit` fails where `lua-no-ffi` passes

It comes down to three printer differences. Each one is a mitigation that `lua-no-ffi` gained
and `lua-jit` never received.

### 3.1 Runtime helpers are chunk locals captured by `module()` (13 of 15 failures)

* `lua-jit` prints each runtime section verbatim at chunk level
  (`Targets/LuaJIT/Printer/src/library/printer.rs:50-56`), so each helper is a chunk-level
  `local function rt_x`. `module()` (`Targets/LuaJIT/Printer/src/statement.rs:703-741`) declares
  no bindings. Every helper that any nested body names is therefore an upvalue of `module()`,
  passed down through each wrapper. `module()` needs `distinct helpers in the module` upvalues:
  74 for `tinyexpr`, 152 for `wasm3`. Every one of those upvalues is an `rt_*` function. No
  `ffi`/`bit` constant reaches `module()`.
* `lua-no-ffi` wraps each section in `do ... end` and publishes the section's definitions in one
  chunk-level `runtime` table (`Targets/LuaNoFFI/Printer/src/library/printer.rs:8, 108-145`).
  `module()` rebinds each helper it needs as a local:
  `local rt_x = runtime.rt_x` (`Targets/LuaNoFFI/Printer/src/statement.rs:761-766`, names from
  `runtime_binding_name` at `:313-324`, list from `CLI/src/targets/luanoffi.rs:34-35`).
  `module()` then captures only `runtime`. The bodies' upvalue counts stay the same, because a
  helper is still one upvalue per body.
  `CLI/src/targets/luajit.rs:30-36` never calls anything like `set_runtime_names`.

Near misses among the `lua-jit` modules that still load: `secret_reader` 60 (exactly at the
limit), `binjgb` 59, `cgltf` 55. One more distinct helper in any of them breaks it.

A second limit is close behind in `lua-jit`. Its prelude is flat, and `wasm3_jit` already has
**186 chunk locals**, near the 200-local limit that `lua-no-ffi` hit and fixed with the `do`
blocks (`problem_lua_limits.md`, "Resolved: The Runtime Prelude").

### 3.2 `module()` locals are never spilled

The `lua-no-ffi` rebinding costs one `module()` local per helper. `lua-no-ffi` absorbs that with
`use_table_backed_module_locals`, which moves every WebAssembly module-level local to
`module_locals[k]` (`Targets/LuaNoFFI/Printer/src/statement.rs:330-340, 770-785`). `lua-jit` always
prints them as plain locals (`Targets/LuaJIT/Printer/src/statement.rs:726`). In the emulation
(§4.2), 10 of the 15 failing modules needed this spill as well: after the helper rebinding they
failed with `more than 200 local variables`.

The spill has a side effect that matters for upvalues. A `lua-jit` wrapper binds its dependencies
with `local d = <module slot>` (`Targets/LuaJIT/Printer/src/expression.rs:240-258`), so it
captures every source slot as an upvalue. This is the wrapper leak of strategies §1.2, and it
produces the 83 and 84 counts. Once the slots are `module_locals[k]`, the wrapper captures one
table instead of 40–49 slots.

### 3.3 Scope packing is by dependency count, not by demand

`lua-jit` packs a scope only at 48 or more dependencies, and then packs all of them
(`Targets/LuaJIT/Printer/src/expression.rs:16, 244, 259-320`). It never counts helpers. The
`gltf_rs` bodies at 65 (24 helpers + 39 dependencies + 2) and 61 have fewer than 48 dependencies,
so they are never packed. `lua-no-ffi` uses `Captures::of`
(`Targets/LuaNoFFI/Printer/src/captures.rs:33-60`) and packs only the coldest overflow above
`CAPTURE_BUDGET = 57` (`Targets/LuaNoFFI/Printer/src/expression.rs:18-30, 261-286`).
It also passes dependencies as wrapper parameters (`:310-365`).

### 3.4 Minimal port, measured by emulation

The port was emulated on fresh `lua-jit` text. The prelude was kept byte-identical, then
`local __rt = { rt_a = rt_a, … }` was inserted just before `module()`, `local rt_a = __rt.rt_a`
was inserted at the top of `module()` (A+B below), and the top-level `local loc_…` list of
`module()` was rewritten to `module_locals[k]` (C below).

| step | what it ports | modules that load (of the 15 failing) |
| --- | --- | --- |
| A+B: helpers published in one table and rebound in `module()` | `library/printer.rs` runtime table plus `statement.rs:761-766` | 3: `tinyexpr`, `miniz-full`, `miniz-file` |
| + C: `module_locals` spill | `statement.rs:330-340, 770-785` | **14**: all except `gltf_rs` |
| + D: `Captures` budget packing and parameter wrapper | `captures.rs`, `expression.rs:255-365` | needed only by `gltf_rs` (bodies 65, 61). Not emulated. |

Results of the emulated ports against `lua-no-ffi` (same process harness, same arguments):
`tinyexpr_hash(256)` = 141480662 / error 6, `miniz_full_hash(6)` = −2109846306,
`miniz_file_hash(6)` = −138697996, `chipmunk_hash_scene(60)` = −1855749543. All four are
identical.

Step A does not have to copy `lua-no-ffi`'s `do` blocks to fix upvalues; one table after the
flat prelude is enough. The `do` blocks are still needed for the 200-chunk-local limit (§3.1).
So the smallest *complete* port is A (with `do` blocks) + B + C + D, which amounts to copying
four `lua-no-ffi` printer pieces into the `lua-jit` printer.

---

## 4. Residual risk in `lua-no-ffi`

### 4.1 Headroom

The hard cases are the ones packing cannot reach.

* **Body:** `helpers + 1 (packed table) + 1 (excess_stack) ≤ 60`, so at most 58 helpers.
  Past that point, `excess = min(demand + 1 − 57, dependencies.len())` at `expression.rs:273`
  runs out of dependencies to move. The printer's own budget leaves 56.
* **Wrapper:** `helpers + 1 (rt_function_type) ≤ 60`.

Histogram of distinct helpers per body (all 28 modules, duplicates such as `space_*` counted
once, 3 946 bodies):

| helpers per body | bodies | share |
| --- | ---: | ---: |
| 0–9 | 2 639 | 66.9 % |
| 10–19 | 1 125 | 28.5 % |
| 20–29 | 159 | 4.0 % |
| 30–39 | 20 | 0.51 % |
| 40–45 | 3 | 0.08 % |

The closest fixtures:

| module | max helpers in a body | slots left under 56 | bodies ≥ 30 helpers |
| --- | ---: | ---: | ---: |
| gltf_rs | 45 (line 184674) | 11 | 2 |
| h264mp4 | 40 (line 11158) | 16 | 2 |
| self-hosting | 40 (line 20421, also packed) | 16 | 12 |
| binjgb, miniz-file, miniz-full, secret_reader | 33 | 23 | 1–3 |

### 4.2 Which helpers dominate

The 21 bodies with 30 or more helpers (six fixtures) all name the same 12 helpers:
`rt_store_i32`, `rt_shift_left_i32`, `rt_not_equal_i32`, `rt_narrow_i64`, `rt_load_i64`,
`rt_load_i32_from_u8`, `rt_equal_i32`, `rt_and_i32`, `rt_add_i64`, `into_bits_i64`,
`buffer_read_i32`, `bit32_or`. The next most common (14–20 of 21) are `rt_store_i64`,
`rt_and_i64`, `rt_store_i32_into_i8`, `rt_shift_right_u32`, `rt_widen_i32`, the `i32`/`i64`
compares, `rt_or_i64`, `rt_multiply_{i32,i64}`, and `rt_shift_{left,right_u}64`.

By family, the 45 helpers of the `gltf_rs` maximum body break down as:

* `i32` compares: 6
* `i64` compares: 6
* `i64` arithmetic and bitwise: 10
* `i64` conversions (`narrow`, `widen`, `into_bits`): 3
* `i32` arithmetic and bitwise (including `bit32_or`): 9
* loads: 4
* stores: 4
* `memory.copy` and `memory.fill`: 2
* `table.get`: 1

### 4.3 What target lowering or grouping would do (simulated on the census)

The first simulation lowers the `i32` families from `target-lowering.md` H2, H3, H5 and H6
(compares disappear; `and`/`or`/`xor`/shifts become `bit_*` primitives; `add`/`sub` become
`bit32_or`; `mul` becomes `bit_tobit`; aligned `i32` load/store become `buffer_trap`). The
simulation removes the lowered helpers from each body's set and adds the primitives it introduces:

| module | mean helpers per body before → after | max before → after |
| --- | --- | --- |
| gltf_rs | 8.54 → 6.21 | 45 → 39 |
| h264mp4 | 8.14 → 5.32 | 40 → 32 |
| self-hosting | 10.52 → 8.36 | 40 → 31 |
| binjgb | 6.26 → 5.02 | 33 → 27 |
| miniz-file | 9.10 → 6.84 | 33 → 28 |
| libjpeg-turbo | 8.72 → 6.19 | 26 → 18 |
| cgltf | 6.74 → 4.11 | 19 → 13 |
| wasm3 | 7.52 → 6.63 | 19 → 16 |

`i32` lowering buys 6–9 slots at the top end. What remains in the worst bodies is `i64` (19 of 39
in `gltf_rs`), which only the two-port `i64` representation (`target-lowering.md` H9,
`i64-representation.md`) would remove.

**Family grouping** (one table per family, 10 families) caps any body at **10** helper upvalues
(corpus mean 3.64 families per body). That is structural headroom that no fixture could exhaust.
The price is the one measured in strategies §3: a table form at each use site. Per §5 below, that
means turning free trace constants into guarded loads.

Since packing already covers the dependency-dominated shape, **the residual `lua-no-ffi` risk is a
single helper-heavy body growing by 11 or more distinct helpers**. Lowering is the cheapest
mitigation that also speeds things up. Per-body redirection of helpers, applied only over budget
(strategies §6), is the backstop.

---

## 5. How much upvalue traffic is hot

`luajit -jdump=bi` over one whole run per fixture, `lua-no-ffi` unless marked. `UGET` counts are
from the recorded bytecode of every trace. `ULOAD` counts are from the trace IR.

| run | traces (looping) | recorded BC | `UGET` (share of BC) | helper `UGET` | runtime-internal `UGET` | dependency `UGET` | IR `ULOAD` before loop / in loop |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `tinyexpr_hash(2000)` | 162 (7) | 93 719 | 10 473 (11.2 %) | 6 304 (60 %) | 3 597 (34 %) | 572 (5.5 %) | 169 / **0** |
| `chipmunk_hash_scene(60)` | 823 (20) | 554 926 | 57 145 (10.3 %) | 27 486 (48 %) | 27 953 (49 %) | 1 706 (3.0 %) | 405 / **0** |
| `gltf-rs main.lua` | 183 (20) | 191 476 | 25 058 (13.1 %) | 12 753 (51 %) | 10 854 (43 %) | 1 355 (5.4 %) + 96 `excess_stack` | 105 / **0** |
| `chipmunk(60)`, emulated `lua-jit` port | 1734 | 1 452 067 | 233 009 (16.0 %) | 228 759 (98 %, prelude and helpers together) | – | 4 250 (1.8 %) | 608 / **0** (418 `tab`, 190 `cdata`) |

Per trace, `lua-no-ffi`:

| run | helper `UGET`s | distinct helpers (max) | dependency `UGET`s | distinct dependencies |
| --- | ---: | --- | ---: | ---: |
| `tinyexpr` | 38.9 | 7.1 (27) | 3.5 | 2.5 |
| `chipmunk` | 33.4 | 7.7 (24) | 2.1 | 1.4 |
| `gltf-rs` | 69.7 | 12.5 (40) | 7.4 | 5.3 |

**Every `ULOAD` in every sampled trace is table-typed (or cdata-typed in `lua-jit`). There is not a
single function-typed `ULOAD`.** LuaJIT's recorder (`rec_upvalue`) specialises to the closure and
turns immutable function upvalues into constants, but it never does this for tables. So:

* The ~50 % of `UGET`s that fetch a module-bound helper, and the ~45 % that fetch a
  runtime-internal helper inside a section block, cost **nothing** in compiled code today. The
  call target is a constant `KGC`, and no guard is needed.
* The dependency `UGET`s (cells, memory, tables) become `UREFC` + `ULOAD`, but all of them are
  loop-invariant. They are CSE'd and sit before the loop. The real per-iteration cost of a
  dependency is the `cell[1]` load after it, which no upvalue strategy changes.
* The interpreter pays one `UGET` per helper call site, about 10–16 % of executed bytecodes.

What each candidate strategy would turn this into, per trace:

| strategy | compiled (per trace) | interpreter (per call site) |
| --- | --- | --- |
| today (helper upvalue) | constant, 0 IR | 1 `UGET` |
| H3 `runtime.rt_x` at the use site | `UREFC`+`ULOAD` of `runtime` (table, never a constant) + `HREFK`+`HLOAD`+`EQ` guard per distinct helper: ~4 IR × 7–12.5 distinct helpers (max 40), unless alias analysis lets them be hoisted | `UGET` + `TGETS`: +1 instruction on 34–70 helper calls per trace |
| family tables `F.op` (≤ 10 upvalues) | same as H3, per distinct helper | same as H3 |
| per-body rebinding on entry (`local rt_x = runtime.rt_x`, strategies H4/H7) | one `HLOAD`+`EQ` per helper per *inlined entry*; inside loops the helpers are locals, so their cost is the same as today | cheaper than today (`MOV` instead of `UGET`), plus entry cost of `TGETS` × helpers |
| packing helpers into `__spider_scoped_dependencies[k]` | `ULOAD` (table) + `AREF`/`ALOAD` + `EQ` per distinct helper | `UGET` + `TGETB` |
| packing dependencies (what ships) | cells are already `ULOAD`ed; adds one `ALOAD` per distinct dependency (1.4–5.3 per trace), before the loop | `UGET` + `TGETB` per access |
| `i32` lowering (target-lowering H2–H6) | removes the call altogether (calls to constant functions are already inlined, so the gain is fewer guards and snapshots) | removes `UGET` + `CALL` + `RET` |

Consequence for the sibling notes: helper upvalues are the one form of capture that is free in
traces. A strategy that keeps them as upvalues or `module()` locals, and spends table indirection
only on dependencies or only over budget, cannot lose speed on hot code. A strategy that routes
every helper through a table (H3, family tables, global `runtime`) changes about 50 % of the
sampled `UGET`s from constants into guarded loads.

---

## 6. Questions the sibling notes must answer by experiment

Ranked by how much the answer changes the decision.

1. **(structure)** Is the four-piece port A+B+C+D to `lua-jit` the whole story, and what does it
   cost at run time? Measure `lua-jit` kernels before and after on the 13 modules that load today.
   This is the first time the FFI baseline would run `tinyexpr`, `chipmunk`, `libjpeg`, `miniz-*`,
   `h264`, `plmpeg`, `wasm3` and self-hosting. Also check whether the helper rebinding changes
   trace counts or aborts.
2. **(environment)** Does anything in LuaJIT 2.1 (current `v2.1` branch versus `2.1.0-beta3`, and
   OpenResty's fork) change the 60-upvalue limit, the choice of which upvalues become constants
   (`rec_upvalue`: tables and userdata are never constants), or the 200-local limit? Can a
   different load path lift the limits, for example `string.dump` round trips or a `load` with a
   custom reader? Expected answer: no, because `LJ_MAX_UPVAL = 60` is a compile-time constant, but
   it has to be checked, not assumed.
3. **(structure)** Is it faster to make dependency cells constant (passing the *function*, not
   the `{ fn }` cell, for sibling calls whose target never changes after instantiation)? Today
   they are tables, so they cannot become constants: `dep_func` is 5.45 per body in `gltf_rs`, and
   each call is `ULOAD` + `cell[1]` + function-identity guard. This is the only upvalue traffic
   that reaches the IR, and it would also let the dependency class drop out of the census.
4. **(structure)** What is the cheapest guarantee for a body with more than 56 helpers?
   Candidates: over-budget-only helper redirection through a single printer method (strategies
   §6); rebinding on entry; splitting the body (outlining, H8). Measure on a synthetic body with 60
   or more helpers, because no fixture has one.
5. **(prior art)** How do other Wasm→Lua or large-code Lua generators (wasm2lua, Wasmoon-style
   interpreters, Fengari, Pallene, Terra, TypeScriptToLua's upvalue workarounds, LuaJIT's own
   `dynasm`/`jit.bcsave` users) structure a module so that per-function captures stay bounded?
   In particular, does anyone use per-module *environment* (`setfenv`/`_ENV`-style) tables for
   helpers? In LuaJIT, `GGET` on an unmodified function environment becomes an `HREFK` guard, the
   same cost as H3, so this has to be measured, not assumed.
6. **(environment)** `setfenv` on each body with a helper table as its environment: helpers
   become `GGET` (0 upvalues, 0 locals). What does it cost in traces (`HREFK` + `HLOAD` + guard per
   distinct global), and does it survive the 1 734-trace `chipmunk` run without extra aborts?
   This is the only helper strategy that costs neither upvalues nor locals.
7. **(structure)** Does `i32` lowering (target-lowering H2–H6) reproduce the 45 → 39 and
   40 → 31/32 predictions of §4.3 when it is actually implemented? Does `i64` two-port lowering
   take the worst body under 20?
8. **(structure)** For `lua-jit`, should the prelude move to `do` blocks now? `wasm3_jit` has 186
   chunk locals, 14 short of the next hard failure.
9. **(prior art / structure)** Does the `lua-jit` parameter wrapper (strategies §5 item 1)
   need the same `stack_top` / `excess_stack` handling as `lua-no-ffi`? `lua-jit` wrappers
   currently capture both (§2.2 rows at lines 175150 and 19811).
10. **(verification)** Add a test that fails when any module's worst `lua-no-ffi` body helper
    count rises above 50, or when any `lua-jit` `module()` count rises above 55. Today
    `secret_reader_jit` sits at exactly 60, with no warning.

---

## 7. Reproducing

```bash
# regenerate both targets for one fixture (the *_jit.lua files in the tree are stale)
target/release/spider-cli tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm -t lua-no-ffi > /tmp/t.lua
target/release/spider-cli tests/manual/real-world-tinyexpr/generated/tinyexpr.wasm -t lua-jit   > /tmp/t_jit.lua

# failing prototype
luajit -e 'print(select(2, loadfile("/tmp/t_jit.lua")))'

# hot upvalue traffic
luajit -jdump=bi,/tmp/dump.txt -e 'local w = dofile("/tmp/t.lua")() print(w.tinyexpr_hash(2000))'
sed -i 's/\x1b\[[0-9;]*m//g' /tmp/dump.txt
grep ' ULOAD ' /tmp/dump.txt | awk '{for(i=1;i<=NF;i++) if($i=="ULOAD") print $(i-1)}' | sort | uniq -c
```

The census script (≈200 lines of LuaJIT) follows §1.1–1.2. Its core is a walk over
`jit.util.funck(pt, k)` for `k = -1, -2, …`, reading `funcinfo(pt).upvalues` and
`funcuvname(pt, i)`. The load-failure path turns `^local function X` / `^local X =` before
`module()` into global assignments and adds each prototype's subtree `GGET`/`GSET` of those names.
