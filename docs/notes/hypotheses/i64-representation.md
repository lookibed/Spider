# `i64` Representation for `lua-no-ffi` — A Design Study

Status: **research only.** Nothing was built, run or measured for this note. Every claim about
the code is cited `file:line` against the working tree of `2026-09-23` (HEAD `bda2246` plus the
uncommitted `IR/Visitor` changes). Timings are quoted from
[`lua-no-ffi-performance-hypotheses.md`](../lua-no-ffi-performance-hypotheses.md) (§5.1, §11) and
carry that source. The static counts in §1.4 were read with `grep` from the checked-in generated
fixtures; they are not timings, and those files may be a little older than HEAD.

Companion notes: [`target-lowering.md`](target-lowering.md) (the `Node::Lowered` design, the
live-range hazard, the plumbing that makes the target known in the pipeline),
[`verification.md`](verification.md).

---

## 0. The one-paragraph version

Today every `i64` result allocates a fresh table `{lo % 2^32, hi % 2^32}`
(`Targets/LuaNoFFI/Printer/runtime/builtin/buffer.lua:560-563`). Every constant *use* allocates
one too, because constant isolation clones constants per use (`IR/Visitor/src/constant_isolator.rs:10-16`)
and the printer spells each clone `into_bits_i64(lo, hi)` (`Printer/src/expression.rs:395-403`).
LuaJIT sinks these tables only when nothing escapes. §5.1 of the performance note measured a
`1.9x` slowdown when an `i64` crosses a call, `5.2x` when it is carried across a loop, and `9.0x`
when it is stored, at about 55 B per operation. **The recommendation is an `i64` legalization pass
in the IR, run only for `lua-no-ffi`.** It maps every `i64` link to two `i32` links in canonical
signed (`bit.tobit`) form. Branch-free operations (bitwise ops, wrap, extend, constant shifts,
add/sub with carry, eq/lt) expand into the existing `I32` nodes. Branching ones (mul, div, rem,
variable shifts, clz/ctz, float conversions) become two-result helper nodes. An `i64.store`
becomes two word stores, high word first, which keeps the store atomic with respect to traps.
Tables and FFI stay out of the representation. Doing this in the IR rather than in the Tree
builder buys three things. The multi-port machinery already exists: `Apply.results`,
Gamma/Theta ports, parallel moves, and a scalar finder that gives multi-result nodes locals.
ISLE constant folding applies to the halves. And the printer barely changes. Before the pass
can be written, the IR has to know value types: contrary to common belief, the IR is **not**
typed per value. Only `FunctionType` carries `ValueType` (`IR/Graph/src/node/control.rs:10-31`),
and `Apply` has no type at all (`IR/Graph/src/node/simple.rs:47-54`). Migration comes in four
stages. The first keeps the boxed ABI at function boundaries (hypothesis E) and so needs no
harness change.

---

## 1. Inventory: where an `i64` lives today

### 1.1 Representation contract

| Item | Where | Contract |
| --- | --- | --- |
| Box | `buffer.lua:560-563` `into_bits_i64(lo, hi)` | new table `{ lo % 4294967296, hi % 4294967296 }`: **unsigned** halves, and one `%` per half even when the input is already canonical |
| Unbox | `buffer.lua:555-558` `from_bits_i64(t)` | `t[1], t[2]`; in the interpreter this is a real call, two per binary operator |
| Constant | `Printer/src/expression.rs:395-403` | prints `into_bits_i64(lo, hi)` at **every use**. `constant_isolator.rs:10-16` clones `Node::I64` per consumer, so a constant inside a loop allocates on every iteration |
| Local seed | `Sources/WebAssembly/Lifter/src/control_flow_lifter/basic_block_lifter.rs:105-111` (`add_i64_into(graph, 0)`), comment at `Printer/src/expression.rs:190-192` | every `i64` wasm local starts as `into_bits_i64(0, 0)` (316 sites in the self-hosting output) |
| Immutability | implicit | helpers never mutate an argument, and `rt_rotate_*_i64` returns `lhs` itself when the count is 0 (`i64.lua:469-471,489-491`). **Tables are shared freely** through locals, `GlobalGet` and parallel moves; any in-place scheme has to respect this (H-C) |
| Mixed-type inputs | `i64.lua:363-365,397-399,431-433,463-465,483-485,590-592,606-608,622-624` | shift, rotate and extend helpers test `type(x) == "table"` because they may receive either an `i32` number or an `i64` table |

### 1.2 Producers, consumers and the cost of each today

"Calls (interp.)" counts Lua calls in the interpreter. In a JIT trace they are all inlined, and
what survives there is the table traffic and the allocation.

| Op class | Runtime | Printer / name | Calls (interp.) | Tables allocated | Notes |
| --- | --- | --- | ---: | ---: | --- |
| constant | `buffer.lua:560-563` | `expression.rs:395-403`, `names_finder.rs:34-38` | 1 | **1 per use** | also a type guard at every consumer |
| `add`/`sub` | `i64.lua:59-93` | `names_finder.rs:96-97`, generic `rt_` path `expression.rs:510-522` | 4 | 1 | branch on the carry; `%` twice inside `into_bits_i64` |
| `and`/`or`/`xor` | `i64.lua:322-353` | `names_finder.rs:107-109` | 4 | 1 | the halves are independent, so this is ideal for splitting |
| `mul` | `i64.lua:95-132` | `names_finder.rs:98` | 4 | 1 | 8 `floor`/`%` digit extractions, 10 multiplies; exact below `2^53` |
| `div`/`rem` (u) | `i64.lua:180-221,260-273,307-320` | `names_finder.rs:99-106` | **about 200** (64 iterations of `raw_shift_left_one`, `raw_compare`, `raw_subtract`) | 2 (quotient **and** remainder, even when one is unused, `:220`) | there is no fast path for small operands |
| `div`/`rem` (s) | `i64.lua:223-258,275-305` | same | about 200 + up to 3 `rt_subtract_i64` | up to 6 | each negation allocates both a zero constant and a result |
| `shl`/`shr_s`/`shr_u` | `i64.lua:355-454` | `names_finder.rs:110-116` | 3 | 1 + the count's constant table | the count is nearly always a constant (`into_bits_i64(47, 0)` in `tests/manual/i64-compare/generated/i64_hash.lua`) |
| `rotl`/`rotr` | `i64.lua:456-494` | `names_finder.rs:117-118` | 3 helpers, each 3 inner | 3 + count | built from shl, shr_u and or: three allocations |
| `clz`/`ctz`/`popcnt` | `i64.lua:1-57` | `names_finder.rs:60-62` | 2–3 + a **bit loop** | 1 | `bit32_countlz/countrz` are while loops over bits (`runtime/builtin/bit32.lua:5-35`) |
| `eq`/`ne`/`lt`/`gt`/`le`/`ge` | `i64.lua:496-577` | `names_finder.rs:154-179` | 3 (and 4 for gt/le/ge through `not` wrappers) | 0 | `eqz` arrives as a compare against a constant, which allocates |
| wrap (`narrow`) | `i64.lua:579-585` | `names_finder.rs:184-187` | 2 | 0 | returns the **unsigned** `lo` as an `i32`; consumers re-normalize (`i32.lua:215-225` `force_i32`) |
| `extend_i32_u` (`widen`) | `i32.lua:298-305` | `names_finder.rs:190-194` | 2 | 1 | |
| `extend*_s` | `i64.lua:587-633` | `names_finder.rs:196-206` | 2 | 1 | |
| `i64 → f32/f64` | `i64.lua:635-702` | `names_finder.rs:221-224` | 2–4 | 0–2 (signed negation) | `raw_convert_u64_to_odd_f64` (`:653-670`) does round-to-odd; correct, and keep it |
| `f32/f64 → i64` | `core/f64.lua:241-331`, `core/f32.lua:247-273` | `names_finder.rs:334-345` | 2–3 | 1 | |
| reinterpret | `i64.lua:704-711`, `f64.lua:333-339` | `names_finder.rs:235` | 2 | 0 or 1 | `from_bits_f64` already takes `(lo, hi)` and applies `%` (`buffer.lua:699-702`) |
| `i64.load` | `core/memory.lua:124-137` | `names_finder.rs:433`, `expression.rs:853-878` | 4 | 1 | `buffer_check` + 2×`buffer_read_i32`, each of which checks bounds again (`buffer.lua:346-370`); `%` twice |
| `i64.load{8,16,32}_{s,u}` | `memory.lua:58-122` | `names_finder.rs:427-432` | 2–3 | 1 | |
| `i64.store` | `memory.lua:196-207` | `names_finder.rs:561`, `statement.rs:582-604` | 4 | 0 (but it forces the producer's table to exist, since it escapes) | writes signed words; the high half is normalized again by `bit_tobit` (`buffer.lua:443-476`) |
| `i64.store{8,16,32}` | `memory.lua:169-194` | `names_finder.rs:558-560` | 2–3 | 0 | |
| global get/set | `expression.rs:733-753`, `statement.rs:473-489` | `GlobalNew` prints `{ init }` | 0 | 0 on get (shared); set **escapes** the producer | an `i64` global is `{ {lo, hi} }`, a double box |
| call argument / return | `statement.rs:447-471`, `expression.rs:428-443`, return list `expression.rs:139-144,162-167` | `Builder/src/code_handler.rs:136-151` | 0 | producer escapes unless the callee is inlined into the same trace | this is the `call` row of §5.1, worth `1.92x` |
| loop-carried / gamma-merged | parallel moves (`statement.rs:419-445` `SwapAll`) | builder bulk assignment | 0 | the producer escapes through a trace PHI | this is the `counter` row, worth `5.2x` and 55 MB per 1M |
| host boundary | `Conformance/tests/harness/luanoffi.start.lua:22,36-37,138-151`; `Conformance/tests/luanoffi.rs:169-178,316-326` | | | | the harness passes and asserts **boxed, unsigned** `into_bits_i64` tables; exports and imports are part of that ABI |

### 1.3 What the IR and the builder know about types

- `ValueType` exists only inside `FunctionType { arguments, results }`
  (`IR/Graph/src/node/control.rs:10-31`), which hangs off `LambdaIn.kind` (`:35-45`).
- `Apply` stores only `function`, `arguments` and `results: u16` (`simple.rs:47-54`). The lifter
  knows the callee type at `handle_call` (`basic_block_lifter.rs:260-277`), but it throws it
  away. Direct calls go through a function global (`Sources/WebAssembly/Lifter/src/lib.rs:109-117,
  498-513`), and indirect calls through `TableGet` carrying only a *string* type key
  (`basic_block_lifter.rs:593-613`).
- Gamma, Theta and Region ports, `Identity` and `Fence` are untyped. An imported global's
  `Import` node is untyped as well (`lib.rs:109-117`).
- The per-value type is recoverable. Every leaf is typed (`Node::I64`, `IntegerBinaryOperation.kind`,
  `LoadType::I64*`, `NumberTruncateToInteger.to`, `IntegerWiden`, `IntegerExtend`,
  `LambdaIn.kind`), and one forward pass in topological order fixes the rest: Theta inputs are
  typed before the back edge is seen. **Two holes need lifter help: `Apply` results, and
  imported `i64` globals.**
- The builder binds **one** `Local` per `Link` (`Builder/src/data_handler.rs:19-23,52-65`). It
  inlines single-use values as nested expressions (`:56-65`, `store_expression :42-46`), and
  gives a node locals when a port is reused, used out of order, is a non-first port, or has
  effects (`local_allocator/scalar_finder.rs:154-176`). Past 197 fast locals it spills to
  `excess_stack[...]` (`local_provider.rs:9,46-58`, printed at `expression.rs:205-208`).

### 1.4 How much `i64` real fixtures carry (static, `grep` over `generated/*.lua`)

| Fixture | `into_bits_i64` sites | `rt_*_{i64,s64,u64}` sites | all `rt_*` sites |
| --- | ---: | ---: | ---: |
| `self-hosting-luanoffi-builder` (Rust) | 2 072 | **5 484** | 14 066 (39 % `i64`) |
| `real-world-gltf-rs` (Rust) | 1 128 | 2 842 | 32 055 |
| `real-world-chipmunk` | 202 | 914 | 5 213 |
| `real-world-wasm3` | 352 | 703 | 7 229 |
| `real-world-lodepng` | 390 | 450 | 8 975 |
| `real-world-libjpeg-turbo` | 204 | 250 | 22 247 |
| `real-world-miniz` | 61 | 56 | 2 737 |

Self-hosting breakdown: `load_i64` 1 041, `and` 811, `store_i64` 762, `xor` 572, `mul` 549,
`shr_u` 408, `narrow` 378, `eq` 323, `add` 191, `widen` 172, `ctz` 153, `shl` 134. This is
Rust's `hashbrown` and `FxHash` signature: 8-byte group loads, xor/and/sub bit tricks,
`mul` by `0x0101010101010101` (visible at line 7034 of that file), `ctz` over match masks, and
`memcpy` of 8-byte fields through `load_i64`/`store_i64` pairs. So the **key fixture** from the
standing direction is also the heaviest `i64` workload in the repository. It is dominated by
exactly the classes that splitting makes almost free (memory moves, bitwise ops, wrap and extend).

---

## 2. Cross-cutting facts every hypothesis must respect

1. **Lua truncates multiple values** everywhere except the *last* expression of an argument list,
   a `return` list or a multiple assignment, and it truncates any parenthesized call. A
   two-result expression can therefore only be (i) the right side of `local a, b = ...`, (ii) the
   last argument of a call, or (iii) the last element of a `return`. Any other use must be
   materialized into locals. Function returns in this fork end with the state values
   (`return loc_3_, loc_2_` in the `i64-compare` output), so (iii) almost never applies.
2. **LuaJIT and multiple returns.** Fixed-count `CALL`/`RET` with two results is compiled
   without vararg machinery. `select`, `...` and `unpack` are what break traces, and none of them
   is needed. A small helper returning `lo, hi` is inlined into the trace as two SSA numbers.
3. **Allocation sinking** covers only allocations that do not reach a store, a non-inlined call
   or a PHI (the `counter` row). Plain numbers are register-allocated through PHIs.
4. **Limits.** There are 200 active locals per function (the allocator budgets 197,
   `local_provider.rs:9`) and 60 upvalues (packing starts at `CAPTURE_BUDGET`,
   `expression.rs:30,268`). Module locals are counted at `statement.rs:330-340`. Splitting can
   double the number of live `i64` values that need a register.
5. **Region boundaries.** In the current tree, ISLE producer lookup no longer looks through
   `RegionIn`/`GammaIn` (`IR/Visitor/src/isle/context.rs:11-19`). A `Split(Join(..))` pair that
   straddles a gamma or theta therefore **will not fold**. Any scheme that keeps a box on a
   region port keeps the allocation, so ports must be split too.
6. **Trap atomicity of stores**: a known fixed bug is that `i64.store` at address `-1` used to
   write half of the value before trapping (`docs/notes/lua-no-ffi-known-bugs.md:45-47`).
7. **The live-range hazard.** Rewrites that change which values are live across a region
   boundary have miscompiled `real-world-miniz` while conformance still passed
   (`IR/Visitor/isle/iNN.isle` comment cited in `target-lowering.md` §3.6). Doubling ports
   exercises the same parallel-move code.

---

## 3. Hypotheses

Every hypothesis gets the same fields. Gains are by op class, relative to today, and use §5.1
numbers where they apply. Where no measurement exists, the gain is **reasoned, not measured**,
and says so.

### H-A — Two Lua locals per `i64`, split while building the Tree

**Mechanism.** The `lua-no-ffi` builder gives each `i64` link two names, `loc_N_lo` and
`loc_N_hi`. Helpers take `(a_lo, a_hi, b_lo, b_hi)` and return `lo, hi`. Calls and returns double
the arity for each `i64` position, and `rt_store_i64(m, base, off, lo, hi)` writes two words.

**Expected gain.**
- Memory `load_i64`/`store_i64`: the allocation disappears, and so do the `%`. Two word reads
  or writes remain. In the `escape` row this is up to `9.0x`.
- Arithmetic and bitwise ops: `1.0x` in a sunk loop (the `hash` row), `5.2x` loop-carried,
  `1.9x` across calls.
- Interpreter: `2.5x`–`7.4x` (§5.1). The `from_bits` and `into_bits` calls go away too.

**Code size.** Names are longer, and a call has four arguments instead of two. Worse, pure
single-use producers can no longer be inlined as nested expressions (fact 1), so each producer
becomes `local lo, hi = rt_x(...)`. Estimated at +40–80 % on `i64` statements. This is a
guess; check it with M0.

**Limits.** Every `i64` value that is not the last argument of its consumer needs two locals,
which is more locals than today, where a single-use value costs zero. Functions near 197
spill. Upvalues are unchanged.

**Correctness risks.** The whole allocator (`scalar_finder`, `argument_finder`,
`reference_finder`, `index_provider`) is keyed by `Link` → one `Local`. `SwapAll` and
`assignment_simplifier.rs` would need pair awareness. Types have to be recovered inside the
builder, which has no view of the callee type.

**Implementation sketch.** Touches `Builder/src/data_handler.rs` (`assignments: Link →
(Local, Option<Local>)`, `load` returns a pair), `local_allocator/*` (two pulls per `i64` port),
`code_handler.rs` (`do_bulk_assignment`, `do_rename`, `do_call`), a Tree `Statement::Assign`
with two destinations, and the printer for every `i64` form.

**Verdict.** Right idea, wrong layer. It re-implements multi-port support that the IR already has.

**Measurement.** M0 (local census), then M2 (hand-split kernels).

### H-B — `i64` legalization pass in the IR (Split/Join plus expansion into `I32` nodes)

**Mechanism.** This is a target-gated IR pass, the same technique as LLVM's `ExpandInteger`
type legalization and Binaryen's `I64ToI32Lowering` used by `wasm2js`. Walking in topological
order, it keeps `map: Link(i64) → (Link lo, Link hi)` and rewrites each `i64` node:

| `i64` op | Lowered to (existing nodes unless marked **new**) |
| --- | --- |
| `I64(k)` | `I32(lo_k)`, `I32(hi_k)`, with both constants in signed form |
| and/or/xor | `I32And(a.lo, b.lo)`, `I32And(a.hi, b.hi)`, and so on |
| add | `lo = I32Add(a.lo, b.lo)`; `c = I32LtU(lo, a.lo)` as 0/1; `hi = I32Add(I32Add(a.hi, b.hi), c)` |
| sub | `lo = I32Sub(a.lo, b.lo)`; `bw = I32LtU(a.lo, b.lo)`; `hi = I32Sub(I32Sub(a.hi, b.hi), bw)` |
| eq/ne | `(a.lo == b.lo) and (a.hi == b.hi)`, with `ne` as the negation |
| lt_s etc. | `I32LtS(a.hi, b.hi) or (a.hi == b.hi and I32LtU(a.lo, b.lo))` |
| wrap | `a.lo` (**free**) |
| extend_i32_u | `(x, I32(0))` (**free**) |
| extend_i32_s / extend{8,16,32}_s | `(x', I32ShrS(x', 31))` with `x'` the existing `i32` extend |
| shl/shr/rotl/rotr by constant `k` | two `i32` shift/or expressions selected by `k < 32`, `k == 32`, `k > 32` at compile time |
| shl/shr/rot by a variable, mul, div, rem, clz/ctz/popcnt, conversions | **new** two-result helper node (`Node::Lowered`, `target-lowering.md` §2.2 option B), printed as `local lo, hi = rt_op(a_lo, a_hi, b_lo, b_hi)` |
| `i64.load` | `I32Load(off)`, `I32Load(off+4)` (loads have no side effect, so a partial read before a trap is invisible) |
| `i64.load32_u/_s`, 16, 8 | the existing `i32` load kind, plus `hi = 0` or `hi = I32ShrS(lo, 31)` |
| `i64.store` | `I32Store(off+4, hi)` **then** `I32Store(off, lo)`, chained through the state port. Writing the high word first makes the store trap-atomic (see H-K). Keep one node if `off > u32::MAX - 4` |
| `i64.store{8,16,32}` | the existing `i32` store of `lo` |
| Gamma/Theta/Region ports, `Identity`, `Fence` | one `i64` port becomes two `i32` ports |
| `LambdaIn` arguments, `LambdaOut` results, `Apply` arguments and results | depends on the stage: boxed (`Join`/`Split` at the boundary, H-E) or doubled arity (H-H) |
| boundaries that are never lowered (host import/export adapters, `i64` globals in the boxed stage) | **new** `I64Join(lo, hi) → box`, printed `into_bits_i64(lo, hi)`; **new** `I64Split(box) → (lo, hi)`, printed `local lo, hi = x[1], x[2]` |

ISLE then folds `Split(Join(lo, hi)).{0,1} → lo/hi` and `Join(Split(x).0, Split(x).1) → x`
(valid because boxes are immutable). It also folds the `i32` identities the expansion exposes:
`and(x, 0) → 0`, `or(x, 0) → x`, `ltu(x, 0) → 0` and constant folding of and/or/xor/shifts.
Today `IR/Visitor/isle/iNN.isle` has only add/sub rules, so these have to be written.

**Why it composes well with the existing pipeline.**
- Multi-result `Apply`/`Lowered` nodes already get locals (`scalar_finder.rs` "non-first port in
  use"), so fact 1 is handled by construction.
- Pure single-use halves stay inlined as expressions (`data_handler.rs:56-65`). A
  hashbrown-style `narrow(xor(shr_u(x, 32), x))` lowers to one `i32` expression,
  `bit_xor(x_hi, x_lo)`, with **zero** locals.
- Port doubling for Gamma, Theta and Region reuses the parallel-move code that the conformance
  suite and all fixtures exercise daily.
- The printer only learns about `Lowered` pair helpers and `Join`/`Split`. All `rt_*_i64` names
  drop out of `names_finder.rs`.

**Expected gain by op class** (reasoned from §5.1, not measured):
- Memory: allocation-free, one bounds test per word. `load_i64`→`store_i64` copies turn into
  word moves (the Rust `memcpy` pattern, about 1 800 sites in self-hosting).
- Bitwise, wrap, extend, constant shifts: `1.0x`–`9.0x` depending on escape. In the interpreter
  they go from four calls to zero or one.
- Compare: no calls, no constant tables.
- Add/sub: branch-free, three or four `i32` ops, no allocation.
- Mul, div, rem: the same algorithm without allocation. Div/rem additionally gain from H-J.
- Calls: `1.92x` in stage 2 (H-H).

**Code size.** Inline halves print as two expressions. Add/sub prints as three `i32` expressions
plus a compare, longer than `rt_add_i64(a, b)`. Constants become two plain literals, shorter than
`into_bits_i64(...)`. Estimated at ±0 to +30 % on `i64` text, which is below H-A because pure
chains stay nested. M0 will tell.

**Limits.**
- Locals: only multi-use halves and two-result helpers cost locals. Loop-carried `i64` values
  cost two instead of one.
- Upvalues: the `rt_*_i64` families (up to about 30 distinct names) collapse into `bit_*`
  primitives that are already shared and about 8 pair helpers. For `i64`-heavy bodies that is net
  better (see `target-lowering.md` §5.1).
- Boundary copies: each `i64` loop-carried port becomes two number moves. The count goes up,
  but the cost per move stays the same.

**Correctness risks.**
- The canonical-half invariant (H-I).
- Trap placement: never build a trapping node on an ISLE right-hand side
  (`target-lowering.md` §3.5). Div and rem stay a single `Lowered` node, pinned through the
  existing `Fence` exactly as today.
- Store ordering (H-K).
- The live-range hazard (fact 7), because more ports go through the gamma and theta moves.
- The pass must run **unconditionally** for `lua-no-ffi`, with or without `-o`, because it
  changes the representation. It is not an optional optimization. The lifter–builder pipeline
  in `CLI/src/main.rs` and `Conformance/tests/common/compiler.rs` must call it in both modes
  (`target-lowering.md` §3.7 plumbing).

**Implementation sketch.**
- `IR/Visitor/src/value_types.rs` (new): forward type inference over links.
- `IR/Graph/src/node/simple.rs`: `Apply { .., kind: Option<Box<FunctionType>> }`, filled by the
  lifter at `basic_block_lifter.rs:260-277` and in the `call_indirect` path. Also a `ValueType`
  on imported globals.
- `IR/Visitor/src/i64_legalizer.rs` (new, estimated 600–900 lines).
- `IR/Graph` node kinds: `I64Split`, `I64Join` and `Lowered` (or Split/Join as `Lowered` opcodes).
- `IR/Visitor/isle/i64.isle` plus more `iNN.isle` identities.
- `Targets/LuaNoFFI/Builder/src/lib.rs`: handle the new nodes.
- `Printer/src/expression.rs` and `names_finder.rs`: `Lowered` pair helpers.
- `runtime/core/i64.lua`: rewritten on `(lo, hi)`.
- `runtime/core/memory.lua`: the `i64` sections become dead.

**Measurement.** M0, M2, M3 (conformance and fixtures), M4 (counters), M5 (A/B in process).

### H-C — Keep tables; intern constants and reuse result tables

**Mechanism.** (1) Every `Node::I64` constant becomes one entry in a per-module constant table
`K`, and the printer emits `K[7]`. That costs one upvalue per function, one table load, and no
allocation. The alternative, one upvalue per constant, would blow the 60-upvalue budget. Sharing
is safe because helpers never mutate their arguments. (2) Results are written in place when the
producer is single-use and the destination table is uniquely owned: `rt_add_i64_into(dst, a, b)`
on a loop accumulator.

**Expected gain.**
- (1): removes one allocation per constant operand per evaluation. That is about half of all
  `i64` operands in the `i64-compare` sample (`loc_7_ = rt_add_i64(loc_5_, into_bits_i64(...))`).
  In the interpreter an estimated 1.2–1.5x on constant-heavy code. Under the JIT little changes,
  because constants consumed by inlined helpers are already sunk.
- (2): would attack the `counter` case (5.2x), but only where ownership is provable.

**Code size.** (1) shrinks it slightly. (2) roughly doubles the helper table.

**Limits.** (1) costs one upvalue and one module local.

**Correctness risks.** (2) is the problem. Aliasing is everywhere: `Assign dst = Local src`
copies share the reference, `SwapAll`, `GlobalGet` returns the global's own table, and
`rt_rotate_*` returns `lhs`. Proving unique ownership needs an escape and alias analysis over
Tree statements, and one mistake silently corrupts values. It also fixes nothing at calls or
stores.

**Implementation sketch.** (1): `constant_isolator.rs` should stop cloning `I64` for this
target, and the printer should hoist a `K` table (`Printer/src/statement.rs` module prologue).
(2): not recommended.

**Verdict.** (1) is a **cheap probe** (it can be tested with `sed`, M1) and a stopgap if H-B
slips. (2) is **rejected**: high risk, and H-B subsumes it.

### H-D — `i64` as a double when range analysis proves 53 bits, slow path otherwise

**Mechanism.** Interval analysis over the IR types an `i64` as "fits in ±2^53" and keeps it as
one number. Anything unproven stays in the general representation. A dynamic variant guards at
run time.

**Expected gain.** §5.1 measured the double `T3` at `0.0274` against `0.0267` for the pair `T2`
under the JIT (no gain), and `12.7x` against `7.4x` in the interpreter (a gain only there, only
for counters).

**Code size and limits.** Two code paths wherever the proof fails, plus conversion at each
boundary between the paths. It saves locals only where it applies.

**Correctness risks.** Wasm `i64` values come overwhelmingly from memory loads (unknown range),
hashes and multiplies (full range), and 32×32→64 widening products, which exceed `2^53`. Range
analysis rarely proves anything outside counters. The dynamic variant pays a type test per
operation. That is exactly the "strictly more work" argument that §5.1 used to reject the hybrid.

**Verdict. Rejected as a representation.** Its only useful part is a *helper-internal* fast
path, see H-J.

### H-E — Hybrid: pairs inside bodies, boxed at escape points

**Mechanism.** Values are split everywhere inside a function body. Boxes appear only where a
value leaves the body's control: function parameters and returns (stage 1 only), host
imports and exports (always), `i64` globals (until H-F), and exported tables and globals.
Memory is **not** an escape point here, because words map straight onto halves (H-K). Wasm
tables never hold `i64`.

**Expected gain.**
- Every intra-body op: the allocation disappears. That covers the `counter` (5.2x), `escape`
  (9.0x) and memory classes.
- Calls stay at today's cost (1.0x relative to today on the `call` row) until H-H.
- It removes the harness risk entirely: exports and imports keep today's boxed unsigned ABI, so
  `Conformance/tests/luanoffi.rs:169-178,316-326` and the harness need no change.

**Code size.** Split at entry (`local a_lo, a_hi = a[1], a[2]`) and Join at each return: one
line per `i64` parameter or result.

**Limits.** Neutral for parameters. It adds up to two locals per `i64` parameter, since the box
parameter stays live.

**Correctness risks.** Few. The box format at the boundary is today's format, so boxing must use
`into_bits_i64` (unsigned) to match `hn_assert_equal_i64` (`luanoffi.start.lua:141-151`).

**Implementation sketch.** H-B in its "boxed ABI" mode. `LambdaIn`, `LambdaOut` and `Apply`
keep their `i64` ports, and the legalizer inserts `Split` after `LambdaIn` and `Apply` results
and `Join` before `LambdaOut` and `Apply` arguments.

**Verdict.** This is **stage 1** of the migration. It is not the end state, because internal
calls keep paying `1.92x`.

### H-F — `i64` globals stored unboxed as two slots

**Mechanism.** A module-internal `i64` global becomes `{ lo, hi }`, a mutable cell rather than a
box inside a box: `g[1] = lo; g[2] = hi`. `GlobalGet` reads `g[1], g[2]`, which are two
independent single-result expressions and so need no locals. Imported and exported `i64` globals
keep today's `{ {lo, hi} }` so the host view is unchanged (harness `global_i64`,
`luanoffi.start.lua:22`).

**Expected gain.** `GlobalSet` no longer forces an allocation, and `GlobalGet` loses one pointer
indirection. This matters only for code with hot `i64` globals: rare in C (the stack pointer is
`i32`), plausible in Rust (TLS and counters) and in wasm3. Probably small in aggregate. M0
counts the sites.

**Code size.** Neutral. **Limits.** None.

**Correctness risks.** The `GlobalGet`/`GlobalSet` state-port renames (`Builder/src/lib.rs:349-370`)
must treat the two slots as one state. ISLE global forwarding is disabled by default
(`target-lowering.md` §3.6), so it cannot reorder anything. The imported/exported split needs the
global's export status at legalization time; it is known from `OmegaOut.exports`
(`control.rs:145-152`).

**Implementation sketch.** The legalizer rewrites `GlobalNew(i64)` into a two-slot form: either a
new `GlobalNew` with two initializers, or `Lowered` opcodes `GlobalNew2`/`GlobalGet2`/`GlobalSet2`.
Printer arms go next to `expression.rs:733-753` and `statement.rs:473-489`.

**Verdict.** Stage 3, and only if M0 shows the sites are there.

### H-G — Comparisons, shifts and rotates on pairs with bit ops

**Mechanism.** Inline expansion on canonical signed halves (H-I), with `MIN = 0x80000000`:
- `eq`: `a_lo == b_lo and a_hi == b_hi`.
- `eqz`: `a_lo == 0 and a_hi == 0`. Recognize `eq(x, I64(0))` so the constant disappears.
- `lt_s`: `a_hi < b_hi or (a_hi == b_hi and bxor(a_lo, MIN) < bxor(b_lo, MIN))`. The signed high
  half compares natively, and the low half compares unsigned through the bias.
- `lt_u`: the same, with `hi` biased as well.
- `shl` by a constant `k`, `0 < k < 32`: `hi = bor(lshift(hi, k), rshift(lo, 32 - k))`,
  `lo = lshift(lo, k)`. For `k == 32`: `(0, lo)`. For `k > 32`: `(0, lshift(lo, k - 32))`.
  `shr_u` and `shr_s` mirror this (`arshift`, sign fill `arshift(hi, 31)`). `rotl`/`rotr` by `k`:
  two `bor`s of shifts, and `k == 32` is a swap.
- A variable count: a two-result helper. The count is `band(count_lo, 63)`, and `hi` is ignored
  per the wasm spec.

**Expected gain.**
- Compares: 3–4 interpreter calls and possibly a constant table become 2–4 bytecode compares,
  with no call.
- Constant shifts (all of the sampled ones): 3 calls and 2 allocations become 3–4 `bit` ops.
- Rotates: 9 calls and 3 allocations become 4 `bit` ops.
- `narrow(shr_u(x, 32))`, the "take the high 32 bits" idiom, becomes plain `x_hi`: zero
  instructions after folding.

**Code size.** About ±0 per site, because the constant-table text disappears.

**Limits.** An operand used in both the `lo` and `hi` expression becomes multi-use and needs a
local, which is usually already the case for loop values.

**Correctness risks.** Masking the shift count (only `band(k, 63)`), the `k == 0` and `k == 32`
edges, and LuaJIT's shift semantics. `bit.lshift(x, 32)` equals `x` (the count is taken mod 32),
so a count of 32 or more must never reach a single `bit.*` call. The expansion has to pick the
branch at compile time. Compares must use `BooleanToInteger` the way `i32` compares do.

**Implementation sketch.** Rules inside the H-B legalizer, plus `I32Shl`, `I32ShrU`, `I32Or`,
`I32Xor` and `I32LtU` constructors in `types.iNN.isle`. If H-B is deferred, the same expansions
could be printer specializations keyed on `Expression::I64` right-hand sides in
`expression.rs:483-543`, but that path leaves the allocation of the result.

**Verdict.** Part of H-B. As printer-only specialization over tables it is **not worth doing**,
because the result allocation remains.

### H-H — Use LuaJIT's multiple-return convention (internal ABI with doubled arity)

**Mechanism.**
- An `i64` parameter becomes two parameters, and an `i64` result becomes two return values.
- `Statement::Call` already prints `r1, r2, ... = f(...)` (`statement.rs:447-471`), and returns
  already print a list (`expression.rs:139-144`). No `select`, no `...`, no `unpack`.
- **Adapters** keep the host ABI boxed:
  - Each exported function whose signature has an `i64` is wrapped in an IR-built lambda that
    unboxes its arguments, calls the internal function and boxes the results.
  - Each imported function with an `i64` in its signature is wrapped the other way at import
    time. The wrapper replaces `GlobalNew(Import)` in `lib.rs:109-117`.
- Everything reachable from inside the module speaks the internal ABI. That includes all wasm
  table entries, because imported functions are already wrapped. `call_indirect` type keys
  (`rt_function_type`, the `LambdaIn.key`) stay the *wasm* type string, so the signature check
  is unaffected.

**Expected gain.** The `call` row: `1.92x` under the JIT and `3.08x` in the interpreter (§5.1).
It also removes the entry Split and return Join lines that H-E adds.

**Code size.** Longer argument lists, and fewer lines than H-E.

**Limits.** A function with more than about 98 `i64` parameters would exceed the 200-local limit
on parameters alone. Such a function should fall back to the boxed ABI for that function type
(decided per `FunctionType` at legalization, so call sites agree). Returns are not a limit.

**Correctness risks.**
- The only ABI hole is a host that pulls a function *out of an exported table or a funcref
  global*: it sees internal arity. Document it. Covering it would mean wrapping on `table.get`
  from the host view, which the byte-view metatable pattern could do if ever needed.
- Cross-module linking in conformance (`register`, `linking.wast`) stays consistent, because
  both modules use the same internal ABI through tables. Direct imports go
  export adapter → import adapter, which is correct if slow.
- Multi-value wasm functions returning several `i64`s are handled naturally.

**Implementation sketch.**
- The legalizer rewrites `FunctionType` (`i64` becomes `I32, I32`), `LambdaIn.kind`, `LambdaOut`
  results and `Apply`.
- Adapter lambdas are built in IR next to `OmegaOut.exports` and the import globals.
- The printer is unchanged.

**Verdict.** Stage 2.

### H-I — Canonical signed (`bit.tobit`) halves instead of unsigned halves

**Mechanism.** Every half is a canonical `i32`, which is what the rest of the runtime already
uses (§11.2 decision 1) and what memory words are (`buffer.lua:1-16`).

**Expected gain.**
- `i64.load` and `i64.store` map onto words without `%` or `tobit`.
- `eq` is a raw `==`, and signed compares use `hi` natively.
- Bitwise ops need no normalization, because `bit.*` already returns the canonical form.
- The halves *are* `i32` values, so the lowering can reuse `I32` nodes and every `i32` ISLE
  rule. With unsigned halves, H-B's reuse of `I32` nodes would be **unsound**, because `I32`
  printing (`bit32_or(a + b, 0)`, `expression.rs:497-510`) produces signed output.
- Today's `%` per half in `into_bits_i64` goes away (`%` on doubles compiles to
  floor, multiply and subtract).

**Costs.**
- Unsigned compares and `u64 → float` conversions need a bias or `force_u32`.
- `mul` must extract 16-bit digits with `band(x, 0xFFFF)` and `rshift(x, 16)`, which are *cheaper*
  than today's `% 0x10000` and `floor(/0x10000)`.

**Correctness risks.** The invariant must hold at every producer:
- Constants must be printed signed.
- Float-to-int results, `into_bits_f64` (which returns unsigned halves, `buffer.lua:748-800`),
  and unboxing at host adapters all need `tobit`.
- A non-canonical half breaks `==` silently.

Mitigation: a debug runtime flag that asserts `x == bit.tobit(x)` at helper entry, plus a
conformance run in that mode.

**Verdict.** Adopt, as part of H-B.

### H-J — Range-guarded fast paths *inside* the helpers (div/rem, mul, conversions)

**Mechanism.**
- `div_u`/`rem_u`: when both `hi == 0`, use `floor(ua / ub)` on unsigned 32-bit doubles. More
  generally, when both operands are in `[0, 2^53)` (`0 ≤ hi < 2^21`), `q = floor(a / b)` in
  doubles is exact. For integers `a, b < 2^53`, a non-integer quotient is at least `1/b` away
  from the next integer, which is more than half an ulp of `a/b`, so the rounded quotient never
  crosses an integer. Then `r = a - q*b` is exact.
- Signed division: take magnitudes the same way, but keep the `INT64_MIN / -1` and divide-by-zero
  traps **before** the fast path, in today's order (`i64.lua:231-241`).
- `mul`: when both `hi` halves are 0 or −1, or one operand is a small constant, fewer digit
  products are needed.
- `u64 → f64` when `hi ≥ 0` in signed form: `hi * 2^32 + ulo` needs one rounding and no
  branch. With signed halves, `s64 → f64` is simply `hi_s * 2^32 + lo_u`: exact product, one
  rounding, and **no negation**, unlike `i64.lua:683-694`.

**Expected gain.** Div/rem go from about 200 calls and 64 loop iterations to a handful of flops
for the common small-operand case (`hash_i64_div` in `i64-compare`, sizes and offsets). That is
an estimated 10–50x on that op class; it is not measured.

**Code size.** A few lines in the runtime. **Limits.** None.

**Correctness risks.**
- The `2^53` bound must be checked on the *magnitudes* after sign handling.
- `rem_s` takes the sign of the dividend.
- The `-0` result of a float `floor` is harmless, because `tobit(-0) == 0`.
- Round-to-odd for `u64 → f32` stays mandatory (`i64.lua:653-670`).

**Verdict.** It works with either representation, so it is a **stage 0 quick win** and can
land first.

### H-K — `i64.store` as two word stores, high word first; `i64.load` as two word loads

**Mechanism.** `buffer_check(base, off, 8)` passes exactly when `base ≥ 0` and
`base + off + 8 ≤ n`. The high-word store checks `base ≥ 0` and `base + off + 4 + 4 ≤ n`, which
is the same condition. The low-word store checks `base + off + 4 ≤ n`, which is implied. So
"store `hi` first" traps before any byte is written, exactly when the combined check would. That
removes the need for a separate `buffer_check`, and the store stays atomic (fact 6). Loads have
no side effects, so the order does not matter.

**Expected gain.** One bounds test fewer per access, plus everything H-B gives. On aligned
addresses the two words are `w[s]`, `w[s+1]`, the future aligned fast path (§9 step 3 of the
performance note).

**Risks.**
- Static offset overflow when `off + 4 > u32::MAX`: keep one node in that case.
- The state chain must order the two stores. They go through the existing
  `MemoryStore.STATE_PORT` renames (`Builder/src/lib.rs:481-490`).
- The *unaligned* word store path writes two words each (`buffer.lua:466-475`). The atomicity
  argument still holds, because each store checks its full 4-byte range before writing.

**Verdict.** Part of H-B.

---

## 4. Comparison

| # | Hypothesis | Gain (JIT) | Gain (interp.) | Code size | Locals / upvalues | Risk | Effort | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | split in the Tree builder | 1.9–9.0x | 2.5–7.4x | +40–80 % `i64` text | locals ↑↑ (no inlining of pairs) | high (allocator rewrite) | high | superseded by B |
| B | IR legalization | 1.9–9.0x, memory up to 9x | 2.5–7.4x + call removal | ±0–30 % | locals ↑ only for shared halves; upvalues ↓ | medium (ports, invariant) | high | **adopt** |
| C1 | intern constants | ~1.0–1.1x | ~1.2–1.5x | ↓ | +1 upvalue | low | low | probe / fallback |
| C2 | in-place results | ≤5.2x where provable | same | ↑ | – | **high** (aliasing) | high | reject |
| D | double with range proof | 1.0x vs pairs | ≤1.7x vs pairs on counters only | ↑ (two paths) | – | high | high | reject |
| E | hybrid, boxed ABI | B minus calls | same | + entry/return lines | neutral | low | (part of B) | **stage 1** |
| F | unboxed globals | small | small | 0 | 0 | low | low | stage 3, if M0 justifies it |
| G | inline compare/shift/rotate | part of B | part of B | ±0 | shared operand → local | low | (part of B) | adopt within B |
| H | multi-return ABI | 1.92x on calls | 3.08x on calls | ↓ vs E | >98 `i64` params → fallback | medium (host edge) | medium | **stage 2** |
| I | signed halves | enables B's `I32` reuse, −`%` | same | ±0 | – | medium (invariant) | (part of B) | adopt |
| J | fast div/rem/conv | 10–50x on small-operand div (est.) | same | +small | – | low | low | **stage 0** |
| K | two word stores, hi first | −1 bounds test | same | ±0 | – | low | (part of B) | adopt |

---

## 5. Recommendation and staged migration

**Direction.** H-B, with H-G, H-I and H-K as its expansion rules, reaching H-H as the end-state
ABI. H-E is stage 1 to de-risk the change. H-J lands independently first. H-F is optional. H-C1
is used only as a measurement probe, or as a fallback if stage 1 slips. H-A, H-C2 and H-D are
rejected.

**Stage 0 — groundwork, no representation change.**
1. `value_types` inference pass (`IR/Visitor/src/value_types.rs`) with a debug assertion that
   every link gets exactly one type.
2. Lifter: record the callee `FunctionType` on `Apply` (`basic_block_lifter.rs:260-277` and the
   `call_indirect` path) and the `ValueType` of imported globals (`lib.rs:109-117`).
3. H-J fast paths in `runtime/core/i64.lua` (div/rem/convert), still on tables.
4. Plumb the target into the pipeline (`target-lowering.md` §3.7). This is shared work with
   target lowering.

Gate: conformance `luanoffi` failure set and messages byte-identical (`280/32`, §11.7);
`luajit` `312/0`; all fixtures, **self-hosting first**.

**Stage 1 — legalize bodies, keep the boxed ABI (H-B in H-E mode, with H-G, H-I, H-K).**
- The legalizer runs for `lua-no-ffi` only, unconditionally (with and without `-o`), before
  `Optimizer::run` (`IR/Visitor/src/pipeline.rs:78-94`) so that ISLE sees the halves.
- `Join`/`Split` appear only at `LambdaIn`/`LambdaOut`/`Apply`, globals and host adapters.
- New ISLE rules: Split/Join folding and `i32` identity and constant rules.
- Runtime: pair helpers `rt_mul_i64p`, `rt_div_*p`, `rt_rem_*p`, `rt_shl_i64p`/`shr`/`rot`
  (variable count), `rt_clz/ctz/popcnt_i64p`, conversions. They take and return `(lo, hi)` in
  signed form.

Gates:
- The same conformance and fixture gates as stage 0.
- M4 counters: `excess_stack` sites and maximum locals per function must not regress badly.
- The inter-region copy share, since it measures the fact 7 risk.
- A debug run with the canonical-half assertion (H-I).

**Stage 2 — internal multi-return ABI (H-H).**
- `FunctionType` is rewritten, and export and import adapters are built in IR.
- There is a per-type fallback to boxed for types with more than about 98 `i64` parameters.
- The harness stays unchanged, by construction.

Gates as before, plus `linking.wast`, `imports.wast`, `exports.wast`, `call_indirect.wast` and
`func_ptrs.wast` in the conformance log.

**Stage 3 — optional: unboxed internal `i64` globals (H-F), cleanup.**
- `from_bits_i64`/`into_bits_i64` survive only in the adapters and the harness.
- The `rt_*_i64` table helpers and the `memory.lua` `i64` sections are deleted.

**Expected outcome (estimated, to be measured).**
- `i64`-heavy kernels (`i64-compare`): in the upper half of §5.1's range, because the constants,
  loop-carried values and calls all stop allocating.
- `self-hosting`: memory moves and hashbrown bit tricks dominate, which is the best case for B.
- C codecs with little `i64` (`libjpeg-turbo`, `miniz`): about neutral.

---

## 6. Cheap measurement plan

None of this needs the compiler change first.

- **M0 — static census (script over `tests/manual/*/generated/*.lua`, about 1 hour).**
  - For each function: fast locals, `i64` locals (`loc_N_ = ` whose right side is an `i64`
    producer), `excess_stack` uses, and `i64` parameters and returns.
  - A projection of the locals after splitting under B's rules: multi-use and loop-carried values
    ×2, single-use values ×0. Flag functions projected above 197.
  - Counts of `i64` constants inside `repeat` bodies, `i64` global sites, and shift and rotate
    counts that are constant versus variable.
  - This decides whether H-F is worth doing and sizes the local risk for B and H.
- **M1 — H-C1 probe.** `sed` the `i64-compare` output so every `into_bits_i64(<lit>, <lit>)`
  becomes a hoisted `K[n]`. Run an in-process A/B with the existing `incall.lua` and
  `kernels.sh` (§11 scripts). This bounds how much of the gap is due to constants alone.
- **M2 — hand-split kernels.**
  - Translate `hash_i64_mix` and `hash_i64_div` from the generated `i64_hash.lua` into signed
    pairs by hand. Use the H-G inline forms and pair helpers, first with the boxed ABI (stage 1)
    and then with multi-return (stage 2).
  - Add three microkernels to `bench_i64.lua` (§5.1): `probe` (hashbrown: `load_i64`, `xor`,
    `sub`, `and`, `ctz`, `narrow`), `copy` (a `load_i64`→`store_i64` loop over words) and
    `divsmall` (div/rem with operands below 2^32).
  - Run with the JIT on and off, and with the GC stopped for allocation totals.
  - This validates the gain of each stage before any Rust is written, and checks H-I's
    signed-half helpers for bit-exactness against the table version on random inputs,
    including `INT64_MIN`, −1, `2^32 − 1`, `2^53 ± 1` and shift counts 0, 31, 32, 33, 63 and 64.
- **M3 — correctness gates** per stage, as listed in §5. Add a dedicated differential test: a
  random `i64` op sequence compared against `wasmtime` in the style of `verification.md`,
  covering div/rem traps, `rem_s` sign, round-to-odd `u64 → f32`, and shift and rotate edges.
- **M4 — structural counters on the real output.** `excess_stack` sites, maximum locals per
  function, the number of packed-upvalue functions, the inter-region copy share, module bytes and
  load time on small fixtures (parse time dominates those, §11.5).
- **M5 — timing.** `sweep2.sh` whole-process and `incall.lua` in-process A/B on `i64-compare`,
  `self-hosting`, `gltf-rs`, `chipmunk` and `wasm3`. `miniz` and `libjpeg-turbo` serve as
  controls that should not move.

---

## 7. Side findings

- `bit32_countlz` and `bit32_countrz` are bit-by-bit while loops (`runtime/builtin/bit32.lua:5-35`).
  They sit under `rt_trailing_zeroes_i64`, which has 153 sites in self-hosting, all on hashbrown
  match masks. A table lookup on the isolated low bit (`CTZ[band(x, -x)]`, 32 keys) avoids the
  loop. Do **not** use the de Bruijn multiply: `band(x, -x) * 0x077CB531` can exceed `2^51`, and
  past that point `bit.tobit` does not reduce modulo `2^32` correctly. This is independent of
  the representation and worth an M2 kernel.
- `raw_unsigned_divide_u64` always boxes both the quotient and the remainder (`i64.lua:220`),
  even when one is discarded. Stage 0 can return pairs internally.
- `rt_narrow_i64` returns an **unsigned** `lo` as an `i32` (`i64.lua:579-585`). That contradicts
  the signed `i32` contract of §11.2 and is only harmless because `i32` consumers normalize again
  (`force_i32`/`force_u32`, `i32.lua:215-296`). H-I removes this inconsistency. Until then, any
  new `i32` fast path that assumes canonical input (§9 step 7 "lazy normalization" of the
  performance note) would be wrong on wrapped `i64` values.
- The claim that the IR is typed per value does not hold (§1.3). Only lambda signatures are
  typed. `value_types` is a prerequisite for every hypothesis except C1 and J.
