# Verification Hypotheses

How to make Spider's verification catch the bugs Spider actually has.

Written: `2026-09-21`. This note is **research only**: nothing was built, run or measured for it.
Every claim below is either a code reading (file and line given) or an explicitly labelled
hypothesis with a falsifiable prediction, so that a later session can check it cheaply.

The sibling note [lua-no-ffi-performance-hypotheses.md](../lua-no-ffi-performance-hypotheses.md)
does the same for speed; this one does it for correctness.

---

## 0. What verification exists today

Read out of the tree, not out of memory:

| Tier | Where | What it proves |
| --- | --- | --- |
| Spec suite | `Conformance/tests/{luau,luajit,luanoffi}.rs`, `Conformance/Suite/*.wast` | 78 non-SIMD `.wast` files compiled to Lua and run under `luajit`; `lua-jit` 312/312, `lua-no-ffi` 280/312 (only NaN-bit failures) |
| Harness | `Conformance/tests/harness/{luajit,luanoffi}.{start,end}.lua`, `luau.{start,end}.luau` | the `hn_*` oracles the generated test file calls |
| Drivers | `Conformance/tests/common/{compiler,process,visitor}.rs` | lift → optional optimizer → build → print; subprocess launch with a timeout |
| Fixtures | `tests/manual/*` (23 directories) | real C/Rust programs, expectations recorded as hashes in each `README.md`, compared by hand against `wasmtime` |
| Host runner | `Tools/WasmtimeHostRunner/src/main.rs` | `wasmtime` **as a library** (`Engine`/`Module`/`Instance`/`TypedFunc`/`Memory`), five hard-coded fixture protocols |
| Unit tests | `IR/Graph/src/link.rs`, `IR/Visitor/src/isle/mod.rs`, `IR/Visitor/src/control/{dead_port_eliminator,region_scope}.rs`, `Sources/WebAssembly/Builder/src/lib.rs`, `Targets/LuaNoFFI/Printer/src/library/{printer,sections}.rs` | 13 `#[test]` functions in the whole workspace |
| CI | `.github/workflows/conformance.yaml` | fmt, clippy, build, unit tests on 3 platforms; conformance on Linux and macOS only |

Four structural facts about that setup matter for everything below.

**(a) The suite's four variants are two dimensions collapsed into one bool.**
`run_and_assert(path, optimized, native)` in `Conformance/tests/luajit.rs:581` passes the *same*
`optimized` flag to `Compiler::run(data, self.optimized)` (the Spider IR optimizer, i.e. `-o`) and
to `luajit -O3`/`-O0` (the LuaJIT trace optimizer). So the four cells are
`(IR O0, -joff)`, `(IR O3, -joff)`, `(IR O0, -jon -O0)`, `(IR O3, -jon -O3)`.
There is no cell with the IR optimizer off and the JIT fully on, and none with the IR optimizer on
and the JIT off but `-O3`. The two dimensions are independent and should be a 2×2, not a diagonal.

**(b) Almost nothing in the spec suite ever reaches machine code.**
LuaJIT's default `hotloop` is 56 and `hotcall` is 56. A `.wast` assertion invokes an export **once**.
Loops inside the module bodies are mostly short. So even the `native_o3` variant executes the
overwhelming majority of generated code in the interpreter. That is a complete explanation of why
"LuaJIT miscompiles `u64`→float when traces get hot" and the flaky `f32` machine-code result were
invisible to 312 passing tests and only showed up on fixtures: **the suite does not exercise the
backend that broke.**

**(c) The oracle is never itself tested.**
`visit_assert_malformed`, `visit_assert_invalid`, `visit_assert_exhaustion`,
`visit_assert_unlinkable`, `visit_assert_exception`, `visit_assert_suspension`, `visit_thread` and
`visit_wait` all return `Ok(())` without emitting anything (`luajit.rs:414-534`). A checker that
silently does nothing is indistinguishable from a checker that passes. The NaN no-op lived for
months for exactly this reason, and the class is still open for every stub above.

**(d) The three test binaries are three copies of the same 600 lines.**
`luajit.rs`, `luanoffi.rs` and `luau.rs` duplicate the whole `wast` visitor, argument formatting
and assertion formatting. A fix applied to one copy does not reach the other two — which is how a
checker can be a no-op in one target and correct in another.

---

## 1. Taxonomy of the bug classes seen

Seven classes. For each: the mechanism, why today's tiers are blind to it, and the cheapest
instrument that would have caught it.

### A. Printer-shape bugs gated by a size threshold

*Seen:* the printer bug that only fires on functions with **≥ 48 captured dependencies**
(found via the self-hosting fixture). Neighbours in the same class, from
[lua-no-ffi-known-bugs.md](../lua-no-ffi-known-bugs.md): the module-local spill heuristic that
undercounted against LuaJIT's 200-local limit, and the `local a, b = 0, 0` initializer.

*Mechanism.* The printer changes **shape** past a constant:
`CAPTURE_BUDGET = LUA_MAX_UPVALUES (60) - RESERVED_UPVALUES (3) = 57`
(`Targets/LuaNoFFI/Printer/src/expression.rs:18-30`), `LUA_MAX_LOCALS = 200`
(`Targets/LuaNoFFI/Printer/src/statement.rs:335`), `MAX_LOCAL_VARIABLES = 197`
(three identical copies at `Targets/{Luau,LuaJIT,LuaNoFFI}/Builder/src/local_allocator/local_provider.rs:9`).
The rewritten shape (packing into `__spider_scoped_dependencies`, table-backed module locals,
`excess_stack` spilling) is a *different program* that no small test ever instantiates.

*Why blind.* The largest module in `Conformance/Suite` is nowhere near 48 live cross-region values
or 197 locals in one function. The threshold path is dead code for the entire spec suite.

*Would have caught it.* (P3) threshold-stress generators that sweep N through
{45…60}, {195…200}, {255, 256}; (P6) a `luajit -bc` compile gate plus a max-upvalue/max-local
metric on every generated file, which is a **static** check and needs no execution at all;
(P5) exact-text goldens for the packed-capture shape.

### B. Backend move sequencing

*Seen:* the region parallel-move miscompile exposed on `miniz` only at `-o` through an ISLE
reassociation rule.

*Mechanism.* `Targets/*/Builder/src/code_handler.rs::do_bulk_assignment` takes the region's
boundary mapping from `DataHandler::load_assign_all` (`data_handler.rs:85`) — a `Vec<(Local, Local)>`
of destination←source pairs that must all take effect **simultaneously** — and sequentialises it in
`assignment_simplifier.rs`: `find_all_assigns` repeatedly emits any pair whose destination is not
still needed as a source, then `find_all_swaps` walks the remaining graph as cycles and emits
`SwapAll`. Every classic parallel-move hazard lives here: a destination clobbering a value another
pair still needs, fan-out (one source read by several destinations) tangled with a cycle, self-moves,
and `find_first_swap`'s unconditional `.unwrap()` (`assignment_simplifier.rs:46`) which assumes the
remaining graph is a disjoint union of pure cycles.

*Why blind.* This function is pure, total and deterministic — and has **zero tests**. It is only
reached with interesting inputs when a region boundary carries many values whose allocator
preferences conflict, which needs a large function; and the optimizer is what makes preferences
conflict, so `-o` is a precondition.

*Would have caught it.* (P4) a property test on `AssignmentSimplifier` alone — a model of
`HashMap<Local, symbol>`, apply the emitted sequence, assert every destination ends up holding its
source's *original* symbol. ~150 lines, no new dependency, runs in milliseconds, and covers the
entire class including the cases that the ISLE rule merely happened to expose.

### C. Optimizer-only miscompiles

*Seen:* the same `miniz` bug; historically the `-o` pipeline regression fixed in `aa08225`.

*Mechanism.* `-o` runs `Optimizer::run` before `run_post_process`; plain mode runs only the latter
(`Conformance/tests/common/compiler.rs:18-29`, mirrored in `CLI/src/main.rs:22-34`). The two
pipelines produce different graphs, therefore different allocations, therefore different move
sequences and different printer shapes. `-o` is a second compiler.

*Why blind.* The suite *does* run both pipelines (see fact (a)) but compares each only against the
`.wast` expectations, which are shallow: a handful of scalar returns per module. Nothing compares
the two pipelines against each other on a program big enough for them to diverge, and no fixture is
run under `-o` as a gate.

*Would have caught it.* (P2) `-o` vs plain differential on the same module — the strongest signal
per line of code in this whole document, because the oracle is free (the other pipeline) and the
inputs already exist. (P1) makes it exhaustive.

### D. Runtime helper semantics

*Seen:* `u64`→float conversion; historically out-of-bounds `buffer_*`, the half-written `i64` store,
`memory.copy` not being a `memmove`, `rt_table_grow` overrunning by one.

*Mechanism.* The `.lua` runtime under `Targets/*/Printer/runtime/` is hand-written Lua that
re-implements WebAssembly semantics on a byte overlay and on `bit`. It is included with
`include_str!` and only ever type-checked by being run.

*Why blind.* Partly it is not: `memory_trap.wast`, `conversions.wast` and friends catch a lot, which
is why this class has the best track record. What escapes is (i) semantics the spec suite exercises
only in the interpreter (class G below), and (ii) helpers with no spec coverage at all.

*Would have caught it.* (P16) direct Lua-level unit tests of the helpers against an independent
reference — the `verify.lua` already written in a scratchpad for the perf study, promoted into the
repo; (P1) random modules, which reach helper combinations no hand-written `.wast` does.

### E. Harness defects

*Seen:* NaN assertions that were silently no-ops in the `luajit` harness for months.

*Mechanism.* Fact (c) and fact (d): an oracle that reports nothing is a green test, and the three
copies of the emitter drift.

*Why blind.* By construction. A test suite cannot notice that one of its own assertions does nothing.

*Would have caught it.* (P7) a harness self-test that feeds every `hn_*` checker a deliberately
wrong value and asserts it *reports*, plus a "checker never invoked in this run" tripwire;
(P12) collapsing the three emitters so there is one copy to be right.

### F. Environment and tooling

*Seen:* the 4 s busy-poll timeout; `wasmtime --invoke` argument-order gotchas that hid a
never-established baseline; the Windows `f32` machine-code path.

*Mechanism.* `Conformance/tests/common/process.rs:9-28` polls `try_wait` every 2 ms until a fixed
deadline. `luajit.rs:587-601` spawns `REPETITION_COUNT = 32` threads per test case, and
`datatest-stable` runs test cases in parallel: 78 files × 4 variants × 32 processes is thousands of
concurrent interpreters on a shared machine. A fixed deadline under that load times out for reasons
that have nothing to do with the code under test. Separately, `.github/workflows/conformance.yaml:29`
sets `luajit: ""` for Windows, and both conformance steps are guarded by `if: matrix.luajit != ''`
— **Windows compiles the compiler and never runs a single generated line**, and no step installs
Luau anywhere, so `--test luau` never runs in CI at all.

*Would have caught it.* (P9) a load-derived budget plus a blocking wait plus a concurrency cap;
(P11) a nightly platform matrix that actually installs LuaJIT on Windows (the harness already reads
`LUAJIT_PATH`, so this is pure YAML); (P13) baselines produced through the `wasmtime` *library*
API, where arguments are typed and positional by construction and cannot be reordered by a CLI
convention.

### G. JIT-dependent divergence

*Seen:* `u64`→float wrong once traces get hot; the flaky `f32` result under load.

*Mechanism.* The generated program has two semantics: interpreted bytecode and recorded traces.
Spider is only correct if both agree with WebAssembly. Fact (b) says the suite essentially only
tests the first.

*Would have caught it.* (P8) conformance variants run with `-Ohotloop=1 -Ohotexit=1`, which forces
recording on the first iteration, so every existing assertion runs through machine code; (P10)
`luajit -jv` abort logs, which also turn this into a perf signal; (P11) more than one CPU
architecture.

### Summary map

| Class | Today's blind spot | Primary instrument | Secondary |
| --- | --- | --- | --- |
| A. Threshold printer shapes | no large inputs | P3 threshold sweeps | P6 static limit gate, P5 goldens |
| B. Move sequencing | untested pure function | P4 property tests | P1, P2 |
| C. Optimizer-only | no pipeline-vs-pipeline oracle | P2 `-o` vs plain | P1, P13 |
| D. Runtime helpers | good, but interpreter-only | P16 helper unit tests | P1, P8 |
| E. Harness | oracle never tested | P7 harness self-test | P12 dedup |
| F. Environment | fixed deadlines, partial matrix | P9 budget, P11 matrix | P13 library baselines |
| G. JIT divergence | `hotloop=56` vs one invocation | P8 hot-loop stress | P10 `-jv`, P11 |

---

## 2. Proposals

Sixteen, each with a design sketch against this repo's actual structure. Effort is one engineer's
uninterrupted time; "files" lists what is added (`+`) or touched (`~`).

### P1 — Differential testing against `wasmtime` on `wasm-smith` modules

**Hypothesis H1.** A random-module differential harness finds classes B, C and D at a rate that no
hand-written corpus can match, and reproduces the `miniz` move-sequencing bug in well under 10 000
seeds because the bug needs only "a region boundary with conflicting preferences under `-o`", which
random modules with many locals hit constantly.

**Design.**

```
Conformance/
  Cargo.toml              ~ dev-deps: wasm-smith, arbitrary, wasmtime
  tests/
    differential.rs       + the fuzz driver (datatest-stable over a seed corpus + an env-driven sweep)
    common/
      generate.rs         + wasm-smith Config + deterministic seed -> Vec<u8>
      oracle.rs           + wasmtime reference execution
      emitter.rs          + shared wast/driver emitter (see P12)
    corpus/               + committed seeds that once failed (regression corpus)
```

*Generation.* `wasm_smith::Config` restricted to what Spider supports — the same filter the suite
already applies by excluding `simd_*`: `simd_enabled = false`, `relaxed_simd_enabled = false`,
`threads_enabled = false`, `exceptions_enabled = false`, `gc_enabled = false`,
`tail_call_enabled = false`, `memory64_enabled = false`, `multi_memory = false`;
`bulk_memory_enabled = true` and `reference_types_enabled = true` (the suite passes
`memory_copy/fill/init`, `ref_*` and `table_*`). Set `export_everything = true`,
`allow_start_export = false`, `canonicalize_nans = true` (this removes the single largest source of
false positives, and is exactly the axis on which `lua-no-ffi` legitimately differs today),
`max_memory32_bytes` small (≤ 1 MiB) so a comparison of full memory is cheap, and
`max_instructions` moderate. Drive it with
`Module::new(config, &mut arbitrary::Unstructured::new(&seed_bytes))` where `seed_bytes` come from a
fixed-stream PRNG keyed by a `u64` seed, so a failure is reproducible from one integer.

*Version pinning is a real constraint.* `Tools/WasmtimeHostRunner` pins `wasmtime = "24.0.1"`,
`Conformance` uses `wast = "222.0.0"` and the workspace pins `wasmparser = "0.235.0"`. Pick the
`wasm-smith` release from the same `wasm-tools` train as `wast` 222 so `wasm-encoder`/`wasmparser`
are shared, and accept (or lift) the second `wasmparser` that `wasmtime` 24 pulls in. Note
`unused_crate_dependencies = "deny"` in the workspace lints: every new dev-dependency needs a
`use foo as _;` in the binary that does not name it, exactly like `luanoffi_builder as _` at
`luajit.rs:29`.

*Reference side.* Not the `wasmtime` CLI. Reuse the pattern already proven in
`Tools/WasmtimeHostRunner/src/main.rs`: `Engine::default()`, `Module::new`, `Store::new`,
`Instance::new`, then for each export call it through `Func::call` with a `Vec<Val>` argument vector
built from the function type and a deterministic per-seed argument corpus (interesting constants:
`0`, `1`, `-1`, `i32::MIN`, `i32::MAX`, `0x8000_0000`, `2^31`, `2^53`, `NaN`, `±0.0`, `±inf`,
subnormals). Record, per call: the result vector as **bit patterns**, whether it trapped and the
trap kind, and afterwards a hash of every exported memory and the value of every exported global.

*Test side.* Compile the same bytes with `Compiler::run(&data, optimize)` → `LuaNoFFIBuilder` →
`LuaNoFFIPrinter`, wrapped in the same section machinery the suite already uses
(`LibrarySections::with_built_ins()`, `parse_from(HARNESS_START_SOURCE)`, `resolve()`,
`LibraryPrinter::print`), with a *generated driver* that performs the identical calls and prints one
canonical line per observation. Arguments and results are formatted by the existing
`fmt_argument_*`/`fmt_assert_equal_*` conventions (i64 as `…LL`, f32 as its `i32` bit pattern) —
another reason to factor them out first (P12).

*Comparison.* Line-by-line on the canonical text. Trap vs trap compares the message the runtime
raises against a mapping of `wasmtime` trap kinds; a Spider trap where `wasmtime` returned a value
(or vice versa) is a failure. On mismatch, write `seed`, the `.wasm`, the `.lua` and both outputs
into `CARGO_TARGET_TMPDIR` and print the seed, then let the reporter add it to `corpus/`.

*Shrinking.* Cheap version first: retry the seed with `max_instructions` and `max_funcs` halved,
keep the smallest still-failing configuration. Real shrinking (removing functions/instructions from
the encoded module) is a later refinement; in practice "same seed, smaller config" plus
`wasm-tools shrink` offline covers it.

*Budget.* PR job: 200 seeds per target (~1-2 minutes). Nightly: 20 000 seeds, sharded across the
matrix, corpus-first.

**Effort.** 3-5 days. **Catches.** B, C, D, and any lifter/structurer bug.

### P2 — `-o` vs plain differential on the same module

**Hypothesis H2.** The optimizer is a second compiler and deserves a second oracle; comparing it to
the first is free. Predicted to catch class C bugs *before* they reach a fixture, and to be the
first of these proposals to fire.

**Design.** Two forms, both trivial because `Compiler::run` already takes the flag.

1. *Inside the fuzz driver (P1).* For each seed, compile twice and compare the two generated
   programs' observations to each other and to `wasmtime`. Three-way disagreement localises the bug
   immediately: if plain agrees with `wasmtime` and `-o` does not, it is the optimizer or what the
   optimizer's graph did to the allocator.
2. *Over the spec suite, decoupled.* Fix fact (a): replace the `(optimized, native)` bool pair with
   an explicit variant enum so the matrix is a real 2×2 of (IR optimizer) × (LuaJIT mode), and add
   the two missing cells. This costs ~30 lines in each of the three test binaries — or ~30 lines
   once, after P12.

**Files.** `~ Conformance/tests/{luajit,luanoffi,luau}.rs`, `+ Conformance/tests/common/variant.rs`.
**Effort.** 1 day (form 2), folded into P1 for form 1. **Catches.** C, and B by proxy.

### P3 — Threshold-stress generators

**Hypothesis H3.** Every shape-changing constant in the printer and the allocator has an off-by-one
neighbourhood, and a sweep of ±3 around each constant is enough to find it. Predicted to reproduce
the ≥ 48-capture bug from a synthetic module of a few hundred lines, without the self-hosting
fixture.

**Design.** `+ Conformance/tests/common/synth.rs` builds modules programmatically (with
`wasm-encoder`, which arrives with P1; `.wat` text plus `wast`'s encoder also works and is easier to
debug). Generators, each parameterised by `N` and each computing its own expected result in Rust so
no reference engine is needed:

| Generator | Sweeps `N` over | Pressures |
| --- | --- | --- |
| `many_locals(N)` | 190…205, 255, 256 | `MAX_LOCAL_VARIABLES = 197`, `LUA_MAX_LOCALS = 200`, `excess_stack` spilling |
| `many_live_across_region(N)` | 44…62 | `CAPTURE_BUDGET = 57`, the old 48 packing threshold, LuaJIT's 60 upvalues |
| `many_module_functions(N)` | 55…65, 100, 250 | table-backed module locals (`statement.rs:335`) |
| `br_table_targets(N)` | 1, 2, 255, 256, 1024 | jump ranges, branch lowering |
| `nested_blocks(N)` | 60…70, 200 | structurer recursion, LuaJIT bytecode jump limits |
| `params_and_results(N)` | 0…3, 16, 64, 200 | multi-value, `Apply` result counts, `Link(id, port)` `u16` ports |
| `memory_pages(N)` | 1, 2, 65535, 65536 | `memory.grow` edges, `u32` page arithmetic |
| `globals(N)`, `table_size(N)` | 60, 200, 65535 | module-level binding pressure |

Each case is run for `lua-jit` and `lua-no-ffi`, in both `-o` modes, and asserts a checksum the
generator computed. A generator that *cannot* be compiled (a limit genuinely exceeded) must fail
with a clear diagnostic, not with `attempt to call a nil value` — assert on the message.

**Files.** `+ Conformance/tests/thresholds.rs`, `+ Conformance/tests/common/synth.rs`.
**Effort.** 1-2 days. **Catches.** A, and the "compiles but LuaJIT refuses to load it" family.

### P4 — Property tests for the parallel-move sequencer and the local allocator

**Hypothesis H4.** `AssignmentSimplifier` is the single highest-density bug surface in the backend
and the single cheapest to test, because it is a pure `Vec<(Local, Local)> -> sequence of statements`
function with an obvious executable specification.

**Design.** `#[cfg(test)] mod tests` inside
`Targets/LuaNoFFI/Builder/src/assignment_simplifier.rs` (and the identical LuaJIT/Luau copies, or
once in a shared crate if they are ever merged). No new dependency is needed — the crates are
`no_std` + `alloc` and the workspace lints are hostile to macro-heavy frameworks; a 20-line
xorshift PRNG driven by a fixed seed list gives reproducibility that `proptest` would only match
with a saved regression file.

*Model.* Assign each `Local` in the problem a distinct symbol. `initial: Map<Local, Symbol>` is the
identity. Interpret the emitted statements in order: `Assign(d, s)` does `state[d] = state[s]`;
`SwapAll([l0, l1, …, lk])` does the rotation the printer actually emits — **read the printer**
(`Targets/LuaNoFFI/Printer/src/statement.rs`, `Print for SwapAll`) rather than assuming, since the
whole point is that the two must agree.

*Properties.*
1. **Correctness.** For every input pair `(d, s)`: `state[d] == initial[s]` at the end.
2. **Totality.** `find_all_assigns` + `find_all_swaps` consume every pair; the loop terminates in
   ≤ `n` iterations.
3. **No panic.** `find_first_swap`'s `.unwrap()` never fires — this is the assumption "everything
   left is a disjoint union of cycles", and it is the one most likely to be false when a source has
   several destinations.
4. **No spurious work.** A pair `(d, d)` emits nothing; an already-correct pair is not re-emitted.
5. **Optional cost bound.** Statements emitted ≤ `n + cycles`, as a regression metric for the
   copy-count problem measured in [upstream-review.md](../upstream-review.md).

*Generators.* Random total maps `dest → src` over `k ∈ [1, 24]` locals, biased to produce:
pure permutations; permutations with fan-out (a source read by 2-4 destinations); chains;
single long cycles; many 2-cycles; self-moves mixed with cycles; the empty problem. Run a few
thousand cases per seed list — microseconds each.

*Second target, same technique.* `local_allocator/{index_provider,local_provider,argument_finder}.rs`:
build random region graphs, run the allocator, assert (i) two links live at the same time never share
a `Local`, (ii) the returned `Declarations.locals` range covers every assigned name, (iii) the
`stack` count fits `u16` and matches the number of spilled slots, (iv) `MAX_LOCAL_VARIABLES` is never
exceeded.

**Files.** `~ Targets/{LuaJIT,LuaNoFFI,Luau}/Builder/src/assignment_simplifier.rs`,
`~ .../local_allocator/mod.rs`. **Effort.** 1 day for the mover, +1 for the allocator.
**Catches.** B. **This is the best ratio in the document.**

### P5 — Golden-file snapshot tests of generated Lua

**Hypothesis H5.** Printer regressions are shape regressions, and shape is exactly what a golden
file pins. Predicted to catch the `(cond and 1 or 0)` precedence class and every future packing or
spilling rewrite, at the cost of some churn.

**Design.** Two tiers, because whole-file goldens of a 1.5 M-line `lodepng` are useless.

*Tier 1 — exact text, small inputs.* `Conformance/golden/*.wat` (20-40 hand-picked shapes: a
`Gamma`, a `Theta` with a boolean latch, a packed-capture function just over 57, a function with a
slow stack, an `i64` round-trip, a table/global round-trip). `Conformance/tests/golden.rs` uses
`datatest-stable` over that directory and compares against `<name>.<target>.lua` next to it;
`SPIDER_BLESS=1` rewrites the expectations. Diffs are readable and reviewable in a PR, which is
where their value is.

*Tier 2 — metrics, big inputs.* For each fixture in `tests/manual/*/generated/*.wasm`, record a row
in `Conformance/golden/metrics.json`: `lines`, `copies` (statements matching `^\s*loc_\d+_ = loc_\d+_;?$`),
`excess_stack` references, distinct `rt_*` helpers, functions, max locals in one function, max
captures in one scope, bytes. These are precisely the numbers the upstream review measured by hand
(24 % / 35 % copies, 1332 → 1956 spills); making them a committed artifact turns that one-off study
into a ratchet.

**Files.** `+ Conformance/tests/golden.rs`, `+ Conformance/golden/**`, `+ Tools/Metrics/` (shared
with P6). **Effort.** 1-2 days. **Catches.** A, plus silent quality regressions.

### P6 — A metrics and hard-limit gate in CI

**Hypothesis H6.** Most of class A is detectable **statically**, without running the program, and
therefore without a fixture, a baseline or a timeout. Predicted: a `luajit -bc` gate alone would have
rejected the ≥ 48-capture output at compile time.

**Design.** `+ Tools/Metrics/src/main.rs` — a small binary that takes a generated `.lua` and emits
the P5 Tier-2 JSON row. Two independent checks in CI:

1. **Load gate.** `luajit -bc file.lua /dev/null` (or `-bl` for a listing) *compiles* the file
   without executing it. It fails loudly on "function or expression too complex", "too many
   upvalues", "too many local variables", "control structure too long" — every LuaJIT hard limit.
   Run it on every fixture's generated output, every golden, every threshold case and every fuzz
   case. It costs milliseconds and needs no expectations. Parsing `-bl` output additionally yields
   the real per-prototype upvalue and local counts straight from the VM, which is a far better
   source of truth than the printer's own estimate — and the disagreement between the two is itself
   the bug signal for class A.
2. **Ratchet.** Compare the JSON against `Conformance/golden/metrics.json`: fail hard if any
   prototype exceeds 60 upvalues or 200 locals; fail if `lines` or `copies` grow by more than a
   configured tolerance (start at 2 %, tighten later); warn on improvements so they get blessed.

**Files.** `+ Tools/Metrics/`, `~ .github/workflows/conformance.yaml`, `~ Cargo.toml` (`Tools/*` is
already a workspace member glob). **Effort.** 1 day (gate 1 is half of that and worth doing first).
**Catches.** A, plus upvalue/local regressions from any future inlining or lowering work — which is
exactly the risk flagged for the deferred-lowering port in the upstream review.

### P7 — A harness self-test (mutation testing of the oracle)

**Hypothesis H7.** Any checker can be a no-op; the only way to know it is not is to make it fail on
purpose. Predicted to find further no-ops today, not just the NaN ones already fixed — the eight
`visit_assert_*` stubs that return `Ok(())` are the standing evidence.

**Design.** `+ Conformance/tests/harness_self_test.rs`. For each target, generate one small Lua
program that loads the harness sections (the same `LibrarySections`/`LibraryPrinter` path the suite
uses) and then, for a table of cases, calls each `hn_*` checker twice: once with a value that must
pass and once with a value that must be reported. Cases must include, per target:

- `hn_assert_equal_i32` with a wrong value, and with a non-number;
- `hn_assert_equal_i64` with a wrong value, with an `i32`, and with a plain number;
- `hn_assert_equal_f32`/`_f64` with a one-ULP-off bit pattern and with the wrong sign of zero;
- `hn_is_f32_nan_canonical` with an *arithmetic* NaN payload (this is the exact case that was a
  no-op), with a non-NaN, and with the wrong type;
- `hn_is_f32_nan_arithmetic` with a non-NaN and with `+inf`;
- the `f64` versions of both, including the `lua-no-ffi` `int64_t`-vs-number type distinction;
- `hn_assert_trap` with a callback that does not trap;
- `hn_assert_ref_null`/`hn_assert_ref_extern` with swapped arguments.

The end file already counts failures in `hn_failed_test_count` (`harness/luajit.start.lua:67`);
expose it (or print it) so the Rust side can assert `failures == expected_failures` exactly. A
checker that reports 0 failures for its wrong value fails the test.

*Tripwire extension, near-free.* Have `report_failure`'s module also count *invocations* per checker
and have the `end` harness print any `hn_*` that was resolved into the file but never called during
a suite run. An assertion family that is emitted and never executed is the same defect one level up.

**Files.** `+ Conformance/tests/harness_self_test.rs`, `~ Conformance/tests/harness/*.{lua,luau}`.
**Effort.** half a day. **Catches.** E — and it retroactively validates the other 312 results.

### P8 — Conformance variants under JIT hot-loop stress

**Hypothesis H8.** Running the *existing* 78 files with `-Ohotloop=1 -Ohotexit=1` moves nearly all
generated code from the interpreter into machine code and thereby tests a backend that is currently
untested. Predicted to reproduce the `u64`→float divergence directly from `conversions.wast`, with
no fixture involved.

**Design.** Add variants to the `datatest_stable::harness!` block:

```rust
fn native_hot(path: &Path) -> Result<()> { run_and_assert(path, Variant::hot()) }
// luajit -O3 -Ohotloop=1 -Ohotexit=1 -Omaxtrace=8000 -Omaxrecord=16000 -jon <file>
```

`run_file` (`luajit.rs:568`) already builds the argument array, so this is a handful of extra
`OsStr`s. Two caveats: (i) `hotloop=1` plus `maxtrace` defaults can exhaust the trace table on large
generated modules, hence the raised `maxtrace`/`maxrecord`; (ii) the variant roughly doubles the
suite's runtime, so it belongs in nightly and on `trunk` pushes rather than on every PR. Pair it with
a `-Ohotloop=1 -jv` run that also captures aborts (P10), so a case that *cannot* be traced is visible
rather than silently falling back to the interpreter and passing.

**Files.** `~ Conformance/tests/{luajit,luanoffi}.rs`, `~ .github/workflows/*`.
**Effort.** 2 hours of code, plus CI budget. **Catches.** G. **Second-best ratio in the document.**

### P9 — A timing budget derived from load, and a bounded concurrency

**Hypothesis H9.** The flaky timeouts and the flaky `f32` result are not one bug: the first is a
fixed deadline meeting an oversubscribed machine, and the second is a real bug that only surfaces
under the scheduling that oversubscription produces. Fixing the first makes the second reproducible
instead of anecdotal.

**Design.** In `Conformance/tests/common/process.rs`:

1. Replace the 2 ms poll loop with a blocking wait on a helper thread plus
   `mpsc::recv_timeout(deadline)`, so a finished process is observed immediately and a waiting
   process costs nothing.
2. Compute the deadline once per test binary: a calibration run of a trivial `luajit -e "os.exit()"`
   measured `k` times gives a process-startup unit; multiply the per-test base budget by
   `max(1, measured_unit / reference_unit)` and clamp to `[10 s, 300 s]`. On Linux, cross-check
   against `/proc/loadavg`. Allow `SPIDER_TEST_TIMEOUT` to override.
3. Cap concurrency: a process-wide semaphore of `std::thread::available_parallelism()` around the
   subprocess spawn, and make `REPETITION_COUNT` (currently a hard-coded 32 at `luajit.rs:38`) read
   `SPIDER_REPETITIONS`, defaulting to 4 locally and 32 in nightly. The 32 repetitions exist to shake
   out nondeterminism; that is a nightly job's business, not a PR's.
4. On timeout, report the elapsed time, the budget, the calibration unit and the load, so a flake is
   diagnosable from the log rather than from a rerun.

**Files.** `~ Conformance/tests/common/process.rs`, `~ Conformance/tests/{luajit,luanoffi,luau}.rs`.
**Effort.** half a day. **Catches.** F — and it is a precondition for P1, whose signal-to-noise
collapses if timeouts are ambient.

### P10 — `luajit -jv` trace-abort logs as a regression signal

**Hypothesis H10.** The chipmunk 691× gap is trace aborts, not instruction count (stated as an
untested hypothesis at the end of [upstream-review.md](../upstream-review.md)); logging aborts turns
it into a number that can regress.

**Design.** A mode in the fixture runner (or `+ Tools/TraceReport`) that runs
`luajit -jv <fixture main.lua> 2> traces.log`, parses `[TRACE --- file:line -- <reason>]` lines,
aggregates by reason (`NYI: bytecode`, `leaving loop in root trace`, `call unroll limit`,
`trace too long`, blacklisting) and by generated-function line, and writes
`tests/manual/<fixture>/generated/traces.json`. Nightly compares against the recorded baseline and
fails on a rise beyond tolerance. Cross-reference the hottest aborting lines with the metrics from
P6 to point at the printer construct responsible.

**Files.** `+ Tools/TraceReport/`, `~ tests/manual/*/README.md` (baseline table).
**Effort.** 1 day. **Catches.** performance regressions; indirectly G, since a function that stops
being traced is also a function that stops exercising the traced semantics.

### P11 — A nightly platform matrix that actually runs LuaJIT on Windows

**Hypothesis H11.** The `f32` machine-code divergence is platform-specific
(see [windows-ffi-machine-instructions.md](../windows-ffi-machine-instructions.md)), and today's CI
cannot see it because the Windows job has no interpreter.

**Design.** Split `.github/workflows/conformance.yaml` into:

- `conformance.yaml` (PR, fast): Linux only; fmt, clippy, build, unit tests, `--test luajit` and
  `--test luanoffi` at `SPIDER_REPETITIONS=4`, P4/P7 property and self-tests, 200 fuzz seeds, the
  P6 `luajit -bc` gate. Target: under 15 minutes.
- `nightly.yaml` (schedule + `workflow_dispatch`): the full matrix.

| Job | OS | LuaJIT source | Extra |
| --- | --- | --- | --- |
| Linux x64 | `ubuntu-latest` | `apt-get install luajit` | full suite + P8 hot variants |
| Linux x64 (hot) | `ubuntu-latest` | same | `-Ohotloop=1`, 20 000 fuzz seeds |
| macOS ARM64 | `macos-latest` | `brew install luajit` | full suite |
| macOS x64 | `macos-13` | `brew install luajit` | full suite (second float ABI) |
| Windows x64 | `windows-latest` | download a LuaJIT release zip (or build the submodule with `msvcbuild.bat`), set `LUAJIT_PATH` | full suite — **the gap** |
| Luau | `ubuntu-latest` | download a `luau` release binary | `--test luau`, which CI has never run |

No Rust change is needed for the Windows job: `run_file` already honours `LUAJIT_PATH`
(`luajit.rs:575`). The Luau job needs the equivalent env hook in `luau.rs` if it does not have one.

**Files.** `~ .github/workflows/conformance.yaml`, `+ .github/workflows/nightly.yaml`.
**Effort.** 1 day, most of it finding a trustworthy Windows LuaJIT artifact.
**Catches.** F, G.

### P12 — One `wast` emitter instead of three

**Hypothesis H12.** Three 600-line copies guarantee that fixes land in one target and not the others;
the NaN no-op is the proof. Deduplication is not itself a test, but it is a multiplier on P1, P3 and
P7, each of which otherwise has to be written three times.

**Design.** `+ Conformance/tests/common/emitter.rs` holds the `Visitor` implementation, the argument
and assertion formatting and the file assembly. A `trait TargetDialect` supplies the parts that
genuinely differ: the `i64` literal form (`…LL` vs the `lua-no-ffi` pair form), the `f64` literal
form, the "is this value an i64" predicate, the file extension, the harness sources, and the
builder/printer pair. Each of `luajit.rs`, `luanoffi.rs`, `luau.rs` shrinks to a dialect impl plus
the `datatest_stable::harness!` block. Do it mechanically, with the suite green before and after.

**Files.** `+ Conformance/tests/common/emitter.rs`, `~ Conformance/tests/{luajit,luanoffi,luau}.rs`.
**Effort.** 1-2 days. **Catches.** E structurally.

### P13 — Fixture expectations as data, produced through the `wasmtime` library

**Hypothesis H13.** A baseline recorded in prose in a `README.md` and re-derived by hand from a CLI
is a baseline that will be wrong exactly when it matters. Moving it into a checked file, produced by
typed calls, removes the `--invoke` argument-order class of error entirely.

**Design.**

1. Extend `Tools/WasmtimeHostRunner` with `FixtureKind::Generic`: read
   `tests/manual/<fixture>/expectations.toml` —

   ```toml
   wasm = "generated/miniz.wasm"
   [[case]]
   export = "hash_roundtrip"
   args = ["i32:512"]
   expect = ["i32:58679047"]
   ```

   — resolve each export with `Instance::get_func` + `Func::call` over `Vec<Val>` (typed, positional,
   no CLI parsing), and print or verify. The existing five hard-coded protocols stay as they are.
2. `+ Conformance/tests/fixtures.rs` (env-gated, e.g. `SPIDER_FIXTURES=1`, since the inputs are
   large): for each fixture, compile with `spider-cli` semantics in-process, run under `luajit`,
   parse the same `Result (...)` lines the fixture mains already print, and compare against the same
   `expectations.toml`. Run each fixture under plain **and** `-o` (this is where the `miniz` bug
   would have been caught as a gate rather than as a discovery).
3. Generate the README tables from the toml rather than the other way round.

**Files.** `~ Tools/WasmtimeHostRunner/src/main.rs`, `+ tests/manual/*/expectations.toml`,
`+ Conformance/tests/fixtures.rs`. **Effort.** 2-3 days, mostly transcription.
**Catches.** C, D, F.

### P14 — A trap and determinism oracle contract

**Hypothesis H14.** Most differential false positives come from three places: NaN payloads, trap
identity, and float formatting. Pin them once, in writing, and the fuzzer stays quiet enough to
believe.

**Design.** A short `Conformance/ORACLE.md` plus the code that enforces it: NaN compared as
canonical only (and `canonicalize_nans = true` on the generator) until `lua-no-ffi` closes its
known NaN-bit gap, at which point the flag flips and the 280/312 becomes 312/312 as a *test*;
traps compared by a mapped kind, not by message text; all floats compared as bit patterns, never as
decimal text; memory compared by a hash over the whole exported memory plus a diff of the first
differing page when it fails. Record the 32 known NaN-bit failures as an explicit allow-list with
expiry, so they cannot quietly grow.

**Files.** `+ Conformance/ORACLE.md`, `+ Conformance/tests/common/oracle.rs`.
**Effort.** half a day, alongside P1. **Catches.** false positives, i.e. the fuzzer's credibility.

### P15 — Coverage-guided fuzzing (later)

**Hypothesis H15.** Pure random generation plateaus; coverage feedback finds the next tier. But
only after P1 exists and its oracle is trusted.

**Design.** `cargo-fuzz`/libFuzzer target that takes the raw bytes as `Unstructured`, runs the P1
comparison, and keeps a corpus in `Conformance/fuzz/corpus/`. Run it out of band, not in CI; feed
findings back as seeds in P1's committed corpus. Note the workspace's `#![no_std]` crates and
`forbid` lint set make an in-tree fuzz crate awkward; keep it in `Tools/Fuzz/` with its own lint
relaxations.

**Effort.** 2 days, after P1. **Catches.** the long tail of B, C, D.

### P16 — Runtime helper unit tests in Lua

**Hypothesis H16.** The `.lua` runtime is a second implementation of WebAssembly semantics and
deserves its own tests independent of the compiler; a differential against a naive byte-array
reference is enough, and it already exists in a scratchpad.

**Design.** `+ Targets/LuaNoFFI/Printer/runtime/tests/*.lua` (and the LuaJIT equivalent), driven by
`+ Conformance/tests/runtime.rs` which assembles the needed sections with `LibrarySections` /
`LibraryPrinter` (the same machinery the suite and P7 use) and runs the result. Cases: thousands of
random aligned and unaligned loads/stores of every width against a reference byte array; every
out-of-bounds and partially-in-bounds address; `memory.copy` with overlapping ranges in both
directions; `memory.fill` and `memory.init` edges; `table.grow`/`table.copy` edges; the whole `i64`
helper family (`into_bits_i64`/`from_bits_i64` round-trips, division and remainder at `INT64_MIN / -1`,
shifts at 0/63/64/65); `u64`→`f32`/`f64` conversions across the rounding boundaries (**the class G
bug**), run both interpreted and with `-Ohotloop=1`.

**Files.** `+ Targets/*/Printer/runtime/tests/`, `+ Conformance/tests/runtime.rs`.
**Effort.** 1-2 days. **Catches.** D, G.

---

## 3. Prioritisation

Ranked by expected bugs caught per day of work, with the dependency order respected. "Class" refers
to section 1.

| # | Proposal | Effort | Classes | New deps | Why here |
| --- | --- | --- | --- | --- | --- |
| 1 | **P4** move-sequencer property tests | 1 d | B | none | pure function, executable spec, the bug class that hurt most this week |
| 2 | **P6.1** `luajit -bc` load gate | 0.5 d | A | none | static, hermetic, would have rejected the ≥ 48 output at compile time |
| 3 | **P7** harness self-test | 0.5 d | E | none | until the oracle is tested, every other number is unverified |
| 4 | **P9** timing budget + bounded concurrency | 0.5 d | F | none | removes the noise that would drown items 6-8 |
| 5 | **P8** hot-loop conformance variants | 0.25 d | G | none | 10 lines buy an untested backend; nightly-only |
| 6 | **P2** `-o` vs plain differential (suite form) | 1 d | C | none | free oracle, inputs already exist |
| 7 | **P12** one emitter instead of three | 1.5 d | E | none | precondition for 8, 9, 10 being written once |
| 8 | **P1 + P14** `wasm-smith` × `wasmtime` differential | 4 d | B, C, D | wasm-smith, arbitrary, wasmtime | the general instrument; the biggest single investment |
| 9 | **P3** threshold-stress generators | 1.5 d | A | wasm-encoder (from 8) | targeted where random generation is weakest |
| 10 | **P4b** allocator property tests | 1 d | B | none | same technique, one layer up |
| 11 | **P6.2 + P5** metrics ratchet and goldens | 2 d | A | none | makes the upstream-review numbers a committed ratchet |
| 12 | **P11** nightly matrix incl. Windows + Luau | 1 d | F, G | none | mostly YAML; the Luau target has never run in CI |
| 13 | **P16** runtime helper unit tests | 1.5 d | D, G | none | promotes the existing scratchpad `verify.lua` |
| 14 | **P13** fixture expectations as data | 2.5 d | C, D, F | none | converts the whole manual tier into a gate |
| 15 | **P10** `-jv` trace-abort logging | 1 d | perf | none | answers the open chipmunk question |
| 16 | **P15** coverage-guided fuzzing | 2 d | tail | cargo-fuzz | only once 8 is trusted |

Roughly: **items 1-6 are one working week and cover five of the seven classes**; items 7-9 are a
second week and add the general instrument; the rest is consolidation.

### Files touched, by area

```
Conformance/
  Cargo.toml                          ~ 8         dev-deps: wasm-smith, arbitrary, wasmtime, wasm-encoder
  ORACLE.md                           + 8
  tests/
    common/process.rs                 ~ 4         blocking wait, calibrated budget, semaphore
    common/variant.rs                 + 6         decouple IR-optimizer from LuaJIT mode
    common/emitter.rs                 + 7         the single wast emitter
    common/{generate,oracle}.rs       + 8
    common/synth.rs                   + 9
    {luajit,luanoffi,luau}.rs         ~ 5,6,7,12  variants, dedup
    harness_self_test.rs              + 3
    differential.rs                   + 8
    thresholds.rs                     + 9
    golden.rs                         + 11
    runtime.rs                        + 13
    fixtures.rs                       + 14
  golden/**                           + 11
  corpus/**                           + 8
Targets/
  */Builder/src/assignment_simplifier.rs  ~ 1
  */Builder/src/local_allocator/mod.rs    ~ 10
  */Printer/runtime/tests/**              + 13
Tools/
  Metrics/                            + 2, 11
  TraceReport/                        + 15
  WasmtimeHostRunner/src/main.rs      ~ 14        FixtureKind::Generic + expectations.toml
tests/manual/*/expectations.toml      + 14
.github/workflows/conformance.yaml    ~ 2,5,12    split into PR-fast
.github/workflows/nightly.yaml        + 12
```

### Constraints to respect while implementing

- **Workspace lints are `forbid`-heavy.** `unused_crate_dependencies = "deny"` forces a
  `use foo as _;` for every dependency a binary does not name (the existing pattern is
  `luajit.rs:29-33`); `missing_docs = "deny"` and `missing_panics_doc = "deny"` apply to new public
  items; `std_instead_of_alloc`/`std_instead_of_core` are `deny` inside the `no_std` crates, so
  property tests living in `Targets/*/Builder` must use `alloc` and a hand-rolled PRNG rather than
  pulling in a `std` test framework.
- **Version trains.** `wast 222.0.0` in `Conformance`, `wasmparser 0.235.0` in the workspace,
  `wasmtime 24.0.1` in `Tools`. Choose `wasm-smith` from the `wast`-222 train; expect (and tolerate)
  a second `wasmparser` under `wasmtime`.
- **CI minutes.** P8 roughly doubles suite time and P1 is unbounded by construction; both belong in
  nightly, with a small, fixed budget on PRs.
- **Determinism of the fuzzer.** One `u64` seed must reproduce a failure exactly, on every platform,
  or the corpus is worthless. Fix the PRNG, the argument corpus and the generator config in code, and
  version the config: when the config changes, old seeds mean different modules.

### Explicit non-goals

- No attempt to make `lua-no-ffi` pass the 32 NaN-bit cases as part of this work; they are recorded
  as an allow-list (P14) so they cannot grow, and closing them is a separate task.
- No replacement of the spec suite. It is the floor, it is cheap, and every proposal above is
  additive to it.
- No new benchmark framework. Upstream's (`#132`) is the candidate if benchmarking is wanted; this
  note is about correctness, and P10 is the only performance item, included because a trace abort is
  also a signal that the traced semantics stopped being tested.

### How to know this note was right

Each hypothesis is falsifiable by a single later session:

- **H4** fails if a few thousand random parallel-move problems find nothing in `AssignmentSimplifier`
  after the `miniz` fix lands — in which case the bug was in the allocator's preferences, not the
  sequencer, and P4b becomes the priority instead.
- **H6** fails if `luajit -bc` accepts an output that the VM then refuses at load time.
- **H8** fails if `-Ohotloop=1` leaves the `conversions.wast` results unchanged on a build with the
  `u64`→float bug reintroduced; that would mean the divergence needs a longer trace than one
  iteration and P16's targeted loops are the right instrument instead.
- **H1** fails if 10 000 seeds produce no disagreement on a build with a known miscompile
  reintroduced — which would say the generator config is too narrow, most likely because
  `max_instructions`/`max_funcs` keep functions too small to pressure the allocator.

Reintroducing a known bug behind a feature flag and measuring which instrument catches it, and how
fast, is the cheapest way to test this entire plan.
