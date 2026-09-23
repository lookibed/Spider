# Giant Functions in `lua-no-ffi` — A Hypothesis Study

Status: **research only.** Nothing was built, run, or benchmarked for this note. The claims are
code readings (`file:line`), or static counts made with `awk`/`grep` over the generated Lua that
is checked into `tests/manual/*/generated/*.lua` (dated `2026-09-21 05:52`, after `aa08225`).
The awk scripts are in the appendix. Every performance number is a **prediction** that comes
with its own falsification test.

Written: `2026-09-23`.

Companion notes: [`../problem_lua_limits.md`](../problem_lua_limits.md),
[`../lua-no-ffi-upvalue-strategies.md`](../lua-no-ffi-upvalue-strategies.md) (its H8, "outline
giant functions", is the strategy this note works out),
[`target-lowering.md`](target-lowering.md), [`verification.md`](verification.md) (P3
threshold-stress, P6 limit gate, P10 `-jv` logs). A register-allocation note is referred to
below as the *register-allocation note*. It did not exist in `docs/notes/hypotheses/` when this
was written. §5 says what this note expects from it.

---

## 0. The short version

1. **Today's corpus has no function near the 200-local limit, and no hot function spills.** The
   inner function with the most locals is `cgltf` at 140. Two things use `excess_stack`: every
   `module()` body (for example wasm3 with 488 slots, used only at init) and **two** `gltf_rs`
   functions (37 and 39 slots; one of them makes 5,962 slow accesses).
2. **The nearest hard limit for giant functions is the jump range.** `binjgb` has a 9,897-line
   opcode executor, and one `if` spans 9,790 of those lines. The self-hosting builder has an
   8,809-line function with a 7,535-line `repeat`. Both still load, so both are under 32,767
   bytecodes today. The headroom is unknown, and my estimate is 1.3–1.6×. That margin can be
   lost to any change that makes code longer, such as target lowering or `-o`.
3. **Most of a giant function is copies.** In binjgb's largest function, **6,966 of 9,897 lines
   (70 %)** are bare `loc_a = loc_b;` moves: the entry moves of Gamma arguments, repeated in each
   of 256 arms. The share is 28 % in the self-hosting builder and 21 % in cgltf. So the cheapest
   size fix is coalescing Gamma arguments, and that belongs to the register-allocation work.
   Outlining is the general mechanism for what is left after that.
4. **The premise needed one correction.** wasm3 is *not* a giant-function fixture: its largest
   function has 496 lines, because wasm3 runs each opcode as a separate C function. Its large
   body is `module()`, and its risks are the trace count, mcode size, and `call_indirect`
   dispatch.
5. **Recommended order** (§4): (a) a bytecode-size estimator plus a CI gate, (b) copy coalescing
   (register-allocation note), (c) outlining at Gamma/Theta/subtree level into closures created
   *once, in the existing Scoped wrapper*, with live-in values as parameters and live-out values
   as returns, (d) a `jit.opt` parameter experiment. The state-table approach, `goto`, and the
   `excess_stack` rewrite stay as fallbacks or local optimisations.

---

## 1. What the code does, as far as function size is concerned

### 1.1 The tree is fully structured, which makes outlining well-defined

- The only statements are `Match`, `Repeat`, `Assign`, `SwapAll`, `Call` and state operations
  (`Tree/src/statement.rs:161-192`). There is **no `break`, `goto`, `return` or label**. Early
  exits from WebAssembly `br` are already encoded as RVSDG predicates: a Theta becomes
  `repeat … until`, and a Gamma becomes a `Match` (`Builder/src/code_handler.rs:45-77`,
  `Builder/src/lib.rs:108-140`).
- As a result, **every `Sequence` has one entry and one exit.** Any subtree (a Match arm, a
  Repeat body, a contiguous run of statements) can be replaced by
  `results = piece(arguments)` with no control-flow repair. This is the most important fact for
  outlining.
- A function has no early return. `returns` is printed once at the end
  (`Printer/src/expression.rs:78-166`). A trap is `error('unreachable code')`
  (`expression.rs:918`) or a helper's `error(...)`, and it unwinds through every Lua frame.

### 1.2 Locals

- Each wasm function is a `Function { arguments, locals, stack, code, returns, key }`
  (`Tree/src/expression.rs:14-27`). All `locals` are declared **at the top of the body** in a
  single `local a, b, c` (`fmt_locals`, `expression.rs:181-199`). So LuaJIT's active-local count
  for a function is `arguments + locals + stack_top?`, and it does not depend on block
  structure.
- `LocalAllocator` (`Builder/src/local_allocator/mod.rs`) walks each function's node range
  backwards and reuses names by liveness (`IndexProvider::try_revive`). The number of names is
  therefore about the *maximum number of values live at once*, plus whatever coalescing fails to
  merge. After 197 names, `LocalProvider::pull` hands out `Local::Slow { offset }`
  (`local_provider.rs:9,46-58`), which is printed as `excess_stack[stack_top - N]`
  (`expression.rs:202-209`).
- `excess_stack` is **one shared frame stack for the whole module**. Each function with a stack
  runs `local stack_top = excess_stack.top + size; excess_stack.top = stack_top` on entry and
  restores it at the end (`expression.rs:57-76`). A trap skips the restore. This is
  pre-existing, and the next call's offset keeps growing without bound.

### 1.3 How the printer lays out control flow (this sets every jump span)

| construct | printed as | longest jump |
|---|---|---|
| `Match`, 2 arms | `if c then T else F end` (`statement.rs:201-310`) | false-jump spans `T`; exit jump spans `F` |
| `Match`, ≤ 512 arms | range check + binary tree of `if (c) < k … elseif (c) > k … else … end` (`print_recursive`, `statement.rs:37-99`, `print_match` `:161-199`) | range check's false-jump spans **all arms**; each tree level's jump spans a whole half-subtree |
| `Match`, > 512 arms | `do local sel = c; …; if sel in [a,b) then <tree> end … end` (`print_grouped_match`, `:102-159`) | spans one group of ≤ 512 arms |
| `Repeat` | `repeat body until cond` (`:380-398`) | the back-edge spans `body` + `cond` |

`MAX_GROUPED_BRANCHES` only limits how many arms one structure holds. It does **not** limit their
total size. The outer range-check jump of a 256-arm match still spans all 256 arms. binjgb's
executor is exactly this shape: `if (loc_968_) >= 0 and (loc_968_) < 256 then` at
`binjgb.lua:16586` spans 9,790 lines.

### 1.4 Where helpers and dependencies come from

The wrapper is `(function(deps…) [local __spider_scoped_dependencies = {…}] return <function>
end)(sources…)` (`expression.rs:310-363`). **The wrapper runs once, when `module()` runs.** The
body captures deps, runtime helpers (`module()` locals), and `excess_stack` as upvalues. This
wrapper is also where outlined pieces should be created (H1).

---

## 2. A model of function size, and which limit breaks first

### 2.1 The LuaJIT limits that matter

Limit values come from LuaJIT 2.1 `lj_def.h` / `lj_jit.h` as I remember them. **Check them
against the pinned build** before relying on the exact numbers.

| limit | value | error | printed construct that approaches it |
|---|---|---|---|
| active locals (`LJ_MAX_LOCVAR`) | 200 | `too many local variables` | top-of-body `local` list; `module()` |
| frame slots (`LJ_MAX_SLOTS`) | 250 | `function or expression needs too many registers` | 197 locals + temporaries of the deepest call/expression; wide `end)(dep1..depN)` in `module()` |
| upvalues (`LJ_MAX_UPVAL`) | 60 | `function at line N has more than 60 upvalues` | solved by packing (`captures.rs`, `CAPTURE_BUDGET = 57`) |
| jump offset | ±32,767 BC (16-bit D, bias `0x8000`) | `control structure too long` | range-check of a big match; loop back-edge; `then` exit over a large `else` |
| constants per proto (16-bit D for `KSTR`/`KNUM`/`FNEW`) | ~65,536 | `too many constants` | only `module()` (children protos + strings); corpus is far below |
| syntax nesting (`LJ_MAX_XLEVEL`) | 200 | `chunk has too many syntax levels` | max indentation in the corpus is 55 (cgltf), so not near |
| JIT: `maxrecord` 4000, `maxside` 100, `maxsnap` 500, `maxtrace` 1000, `maxmcode` 512 KB | soft | trace aborts, blacklisting, trace flushes | giant dispatchers (side exits per arm), modules with 1,500 protos |
| JIT: NYI bytecodes | soft | trace abort or stitch | `FNEW` (closure creation), `math.frexp` (`into_bits_f64`, `builtin/buffer.lua:773`), `pairs` (init only) |

### 2.2 What makes a printed function large

Approximate bytecode costs per construct. These are my estimates, to be calibrated by M0 (§3,
H4).

- **Region entry moves.** `do_bulk_assignment` (`code_handler.rs:106-138`) emits one `MOV` per
  Gamma/Theta argument that did not coalesce with its producer. **Every Gamma arm repeats all of
  them.** A 256-arm match with 27 uncoalesced arguments therefore costs ~6,900 `MOV`s before any
  arm does real work.
- **Helper calls.** `rt_x(a, b)` costs `UGET`/`MOV` for the function, one `MOV` per argument that
  is not already in place, and a `CALL`: 3–5 BC. Inlined `bit32_or(a + b, 0)` costs about the
  same.
- **Memory access.** `rt_load_*`/`rt_store_*` calls (3–6 BC). After target lowering (H6/H7 of
  that note) they become inline `__w[...]` expressions. These are longer in BC but have no call.
- **Dispatch scaffolding.** `log2(k)` compares per arm path, a few BC per tree node, and the
  range check repeated at the top.
- **Spill traffic.** Each slow read is `TGETV excess_stack, (stack_top - N)` (2 BC, or 1 BC plus
  a temporary). Each slow write is `TSETV` plus a subtraction.

### 2.3 Measured static shape of the corpus

From the appendix awk over `tests/manual/*/generated/*.lua` (lua-no-ffi outputs only):

| fixture | Lua lines | largest fn (lines) | max locals (any fn) | biggest single block | copy lines in largest fn | `excess_stack` hot use |
|---|---:|---:|---:|---|---:|---|
| real-world-binjgb | 34,926 | **9,897** (256-arm opcode executor, `binjgb.lua:16579`) | 50 | `if` 9,790 lines | **6,966 (70 %)** | none (module init only) |
| self-hosting-luanoffi-builder | 49,794 | **8,809** | 87 | `repeat` 7,535 lines | 2,490 (28 %) | none (module: 60 slots) |
| real-world-cgltf | 22,884 | 7,495 | **140** | — | 1,608 (21 %) | none |
| real-world-gltf-rs | 187,106 | 5,120 | 119 fast + **37–39 slow** | — | — | **5,962 slow accesses in one fn** (`gltf_rs.lua:42839`) |
| real-world-miniz(-file/-full), real-archive-secret | 11–25 K | 4,619 | 61 | — | — | none |
| real-world-h264bsd-mp4 | 50,632 | 4,039 | 76 | `if` 4,018 / `repeat` 3,834 | 1,336 (33 %) | none |
| real-world-libjpeg-turbo(-mjpeg) | ~73 K | 3,162 | 101 | — | — | module only |
| real-world-lodepng | 33,613 | 2,324 | 79 | — | — | module only |
| real-world-plmpeg | 21,451 | 1,568 | 64 | — | — | module only |
| real-world-wasm3 | 30,729 | **496** | 35 | — | — | module only (488 slots) |
| chipmunk family | ~14 K | 344 | 39 | — | — | module only |

A consistency check on the jump range: binjgb loads, so the 9,790-line `if` is under 32,767 BC,
which means fewer than 3.35 BC per line in that span. With 70 % of the lines being 1-BC `MOV`s,
my estimate is 20–25 K BC, or **1.3–1.6× headroom**. M0 settles this.

### 2.4 Classes of giant functions and the limit each hits first

| class | fixtures | first limit | second | why |
|---|---|---|---|---|
| **A. Opcode dispatcher** (large `br_table` over a small per-arm body) | binjgb executor | **jump range** (range-check jump spans every arm) | JIT `maxside` (one side exit per hot opcode, up to 100 per root trace) | size grows as arms × (uncoalesced args + body); locals are low (≤ 50) |
| **B. Big loop over a state machine** (compiler passes, parsers) | self-hosting builder, cgltf, secret_reader/miniz `tinfl` | **jump range** (loop back-edge) | locals (cgltf is at 140/197) | one `repeat` holds almost the whole function |
| **C. Spill-heavy straight-line code** (Rust serde, monomorphised generics) | gltf_rs | **200 locals (already spilling)**, then 250 frame slots | `excess_stack` cost | many values live at once |
| **D. Decoder kernels** | h264bsd, libjpeg, lodepng, plmpeg | **JIT** (trace length, side exits, `maxrecord`) | none nearby | 2–4 K lines, well under every hard limit |
| **E. Many small functions** | wasm3, chipmunk | **`module()`** (locals already handled, frame slots for wide wrapper calls) and **JIT trace/mcode count** | `call_indirect` cost | no giant wasm function |

---

## 3. Hypotheses

Each hypothesis is written so a single experiment can falsify it. **H0** is listed because it is
the biggest lever, but it belongs to the register-allocation note.

### H0 — Coalescing Gamma-argument entry moves removes most of a giant function's size (owned by register allocation)

- **Mechanism.** `handle_region_in` (`Builder/src/lib.rs:108-116`) makes every Gamma arm open
  with a `do_bulk_assignment` from the Gamma's inputs to the region's argument locals. When the
  allocator's `try_revive_into` (`local_provider.rs:66-86`) gives a region argument the same local
  as its source, the move disappears (`code_handler.rs:84-86`, and `AssignmentSimplifier`). In
  binjgb it does not, 256 times over.
- **Limit addressed.** Jump range (classes A and B), bytecode size, and parse time.
- **Prediction.** binjgb's executor loses ≥ 60 % of its lines. The jump-range headroom grows to
  about 3×. The runtime gain is small in the JIT (moves are free in SSA) and noticeable in the
  interpreter (each dispatch saves 27 `MOV`s).
- **Risk.** Coalescing lengthens live ranges and can *raise* max-live, which means more spills.
  upstream-review.md:21 already records `-o` producing +47 % spills. The region-scope validator
  in `IR/Visitor/src/control/region_scope.rs` (in the working tree) guards the "boundary port
  shares the producer's local" invariant that this relies on.
- **Measurement.** Take the appendix copy count per function, before and after, and M0's BC count
  for `binjgb.lua:16579`.

### H1 — Outline Theta bodies or Gamma arms above a size threshold into closures that the Scoped wrapper creates once

- **Mechanism.** Add a tree-level pass after `LuaNoFFIBuilder::run`. For each `Function`, walk
  `code` bottom-up with a size estimate (H4). When a `Repeat` (the **whole** loop, not its body)
  or a `Match` arm goes over `T_outline` BC, replace it with
  `Statement::Call { function: Local(piece), arguments: live_in, results: live_out }`. Move the
  subtree into a new `Function { arguments: live_in, locals: renamed, stack: 0, code, returns:
  live_out, key: None }`.
  - **live_in** = every name the piece *reads or writes*. Writes are included so that paths which
    do not write a name still return its incoming value. **live_out** = the names the piece
    writes. A later refinement intersects this with liveness after the piece. The conservative
    rule needs no liveness analysis and is always correct.
  - **Where the piece lives.** Give `Scoped` a `pieces: Vec<(Name, Function)>`. The printer then
    emits `local piece_k = function(…) … end` **inside the wrapper, before `return`**. The wrapper
    runs once per module instantiation, so the pieces are created once (no `FNEW` in hot code),
    they see the same deps as upvalues, and `module()` gets no new locals. A body without deps
    still gets a wrapper when it has pieces.
- **Limits addressed.** Jump range (always), 200 locals (each piece has its own budget of 197),
  and frame slots. It does *not* address upvalues: each piece costs the body one upvalue and has
  its own capture budget. `packed_scoped_dependencies` (`expression.rs:261-286`) must run per
  piece and count the pieces it calls.
- **Performance.**
  - Interpreter: one `CALL` + `RET` + |live_in| + |live_out| moves per piece execution.
  - JIT: calls to a constant upvalue closure are recorded inline, so the argument and return
    moves disappear in SSA. The cost is roughly one closure-identity guard.
  - Outlining a whole Theta means one call per loop *entry*, and the loop becomes a root trace
    inside the piece, which is better than a call per iteration.
  - Outlining an opcode arm costs one call per dispatch. In the interpreter I predict < 5 % on
    binjgb's executor; in the JIT, noise.
- **Correctness risks.**
  - *Trap ordering:* preserved. The piece runs the same statements in the same order, and
    `error` unwinds through it.
  - *`excess_stack`:* a piece must **not** enter or leave the stack. It takes the parent's
    `stack_top` as an extra parameter whenever it touches `Local::Slow`, and `excess_stack` is
    already a `module()` upvalue.
  - *Recursion and reentrancy:* pieces are pure functions of their parameters and the
    module-level deps, so recursive wasm calls inside them are safe.
  - *Slow locals as results:* `a, excess_stack[stack_top-3] = piece(...)` is valid Lua.
    Check the printed order of evaluation.
  - *Printer exact-name rewriting:* `print_function_body` rebinds packed deps via
    `set_exact_name` (`expression.rs:93-127`). Pieces must print inside that same scope, or
    perform the rebinding themselves.
  - *Name ids:* fresh `Name`s must not collide with the allocator's id space. Take
    `max_id + 1…` from a tree walk.
- **Implementation sketch.**
  - New `Targets/LuaNoFFI/Builder/src/outliner.rs`, called at the end of `LuaNoFFIBuilder::run`
    (`lib.rs:631-641`). A small mutable walk over `Sequence`, since `Tree/src/visitor.rs` is
    immutable only.
  - `Tree/src/expression.rs`: add the `Scoped::pieces` field and a `Function::is_piece` flag,
    so that `rt_function_type` is not emitted.
  - `Printer/src/expression.rs` `impl Print for Scoped`: print the pieces.
  - `Printer/src/captures.rs`: count the pieces.
- **Measurement.** M0 on binjgb and the self-hosting builder with `T_outline` at ∞, 24 K and 8 K.
  Run the binjgb 16-frame probe (`lua-no-ffi-measurements.md:71`) under `-joff` and with the
  JIT. The self-hosting fixture must stay green (pinned-memory rule).

### H2 — Choose outlining regions by jump-range budget, using the binary dispatch tree

- **Mechanism.** H1 with a *budget* instead of a threshold. Compute each jump's span exactly as
  the printer lays it out (§1.3). While some span exceeds `B = 24 K` BC (a 25 % margin), outline
  the **largest child that reduces that span**.
  - For a Match this is a *subtree* of `print_recursive`. For example, outline arms
    `[start, center)` as a single piece that contains its own dispatch, so there is one call per
    dispatch whatever the arm count.
  - For a Repeat it is the largest top-level statement of the body, or a contiguous run of body
    statements.
  - Ties go to the lowest estimated execution frequency: prefer arms over loop bodies, and
    trap-only arms first.
- **Limit addressed.** Jump range only, with the least outlining. Most functions are untouched.
- **Performance.** At most one or two extra calls on each hot path. Size-based outlining (H1)
  would split every big arm.
- **Risks.** As H1, plus: the printer's layout decisions (grouping at 512 and the binary split)
  become an input to the outliner, so they must live in a shared module and not be duplicated.
- **Sketch.** `Printer/src/statement.rs` `conditional` exposes a `layout(branches) -> tree of
  spans`. `outliner.rs` consumes it through a size callback, or the outliner moves into the
  printer crate as a pre-print pass over the tree.
- **Measurement.** Use the synthetic generator from verification.md P3. A wasm function with a
  `br_table` of N arms of S instructions each gives the exact failing N×S today, and shows that
  the budget pass keeps it loading up to 10× beyond that. Count outlined pieces per fixture: it
  should be 0 for everything except binjgb and the self-hosting builder.

### H3 — A state table for pathological functions (fallback)

- **Mechanism.** When the estimated live-in of a piece exceeds ~150, or when the outliner cannot
  find a split, switch the whole function to a register-file table. Every local becomes `R[i]`
  in a per-call `R = table.new(n, 0)` (constant index: `TGETB`/`TSETB` for i ≤ 255, `TGETV` above
  that). The body is cut into pieces `P[k] = function(R) … return next_k end` and driven by
  `local k = 1 repeat k = P[k](R) until k == 0`. Pieces take no parameters and return nothing
  else, so liveness is never needed.
- **Limits addressed.** All of them, for any size: locals, slots, jumps, and the upvalues of the
  pieces, which only need `R`, deps and helpers.
- **Performance.** Interpreter: every local access becomes a table access, so I predict 1.5–3×
  slower on that function. JIT: LuaJIT forwards stores and loads to constant keys on a
  non-escaping table within a trace (FWD/DSE), and inlines the pieces, so the prediction is
  1.1–1.5×. Add one `table.new` per call, which is an allocation. This option is not acceptable
  for binjgb's per-instruction executor, and acceptable for once-per-frame or once-per-file
  functions.
- **Risks.** It is simple to get right, since there is no liveness and `R` belongs to one
  activation, which makes it reentrant. `table.new` needs `require("table.new")` with a fallback.
- **Sketch.** A second mode in `outliner.rs`. The printer maps `Local::Fast{name}` to `R[idx]` via
  `set_exact_name`, the same trick `module_locals` uses (`statement.rs:770-783`).
- **Measurement.** Force the mode on in `hash-compare` and `chipmunk-profile` (small and hot), and
  compare the interpreter and JIT against normal output. That gives an upper bound on the cost.

### H4 — A bytecode-size estimator in the printer, plus a gate

- **Mechanism.** Add `fn estimate(&Statement) -> u32` and `fn estimate(&Expression) -> u32` with
  per-kind costs (§2.2), as an upper bound. Calibrate it against real counts from M0 (a least-
  squares fit per node kind over the corpus, then take the 95th percentile ratio as the safety
  factor). Use it (a) to drive H1/H2, and (b) to fail compilation with a precise message ("span
  of match at wasm func N is ~41 K BC, limit 32 K") instead of letting LuaJIT fail at load.
- **Limit addressed.** None directly. It is the prerequisite that makes every other decision
  measurable and makes regressions visible before load time.
- **Performance.** None at runtime.
- **Risk.** Underestimation: a silent miss means a load-time failure, which is the status quo. Keep
  the model conservative and re-fit it after every target-lowering stage, because lowering changes
  BC per node.
- **Sketch.** `Printer/src/size.rs`, implemented as a `Visitor` like `captures.rs`. An optional
  `--emit-size-report` in the CLI.
- **Measurement.**
  - **M0**, a Lua script (`tools/proto_stats.lua`, to be written). It loads a generated module
    with `loadfile` and walks all prototypes via `jit.util.funck(fn, -i)`. For each one it
    records `jit.util.funcinfo(p).bytecodes`, `.upvalues`, `.stackslots`, `.params`, and the
    longest jump, found by decoding `jit.util.funcbc` and taking the maximum |D − 0x8000| over
    `JMP`/`LOOP`/`ISNEXT` etc.
  - It needs no compiler change and runs in seconds per fixture. This gives the true headroom
    for §2.3 and the calibration data for the estimator.

### H5 — Replace `excess_stack[stack_top - N]` with constant indices

- **Variants.**
  - (a) **Per-activation frame table**: `local F = table.new(size, 0)` at entry, with
    `F[N]` constant indices, instead of the shared stack. This costs one allocation per call.
  - (b) **Shared stack, constant-base rebinding**: keep `excess_stack`, but make the base 0 by
    swapping in a fresh table per depth level from a pool indexed by recursion depth (upstream's
    size-class pools, upstream-review.md:64, cost `stack_acquire`/`release` per call).
  - (c) Keep the scheme as it is, but hoist `stack_top` into the index expression's constant
    folding. LuaJIT's JIT already narrows `stack_top - N` to integer arithmetic, so this is
    interpreter-only.
- **Limit addressed.** None. It only makes spilled code faster.
- **Evidence that decides priority.** The static scan found hot-code slow accesses in **exactly
  two gltf_rs functions**. Every other use is in `module()`, which runs once, at init. **H5 is
  low priority** unless H0 (coalescing) or H1 raise max-live elsewhere.
- **Performance prediction.** On the gltf_rs function: interpreter −10–20 % of that function's
  time for (a); JIT ≈ 0 for (c) and slightly negative for (a) because of the allocation. Whole
  fixture: noise.
- **Risks.** (a) and (b) change the trap-unwind story. Today a trap leaks `excess_stack.top`; (a)
  leaks nothing, so it is actually safer. Recursion is fine for (a).
- **Sketch.** `Printer/src/expression.rs:57-76,202-209` only.
- **Measurement.** Before touching code, count slow accesses *executed* per fixture: a
  `debug.sethook` line counter over lines that contain `excess_stack[`, in the `-joff`
  interpreter. If gltf_rs is not in a benchmark, stop here.

### H6 — Use `goto` for relay jumps and direct loop exits

- **Mechanism.**
  - (a) *Relays*: turn `repeat body until c` into `::top:: body; if not c then goto top end`, and
    insert relay islands `goto skip_k ::relay_k:: goto relay_{k-1} ::skip_k::` between top-level
    body statements every ~24 K BC, so that no single jump goes over the limit.
  - (b) *Direct exits*: print `goto`/`break` for the RVSDG exit predicates, where a Theta is
    followed by a Gamma on the same predicate, which removes predicate materialisation.
- **Limit addressed.** (a) addresses the jump range, **but only for back-edges and only between
  top-level statements**. Lua labels are not visible from outside the block that contains them,
  so a forward jump over one giant arm cannot be relayed, and one top-level statement larger than
  32 K cannot be split. (b) addresses no limit; it is a size and speed optimisation.
- **Performance.** (a) adds one unconditional `JMP` per relay on the hot path, which is
  negligible. **Risk to verify:** LuaJIT may not treat a backward `goto` as a loop (no `LOOP`
  bytecode, so no hot-loop counting). The loop would then be traced only through side exits or
  not at all. Check with `luajit -bl` on a 5-line sample.
- **Correctness risks.** `goto` into the scope of a `local` is a parse error. Every body local is
  declared at the function top (§1.2), so this is safe here. The exception is
  `__spider_match_selector` (`statement.rs:112-117`), which lives in its own `do` block and is
  fine.
- **Verdict.** Dominated by H2 for the jump range. Keep (b) as a separate optimisation idea for
  the register-allocation or target-lowering track.
- **Measurement.** Take the `-bl` listing of `repeat … until` against `::l:: … goto l`, and check
  the `-jv` trace start in each.

### H7 — Live-range reduction and rematerialisation to cut locals, plus a frame-slot guard

- **Mechanism.**
  - (a) Rematerialise constants and cheap pure expressions (`into_bits_i64(0,0)`, small `I32`,
    `GlobalGet` of immutable globals) at their uses, instead of holding them in a local across a
    region.
  - (b) Sink single-region values into the region that uses them.
  - (c) Guard: at print time, compute `locals + max temporaries of any statement + 2` and fail
    early if it exceeds 250. For the wrapper call in `module()`: helpers + fixed + 1 + |deps|.
- **Limit addressed.** 200 locals (class C) and 250 frame slots (class C and `module()`).
- **Evidence.** Only gltf_rs has an inner function above 197, and cgltf (140) is the only other
  one above 120. The benefit is therefore concentrated in gltf_rs, and the risk is concentrated
  wherever (a) introduces recomputation inside loops.
- **Performance.** (a) saves one `MOV` and one slot, but costs re-evaluation. For
  `into_bits_i64(0,0)` it creates a table *per evaluation* unless i64 constants are interned,
  so **constants of representation type i64 must not be rematerialised naively.**
- **Risks.** Rematerialising anything with state ports (loads) is wrong. Only nodes with no state
  input qualify, which the `ScalarFinder` already classifies (`scalar_finder.rs:159-176`).
- **Sketch.** This mostly belongs to the register-allocation note: (a) and (b) are allocator
  policies. (c) is a printer assertion that sits next to `use_table_backed_module_locals`
  (`statement.rs:330-340`).
- **Measurement.** Compare `stackslots` from M0 against 250 per proto (the report shows the
  headroom). Count gltf_rs slow slots before and after.

### H8 — JIT-friendliness of giant code and giant modules

- **Sub-hypotheses.**
  - **H8a — `jit.opt` parameters.** Modules with 400–1,500 prototypes may exhaust
    `maxtrace = 1000` or `maxmcode`, which triggers a flush of *all* traces, and dispatchers may
    exhaust `maxside = 100`. Test with command-line flags first:
    `-Omaxtrace=8000 -Omaxmcode=16384 -Omaxside=400 -Omaxsnap=2000 -Omaxrecord=16000`. Only if
    it wins, emit `if jit and jit.opt then jit.opt.start(...) end` from the runtime prelude. That
    is a host-policy decision, so it must be opt-in behind a CLI flag.
  - **H8b — no `FNEW` in hot code.** A hard rule for H1/H3: pieces are created in the wrapper
    (§1.4). `FNEW` aborts traces.
  - **H8c — `math.frexp`** sits on the `into_bits_f64` path (`builtin/buffer.lua:773`), which is
    reached by f64 stores and reinterprets. It is NYI and causes a trace stitch or abort. Replace
    it with the Veltkamp/exponent-scan technique already used for f32 in the same file
    (`buffer.lua:575,647`). This is relevant to chipmunk-class physics code, and it overlaps the
    target-lowering f32/f64 stage.
  - **H8d — other NYI.** `pairs` appears only in `table_new`/`memory_new` initialisers (cold).
    The runtime has no varargs and no `string.format`. `error` appears on trap paths only (cold).
    **Unverified:** whether `math.modf` compiles on the pinned LuaJIT. It is on the hot
    truncation path (`core/i32.lua:86`, `core/f32.lua:59,72`, `core/f64.lua:37,46`).
  - **H8e — smaller hot closures.** Outlining (H1) does not by itself help the JIT, because
    traces inline across calls. It helps only when a piece's loop becomes a separate root trace
    instead of an "inner loop in root trace" abort. That is a measurable prediction, not an
    assumption.
- **Limit addressed.** JIT give-up (classes A, D, E).
- **Measurement.** Use `-jv` abort logs per fixture (verification.md P10); count "trace too long",
  "too many side traces", "NYI: FNEW/bytecode", "flush". Then run the binjgb, h264bsd, and wasm3
  benchmarks with the H8a flags, with no compiler change needed.

### H9 — Tail calls between consecutive outlined pieces

- **Mechanism.** When H1/H2 splits a *straight-line tail* of a function body into pieces
  A → B → C, print `return B(live_out_A)` at the end of A, and so on. The last piece returns the
  function's `returns` directly. The parent does `return A(...)`. That gives one set of moves per
  boundary instead of return + reassign + call.
- **Limit addressed.** Jump range and locals, the same as H1. The gain is in boundary copies and
  frame depth.
- **Performance.** Interpreter: saves one `RET` + multi-assign per boundary. JIT: LuaJIT records
  tail calls, so the gain is ≈ 0.
- **Risks.**
  - Only applicable at the function *tail*. A body with a stack must do
    `excess_stack.top = stack_top - size` before the tail call, which means the last piece takes
    over `fmt_stack_leave`. That requires passing `size` or `stack_top`.
  - A trap inside B loses A's frame from `debug.traceback`, but it changes no wasm semantics.
- **Sketch.** Add a `TailCall` statement variant, or a `returns = [Call]` pattern that the
  printer detects in `print_function_body` (`expression.rs:78-166`).
- **Measurement.** Only worth measuring if H2 ever splits a straight-line tail. Count that first.

### H10 — Table dispatch of arm pieces for very wide matches

- **Mechanism.** For a `Match` with ≥ 64 arms that H2 decides to outline, replace the
  `log2(k)`-deep comparison tree with `local f = ARMS[sel] or default; results = f(live_in)`.
  `ARMS` is created once in the wrapper.
- **Limit addressed.** Jump range (the dispatch becomes O(1) BC) and scaffolding size.
- **Performance.** Interpreter: 1 `TGETV` + `CALL` instead of 8 compares, which should be
  faster. JIT: the trace guards the loaded closure's identity. Each distinct hot opcode is still
  a side exit, the same as today's compare tree, so there is **no change to the `maxside`
  problem**. Every arm must share one live_in/live_out signature (the union of all arms), which
  costs moves on arms that use few values.
- **Risks.** The union signature can exceed parameter limits on wide functions, in which case it
  falls back to H3. Out-of-range `sel` must hit the default arm with the same semantics as the
  range check today.
- **Measurement.** Run the binjgb executor both ways on the 16-frame probe, under `-joff` and
  with the JIT.

---

## 4. Staged plan

Every stage keeps the output byte-identical on fixtures below its threshold, which is how the
upvalue work kept "99.8 % of printed functions" untouched (`lua-no-ffi-upvalue-strategies.md`).

| stage | what | exit criterion |
|---|---|---|
| **S0 (measure)** | M0 `tools/proto_stats.lua` (BC, jump span, slots, upvalues per proto); `-jv` abort census (H8); H8a flag A/B; executed-slow-access count (H5) | a table of real headroom per fixture; a decision on H5 (likely drop) and H8a |
| **S1 (gate)** | H4 estimator calibrated on S0; CI limit gate (verification.md P6) with warnings at 75 % of any hard limit | the estimator's upper bound ≥ the M0 count on 100 % of protos |
| **S2 (shrink)** | H0 coalescing through the register-allocation note; re-run S0 | binjgb executor copy lines −60 %; spills not up on any fixture |
| **S3 (split)** | H1 mechanism + H2 budget policy, pieces created in the Scoped wrapper; H7c frame-slot assertion | synthetic P3 generator loads at 10× today's failing size; outputs unchanged except pieces in functions over budget; self-hosting fixture green |
| **S4 (fallback)** | H3 state table only for functions S3 cannot split | never triggers on the corpus; a synthetic test forces it |
| **S5 (optional)** | H10 for ≥ 64-arm dispatch, H9 tail chaining, H8c `frexp` removal, H5 only if S0 justifies | each passes an A/B with ≥ 5 runs, as in the performance-hypotheses method |

### Interaction with the sibling tracks

- **Register allocation.** H0 is the largest size lever and belongs there. Coalescing raises
  max-live, and outlining gives every piece a fresh 197-local budget. So **S3 is the release
  valve that lets S2 coalesce aggressively**, and the two should be tuned together. Outlining as
  a *tree* pass after allocation keeps the allocator untouched, but pieces inherit sparse name
  ids and need renaming. Outlining at IR level (extracting a region into a new Lambda before
  allocation) would let the allocator see real function boundaries. It is more invasive, touches
  the invariants that `region_scope.rs` validates, and should be postponed until the tree-level
  version has been measured.
- **Target lowering.** Lowering removes helper names, which lowers the capture demand of pieces
  (target-lowering §5.1), and that helps H1. However, it **changes BC per node**: inline
  `__w[...]` loads are longer than `rt_load_i32(...)` calls. Its stage 6, hoisting `__w`/`__n`
  per loop, **spends locals**. Both erode the jump and local headroom of class A and B functions,
  so **S1 (the estimator gate) must land before target-lowering stage 4**, and the estimator
  must be re-fitted after each lowering stage. When a Theta is outlined, the hoisted `__w`/`__n`
  should be hoisted *inside* the piece, where the loop lives, rather than passed as parameters.
- **Verification.** P3 (threshold-stress generators) supplies the synthetic giant functions for
  S3. P6 is the S1 gate. P10 supplies the S0 abort census. P2 (`-o` against plain) must be run
  with and without outlining, because outlining changes what `-o` can reach only if it moves to
  IR level.

---

## 5. Open questions (cannot be settled from the code)

1. Is the true BC/line ratio of the binjgb executor about 2.2, or closer to 3.3? M0 answers this.
   If it is closer to 3.3, the executor is at the edge **today**, and S1 is urgent.
2. Why do the 256 arms' Gamma arguments not coalesce? `try_revive_into` should succeed when a
   source's last use is the Gamma itself. Candidates: (i) the source is still live after the
   Gamma, (ii) a Gamma output reuses the name, (iii) `find_first_producer` see-through
   (target-lowering §3.5). This is the first question for the register-allocation note.
3. Does the pinned LuaJIT compile `math.modf` and a backward `goto` as a loop? Check with a
   5-line `-jv`/`-bl` sample each.
4. Should `jit.opt.start` ever be emitted by the compiler, or remain a host responsibility? This
   is a policy question for the user.

---

## Appendix: the static scans

The largest function per file, with loops, `if`s, locals (first `local loc_` line) and slow
accesses:

```awk
function depth(s){ match(s,/^\t*/); return RLENGTH }
/\(function\(/ { d=depth($0); sp++; st[sp]=NR; sd[sp]=d; ex[sp]=0; rp[sp]=0; mt[sp]=0; lc[sp]=0; next }
{ if (sp>0) { if ($0 ~ /excess_stack\[stack_top/) ex[sp]+= gsub(/excess_stack\[stack_top/,"&");
  if ($0 ~ /^\t*repeat$/) rp[sp]++; if ($0 ~ /^\t*if /) mt[sp]++;
  if (lc[sp]==0 && $0 ~ /^\t*local loc_/) lc[sp]=gsub(/,/,",")+1 } }
/^\t*end\)/ { d=depth($0); if (sp>0 && sd[sp]==d) { printf "%d %d ex=%d rep=%d if=%d locals=%d\n",
  NR-st[sp], st[sp], ex[sp], rp[sp], mt[sp], lc[sp]; sp-- } }
```

Run it as `awk -f spans.awk X.lua | sort -rn | head`. The largest block inside a line range
`S..E` pairs `if … then`/`repeat`/`do` with `end`/`until` at equal indentation. The copy count is
`sed -n 'S,Ep' X.lua | grep -cE '^\s*loc_[0-9]+_ = loc_[0-9]+_;$'`. Line counts are a proxy for
bytecodes. M0 replaces them with the real numbers.
