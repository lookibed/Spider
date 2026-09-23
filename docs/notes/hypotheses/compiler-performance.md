# Compiler Performance — A Hypothesis Study

Status: **research only.** Nothing was built, run, profiled or measured for this note. Every
claim about the code is derived from the checked-in source and cited `file:line`; every cost
figure is an *estimate from reading*, stated in the symbols below, and must be confirmed by the
measurement plan in §4 before anything is changed. Numbers quoted from other notes carry their
source.

Written: `2026-09-23`. Code state: `a32b931`.

Companion notes: [`target-lowering.md`](target-lowering.md) (changes the node mix the optimizer
sees), [`verification.md`](verification.md) P4 (property tests for the move sequencer and the
local allocator, which several hypotheses below touch), [`../upstream-review.md`](../upstream-review.md)
(the only compile-time/RSS measurement so far: fork `-o` 0.91 s / 866 MB vs 0.39 s / 86 MB
without `-o` on `libjpeg_turbo_mjpeg`, before `aa08225`).

Symbols used throughout:

| symbol | meaning |
|---|---|
| `N` | nodes in the `DataFlowGraph` (whole module, one flat `Vec<Node>`) |
| `E` | argument links (sum over nodes of `for_each_argument`) |
| `P` | output ports (sum over nodes of `ports_output`) |
| `W` | the widest node's port count (the DPE stride) |
| `K` | optimizer rounds until fixed point (bounded by 64) |
| `R` | gamma/theta regions in one function |
| `D` | references (functions, globals, tables, memories) one function depends on |
| `L` | live WebAssembly locals at a region boundary |
| `B` | basic blocks in one function's CFG (`u16`) |
| `k` | width of one parallel move (ports on one region boundary) |
| `F` | size of the local allocator's free heap |

---

## 0. The one-paragraph version

The compiler is a sequence of **whole-module full scans**. The optimizer runs up to 64 rounds and
every round re-sorts the entire graph, rescans every node for identities, invariants, dead ports
and ISLE candidates, plus one more scan in debug builds — about seven `O(N + E)` passes per
round whatever changed (`IR/Visitor/src/pipeline.rs:84-105`). The graph the lifter produces is
wider than it needs to be: every gamma and theta threads *every* dependency of the function
through its ports (`Sources/WebAssembly/Lifter/src/control_flow_lifter/basic_block_lifter.rs:129-160`),
so `P` starts near `Σ_regions (D + L)`. The first dead-port round then has to remove them, and one
wide node sets the stride of the DPE bitset for all `N` nodes. Downstream, the backend keys almost
everything by `Link` in `hashbrown` maps. It sequences parallel moves with an `O(k³)` loop
(`Targets/LuaNoFFI/Builder/src/assignment_simplifier.rs:15-32`), and the printer re-parses 128 KB of
runtime Lua on every compile (`Targets/LuaNoFFI/Printer/src/library/sections.rs:200-223`). On a
native 64-bit host most of this is sub-second. **For self-hosting it is not**, for a reason
specific to this project: under `lua-no-ffi` every 64-bit integer operation is a runtime call that
allocates a `{lo, hi}` table (`Targets/LuaNoFFI/Printer/runtime/builtin/buffer.lua:556-563`). The
`set` crate stores its bits in `u64` words, and `hashbrown`'s default hasher mixes in 64-bit
arithmetic. So the two most-used containers in the compiler turn into allocation storms
when the compiler itself is compiled to wasm32 and run under `lua-no-ffi`. The fixture's global
allocator is also a bump allocator whose `dealloc` is a no-op
(`tests/manual/self-hosting-luanoffi-builder/src/lib.rs:53-93`), so every `Vec` doubling and every
hash-table rehash is permanent memory there. The ordered plan in §3 therefore starts with the
container representation (u32 words, dense index tables instead of hash maps) and only then moves to
the algorithmic optimizer work.

---

## 1. Hot paths and suspicious complexity

### 1.1 Driver: the optimizer round

`Optimizer::run` (`IR/Visitor/src/pipeline.rs:84-105`) per round:

| step | where | cost per round | note |
|---|---|---|---|
| topological normalize | `topological_normalizer.rs:111-114` | `O(N + E)` DFS + `N` node moves + `E` id rewrites | also the only dead-*node* elimination |
| `region_scope::assert_scoped` (debug) | `control/region_scope.rs:101-128` | `O(N + E)` | linear, stack of open ranges; cheap but a full extra scan per round |
| invariant port mover | `control/invariant_port_mover.rs:128-208` | `O(N)` scan + `O(Σ gamma ports × regions)` + `O(E)` rename scan with a hash probe per argument when the map is non-empty | |
| dead port eliminator | `control/dead_port_eliminator.rs:290-296` | `find_stride` `O(N + E)`, `mark` `O(P + E)`, `seen.clear` `O(N·W/64)` words, `sweep` `O(N + P)` + `O(E)` hash probes | see 1.3 |
| ISLE | `pipeline.rs:50-61`, `isle/mod.rs:105-165` | `O(N)` dispatch, rules only on `IntegerBinaryOperation` | iterates ids **descending** |
| `region_identity::remove` | `control/region_identity.rs:39-52` | `O(N + E)`, `mem::take` + write-back of every node | runs even when no identity exists; its `bool` is ignored at `pipeline.rs:101` |

So one round is about seven `O(N + E)`-class sweeps in debug and six in release, whether the
previous round changed one node or ten thousand, and the whole module waits for the slowest
function to converge. Total ≈ `K × 7 × (N + E)` plus the DPE bitset term. `K` has never been
recorded; the comment at `pipeline.rs:18-23` expects "a handful".

**ISLE sweep direction.** `run_isle` walks `(0..len).rev()` (`pipeline.rs:54`). After
normalization producers have lower ids than consumers, so the sweep visits a consumer *before*
its producers. Take `(x + 1) + 2`: if the rules first need `x + 1` to become canonical or folded,
the outer node was already visited in this sweep and can only benefit next round, which costs a full
`K += 1` of everything above. Nodes a rule appends (`id >= len`) are also never visited in the
same sweep. The inner `while isle::simplify(...)` (`pipeline.rs:55`) only re-tries the same id.

**`find_first_producer`** (`isle/context.rs:85-95`) walks `Identity` chains. After
`region_identity::remove` the chains are length ≤ 1 except for identities created by ISLE in the
same sweep, so this is `O(1)` amortized today. It is not a hot path, and would only become one if
identity removal stopped running each round.

### 1.2 Topological normalizer rebuilds the graph every round

`TopologicalNormalizer::handle_nodes` (`topological_normalizer.rs:79-96`) does a two-phase DFS
from omega, `mem::take`s every live node into a second `Vec<Node>`, and swaps. `handle_edges`
(`:98-108`) then rewrites every id through `id_to_post`. Costs:

- **Memory:** two node arrays resident at once (`graph.nodes` and `self.nodes`, both of capacity
  ≥ `N`), plus `id_to_post` (`4N` bytes) and the DFS stack (up to `E` entries of 8 bytes). After
  the swap, `self.nodes` still owns the *dead* nodes that were never taken, with their heap
  `Vec`s, until the next round's `clear()` (`:82`).
- **Time:** `N` moves of a `Node` (40-56 bytes on x86-64: the largest inline variant is `Identity`/
  `Fence` with `Resizable<Link, 4>`, `IR/Graph/src/node/simple.rs:35-44`, or `LambdaIn`), plus a
  `Set::grow_insert` per visit, plus the id rewrite. It is linear, but it runs every round,
  including the last round where nothing changes.
- It is **also the dead-code eliminator**: unreachable nodes vanish only here. Any
  change-tracking scheme (H4) must keep an equivalent.

### 1.3 Dead port eliminator bitset

After `aa08225` the key is `id * W + port` (`dead_port_eliminator.rs:54-58`) with
`W = max ports over all nodes + 1` (`:39-51`). This removed the `2^16` factor, but the set is
still `N × W` bits, and **`W` is set by the single widest node in the module**. Widest candidates:

- `LambdaIn` output ports = arguments + dependencies (`IR/Graph/src/node/sinks.rs:667-672`);
- every `GammaIn`/`ThetaIn`/`RegionOut` created by the lifter carries `D + L + 1` ports because
  `get_active_bindings` threads *all* dependencies and all live locals through every boundary
  (`basic_block_lifter.rs:129-145`, `:147-160`);
- the per-function fence built with one source per mutable dependency (`basic_block_lifter.rs:55-69`).

For a large module (`D` in the hundreds, say `W ≈ 500`, `N ≈ 2·10^6`) that is `10^9` bits
≈ 125 MB for a set whose useful population is `P ≈ 3-5 N`. `Set::clear`
(`set/src/owned.rs:236-256`) stops early once it has cleared all set bits, so the cost is mostly
memory, not time. There is also a **32-bit hazard**: `(id as usize) * self.stride` overflows
`usize` on wasm32 as soon as `N × W > 2^32` (e.g. `N = 2·10^6`, `W = 2 200`). In release that wraps
silently and aliases keys, which is a miscompile rather than a crash. Not reachable in the v1
fixture (it self-hosts only the builder), but reachable the day the optimizer is self-hosted.

The `map: HashMap<Link, Link>` renumbering (`:13`, `:225-243`, `:270-280`) costs one hash per
argument link in the whole graph whenever any port was dropped anywhere.

### 1.4 `region_identity` insert/remove churn

- `remove` (`region_identity.rs:39-52`) runs every round (`pipeline.rs:101`). It takes and puts
  back every node even though, per the comment at `pipeline.rs:99-100`, identities only come from
  ISLE, which today fires only on `IntegerBinaryOperation` (`isle/mod.rs:108`). When ISLE did
  nothing in a round, this whole scan is wasted.
- `insert` (`:143-153`, `:69-136`) appends one `Identity` node per `RegionOut`/`ThetaOut` result
  and per `ThetaIn` argument. That is one heap-free node each (`Resizable<Link, 4>` inline) but
  `+Σ region ports` nodes appended **out of topological order**, which forces the final
  normalizer pass in `run_post_process` (`pipeline.rs:117-127`) to re-sort the whole graph again.
- `constant_isolator::run` (`constant_isolator.rs:116-129`) likewise appends copies at the end.

### 1.5 `hashbrown`-heavy loops and `Link` keys

| map | key → value | population | where |
|---|---|---|---|
| `InvariantPortMover::map` | `Link → Link` | renamed ports | `invariant_port_mover.rs:11` |
| `DeadPortEliminator::map` | `Link → Link` | renumbered ports | `dead_port_eliminator.rs:13` |
| `LocalAllocator::preferences` | `Link → Link` | ~every assigned port in the module | `local_allocator/mod.rs:26`, filled by `reference_finder.rs:343`, `scalar_finder.rs:164-176` |
| `DataHandler::assignments` | `Link → Local` | ~every assigned port in the module | `data_handler.rs:21` |
| `DataHandler::expressions` | `u32 → Expression` | inlined expressions in flight | `data_handler.rs:23` |
| `DataHandler::declarations` | `u32 → Declarations` | one per function | `data_handler.rs:20` |
| `ScalarFinder::handled` | `u32 → bool` | every node with a used output | `scalar_finder.rs:78` |
| `CodeHandler::regions` | `u32 → Sequence` | open gamma regions | `code_handler.rs:17` |
| printer `exact_names` | `Name → Arc<str>` | module locals when table-backed | `Printer/src/lib.rs:24` |
| `Captures::{runtime, locals}` | per function | | `captures.rs:147-148` |

Every one of the `u32`-keyed maps is keyed by a dense id and could be a `Vec`. The `Link`-keyed
maps are keyed by `(node, port)`, which becomes dense once a per-node port offset table exists
(H3). `hashbrown` 0.16 with `default-hasher` (`Cargo.toml:23-27`) is foldhash, which mixes
with 64-bit multiplies. That is cheap natively and very expensive under `lua-no-ffi` (§3).

### 1.6 The `list` and `set` git crates

- `list::resizable::Resizable<T, N>` (`RustListDataStructure@a236bf9/src/resizable/collection.rs:80-84`)
  is an inline/heap enum. Spilling to the heap does `to_vec_reserve(len)`, i.e. capacity `2·len`
  (`:437-500`, `fixed/collection.rs:495-501`), then plain `Vec` doubling. Every access branches
  on the variant. `Clone` of a list of exactly `N` elements goes to the heap because of `len() < N`
  (`:774-781`): harmless, but it means cloning a full inline list allocates.
  Used for `Identity`/`Fence` sources (`N = 4`), `FunctionType` (`N = 15`, boxed),
  CFG predecessor/successor lists (`N = 7`, `Sources/WebAssembly/Graph/src/basic_block.rs:4-13`).
- `set::Set` (`RustSetDataStructure@b82ef8c/src/owned.rs`) is `Box<[u64]>` + `ones`
  (`bits.rs:3` `type Inner = u64`). `grow_length` (`owned.rs:287-296`) converts
  `Box<[_]> → Vec → reserve → resize to capacity → Box`, which is geometric and fine on a real
  allocator. Under a bump allocator each growth leaks the previous buffer. **All bit
  operations are on `u64` words**, including `count_ones` in `clear` and the ascending
  iterator used by liveness (`Liveness/src/locals.rs:65-72`).
- Node port lists are separate `Vec<Link>` heap allocations per control node (`control.rs`
  `LambdaIn.dependencies`, `GammaIn.arguments`, `RegionOut.results`, …), so a region costs
  3-4 allocations just for its port vectors.

### 1.7 Front end: structurer and liveness

- **Repeat structuring** (`Structurer/src/repeat/bulk.rs:29-52`) re-runs Kosaraju
  (`strongly_connected_finder.rs:94-135`) on every discovered loop body, so a loop nest of depth
  `d` costs `O(d·B)`, `O(B²)` worst case. Fine at `B ≤ 65 535`, but it is per function.
- **`ControlFlowGraph::replace_edge`** (`Graph/src/lib.rs:164-177`) does two linear `position`
  scans and a `Resizable::remove` (shift). `repeat::single::set_new_entry`
  (`repeat/single.rs:54-72`) calls it once per predecessor of every entry, and a `br_table`
  dispatcher gives one block `k` predecessors, so that is `O(k²)` per multi-entry loop.
  Interpreter-style modules (wasm3, binjgb) are exactly the case with large `k`.
- **`ContinuationFinder::run`** (`branch/continuation_finder.rs:97-106`) repeats `handle_stack`
  until no change, re-testing `dominates` (an all-predecessors scan) on deferred points each
  time: `O(B · deg · iterations)`.
- **Liveness** (`Liveness/src/locals.rs:651-666`) runs `handle_all` a second time when the
  function has any loop. Both passes append to `Locals::locals` (`:65-72`), so the first pass's
  sets stay allocated as garbage. The stored per-block sets are materialized `u16` lists, `O(B·L)`
  words per function in the worst case. `get_union` (`:48-57`) extends, sorts and dedups on every
  call. (Separately from speed: whether two passes are enough for arbitrary loop nesting deserves
  a proof or a test; see `verification.md` P4.)

### 1.8 Backend: local allocator and tree building

- `IndexProvider::try_revive` (`local_allocator/index_provider.rs:73-81`) calls
  `remove_free_if_found` (`:59-71`): a linear `position` over the free `BinaryHeap`, then
  `into_vec`, `swap_remove`, and `BinaryHeap::from` (**a full `O(F)` heapify**). That is
  `O(F)` per revive attempt. `LocalAllocator::handle_arguments` (`mod.rs:56-93`) calls it up to
  twice per argument (`:69-74`, `:80-87`). `F` is at most 197 for fast locals
  (`local_provider.rs:9`) but unbounded for the spill table provider. Spill-heavy functions
  (1 300-1 900 spill sites on `libjpeg_turbo_mjpeg`, `isle/mod.rs:101-104`) are where `F` is
  largest.
- `LocalAllocator::handle_definitions` (`mod.rs:95-104`) probes `preferences` port by port until a
  miss, so it does one hash per port plus one.
- **`AssignmentSimplifier`** (`assignment_simplifier.rs`) is the worst asymptotic in the backend.
  `find_all_assigns` (`:23-32`) loops `while let Some(i) = find_first_assign()` and
  `find_first_assign` (`:15-21`) is `position(... all(...))`, which is `O(k²)`, so the loop is
  **`O(k³)`**, plus `Vec::remove` shifts. `find_first_swap` (`:34-52`) is `O(k²)` with
  `path.contains`. It is called on every region entry (`code_handler.rs:106-134`), and `k` is the
  boundary width, `D + L + 1` before DPE and still tens to hundreds after. At `k = 300` that is
  about `2.7·10^7` comparisons for one boundary.
- `handle_lambda_out` (`Builder/src/lib.rs:87-89`) filters locals with `arguments.contains` and
  `dependencies.iter().any`, which is `O(locals × (A + D))` per function. `handle_omega_out`
  (`:162`) does a `Vec::remove`. Both are minor.
- The tree boxes every `Statement` payload (`Tree/src/statement.rs:157-190`) and 30 expression
  fields (`Tree/src/expression.rs`). That is one allocation per statement, and the whole tree is
  materialized before printing (`CLI/src/targets/luanoffi.rs:52-57`), so for the 8 MB output case
  the tree's peak memory adds on top of the graph's.

### 1.9 Printer

- **Runtime library parsing on every compile.** `Sections::with_built_ins`
  (`library/sections.rs:200-223`) parses 11 embedded sources (~128 KB, `runtime/`). For each
  section it scans every line for definitions (`:69-77`) and every identifier for mentions
  (`:84-103`: char-by-char `find` with closures, push, `sort_unstable`, `dedup`), then sorts the
  sections and the owner table (`:246-277`). All of it is a pure function of `include_str!`
  inputs. Natively this is well under a millisecond. Self-hosted, it is a per-compile constant of
  hundreds of thousands of closure calls and UTF-8 decodes, paid even for a 10-line module.
- **`NamesFinder` runs twice** over the whole tree (`CLI/src/targets/luanoffi.rs:31` and `:44`),
  and it pushes *every occurrence* of a runtime helper name, not every distinct name
  (`library/names_finder.rs:634-653`). The `Vec` grows to one entry per helper use (tens of
  thousands on the big fixtures) before `sort_unstable` + `dedup` (`Printer/src/lib.rs:86-90`).
  `Captures::of` (`captures.rs:158-170`, called at `expression.rs:265`) is a third traversal per
  scoped function, with two hash maps.
- **Names.** Every `Name` print does an `exact_names` probe, then a `names` probe (a map that
  nothing ever inserts into: no `names.insert` exists in the crate), then
  `write!(out, "{prefix}_{id}_")` through `core::fmt` (`expression.rs:168-178`,
  `Printer/src/lib.rs:51-58`). The packed-dependency path allocates a fresh `Arc<str>` via
  `format!` per binding per function (`expression.rs:96-104`), and the prologue-alias loop clones
  `exact.to_owned()` into another `Arc` (`:121-128`). Table-backed module locals allocate one
  `format!` string per local (`statement.rs:783`).
- **Write granularity.** Output goes through `&mut dyn Write` (`Printer/src/print.rs:5-7`) to a 1 MB
  `BufWriter` (`CLI/src/main.rs:16-20`). The buffer size is fine. The cost is per call: every
  token is a `write!` → `fmt::write` → vtable call, and `tab()` (`Printer/src/lib.rs:46-48`)
  issues **one `write!` per indentation level**. `print_local_list`
  (`library/printer.rs:80-106`) issues two `write!`s per name. An 8 MB output is on the order
  of 10^6-10^7 dynamic `write_fmt` calls.

### 1.10 Other whole-module costs

- `wasmparser::Validator::validate_all` (`CLI/src/sources/web_assembly.rs`) is a full extra parse
  before lifting. It is necessary for safety, but it could be fused with lifting by driving
  `Validator::payload`/`FuncValidator` alongside the lifter. That is a small native win and a
  large self-hosted one.
- The lifted graph is one module-wide graph: lifting, optimization, allocation, tree building
  and printing are strictly phase-sequential over the whole module, so peak memory is the
  **sum** of graph + tree + output buffers, not the max per function.

---

## 2. Hypotheses

Each entry gives: the change, expected effect on time and memory (native / self-hosted), risk,
a sketch, and what to measure. The effects are reading-based guesses meant to be falsified.

### H1 — `u32` words in `set::Set` on 32-bit targets

- **Change:** `type Inner = usize` (or `u32` under `cfg(target_pointer_width = "32")`) in a
  vendored/`[patch]`ed `set` crate.
- **Effect:** none natively. Self-hosted: *large*. Every `contains` / `grow_insert` /
  `count_ones` / ascending-iterator step is currently a 64-bit shift/and/or that `lua-no-ffi`
  lowers to `rt_*_i64` calls allocating `{lo, hi}` tables. I would expect the bitset-heavy phases
  (DFS in normalizer, DPE, argument finder, liveness) to drop by a large constant factor and GC
  pressure to drop sharply.
- **Risk:** low. It is a representation change behind the same API, but the crate belongs to the
  upstream author, so the fork has to vendor it.
- **Measure:** count `rt_*_i64` call sites in the generated fixture Lua before/after; wall time
  and `collectgarbage("count")` peak of the fixture probes.

### H2 — A 32-bit-friendly hasher, or no hashing at all

- **Change:** replace foldhash with a `u32` multiply-xorshift hasher (FxHash-32 style) on 32-bit
  targets, via `HashMap<K, V, BuildHasherDefault<Fx32>>` type aliases in one place. H3 then
  removes most maps entirely.
- **Effect:** native: neutral to slightly positive. Self-hosted: large for every map in §1.5
  (`Link`'s derived `Hash` feeds two `write_*` calls into 64-bit mixing today).
- **Risk:** low. Maps are not iterated for output order anywhere I found. Before switching,
  check with a grep for `.iter()` over maps that output order does not depend on hash order.
- **Measure:** same as H1, plus native `perf stat` to confirm no regression.

### H3 — Per-node port offset table; dense `Vec` instead of `Link`/`u32` maps

- **Change:** after each normalization, compute `offset[id] = Σ_{j<id} ports(j)` (one pass, `4N`
  bytes). Then `Link(id, p) ↦ offset[id] + p` is a dense index in `0..P`. Use it for the DPE
  `seen` set (exact size `P`, no stride), for DPE/mover renames (`Vec<Link>` with a sentinel),
  and in the backend for `preferences` and `assignments` (`Vec<Link>`, `Vec<Local>`).
  `ScalarFinder::handled` becomes a 2-bit-per-node `Vec<u8>`, and `declarations`,
  `CodeHandler::regions`, `DataHandler::expressions` become `Vec<Option<_>>` indexed by id
  (or by a per-function local index to keep them small).
- **Effect:** DPE memory goes from `N·W` bits to `P` bits (≈ 100× less in the wide-node case of
  §1.3) and the 32-bit overflow disappears. The backend loses a hash per port lookup. Natively
  this is a solid constant-factor win. Self-hosted it is the biggest single win after H1, since it
  deletes the hashing entirely.
- **Risk:** medium. Offsets are invalidated by any pass that changes port counts, so they must be
  recomputed or passes must be ordered so they read a fresh table. `Vec<Option<Expression>>`
  sized to `N` is larger than today's sparse map when few expressions are in flight, so use a
  per-function window.
- **Measure:** peak RSS (`/usr/bin/time -f %M`) and DPE time on the largest fixture; allocation
  counter (§4) for the backend.

### H4 — Worklist / change-tracked rounds instead of whole-module fixed point

- **Change:** keep the round structure but make every pass report *which* nodes/regions it
  touched (a `Set` of dirty lambda ids is enough). The next round then runs mover, DPE and ISLE
  only inside dirty lambdas, and the normalizer only re-sorts if nodes were appended or died. A
  cheaper first step: iterate to a fixed point **per lambda** (every lambda occupies a
  contiguous id range after normalization, `region_scope.rs:20-28` relies on the same fact), so
  one slow function no longer drags the whole module through extra rounds.
- **Effect:** time `K × 7(N+E)` → roughly `7(N+E) + Σ_dirty (K_f × 7(N_f+E_f))`. For modules
  where a few functions need many rounds, the saving is close to `(K-1)/K` of optimizer time.
  Memory is unchanged.
- **Risk:** medium-high. The mover and DPE have cross-region effects (a removed output port of a
  lambda changes its callers' `Apply`), so dirtiness must propagate to consumers. The cheap
  first step, a per-lambda loop, is safer because lambdas only interact via their `LambdaIn`
  dependencies.
- **Measure:** instrument `K` and nodes changed per round first (§4.1). If `K ≤ 3` on the real
  fixtures, H4 is not worth its risk and H5/H6 matter more.

### H5 — Single fused sweep: normalize + rename + identity removal

- **Change:** fold `region_identity::remove` and the rename maps of mover/DPE into the
  normalizer's edge rewrite: while rewriting `id → post[id]`, first resolve renames and forward
  through identities. Skip `region_identity::remove` entirely in rounds where ISLE applied
  nothing (it is the only source of identities in the loop, `pipeline.rs:99-100`). Keep the
  normalizer's scratch `Vec<Node>` but `clear()` it right after the swap so dead nodes' heap
  memory is released immediately (§1.2).
- **Effect:** saves 2-3 of the ~7 full sweeps per round, i.e. about 30-40 % of optimizer time,
  and trims transient memory.
- **Risk:** low-medium. It is purely mechanical, but region scoping is subtle
  (`isle/context.rs:11-19`); `assert_scoped` in debug guards it.
- **Measure:** optimizer wall time split per pass (§4.1).

### H6 — ISLE: ascending sweep, candidate list, visit appended nodes

- **Change:** iterate ids ascending so producers settle before consumers, and extend the loop to
  nodes appended during the sweep (`while id < graph.len()`). Build the list of
  `IntegerBinaryOperation` ids during the normalizer's DFS and iterate only that.
- **Effect:** fewer rounds (`K`), and ISLE cost proportional to candidates instead of `N`.
- **Risk:** medium, because output may change. Rules that were tuned against spills
  (`isle/mod.rs:98-104`, reassociation disabled at `IR/Visitor/isle/iNN.isle`) may now fire in
  different combinations. Compare line/spill counts on `libjpeg_turbo_mjpeg` and `lodepng`
  before accepting.
- **Measure:** `K`, ISLE applications per round, and the copy/spill metrics from
  `upstream-review.md`.

### H7 — Thread only used dependencies through regions at lift time

- **Change:** compute per-region *reference liveness* the same way `LocalTracker` computes local
  liveness (`Liveness/src/locals.rs`), and let `get_active_bindings`/`set_active_bindings`
  (`basic_block_lifter.rs:129-160`) pass only dependencies that are used inside or after the
  region instead of all `D`.
- **Effect:** initial `P` drops from `Σ_regions(D + L)` to `Σ_regions(D_used + L)`. The first DPE
  round has far less to remove, `W` drops (which also fixes §1.3 without H3), and the unoptimized
  path (no `-o`, which never runs DPE) gets narrower boundaries. That means smaller `k` for the
  `O(k³)` sequencer and fewer locals. Possibly the largest *memory* win for the lifted graph.
- **Risk:** medium. Mutable dependencies (memories, mutable globals) are state tokens that must
  still be threaded where written. A missed dependency is a region-scope violation, which
  `assert_scoped` catches in debug.
- **Measure:** `P` and `W` right after lifting, peak RSS, and output diff on the conformance suite.

### H8 — `O(k)` parallel-move sequencing

- **Change:** replace `AssignmentSimplifier` with the standard algorithm: count readers per
  source, emit moves whose destination has zero pending readers from a worklist, then break the
  remaining pure cycles. `SwapAll` already exists for that (`code_handler.rs:124-133`).
- **Effect:** `O(k³)` → `O(k log k)` or `O(k)` per region boundary. Natively this matters only for
  wide boundaries; self-hosted, cubic loops are painful at any `k` above a few dozen.
- **Risk:** medium. This is exactly bug class B in `verification.md`
  ("backend move sequencing"), so it must land together with that note's P4 property test.
  Emission order will change, so compare outputs semantically, not textually.
- **Measure:** backend time on the widest-boundary fixture, plus the P4 property test.

### H9 — Local allocator: bitset free list, `O(1)` revive

- **Change:** keep a free-name bitset alongside (or instead of) `free: BinaryHeap<u32>`
  (`index_provider.rs:11`). `try_revive` becomes a bit test + clear and `pull` takes the highest
  set bit (matching today's max-heap order, so output is identical). Holds can stay a heap.
- **Effect:** `O(F)` + heapify per revive → `O(1)` (plus `O(F/32)` to find the highest bit on
  pull). Most visible on spill-heavy functions.
- **Risk:** low if pop order is preserved exactly; any change of order shows up as a diff in
  generated names.
- **Measure:** byte-identical output on all fixtures, plus allocator time.

### H10 — Build-time runtime section table (`build.rs`)

- **Change:** a `build.rs` in `luanoffi-printer` runs today's `Section::try_parse` logic on the
  11 runtime files at build time and emits a `static SECTIONS: [Section; M]` with `references`,
  `defines`, owner table, and *precomputed transitive dependency closures* as `&'static [u16]`
  section indices. Mentions only matter for resolution, so they can be folded into the closure
  and dropped. `with_built_ins` becomes a `const` reference, and the duplicate-name asserts become
  build errors.
- **Effect:** removes a fixed per-compile cost: tiny natively (< 1 ms), large self-hosted (all the
  char scanning), and it makes the runtime table zero-allocation. Resolution becomes a bitset OR
  over precomputed closures.
- **Risk:** low. The main hazard is that editing a `.lua` file has to rebuild, which
  `cargo:rerun-if-changed` handles. `AGENTS.md` already asks for a rebuild after runtime edits.
- **Measure:** printer time on a tiny module (where this dominates), and the self-hosted printer
  once it is in scope.

### H11 — Runtime-name set instead of name occurrences; one names pass

- **Change:** give each section a dense index (from H10). `NamesFinder` sets bits in a
  `[u32; M/32]` instead of pushing `&'static str` per occurrence, and it runs once, with the
  result shared by `print_library` and `print_tree` (`CLI/src/targets/luanoffi.rs:27-50`).
  `Captures` can use the same bitset per function, and its `locals` count map can become a `Vec`
  indexed by `Name.id - function_first_local`.
- **Effect:** removes one full tree traversal and an `O(uses log uses)` sort. Memory: tens of
  thousands of entries → a few words.
- **Risk:** low.
- **Measure:** printer time split (§4.1).

### H12 — Interned name strings indexed by `Name.id`

- **Change:** replace `exact_names: HashMap<Name, Arc<str>>` and the always-empty `names` map
  with a `Vec<NameText>` indexed by `Name.id` (ids are dense and module-global,
  `local_provider.rs:46-58`), where `NameText` is either "default `loc_{id}_`" or a small inline
  string/index into a string arena. Use a save/restore stack for the packed-dependency override
  (`expression.rs:96-148`) instead of `take`/`set` with fresh `Arc`s. Print `loc_{id}_` via a
  hand-written itoa into a stack buffer.
- **Effect:** one array load per name instead of two hash probes and a `core::fmt` call. It also
  removes `Arc<str>` allocate/free churn per function binding. Printing names is plausibly the
  hottest printer path (every expression mentions one or more).
- **Risk:** low.
- **Measure:** `perf record` share of `Name::print` before/after.

### H13 — Coarser writes, static indentation, generic writer

- **Change:** `tab()` writes `&TABS[..depth]` from a static `"\t\t\t…"` with one `write_all`.
  Constant tokens use `write_all(b"...")` instead of `write!`. Make `Print` generic over
  `W: Write` (or print into a `Vec<u8>` per function and `write_all` it once) instead of
  `&mut dyn Write`.
- **Effect:** removes the per-token vtable + `fmt::Arguments` overhead. Natively maybe 10-30 % of
  print time. Self-hosted it matters more, since `call_indirect` and `core::fmt` expand heavily in
  wasm.
- **Risk:** low. A generic `Print` increases monomorphized code size, so check wasm size for the
  self-host build.
- **Measure:** printer time; `.wasm` size of a self-hosted printer build.

### H14 — Arena/bump allocation per phase for node port lists and tree nodes

- **Change:** (a) store all node port lists in one `Vec<Link>` pool with `(start, len)` in the
  node (CSR layout), rebuilt by the normalizer each round. That gives one allocation instead of
  one per control node, and it makes H3's offsets free. (b) Allocate the tree in a typed arena
  (or `Vec<Statement>` pools with indices) instead of `Box` per statement.
- **Effect:** allocation *count* drops by roughly the number of control nodes + statements; cache
  locality improves in every full scan. On the self-host bump allocator it removes the per-growth
  leak of every small `Vec`.
- **Risk:** high for (a). It is a structural change to `ir-graph` touching every pass and both
  front ends. (b) is medium and confined to Tree/Builder/Printer. Do (b) or H15 first; do (a) only
  if §4 shows allocator time is significant.
- **Measure:** allocation counter (§4.2), `perf` share of `malloc`/`free`.

### H15 — Streaming output per function

- **Change:** build and print one lambda at a time. The builder already processes nodes in id
  order and lambdas are contiguous. Emit each function's text as soon as its `LambdaOut` is
  handled, keep only the module-level skeleton, and drop the function's tree. The
  runtime-library header must come first, so either buffer function texts (bytes are much
  smaller than trees) or do a cheap pre-pass for runtime names on the graph.
- **Effect:** peak memory of the tree phase goes from `O(whole tree)` to `O(largest function)`
  + the output buffer. Time is neutral.
- **Risk:** medium. `Captures`/packing decisions are per function and fine, but module-level
  decisions (`table_backed_locals`, `statement.rs:760-798`) must be known before the first
  function prints.
- **Measure:** peak RSS on the 553 KB / 8 MB case.

### H16 — Parallel per-function lifting and tree building (native only)

- **Change:** behind a `std`/`parallel` feature of the CLI, lift function bodies into
  per-function graphs in parallel (wasmparser bodies are independent; `GlobalState` is
  read-only after the declaration sections) and splice them into the module graph. Likewise,
  run structurer + liveness per function in parallel, and run H15's per-function print in
  parallel with ordered output. `no_std` crates stay single-threaded; only the CLI orchestrates.
- **Effect:** native wall time ≈ `/cores` for lift and build. **Zero** for self-hosting (no
  threads under Lua).
- **Risk:** medium: graph splicing requires id relocation, which the normalizer already does
  (`handle_edges`), and output determinism must be preserved.
- **Measure:** wall vs CPU time; byte-identical output across thread counts.

### H17 — Real allocator in the self-hosting fixture

- **Change:** replace the fixture's bump allocator (`self-hosting-luanoffi-builder/src/lib.rs:53-93`,
  `dealloc` is a no-op) with a small size-class free-list allocator, or `dlmalloc`, and compare
  wasm size, Lua size and run time.
- **Effect:** memory in the self-hosted run goes from "total bytes ever allocated" to "live
  bytes". Every `Vec` doubling, `Set` growth and hash rehash stops being permanent. Time may go up
  slightly (more code on the alloc path) or down (smaller heap → cheaper `memory.grow`, less
  buffer paging in `lua-no-ffi`).
- **Risk:** low. The fixture is test scaffolding, but its hashes must stay bit-identical to
  wasmtime.
- **Measure:** `collectgarbage("count")` + `memory.size` at exit; fixture probe times.

### H18 — Fuse validation with lifting

- **Change:** drive `wasmparser::Validator` payload-by-payload inside the lifter's own section
  loop, and `FuncValidator` per body while the builder walks operators, instead of
  `validate_all` up front.
- **Effect:** one parse instead of two. Small natively (validation is fast); meaningful
  self-hosted, once the front end is in scope.
- **Risk:** low-medium: error reporting moves later, and a malformed module must still be
  rejected before any `unwrap` in the lifter panics.
- **Measure:** front-end time on the largest module.

---

## 3. What matters for self-hosting, and an ordered plan

### 3.1 Why the priorities differ from the native case

The self-hosting path compiles the compiler to `wasm32-unknown-unknown` and runs it under
`lua-no-ffi` on LuaJIT. Four properties of that environment reorder everything:

1. **64-bit integers are the most expensive thing in it.** An `i64` is a heap table `{lo, hi}`
   and every operation is a runtime call that allocates (`buffer.lua:556-563`,
   `runtime/core/i64.lua` sections `add_i64` … `rotate_right_i64`). `usize` is 32-bit, so
   ordinary indexing is cheap, but `u64` bitset words (`set`), foldhash's 64-bit mixing, `Link`
   packing via `into_u64` (`IR/Graph/src/link.rs:16-18`) and `i64` node payloads are not.
   **H1 and H2 are worth more than any algorithmic change**, and they are nearly free.
2. **The fixture allocator never frees.** Allocation *bytes*, not just live bytes, are the
   memory footprint. Anything that grows geometrically or rehashes leaks its history. H17 fixes
   the environment; H3/H14 reduce the demand.
3. **No threads.** H16 is irrelevant there; it is a native-only convenience.
4. **Every indirect call and every `core::fmt` expansion is expensive** (`call_indirect` → a
   table lookup in Lua; `fmt` pulls in large generic code). H12/H13 matter more than natively,
   but only once the printer is self-hosted (out of scope for v1 per the fixture README).

The v1 fixture self-hosts `ir-graph` + `luanoffi-tree` + `luanoffi-builder` only. Of the hot spots
above, it exercises the local allocator (§1.8: `hashbrown` maps, `Set` in `ArgumentFinder`,
`BinaryHeap` revive), the assignment simplifier, and the `list`/`Set` crates. It does *not* yet
exercise the optimizer, the front end or the printer.

### 3.2 Ordered plan

Each step is independently shippable and ends with the self-hosting fixture's 15 probe values
unchanged (`tests/manual/self-hosting-luanoffi-builder/README.md`, "Verified output") plus the
conformance suites.

0. **Measure first (§4).** Add round/pass counters and a counting global allocator. Record `K`,
   `N`, `E`, `P`, `W` after lifting and after each round, per-pass wall time, allocation
   count/bytes per phase, and the fixture's Lua-side time and GC peak. Without `K` it is
   impossible to rank H4 against H5/H6.
1. **H1 (u32 set words) + H2 (32-bit hasher).** Smallest diffs, largest expected self-hosted
   effect, no output change. Verify by counting `rt_*_i64` sites in the regenerated fixture Lua.
2. **H17 (real allocator in the fixture).** Makes every later memory measurement meaningful.
3. **H9 (bitset free list) + H8 (`O(k)` move sequencer, with `verification.md` P4).** They sit on
   the path the fixture already runs; H9 is output-identical, H8 is not and needs the property
   test.
4. **H3 (port offset table, dense maps).** Start with the backend maps (`preferences`,
   `assignments`, `handled`) that the fixture exercises, then the DPE bitset. This also closes
   the 32-bit overflow in §1.3 before the optimizer is ever self-hosted.
5. **H7 (used-only dependencies at lift).** The largest reduction of graph *size*. It helps
   native RSS on the 553 KB case and shrinks every later phase.
6. **H5 (fused sweep) → H6 (ISLE order) → H4 (per-lambda fixed point)**, in that order and only
   as far as the step-0 numbers justify.
7. **H10 + H11 (build-time section table, one names pass)**, then **H12 + H13** when the printer
   joins the self-hosting scope.
8. **H14(b)/H15 (tree arena, streaming)** for native peak memory on the 8 MB output case;
   **H18** when the front end joins the self-hosting scope.
9. **H16 (parallel)** last, native-only, behind a feature flag. **H14(a) (CSR port pool)** only if
   allocator time still shows up in profiles after all of the above.

---

## 4. How to measure later

### 4.1 Native

- **Phase timers:** a `SPIDER_STATS=1` env switch in the CLI that prints, to stderr, the wall time
  of validate / lift / each optimizer round (with per-pass split) / post-process / allocate /
  build tree / print library / print tree, and the graph metrics `N, E, P, W` after lift and
  after each round, plus `K`. Use `std::time::Instant` in the CLI only; the `no_std` passes
  return counts.
- **`perf stat -e task-clock,page-faults,cache-misses`** and **`perf record -g`** on the largest
  fixture with `-o` and without. Expect `Node::for_each_argument`, the normalizer, `hashbrown`
  probes and `Name::print`/`fmt::write` near the top.
- **Peak RSS:** `/usr/bin/time -f "%e s %M KB"`, as in `lua-no-ffi-performance-hypotheses.md`.
  Take the minimum of ≥ 5 runs for time and the max RSS.
- **`cargo build --timings`** measures *build* time of the compiler crates, not compile speed of
  the tool. Use it to check that H10's `build.rs` and H13's generic printing do not blow up build
  times or codegen units.
- **Allocation counters:** a `#[global_allocator]` wrapper in the CLI (behind the same env or a
  feature) that counts calls and bytes to `alloc`/`realloc`/`dealloc`, snapshotted at each phase
  boundary. Alternatively, `heaptrack` or `valgrind --tool=dhat` for allocation-site attribution.

### 4.2 Self-hosted

- Wrap each fixture probe in `os.clock()` (min of N runs) and record
  `collectgarbage("count")` before/after, plus the wasm `memory.size` the module reaches.
- Count `rt_*_i64` / `into_bits_i64` call sites and `call_indirect` sites in the generated Lua
  (`grep -c`) as a static proxy for H1/H2/H13.
- The fixture's bump allocator already knows the total bytes allocated. Export it as a probe
  (`builder_probe_heap_bytes`) so every hypothesis gets an allocation-bytes number without extra
  tooling.
- `luajit -jv` on the fixture to see whether the hot loops of the self-hosted builder trace at
  all (NYI on `{lo, hi}` table allocation paths is likely), in the spirit of
  `verification.md` P10.

### 4.3 Guard rails

- Byte-identical output is required for H1, H2, H3, H5, H9, H10, H11, H12, H13, H14, H15, H16,
  H17 and H18. H4, H6, H7 and H8 may legitimately change output and must be judged on the
  conformance suites plus the copy/spill/line metrics used in `upstream-review.md`.
- The self-hosting fixture's 15 probe values must stay bit-identical to wasmtime after every
  step.
