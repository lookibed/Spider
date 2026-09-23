# Target Lowering in the Fork's Architecture — A Design Study

Status: **research only.** Nothing was built, run or measured for this note; every claim is
derived from the checked-in source and is cited `file:line`. Numbers quoted from other notes
carry their source.

Written: `2026-09-21`.

Companion notes:
[`upstream-review.md`](../upstream-review.md) §"Обязательно портировать" item 1 (what upstream
did and what it bought), [`lua-no-ffi-performance-hypotheses.md`](../lua-no-ffi-performance-hypotheses.md)
(the memory/value representation this lowering has to target),
[`problem_lua_limits.md`](../problem_lua_limits.md) (the limits lowering moves).

---

## 0. The one-paragraph version

Upstream lowers `MemoryLoad`/`IntegerBinaryOperation` into subgraphs of target-level nodes
*inside the IR, before optimization*, and at `-O3` this removed all 16 671 `rt_load/store_*`
calls and all 18 937 `rt_add_i32` calls on a 375 KB fixture, and cut module-level locals from
100 to 35 (`upstream-review.md:13-14,28-31`). This fork can do the same without a second graph
type, because its `DataFlowGraph` is a flat `Vec<Node>` that any pass may append to
(`IR/Graph/src/lib.rs:24-26,88-94`) and the topological normalizer re-sorts the whole thing at
the top of every optimizer round (`IR/Visitor/src/pipeline.rs:81`,
`IR/Visitor/src/topological_normalizer.rs:111-114`). The three things that are genuinely hard
here are **(a)** keeping the state ports and trap fences intact, **(b)** not re-triggering the
live-range regression that already forced three ISLE reassociation rules to be disabled
(`IR/Visitor/isle/iNN.isle:39-54`) and the invariant port mover to be restricted to constants
(`IR/Visitor/src/control/invariant_port_mover.rs:94-113`), and **(c)** the fact that the target
is not known at the point where the graph is optimized (`CLI/src/main.rs:22-34`).

---

## 1. The lowerability rule, derived from the code

A runtime helper can become an **expression** only if its body is branch-free and
statement-free. This is not a style preference; it is forced by the tree:
`luanoffi_tree::expression::Expression` (`Targets/LuaNoFFI/Tree/src/expression.rs:389-476`) has
no conditional and no `error()` form, and all control lives in `Statement`
(`Targets/LuaNoFFI/Tree/src/statement.rs`). A helper whose body contains an `if` can only be
lowered by materialising a real `Gamma` region, which the builder prints as a Lua `if`
(`Targets/LuaNoFFI/Printer/src/statement.rs:272-287`) and which forces every value crossing it
into a local (`Targets/LuaNoFFI/Builder/src/local_allocator/reference_finder.rs:38-96`).

So the families sort themselves:

| Family | Current emission | Body shape | Verdict |
| --- | --- | --- | --- |
| aligned `i32` load | `buffer_read_i32(m[1], base, off)`, `Printer/src/expression.rs:863-866` | one bounds `if`, then `words[slot]` when `shift == 0`, `buffer.lua:354-370` | **Lower the accessor; split the check out** (§4) |
| aligned `i32` store | `rt_store_i32(...)`, `Printer/src/statement.rs:582-604` | same shape, `buffer.lua:453-476` | **Lower** (statement form) |
| `i32.add`/`sub` | already inlined as `bit32_or(a + b, 0)`, `Printer/src/expression.rs:496-509` | branch-free | **Lower** — see §1.1 |
| `i32` and/or/xor/shl/shr/rotl/rotr | `rt_and_i32` etc., which are *aliases* of `bit32_*` (`runtime/core/i32.lua:148-213`) | branch-free | **Lower** — nearly free |
| `i32` comparisons | `rt_less_than_s32(a,b)` + `(x and 1 or 0)`, `Printer/src/expression.rs:527-543,445-455` | `force_s32` twice then `<`, `runtime/core/i32.lua:229-243` | **Lower** — highest ratio (§7) |
| `i32.mul` | `rt_multiply_i32`, `runtime/core/i32.lua:44-56` | branch-free, 4 shifts + 3 muls + 1 or | **Lower** |
| `i32` div/rem | `rt_divide_s32`, `runtime/core/i32.lua:74-90` | **two `error()` branches** | **Keep a call** |
| `clz`/`ctz`/`popcnt` | `runtime/core/i32.lua:4-21` | `popcnt` is branch-free but 6 statements | Lower only if measured; low frequency |
| `i64` add/sub/bitwise/shift | `rt_add_i64` on `{lo,hi}` tables | branch-free once `(lo,hi)` are two SSA values | **Lower, after** the representation change (Step 5 of the perf plan) |
| `i64` mul/div/rem | | branching | **Keep a call** |
| `f32` arithmetic | `from_bits`→op→`into_bits`, `runtime/builtin/buffer.lua:606-697` | `round_f32` has 2 early-outs (`lua-no-ffi-performance-hypotheses.md:295-311`) | **Lower the Veltkamp fast path only**, keep a slow call |
| `f64` arithmetic | native | already an expression | nothing to do |
| bounds check | inside every accessor | one `if` + `error` | **Lower to its own statement node**, then merge (§4) |
| traps / `unreachable` | `error('unreachable code')`, `Printer/src/expression.rs:918` | statement | **Keep** |
| `memory.grow` / `size` / `copy` / `fill` / `drop` | `runtime/core/memory.lua:221-269` | loops, realloc | **Keep** |
| table ops, `function_type`, imports | | | **Keep** |
| saturating `trunc_sat_*` | `runtime/core/f32.lua` etc. | branching | **Keep** |

### 1.1 The printer already lowers, at the wrong layer

`Printer/src/expression.rs:495-509` special-cases `(I32, Add|Subtract)` into
`bit32_or(lhs + rhs, 0)`, and `:863-866` special-cases `LoadType::I32` into
`buffer_read_i32(ref[1], ...)`. Both produce the right text and both are invisible to the
optimizer: CSE cannot see that two loads share `ref[1]`, the ISLE rules cannot see the `+`, and
`Captures` (`Printer/src/captures.rs:47-59`) still counts `bit32_or` as an upvalue. **Moving
these two special cases into the IR is the smallest possible proof that the mechanism works**,
because the generated text should come out byte-identical on the first cut.

---

## 2. What the new node kind should be

### 2.1 The extension point that already exists

`Node::Host(Box<dyn Host>)` (`IR/Graph/src/node/mod.rs:55-56`) with the `Host` trait
(`IR/Graph/src/node/simple.rs:9-32`) is exactly the shape a foreign-node family needs:
`identifier()`, `for_each_id`, `for_each_mut_id`, `for_each_argument`, `for_each_mut_argument`.
It is already threaded through the generic visitor (`IR/Graph/src/node/sources.rs:40`), dead
port elimination (`dead_port_eliminator.rs:176` falls into `mark_operation`), the invariant port
mover (`invariant_port_mover.rs:144`, ignored), region identity (`region_identity.rs:91`,
ignored), constant isolation (`constant_isolator.rs:25`, correctly not clonable) and the JSON
printer (`Targets/Json/src/label.rs:28`).

It is, however, **not usable as-is**, in four specific places:

1. `scalar_finder::result_count_of` returns `0` for `Host`
   (`Builder/src/local_allocator/scalar_finder.rs:25`). A lowered node that produces a value
   would never get a local, and `DataHandler::load` would then take the `expressions.remove`
   path and panic on the second consumer (`Builder/src/data_handler.rs:56-65`).
2. `Node::ports_output` returns `None` for `Host` (`IR/Graph/src/node/sinks.rs:954-1016`), so
   `DeadPortEliminator::sweep_outputs` skips it (`dead_port_eliminator.rs:225-228`).
3. `for_each_requirement` does not dispatch to `Host` (`IR/Graph/src/node/sources.rs:496-556`).
   For a *pure* node that is correct — ordering then comes only from the argument links, which
   is what we want — but it must be a conscious decision, not an omission.
4. `LuaNoFFIBuilder::handle_host` is `unimplemented!()` (`Builder/src/lib.rs:183-189`), and the
   same hole exists in the LuaJIT and Luau builders (`Targets/LuaJIT/Builder/src/lib.rs:187`,
   `Targets/Luau/Builder/src/lib.rs:187`).

And one structural blocker: **ISLE cannot match through `Box<dyn Host>`.** Every extractor is
an `extern extractor` over a concrete variant (`IR/Visitor/src/isle/context.rs:114-276`,
declarations in `IR/Visitor/isle/types.memory.isle:1-21`). Matching a `dyn Host` needs an
`Any` downcast the trait does not offer, and the whole point of lowering is that the ISLE rules
then work *inside* the former helper body.

### 2.2 Three options

**Option A — extend `Host`.** Add `fn as_any(&self) -> &dyn Any` and `fn results(&self) -> u16`,
fix the four sites above. Cheapest in lines; worst in ergonomics, because every ISLE extractor
becomes a downcast chain and the opcode is a `&'static str`.

**Option B — a new `Node::Lowered` variant (recommended).**

```rust
/// A target-lowered operation. The IR assigns no meaning to `opcode`.
pub struct Lowered {
    pub target: u8,                       // which target crate owns `opcode`
    pub opcode: u16,                      // opaque to ir-graph
    pub operands: Resizable<Link, 4>,
    pub results: u16,
    pub traps: bool,                      // participates in the fence chain
}
```

Target neutrality is preserved because `ir-graph` never interprets `opcode`; the LuaNoFFI crate
owns a `#[repr(u16)] enum Opcode { LoadWord, StoreWord, TobitAdd, BitAnd, ... }` and each
builder asserts `target == Self::TARGET` before handling the node, so a `Lowered` node can never
silently leak into a target that did not produce it.

The cost is one match arm in each exhaustive `match` over `Node`. There are about a dozen:
`sources.rs:26-83` (the `for_each_visit!` macro, one line), `sinks.rs:954-1016`, `:1020-1082`,
`:1086-1148`, `isle/mod.rs:105-165`, `isle/context.rs:12-75`, `region_identity.rs:69-136`,
`invariant_port_mover.rs:131-191`, `dead_port_eliminator.rs:162-222`,
`constant_isolator.rs:10-70`, `scalar_finder.rs:4-67`, `reference_finder.rs:279-341`,
`Builder/src/lib.rs:555-622`, plus the three sibling targets and `Targets/Json/src/label.rs`,
`color.rs`. Because they are exhaustive (the only wildcard in the repo is
`argument_finder.rs:9-12`), the compiler enumerates every one of them — this is a guided,
mechanical change, not a search.

**Option C — a separate late pass producing a target-specific graph.** This is what upstream
did (`Targets/LuaNoFFI/{Foreign,Lower}` crates, `upstream-review.md:30`). In *their*
architecture each region owns its own `Vec<Node>`, so a second graph type is cheap. Here it is
not: every pass matches exhaustively on `Node`, so a second node type means a second
normalizer, a second DPE, a second invariant mover and a second ISLE rule set — roughly 1 500
lines duplicated, with two copies of the `find_stride`/`seen`-set logic to keep in sync.

**Verdict: Option B.** One variant, ~16 arms, a `target` tag for hygiene, and the whole existing
pass suite applies unchanged.

### 2.3 ISLE integration

`IR/Visitor/build.rs:43-50` compiles every file in `IR/Visitor/isle/`, so a new
`lowered.isle` + `types.lowered.isle` pair needs no build-script change. One extern extractor
suffices:

```lisp
(decl Lowered (u8 u16 Link Link) Link)
(extern extractor Lowered get_lowered)
```

with `get_lowered` following the existing pattern of running `find_first_producer` on each
operand (`isle/context.rs:114-132`). Dispatch is already per-variant
(`isle/mod.rs:105-165`), so a `Node::Lowered(_) => simplify_lowered(graph, id)` arm keeps the
sweep proportional to the nodes a rule could rewrite, as the doc comment there requires.

---

## 3. How the existing invariants interact

### 3.1 Topological normalizer

`DepthFirstSearcher::add_predecessors` (`topological_normalizer.rs:28-35`) walks
`for_each_requirement` then `for_each_argument`, and `handle_nodes` (`:79-96`) rebuilds the
whole `Vec<Node>` in post-order, renumbering every id in `handle_edges` (`:98-108`). Two
consequences:

- **A lowering pass may append nodes in any order and never think about placement.** The
  normalizer runs first in every optimizer round (`pipeline.rs:81`) and again in
  `run_post_process` (`:105`).
- **A node not reachable from the omega output is silently deleted**, since `handle_nodes`
  only pushes what the DFS visits. A lowered store whose state port is no longer on the fence
  chain therefore *disappears*. This is the single most likely way to miscompile during
  stage 4.

### 3.2 Dead port elimination

`mark_operation` (`dead_port_eliminator.rs:153-155`) marks every argument of an ordinary node,
so a `Lowered` node needs no special handling to stay alive — provided something reads one of
its ports. `sweep_outputs` (`:225-243`) only runs when `ports_output` returns `Some`, so
returning `None` for `Lowered` is the conservative default: no port renumbering, no risk, at
the cost of not compacting dead results.

One quiet cost: `find_stride` (`:39-51`) sizes the dense `seen` bitset as
`node_count * (widest_port + 1)`. Today the widest port is small (`MemoryLoad` uses 2,
`MemoryCopy` 2, `Fence` as many as it has mutable dependencies). A lowered node with 4 results
would raise the stride for *every* node in the graph. **Keep lowered nodes at one or two
ports**; a two-port `(value, state)` shape matches `MemoryLoad` exactly and costs nothing.

### 3.3 `region_identity`

`remove` (`region_identity.rs:39-52`) folds identities away once per round (`pipeline.rs:89`),
so a lowering pass may produce `Identity` nodes freely, exactly as the ISLE driver does
(`isle/mod.rs:13-17,37-46`). `insert` (`:143-153`) runs only in `run_post_process`
(`pipeline.rs:101`) and exists to force `RegionOut`/`ThetaIn`/`ThetaOut` ports through locals so
the parallel move is ordered correctly.

**Therefore: lowering must run strictly before `run_post_process`.** After `insert`, the graph's
identities carry move-ordering meaning, and adding nodes between them would break the very
invariant they encode.

### 3.4 Pin-to-trap fences and state ports

`BasicBlockLifter::pin_to_trap` (`Sources/WebAssembly/Lifter/src/control_flow_lifter/basic_block_lifter.rs:49-53`)
chains a possibly-trapping value onto the trap token through a `Fence`, and `create_fence`
(`:55-70`) threads the trap token plus one port per mutable dependency. The DPE test at
`dead_port_eliminator.rs:364-380` is precisely a regression test for this: an unread division
survives elimination *only* when pinned.

Memory ops carry their ordering in a second way: `MemoryLoad` publishes
`RESULT_PORT = 0` and `STATE_PORT = 1` (`IR/Graph/src/node/sinks.rs:500-522`), the builder
renames the state port onto the memory reference (`Builder/src/lib.rs:469-479`) and
`reference_finder::handle_memory_load` (`:229-233`) makes the two share a local.

So a lowered load **must keep the same two ports with the same meanings**. If it does not,
`DataHandler::load_assign_all` (`data_handler.rs:85-93`) indexes `self.assignments[&link]` for a
link that was never assigned and panics — which is exactly the failure mode the upstream review
describes when it corrects the `Apply.results` false positive (`upstream-review.md:112`).

### 3.5 The `find_first_producer` see-through — the real correctness trap

`get_next_producer` (`isle/context.rs:12-75`) sees through `RegionIn` (to the enclosing gamma's
input port), through `GammaIn` arguments, and through `Identity`. That is what lets a rule
rooted *inside* a branch match an operand defined *outside* it.

Combined with §3.1, this means: **a node constructed by an ISLE right-hand side is appended at
the end of the flat vector, and the normalizer will then schedule it wherever its own operands
allow — which can be outside the region the matched node was in.** For a pure arithmetic node
that is a legal speculation. For a node that traps it is a miscompile: the trap fires on a path
where WebAssembly says it must not.

Two rules fall out, and they should be written as doc comments next to the new rule set:

1. **Never construct a trapping node on an ISLE right-hand side.** Rules may delete, merge or
   re-point trapping nodes, never create them.
2. `get_next_producer` must return `None` for `Node::Lowered` (the default for an unlisted
   variant), so that no rule accidentally looks *through* a lowered op.

### 3.6 The live-range hazard, restated

This is the reason to be cautious, and it is documented twice in the tree:

- `IR/Visitor/isle/iNN.isle:39-54`: three sound reassociation rules are disabled because
  "these rules change which values stay live across a region boundary, and the backend then
  mis-sequences that region's parallel move", miscompiling `real-world-miniz` (returns `-1997`
  instead of `58679047`) *while the conformance suites still pass*.
- `invariant_port_mover.rs:94-113`: lifting non-constant values out of a gamma cost "76% more
  copies and 20% more lines than not optimizing at all" on `libjpeg_turbo_mjpeg`.
- `isle/mod.rs:98-104`: memory/table/global forwarding is disabled by default because it
  raised spill sites from 1323 to 1874 on `libjpeg_turbo_mjpeg` and made `lodepng` 29% slower.

Lowering changes live ranges by construction. **Any lowering stage that shares a value between
two former helper bodies is doing the same thing that regressed those three times.** The
staged plan in §7 is ordered so that the first three stages share nothing.

### 3.7 The target is not known where optimization happens

`build_graph` (`CLI/src/main.rs:22-34`) lifts, optionally runs `run_all_optimizations`, then
unconditionally runs `run_post_process` — and only then does `print_graph` (`:36-47`) pick a
target. Lowering needs the target at optimization time, so the minimum plumbing is: thread
`Target` into `build_graph`, and add `CLI/src/common.rs::run_lowering(graph, omega, target)`
between the lift and `run_all_optimizations`. The conformance harness must make the same change
(`Conformance/tests/common/compiler.rs`) or it will stop exercising the same pipeline the CLI
does, which is the stated purpose of `pipeline.rs` (`:1-4`).

Also note that `run_post_process` runs **even without `-o`** (`main.rs:31`). If lowering is
gated on `-o`, the un-optimized output keeps every call and the two modes diverge much more than
today. Gating it on `-o` initially is the safe choice precisely because of that divergence being
visible and diffable.

---

## 4. Bounds checks after lowering

### 4.1 Where the check lives today

`buffer_read_i32` (`runtime/builtin/buffer.lua:354-370`):

```lua
local index = base + offset
if base < 0 or index + 4 > buf.__n then buffer_trap() end
```

and multi-word accesses call `buffer_check` first (`:127-136`, used by `rt_load_i64`
`runtime/core/memory.lua:124-137`). `buffer_trap` is `error(...)` (`buffer.lua:19-22`).

The perf note measures the check at **17% under the JIT and 57% in the interpreter**
(`lua-no-ffi-performance-hypotheses.md:148-165`) — "eliminating provably-in-range checks is
worth roughly as much as the entire helper-call overhead", which is why it is a stage-5 item and
not a stage-1 item.

### 4.2 Shape

The check traps, so by §1 it cannot be an `Expression`. It becomes a one-port
`Lowered(BoundsCheck){ memory, address, size } -> state` that the printer emits as a statement:

```lua
if a < 0 or a + 4 > m.__n then buffer_trap() end
```

and the accessor becomes a pure expression that no longer checks. The accessor must then
consume the check's state port, so that the normalizer cannot schedule the access before its
check and DPE cannot delete the check.

### 4.3 Merging rule, and why it is sound

Two checks `C(m, a, n₁)` and `C(m, a + k, n₂)` with `k` a non-negative constant merge into
`C(m, a, max(n₁, k + n₂))` when:

- both read the same memory *state* link after `find_first_producer`, i.e. nothing wrote `m`'s
  state between them, and
- neither is separated from the other by a region boundary.

The soundness argument comes straight from the runtime: `buffer_resize` only ever extends the
word array and only then publishes the new `__n` (`buffer.lua:142-152`), and `rt_memory_drop`
replaces the buffer wholesale (`runtime/core/memory.lua:264-269`). Both are state-port writers
on `m` (`sinks.rs:562-575,625-635`), so "same state link" is exactly "no grow and no drop in
between". Because `__n` is monotonically non-decreasing, **sinking a check is always sound and
hoisting one across a grow is not** — which is the direction the merge rule takes (it hoists the
*later* check to the *earlier* one's position). The merge is therefore only legal when the
earlier check's state link is the later one's transitive producer.

### 4.4 Trap ordering, and the one case that is not sound

For a run of **loads**, merging is unconditionally sound: loads have no effect, so no observable
state differs between "trap at the third load" and "trap before the first".

For a run of **stores**, it is not. WebAssembly says the stores preceding a trapping store
commit. A merged up-front check makes none of them commit. This is only observable if the host
inspects linear memory after catching the error — which the `tests/manual/*/main.lua` harnesses
could do. **Gate store-group merging behind a flag, default off**, and merge load groups
unconditionally.

### 4.5 Finding the dominating check without a dominator tree

There is no dominator information in this IR, and `get_region_range`
(`Builder/src/local_allocator/argument_finder.rs:13-30`) computes ranges only for
`Lambda`/`Omega`, not for `Gamma`/`Theta`. The cheap approximation that needs no new analysis is
**the state chain itself**: every memory op threads a state port (`sinks.rs:500-545`) and
`Fence` chains them (`basic_block_lifter.rs:49-70`). Walking the state link backwards from a
check, stopping at any `RegionIn`/`ThetaIn`, enumerates exactly the checks that dominate it
within the current basic block. That is "one check per basic block for consecutive accesses
with constant offsets" with no new data structure.

### 4.6 What *not* to do

Do not extend `InvariantPortMover` to hoist checks out of loops. It is restricted to
rematerializable values (`invariant_port_mover.rs:81-86`) for a measured reason
(`:94-113`), and a bounds check is not rematerializable. The loop win available without touching
that pass is hoisting `m.__w` and `m.__n` — two loop-invariant table reads, one local each —
which is precisely the lua-no-ffi-specific gain the upstream review calls out as *larger* here
than for Luau (`upstream-review.md:29`).

---

## 5. Interaction with the LuaJIT limits

### 5.1 Upvalues — lowering helps, and the mechanism is exact

`Captures::runtime_len` counts **distinct** helper names a body mentions
(`Printer/src/captures.rs:47-53`), and `packed_scoped_dependencies`
(`Printer/src/expression.rs:261-286`) starts packing once
`dependencies.len() + captures.runtime_len()` exceeds `CAPTURE_BUDGET = 57`
(`:18-30`). Every family removed from `NeedsName` (`Printer/src/library/names_finder.rs`)
drops out of that count.

But lowering *introduces* names: `bit_and`, `bit_or`, `bit_xor`, `bit_lshift`, `bit_rshift`,
`bit_arshift`, `bit_tobit`, `buffer_trap` (`runtime/builtin/bit.lua:17-51`,
`buffer.lua:19-22`) — about eight primitives shared by everything. So the trade is
**"N distinct per-operation helpers → ~8 shared primitives"**, and it is a win exactly when a
body used more than eight distinct helper families. That is a one-line instrumentation question
(§6, M1), not a guess.

### 5.2 Module-level locals — lowering helps

`use_table_backed_module_locals` (`Printer/src/statement.rs:330-340`) counts
`printer.runtime_names().len()` against a 200 budget, and each resolved section becomes one
`local rt_x = runtime.rt_x` line (`:761-766`). Upstream's 100 → 35 module locals
(`upstream-review.md:31`) is this number. The library printer's per-section budget
(`MAX_ACTIVE_LOCALS = 190`, `library/printer.rs:14,127-131`) also gets safer, since fewer
sections are resolved at all.

### 5.3 Function locals — the surprise is that pure lowering is free

`MAX_LOCAL_VARIABLES = 197` (`Builder/src/local_allocator/local_provider.rs:9`); past it the
allocator spills to `excess_stack[stack_top - offset]`
(`local_provider.rs:46-58`, printed at `Printer/src/expression.rs:205-208`).

`ScalarFinder::run` assigns a local to a node's ports only when a port is used out of local
order, used more than once, is a non-first port, or the node has side effects
(`scalar_finder.rs:159-176`). **A lowered chain of pure, single-use nodes therefore costs zero
locals** — the builder keeps it in `expressions` and inlines it
(`Builder/src/data_handler.rs:42-65`). Local pressure comes only from *sharing*: hoisting
`m.__w` out of a loop makes it multi-use and costs one local, which is the local we want to
spend.

The genuine risk is second-order: more shared values → more spill sites. Under `-o` today the
fork already has 35% of its lines as inter-region copies and 1956 spill sites versus upstream's
8–9% and 113 MB peak (`upstream-review.md:15-21`). Lowering that shares nothing does not move
this; lowering that shares `__w`/`__n` will, and must be measured against exactly that counter.

### 5.4 Expression size

There is no expression-size limit in LuaJIT, but there is a 200-slot register file per function
and a 16-bit jump range, which the printer already works around for wide matches
(`MAX_GROUPED_BRANCHES = 512`, `Printer/src/statement.rs:8-15`). A fully lowered
`store(load(a) * load(b))` nests roughly ten temporaries; that is comfortable, but a canary
assertion on maximum expression depth is cheap insurance once stages 3–4 land.

### 5.5 Net position

| Limit | Today | Direction under lowering |
| --- | --- | --- |
| 60 upvalues per function | packed at 57 (`expression.rs:18-30`) | **better** — N families → ~8 primitives |
| 200 module locals | table-backed spill (`statement.rs:330-340`) | **better** — fewer resolved sections |
| 197 function locals | slow-stack spill (`local_provider.rs:9`) | **neutral** for pure chains, **worse** for shared hoists |
| 190 locals per library section | asserted (`library/printer.rs:127-131`) | **better** — fewer sections |
| inter-region copies | 24–35% of lines (`upstream-review.md:15-16`) | **at risk** — this is the number to watch |

---

## 6. Hypotheses

Each carries mechanism, expected gain, risk, files, and a measurement that costs one compile of
one fixture — no benchmark run unless stated.

Standing measurement primitives (all cheap, all static):

- **M1** — `grep -c` on the generated `.lua` for `rt_`, `buffer_read_`, `buffer_write_`,
  `bit32_or(`, `excess_stack[`, and total line count. The upstream review used exactly this
  (`upstream-review.md:11-16`).
- **M2** — module-local count: number of `local rt_… = runtime.` lines in the module body
  (`Printer/src/statement.rs:761-766`).
- **M3** — per-body upvalue demand: print `Captures::runtime_len()` and
  `dependencies.len()` at `Printer/src/expression.rs:266-268` behind a debug flag; record the
  max over all bodies.
- **M4** — inter-region copy ratio: fraction of lines matching `^\s*loc_\d+_ = loc_\d+_;$`.
- **M5** — compile wall time and peak RSS of `spider-cli` itself.
- **G** — the gate for every stage: `cargo test -p conformance --test luanoffi`, plus a
  bit-identical check of the four fixtures in `tests/manual` against `wasmtime`.

---

### H1 — `Node::Lowered` with an opaque, target-tagged opcode is cheaper than a second graph crate

**Mechanism.** One enum variant plus ~16 exhaustive match arms (enumerated in §2.2), versus
duplicating the normalizer, DPE, invariant mover and ISLE driver for a second node type. The
flat `Vec<Node>` (`IR/Graph/src/lib.rs:24-26`) and the whole-graph normalizer
(`topological_normalizer.rs:111`) mean an appended node needs no placement logic at all.

**Expected gain.** Not a runtime gain — a ~1 500-line saving and one fewer pass suite to keep in
sync. It also keeps `Targets/Json` able to render lowered graphs (`Targets/Json/src/label.rs:28`
already prints `Host::identifier`; a `Lowered` arm is one line), which is the only debugging
surface this compiler has.

**Risk.** The IR stops being purely target-neutral in *spirit* even if it is in *letter*. Mitigate
with the `target: u8` tag and a `debug_assert` in each builder; and with a rule that
`ir-graph` never matches on `opcode`.

**Files.** `IR/Graph/src/node/{mod.rs,simple.rs,sinks.rs,sources.rs}`, the twelve pass files
listed in §2.2, `Targets/Json/src/{label.rs,color.rs}`.

**Measurement.** Compile only. Stage 0 below is the empty-lowering smoke test: the pipeline must
still converge within `MAX_OPTIMIZER_ROUNDS = 64` (`pipeline.rs:23`) and output must be
byte-identical.

---

### H2 — Lowering the `i32` comparison family, fused with `BooleanToInteger`, is the highest gain per line

**Mechanism.** Today an `i32` comparison prints `rt_less_than_s32(a, b)` wrapped in
`(x and 1 or 0)` (`Printer/src/expression.rs:527-543`, `:445-455`), and the helper does
`force_s32` on both operands before comparing (`runtime/core/i32.lua:229-243`). Under the signed
load contract now landing in `buffer.lua:352-370`, both operands are already in `bit.tobit`
form, so `force_s32` is a no-op and the whole thing is `a < b`. Lowering it into a
`Lowered(LtS32)` node lets the existing `into_boolean` machinery
(`Targets/LuaNoFFI/Tree/src/expression.rs:504-583`) and the `repeat` peephole
(`Printer/src/statement.rs:363-379`) collapse the 0/1 round-trip.

**Expected gain.** `upstream-review.md:42-48` counts **913 such loops in libjpeg**, each paying
"boolean → materialise 0/1 → store to a local → compare" per iteration. Twenty helper names
(`names_finder.rs:123-182`) leave `runtime_names`, directly helping M2 and M3.

**Risk.** Low. The comparisons are pure, single-use and branch-free, so by §5.3 they cost no
locals. The one real hazard is signedness: `rt_equal_i32` still calls `force_i32`
(`runtime/core/i32.lua:217-225`) and the unsigned comparisons legitimately need `force_u32`.
Lower only the signed and equality forms first; leave `*_u32` as calls until the signed contract
is confirmed end to end.

**Files.** New `IR/Visitor/isle/lowered.isle`, the lowering pass, `Builder/src/lib.rs:265-269`,
`Builder/src/data_handler.rs:227-243`, `Printer/src/expression.rs:527-543`,
`names_finder.rs:123-182`.

**Measurement.** M1 (`rt_less_than`, `rt_greater_than`, `and 1 or 0` counts), M3, then G.

---

### H3 — Lowering `i32` bitwise and shift ops is nearly free, because the helpers are already aliases

**Mechanism.** `rt_and_i32 = bit32_and`, `rt_or_i32 = bit32_or`,
`rt_exclusive_or_i32 = bit32_xor` (`runtime/core/i32.lua:148-158`), and the shifts are
`bit32_and(rhs, 0x1F)` plus one `bit32_*` call (`:160-213`). The masking is required by
WebAssembly and is a single node.

**Expected gain.** Removes 7 helper names per body that uses them, replacing them with the 3–4
shared `bit_*` primitives (`runtime/builtin/bit.lua:21-51`). Enables the constant-shift fold
`shl(x, K)` and mask-merging rules later.

**Risk.** Very low. Pure, branch-free, one-to-one.

**Files.** the lowering pass, `names_finder.rs:84-95`, `Printer/src/expression.rs:483-525`.

**Measurement.** M1, M2, M3, G.

---

### H4 — Lowering `i32.add`/`sub` into the IR changes nothing in the output, and everything downstream

**Mechanism.** `Printer/src/expression.rs:496-509` already emits `bit32_or(lhs + rhs, 0)`. Moving
that into a `Lowered(TobitAdd)` node should produce **byte-identical output on day one** while
making the `+` visible to ISLE and to CSE.

**Expected gain.** Zero immediately; it is the prerequisite for the three reassociation rules
that are currently disabled (`IR/Visitor/isle/iNN.isle:39-54`) and for address-expression sharing
between neighbouring accesses. Upstream's 18 937 `rt_add_i32` → 0 (`upstream-review.md:13-14`)
is the ceiling, but note the fork already inlines these, so the honest delta here is *structure*,
not text.

**Risk.** This is exactly where the miscompile lives. `iNN.isle:39-54` records that
reassociating a constant into an enclosing constant miscompiles `real-world-miniz` (returns
`-1997` instead of `58679047`) **while conformance still passes**. Do not enable any
reassociation rule in the same stage as the lowering; land the lowering with the rule set
unchanged, confirm byte-identical output, and only then revisit the rules.

**Files.** the lowering pass, `Printer/src/expression.rs:483-525`, `names_finder.rs:72-74`.

**Measurement.** Byte-identical diff of all `tests/manual` outputs is the whole test. If the
diff is not empty, the lowering is wrong.

---

### H5 — Lowering `i32.mul` converts a 9-statement helper into one expression

**Mechanism.** `rt_multiply_i32` (`runtime/core/i32.lua:44-56`) is four `bit32` extractions,
three multiplies and one `bit32_or` — branch-free, so it lowers into a nine-node pure subgraph
that the builder will inline as one expression (§5.3).

**Expected gain.** One call per multiply removed; CSE can then share `bit32_rshift(lhs, 16)`
between two multiplies of the same operand, which a call can never do.

**Risk.** Expression depth grows to ~9 per multiply; nested in an address computation this gets
wide. Watch §5.4. Also, if the multiply result has two consumers, `scalar_finder`
(`scalar_finder.rs:159-163`) assigns one local — same as today.

**Files.** the lowering pass, `names_finder.rs:75`, `runtime/core/i32.lua:39-56` (the section can
eventually be deleted).

**Measurement.** M1 (`rt_multiply_i32` count), M4 (copies must not move), G.

---

### H6 — Lowering the aligned `i32` load is worth more here than for Luau, and the win is `__w`/`__n` sharing

**Mechanism.** `buffer_read_i32` (`buffer.lua:354-370`) is: bounds `if`, `local words = buf.__w`,
`slot = rshift(index,2)+1`, `shift = lshift(band(index,3),3)`, then either `words[slot]` or a
two-word merge. Split into `Lowered(BoundsCheck)` (§4) + `Lowered(LoadWord)`, the `buf.__w`
read becomes an ordinary IR value that CSE and the invariant mover can see. `upstream-review.md:29`
makes exactly this argument: `buffer_read_u32` is "not a C primitive but 20+ bytecode
instructions of pure Lua", and hoisting `__d`/`__s`/`__n` out of a loop "is impossible through a
call, ever".

**Expected gain.** Upstream: all 16 671 load/store calls eliminated
(`upstream-review.md:13-14`). Here, additionally, one table read per access saved once `__w` is
hoisted, and the `ref[1]` indirection dropped if `rt_memory_new` stops wrapping the buffer
(`runtime/core/memory.lua:8-16`, `upstream-review.md:62`).

**Risk.** Highest of the arithmetic stages. Three separate hazards: (a) the state port must be
preserved exactly (§3.4) or the builder panics or the store vanishes; (b) the unaligned path
(`shift ~= 0`) must stay a call or become a gamma — do **not** lower it in the same stage;
(c) sharing `__w` across accesses creates a live range that is exactly the kind the invariant
mover was restricted to avoid (`invariant_port_mover.rs:94-113`).

**Files.** the lowering pass, `Builder/src/lib.rs:469-479`,
`Builder/src/local_allocator/reference_finder.rs:229-239`, `Printer/src/expression.rs:853-878`,
`names_finder.rs:417-438`, `runtime/builtin/buffer.lua:346-370`.

**Measurement.** M1 on `buffer_read_i32`/`buffer_write_i32`, M4 (copies — the regression signal),
M2/M3, then G, then one `luajit -jv` run on `chipmunk` to confirm traces are not being stitched
(`lua-no-ffi-performance-hypotheses.md:118` flags this as an unverified assumption).

---

### H7 — Splitting the bounds check into its own node and merging constant-offset runs is worth ~17% JIT / ~57% interpreter on the access path

**Mechanism.** §4. One `Lowered(BoundsCheck)` statement per group instead of one inline `if` per
access, merged along the state chain by the rule in §4.3.

**Expected gain.** `lua-no-ffi-performance-hypotheses.md:148-165` measures the check itself at
`1.17x` under the JIT and `1.57x` in the interpreter. Merging a run of four consecutive word
loads (very common in a decoder inner loop) removes three of four checks.

**Risk.** Store-group merging changes post-trap memory state (§4.4) — flag it. Merging across a
`memory.grow` is unsound — the state-link test prevents it, but the test must be written against
`find_first_producer`, not against node ids.

**Files.** the lowering pass, a new ISLE rule file, `Printer/src/statement.rs` (a new statement
form), `runtime/builtin/buffer.lua:127-136` (`buffer_check` survives for multi-word cases).

**Measurement.** M1 on `buffer_trap`/`__n` occurrences; a differential fuzz over in-range and
out-of-range addresses (the review recommends `wasm_smith`, `upstream-review.md:73`); G.

---

### H8 — Hoisting `__w` and `__n` per loop is the single lua-no-ffi-specific win that a call can never deliver

**Mechanism.** After H6, `m.__w` and `m.__n` are ordinary IR values. They are loop-invariant
whenever no `memory.grow`/`drop` occurs in the loop — decidable by the same state-link test as
§4.3. Hoisting them gives the loop body two locals and removes two table reads per access.

**Expected gain.** On a four-access inner loop, eight table reads per iteration removed. This is
the mechanism behind the `45.9x` chipmunk figure only in combination with the word memory
(`lua-no-ffi-performance-hypotheses.md:461`); on its own it is a smaller but real constant
factor.

**Risk.** This is the stage that spends locals (§5.3) and the one most likely to reproduce the
`libjpeg` copy regression (`invariant_port_mover.rs:94-113`). It must be measured with M4 as the
primary metric, not M1.

**Files.** a new hoisting pass or an extension to `invariant_port_mover.rs` gated on
`Lowered(LoadField)` only.

**Measurement.** M4 first (copies must not grow more than a few percent), then M1, then G, then a
timed run of `chipmunk` and `lodepng`.

---

### H9 — `i64` as two ports lowers cleanly only *after* the `(lo, hi)` representation change

**Mechanism.** Today `into_bits_i64` allocates a fresh table per `i64` result
(`runtime/builtin/buffer.lua:560-563`), measured at `9.01x` and ~55 B/op when the value escapes
(`lua-no-ffi-performance-hypotheses.md:249-264`). The review proposes a two-port `FromBitsI64`
node holding `(lo, hi)` as two SSA values plus an ISLE rule `into(from(x)) → x`
(`upstream-review.md:58`). A two-port `Lowered` node is exactly that shape, and DPE already
handles multi-port nodes (`dead_port_eliminator.rs:225-243`, subject to `ports_output`).

**Expected gain.** `1.9x`–`9.0x` on `i64`-heavy code plus the allocation removal
(`lua-no-ffi-performance-hypotheses.md:627-634`).

**Risk.** Widest blast radius of anything here: every `i64` local becomes two Lua locals, every
`i64` parameter two parameters, every `i64` return two returns — which doubles `i64` pressure
against `MAX_LOCAL_VARIABLES = 197`. The perf note puts this last for the same reason
(`:634`). Also the fixture coverage is thin: the benchmarks "do not touch i64 at all"
(`upstream-review.md:75`).

**Files.** `Printer/src/expression.rs:395-403`, `Printer/src/statement.rs`,
`runtime/core/i64.lua`, `runtime/builtin/buffer.lua:555-563`, the local allocator.

**Measurement.** A new `i64` fixture first (there is `i64-compare` in the measurement table,
`lua-no-ffi-measurements.md:36`); M1 on `into_bits_i64`; local counts; G.

---

### H10 — `f32`: lower the Veltkamp fast path, keep the slow path a call

**Mechanism.** `round_f32` as proposed (`lua-no-ffi-performance-hypotheses.md:295-311`) is
`c = x * SPLIT; return c - (c - x)` guarded by two early-outs for subnormals and overflow. The
guards are branches, so by §1 only the three-operation fast path lowers; the guard must remain a
call or a gamma. A `Lowered(RoundF32Fast)` plus a residual `rt_round_f32_slow` call inside a
gamma is the honest shape.

**Expected gain.** `13.4x` under the JIT on `f32`-heavy code
(`lua-no-ffi-performance-hypotheses.md:288`), on `chipmunk`, `plmpeg`, `float-compare`.

**Risk.** Correctness: the split must be exact for subnormals, the overflow boundary and NaN —
verified bit-exactly on 320 024 cases (`:313-316`), but that verification is for the *runtime*
function, and a lowered version must be differentially tested against it. Also depends on Step 4
of the perf migration plan landing first (`:616-625`).

**Files.** `runtime/core/f32.lua`, `runtime/builtin/buffer.lua:565-697`, the lowering pass,
`Printer/src/expression.rs:405-416` (the `f32` constant form still prints a bit pattern).

**Measurement.** Differential test of lowered vs. runtime `round_f32` over the same 320 024
cases; then `float-compare` and `chipmunk`; G.

---

### H11 — Lowering alone unblocks the 60-upvalue fixtures

**Mechanism.** §5.1–5.2. `gltf-rs`, `wasm3` and `plmpeg-stream` fail at load with
"more than 60 upvalues" (`problem_lua_limits.md:71-77`); upstream at `-O3` has 35 module locals
where the fork has 100 (`upstream-review.md:31`).

**Expected gain.** If M3's maximum drops below 57 (`Printer/src/expression.rs:30`), the packing
workaround (`:261-286`) stops firing entirely, which also removes the
`__spider_scoped_dependencies[i]` table indirection from every capture in those bodies.

**Risk.** The fork already solved this for `lua-no-ffi` by packing
(`problem_lua_limits.md:3-8`), so the gain is speed and simplicity, not unblocking — *unless*
the packing threshold is still being hit, which M3 answers directly.

**Files.** measurement only.

**Measurement.** M3 before and after each stage, on `gltf_rs`, `wasm3`, `plmpeg-stream`.

---

### H12 (falsification target) — Lowering will reproduce the live-range miscompile, and conformance will not catch it

**Mechanism.** Three independent regressions in this tree share one cause: changing which values
cross a region boundary breaks the backend's parallel-move sequencing
(`IR/Visitor/isle/iNN.isle:39-54`, `invariant_port_mover.rs:94-113`, `isle/mod.rs:98-104`). The
first of these explicitly notes that `real-world-miniz` miscompiles **while the conformance
suites still pass**.

**Expected outcome.** At least one of stages 4–6 produces a wrong answer on a real fixture with
a green conformance run.

**Risk if ignored.** A silent wrong-answer bug shipped behind a green test suite.

**Mitigation, and this is a prerequisite not a follow-up.** Every stage's gate `G` must include
a bit-identical output check of `tests/manual` fixtures against `wasmtime`, not just
`cargo test -p conformance --test luanoffi`. The review's recommendation of `wasm_smith`
fuzzing (`upstream-review.md:73`) is cheap here and targets exactly this class.

**Measurement.** `G` as defined, plus a note in each stage's commit recording which fixture
outputs changed and why.

---

## 7. Staged plan

Ordered by gain-per-line, with the constraint that no stage shares a value across a region
boundary until stage 6.

**Stage 0 — make `Lowered` exist and do nothing.** Add the variant, fill the ~16 match arms,
make `result_count_of` (`scalar_finder.rs:4-67`) and `ports_output` (`sinks.rs:954-1016`)
correct for it, make `handle_lowered` in each builder a `panic!` with the opcode name (mirroring
`handle_host`, `Builder/src/lib.rs:183-189`). Thread `Target` into `build_graph`
(`CLI/src/main.rs:22-34`) and add `run_lowering` to `CLI/src/common.rs`. Add a `lowered.isle`
with zero rules. *Exit criterion: output byte-identical on all fixtures, pipeline converges.*

**Stage 1 — comparisons + `BooleanToInteger` (H2).** Pure, branch-free, removes ~20 helper
names and the 0/1 round-trip in 913 libjpeg loops. Lower the signed and equality forms only.

**Stage 2 — bitwise and shifts (H3).** Mechanical; the helpers are already aliases.

**Stage 3 — `add`/`sub` (H4), then `mul` (H5).** Land `add`/`sub` expecting a byte-identical
diff; treat any diff as a bug. Keep the reassociation rules disabled.

**Stage 4 — aligned `i32` load and store (H6), check still a call.** Split value from check;
keep `buffer_check`-style calls. Do not lower the unaligned path. This is the first stage that
touches state ports — budget the debugging.

**Stage 5 — check as its own node, merge load groups (H7).** Store-group merging behind a flag,
default off.

**Stage 6 — hoist `__w`/`__n` (H8).** The first stage that deliberately spends locals. M4 is the
primary metric here, not M1.

**Stage 7 — `i64` two-port (H9) and `f32` fast path (H10).** Both gated on the corresponding
runtime representation steps landing first (`lua-no-ffi-performance-hypotheses.md:616-634`).

If only three stages are ever done, do 1, 2 and 3: they are pure, share nothing, need no state
ports, remove the most helper names per line of compiler code, and carry essentially none of the
live-range risk that §3.6 documents.

---

## 8. Open questions this note could not settle from the code

1. **Does the fork want lowering under `-o` only, or always?** `run_post_process` runs
   unconditionally (`CLI/src/main.rs:31`) while `run_all_optimizations` does not (`:29`), so
   gating on `-o` makes the two modes diverge much further than today. Gating is safer for
   bisection; not gating is better for the default user.
2. **Is the unaligned path worth a gamma?** The static mix says 57–66% of accesses are aligned
   `i32`/`i64` (`lua-no-ffi-performance-hypotheses.md:437-441`), but the *dynamic* mix is
   unknown, and WebAssembly carries a static alignment hint the printer does not currently use
   (`:609-614`, listed there as Step 3).
3. **Does `rt_memory_new` need to stop wrapping the buffer?** Dropping `{ data, maximum }` for
   the bare buffer removes one `source[1]` from every access (`runtime/core/memory.lua:8-16`,
   `upstream-review.md:62`), but `rt_memory_grow` and `rt_memory_drop` both mutate the wrapper
   (`memory.lua:227-269`). Lowering makes this indirection visible for the first time, so it is
   worth deciding before stage 4 rather than after.
4. **Is the LuaJIT trace actually aborting on generated code?** The perf note flags this as an
   unverified assumption underlying the whole interpreter-side argument
   (`lua-no-ffi-performance-hypotheses.md:118`). One `luajit -jv` run on `chipmunk` settles it,
   and it changes the priority of H6/H7 substantially: if traces hold, the call overhead is
   ~0 under the JIT (`:148-165`) and lowering is worth doing for the *enabled optimizations*,
   not for the removed calls.
