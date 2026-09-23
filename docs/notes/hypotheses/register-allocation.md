# Boundary Copies and the Local Allocator: A Design Study

Status: **research only.** Nothing was built, run or measured for this note. Every claim
about the compiler comes from the checked-in source (plus the uncommitted
`IR/Visitor/src/control/region_scope.rs`, `IR/Visitor/src/isle/context.rs` and
`Conformance/tests/region_scope.rs` in the working tree on 2026-09-23) and is cited
`file:line`. Numbers are quoted from other notes with their source. Anything I could not
confirm from the code is labelled **unknown** or **guess**.

Written: `2026-09-23`.

Companion notes: [`upstream-review.md`](../upstream-review.md) (the 24-35 % vs 8-9 % copy
measurement, lines 11-21), [`target-lowering.md`](target-lowering.md) (the same live-range
regression seen from the lowering side), [`problem_lua_limits.md`](../problem_lua_limits.md).

Paths below are relative to the repo root. `LA/` means
`Targets/LuaNoFFI/Builder/src/local_allocator/`, `B/` means `Targets/LuaNoFFI/Builder/src/`.
The LuaJIT and Luau builders carry their own copies of the same allocator
(`Targets/{LuaJIT,Luau}/Builder/src/local_allocator/`, same `MAX_LOCAL_VARIABLES = 197`), so
every hypothesis here ports to them mechanically; per project direction only `lua-no-ffi`
matters.

---

## 0. The one-paragraph version

The allocator is a **single backward linear scan** over the topologically ordered graph
(`LA/mod.rs:123-135`). A value gets a Lua local the first time the walk meets one of its uses
and releases it when the walk passes its definition (`LA/index_provider.rs:83-93`). Coalescing
is a *single* preferred partner per producer, recorded in a `HashMap<Link, Link>` where a later
node silently overwrites an earlier one (`LA/reference_finder.rs:343-347`), and it succeeds
only if the partner's name happens to be on the free list at that instant
(`LA/index_provider.rs:73-81`). Region exits never emit a move at all
(`B/lib.rs:117-119`, `B/lib.rs:137-142`): they rely on that coalescing succeeding, which is only
guaranteed by the scope invariant that `region_scope.rs` now asserts. Region entries emit a
real parallel move (`B/lib.rs:108-115`, `B/code_handler.rs:106-134`) that is *not* elided when
the outer value is still live after the region, when the port is dead in that branch, or when
some unrelated value stole the preferred name first. That gives the copy classes below. The
single most promising change is to let a region port **share the local of a live-through outer
value** (value-based interference, H1): it is the one that removes the specific cost which
forced gamma invariant motion to be restricted to constants, and it lowers register pressure
instead of raising it.

---

## 1. How the allocator actually works (the model)

### 1.1 Order and lifetimes

* The graph is ordered by a DFS post-order from the omega result
  (`IR/Visitor/src/topological_normalizer.rs:28-56`), after identities are inserted and
  constants isolated (`IR/Visitor/src/pipeline.rs:117-127`). A region occupies a contiguous
  id range from its opening node to its closing node (`region_scope.rs:20-27`), and sibling
  gamma regions are laid out one after another before the `GammaOut`.
* `LocalAllocator::run` (`LA/mod.rs:157-180`) first builds `preferences` from two finders,
  then walks each function (`LA/mod.rs:137-155`) **backwards** (`LA/mod.rs:132-134`).
* For each node, `handle_node` (`LA/mod.rs:106-121`): (1) `handle_definitions` pulls a name for
  every output port that is in `preferences` but still unassigned, meaning a defined but unused
  value (`LA/mod.rs:95-104`); (2) `push_until(start)` frees every hold whose definition is at
  or after this node (`LA/index_provider.rs:83-93`); (3) `handle_arguments` assigns the node's
  operands (`LA/mod.rs:56-93`).
* `handle_arguments` collects operands transitively through values that have no local and are
  therefore inlined as expressions (`LA/argument_finder.rs:49-85`), so an inlined expression's
  operands stay live up to the point where the expression is printed.
* Pass 1 revives each operand into its preferred partner's name if that name is free
  (`LA/mod.rs:67-74`); pass 2 retries in reverse sorted order and otherwise pulls a fresh name
  (`LA/mod.rs:76-90`).
* A fresh name is the **largest** free index (`BinaryHeap<u32>`, `LA/index_provider.rs:51-57`)
  or a brand-new one. Reviving is a linear search plus a heap rebuild
  (`LA/index_provider.rs:59-71`), which is O(n) per revive. That only matters for compile time.
* Once 197 holds are live, every new pull goes to the spill table as `Local::Slow`
  (`LA/local_provider.rs:9`, `LA/local_provider.rs:46-58`). The value that gets spilled is
  **whichever one is pulled next**, with no cost model. Every access is printed as
  `excess_stack[stack_top - k]` (`Targets/LuaNoFFI/Printer/src/expression.rs:200-208`).

Which values get a local at all: `ScalarFinder` gives one when a port has more than one use,
is not port 0, or has side effects (`LA/scalar_finder.rs:159-176`). `ReferenceFinder` gives one
to every boundary port and state port and records the preferred partner
(`LA/reference_finder.rs:279-347`).

**A property worth keeping.** Given the scope invariant, **linear intervals in this layout
are exact**. A value defined inside region *k* dies inside it. The only values live across a
region are ones defined before the `GammaIn`/`ThetaIn` and used after the closing node, and
those really are live on every path. The loop back edge carries values only through `ThetaIn`
ports, which the scan models explicitly (§1.3). So a linear scan is not an approximation
here. Its weakness is the *greedy single-preference coalescing*, not the liveness.

### 1.2 Preferences, precisely

| producer link | preferred partner | source |
|---|---|---|
| each `RegionOut` result | `GammaOut` output port | `LA/reference_finder.rs:28-36` |
| `RegionIn_k` port, non-last region | last region's `RegionIn` port | `LA/reference_finder.rs:56-61` |
| last region's `RegionIn` port | none (`DANGLING`), always gets a name | `LA/reference_finder.rs:51-54` |
| `GammaIn` argument producer | last region's `RegionIn` port | `LA/reference_finder.rs:63-66` |
| `ThetaIn` arg / `ThetaIn` port / `ThetaOut` result | `ThetaOut` output port | `LA/reference_finder.rs:98-115` |
| `Identity`/`Fence` source | the identity/fence output | `LA/reference_finder.rs:131-155` |
| memory/table/global reference | the op's state output port | `LA/reference_finder.rs:157-277` |

`assignments.extend` **overwrites**, and the finder visits nodes in id order
(`LA/reference_finder.rs:343-347`), so a producer feeding several boundaries keeps only the
preference of the **highest-numbered** consumer. Concrete case: a port `RegionIn_k:p` that is
returned unchanged gets its preference set to the identity output by `handle_identity`, then
overwritten back to the last region's port by the later `GammaOut`'s `handle_region_post`.

### 1.3 Where statements are emitted

| site | what | elided when | source |
|---|---|---|---|
| `RegionIn` | parallel move `port_k := arg` for **every** argument | `dst == src` only | `B/lib.rs:108-115`, `B/code_handler.rs:88-134` |
| `RegionOut` | nothing | - | `B/lib.rs:117-119` |
| `ThetaIn` | parallel move `port := arg`, **inside** the loop body (scope is pushed first) | `dst == src` | `B/lib.rs:129-135` |
| `ThetaOut` | nothing but the `repeat ... until` | - | `B/lib.rs:137-142` |
| `Identity` / `Fence` | parallel move `out := src` | `dst == src` | `B/lib.rs:215-227` |
| state ops | rename `state_out := ref` | `dst == src` or state port unused | `B/code_handler.rs:78-86`, `B/lib.rs:349-553` |
| constant or other value with a local | `loc := <expr>` | never (it is a definition) | `B/lib.rs:56-62` |

The parallel move is `AssignmentSimplifier`. It first emits every move whose destination is
not read by another move (`B/assignment_simplifier.rs:15-32`), then emits each remaining cycle
as a `SwapAll` (`B/assignment_simplifier.rs:34-68`). That prints as chained
`a, b = b, a` multiple assignments
(`Targets/LuaNoFFI/Printer/src/statement.rs:419-440`). Entry moves are therefore correctly
sequenced, and **cycle breaking already exists**.

`region_identity::insert` wraps each `RegionOut`/`ThetaOut` result and each `ThetaIn`
argument in its **own single-source** `Identity` (`IR/Visitor/src/control/region_identity.rs:54-80`).
Exits are therefore not parallel moves. They are a sequence of independent copies, ordered by
the DFS. They stay correct because each identity output may take its target name only if the
scan finds that name free, so no still-live value can occupy it.

### 1.4 The invariant exits rely on (and what the concurrent fix protects)

Exits emit no move, so every identity output **must** coalesce into its `GammaOut`/`ThetaOut`
output name. That succeeds today only because, at each `RegionOut` in the backward walk,
nothing assigned inside a *later sibling region* is still held. The only exception would be a
value that is defined before the gamma and read directly inside a region. The uncommitted
`region_scope.rs:1-12` states exactly this, `find_escape` (`region_scope.rs:101-128`) checks
it, and `Conformance/tests/region_scope.rs:1-8` documents the miscompile: an escaped value "held
on to a local that a sibling region's result was meant to be coalesced into ... the move into
the gamma's output was silently dropped". The ISLE fix stops `get_next_producer` from looking
through `RegionIn`/`GammaIn` (`IR/Visitor/src/isle/context.rs`, diff hunk at the top of the
file).

Consequence for every hypothesis below: **`try_revive_into` failing for an exit identity is a
silent miscompile, not a missed optimization.** Any allocator change has to keep that
guarantee or add a fallback move at `RegionOut`/`ThetaOut`. A cheap safety net (S0 in §3) is a
debug assertion in `handle_arguments` for exactly that case.

---

## 2. Where the copies come from (classification)

Each class lists the mechanism, the code, and a guess at its share. **No per-class breakdown
has ever been measured**: the 24 % / 35 % figures (`upstream-review.md:15-16`) count all
`a = b` lines. S1 in §3 is how to get the split.

**C1. Gamma entry moves** (`B/lib.rs:108-115`). One `port_k := arg` per region per argument,
kept whenever the names differ. There are four ways they come to differ:

* **C1a, the argument is live through the gamma.** The producer `x` has another use after the
  `GammaOut`. The backward walk reaches that use first, so `x` already owns a name `X` when
  `GammaIn` is handled. `try_revive_into` then takes the `Entry::Occupied` branch and returns
  `true` without sharing anything (`LA/local_provider.rs:77-79`). The ports took their own name
  earlier, and **every region that uses the port pays a copy**. This is exactly what invariant
  motion creates: lifting a gamma output to its outer source makes that source live through
  the gamma (`IR/Visitor/src/control/invariant_port_mover.rs:94-104`). *Guess: the largest class
  under `-o`, and the cause of the +76 % copies measured before the restriction.*
* **C1b, the port is dead in this branch.** For a non-last region an unused port is still in
  `preferences` (`LA/reference_finder.rs:57-61`). `handle_definitions` therefore *pulls a fresh
  name* for it without even trying the preference (`LA/mod.rs:95-104`), and `do_bulk_assignment`
  emits the move anyway, because it iterates every argument (`B/data_handler.rs:85-93`). That is
  a dead store, and it always survives. The dead-port eliminator only removes ports that are
  dead in every region.
* **C1c, name theft.** In region *k*, the port wants the last region's name `P`, which is free
  after the walk leaves region *k+1*. Any value in region *k* whose last use comes later than
  the port's is pulled first and may pop `P`, because the heap hands out the largest free name
  (`LA/index_provider.rs:52`). The port then gets a fresh name and a copy.
* **C1d, a single preference.** A producer that feeds two ports (the same link appearing twice
  in `arguments`), two gammas, or a gamma and a theta keeps one partner
  (`LA/reference_finder.rs:343-347`). Every other consumer gets a copy.

**C2. Gamma exit identities** (`region_identity.rs:71-75`, emitted by `B/lib.rs:215-220`). The
move `O := r` is kept when `r`'s name is not `O`. This happens when (i) `r` is a pass-through
`RegionIn` port whose preference was overwritten back to the last region's port (§1.2), so the
port lands in `P` and the identity copies `P` into `O`; (ii) `r` is also live after its identity,
because it is returned in two ports or feeds another identity; or (iii) `r` stays live while an
earlier identity holds `O`.

**C3. Theta moves**, three sites per loop-carried variable, all aiming at one name `L`, the
`ThetaOut` output (`LA/reference_finder.rs:98-115`):

* **C3a, entry identity** `L := init`, emitted before the loop. It is kept when `init` is live
  after the loop starts, which is the C1a analogue. Loop-invariant ports are only redirected
  *outside* the loop (`invariant_port_mover.rs:116-121`, `:56-74`), so the outer value becomes
  live across the loop and forces this copy.
* **C3b, loop-top move** `T := L`, emitted **inside** the body on every iteration
  (`B/lib.rs:129-135`, scope pushed before the move). It is kept when the `ThetaIn` port cannot
  take `L` because the port is still read after some result identity has already written `L`.
  That happens whenever the DFS places identity *a* before the last read of port *a*. This is
  the only class that is **per iteration**, so it matters far more at run time than its line
  count suggests.
* **C3c, tail identity** `L := r`. It is kept when `r` is a different port (the swap pattern,
  for example `a, b = b, a + b`) or is live past its identity.

**C4. State renames** (`B/code_handler.rs:78-86`). Every memory, table or global op whose
state output is used emits `state_out := ref` unless the two share a name. A reference with
fan-out keeps one preference (C1d again), so each extra consumer is a real copy of the same
Lua table or buffer. *Share unknown. It may be small after the packed-word memory change
(`bda2246`), but it was never counted.*

**C5. Spills** (`LA/local_provider.rs:46-58`). They are not copies in themselves, but any C1-C4
move that touches a `Local::Slow` becomes a table read or write, and so does every ordinary use
of a spilled value. The spilled value is simply the one pulled at the moment the limit is hit,
with no regard for how hot it is. The spill counts that were measured, 1323 to 1956 sites
(`upstream-review.md:21`) and 1323 to 1874 with forwarding (`IR/Visitor/src/isle/mod.rs:98-104`),
show that this is where extra live range turns into run time.

**C6. Constant materialization.** It is not `a = b`, but it adds lines. Constants are isolated
per consumer *after* identities are inserted (`pipeline.rs:117-121`,
`IR/Visitor/src/constant_isolator.rs:72-130`). A constant that feeds a `GammaIn` argument
therefore becomes `P := K` before the `if`, and it keeps a port and a name alive through the
region. A constant result becomes `O := K` in its region. There is no pass that sinks a constant
argument into the regions. Since the ISLE fix, folding also no longer sees a constant through a
port (`isle/context.rs`), so constant-through-port folds are now lost.

---

## 3. Safety net and measurement (prerequisites, not hypotheses)

**S0, an assertion.** In `LA/mod.rs:56-93`, when `preferred` is a `GammaOut` or `ThetaOut`
output and neither pass manages to revive it, hit `debug_assert!`. This turns the failure mode of
§1.4 into a crash in the conformance suites. Every experiment below should run with it.

**S1, categorized counters.** The builder is `no_std`, so use counters on `CodeHandler`
returned through a test-only accessor, not `eprintln!`. Increment them at the five emission sites
of §1.3, keyed by kind: `RegionIn`, `ThetaIn`, `Identity`-at-`RegionOut`, `Identity`-at-`ThetaOut`,
`Identity`-at-`ThetaIn`-arg, rename, and `Local::Slow` involvement. An identity can be classified
by its single consumer. Also record the enclosing `Repeat` depth, which gives a
*dynamic-weight proxy* (copies × 10^depth) without running anything.

**S2, the static diff.** Reuse the review's regex on `libjpeg_turbo_mjpeg`, `lodepng` and
`real-world-miniz`, at `-o` and without it: total lines, `a = b` lines, `SwapAll` lines,
`excess_stack[` occurrences, and the largest `locals` count per function. **Unknown:** whether
the review counted `SwapAll` lines as copies.

**S3, run time and correctness.** Run the miniz roundtrip hash (expected `58679047` under `-o`,
from `iNN.isle` in `HEAD`), the `luanoffi` conformance suite, `Conformance/tests/region_scope.rs`,
and the self-hosting fixture. For timing, use `luajit` and `luajit -joff` on the same fixtures.
Copies are close to free inside compiled traces, since LuaJIT's trace IR forwards them. They
cost one `MOV` each in the interpreter, add bytecode and pressure, and cost a lot when spilled.
So **line reductions will overstate JIT-on speedups**, and the `-joff` number is the honest
upper bound.

---

## 4. Hypotheses

The effect sizes are order-of-magnitude **guesses** derived from the mechanism, not
measurements. "Share" means the share of all boundary copies.

### H1. Value-based sharing for live-through values (region ports inherit the outer local)

* **Mechanism.** Two SSA values that provably hold the same value do not interfere, even when
  their live ranges overlap (Boissinot et al., "Revisiting Out-of-SSA Translation", 2009). A
  gamma `RegionIn` port always equals its `GammaIn` argument. If the argument's name `X` is held
  across the whole gamma, which is exactly C1a, the port can simply **use `X` without a hold of
  its own**. Nothing inside the region can be assigned `X`, since it is not free, and `x` is
  never redefined. The same rule applies to a *loop-invariant* `ThetaIn` port, one whose result
  is the port itself, provided `X` is not the `ThetaOut` name. It also applies to state renames
  (C4): a state output is the same Lua object as its reference.
* **Expected effect.** It removes C1a completely, and C3a/C4 where they apply. It also removes
  one live name per such port, so **register pressure goes down**. Guess: a 20-40 % cut of
  boundary copies under `-o` and less without it. This is the class that made general
  invariant motion lose.
* **Correctness risk.** The whole argument needs the scope invariant: nothing inside may read
  `x` directly, because otherwise the entry move itself would be the thing that clobbers. The
  concurrent fix plus `assert_scoped` supply it. Parallel-move cycles are unaffected, since the
  move for an aliased port becomes `X := X` and is dropped (`B/code_handler.rs:89-93`). There is
  no local-limit risk, as it only saves names. The upvalue risk looks low: closure dependencies
  are captured through `Scoped` wrapper locals (`B/data_handler.rs:95-146`) rather than by
  aliasing the outer name. **Verify with the self-hosting fixture.**
* **Sketch.** Add `LocalProvider::share_into(assignments, destination, source) -> bool` in
  `LA/local_provider.rs`. It copies `assignments[source]` into `destination` without touching
  the holds. `ReferenceFinder` then needs a second map, `aliases: HashMap<Link, Link>`, recording
  `RegionIn_k:p -> GammaIn.arguments[p]` for every region, including the last one. It is built in
  `handle_gamma_out` (`LA/reference_finder.rs:82-96`). In `LA/mod.rs::handle_arguments`, before
  pass 1, a destination that has an alias target which is already assigned, **and whose target
  is live after the gamma's closing node**, takes `share_into`. "Live after" needs one datum the
  scan does not keep today: the id of each value's last use. Record it when the value is first
  assigned in the backward walk. Its first appearance is its last use, and the id is available
  in `handle_arguments`.
* **Measure.** S1 `RegionIn` counter, S2 locals-per-function (it should drop), S3.

### H2. Drop entry moves into ports that are dead in that branch

* **Mechanism.** Covers C1b. A port that has no reader in region *k* needs no value.
* **Expected effect.** It removes all of C1b. Share unknown; guess 5-15 % of entry moves in
  code with asymmetric `if`s. It also frees the fresh name that `handle_definitions` pulls
  today.
* **Risk.** None to semantics, because the write is dead. The last region's unused port must
  keep its name, since it is the preference target for the argument and the other regions
  (`LA/reference_finder.rs:51-54`). Only the *move* goes away.
* **Sketch.** In `LA/mod.rs::handle_definitions`, skip non-last `RegionIn` ports. Unused
  `ThetaIn` ports cannot be skipped the same way, because their name is `L` and is still
  carried. In `B/code_handler.rs::do_bulk_assignment` / `B/data_handler.rs:85-93`, skip pairs
  whose destination link has no assignment instead of indexing `assignments[&link]`, which
  would panic.
* **Measure.** S1 `RegionIn` counter. It is the cheapest experiment and establishes the method.

### H3. A single parallel move at every exit instead of one identity per result

* **Mechanism.** Covers C2, C3c and, indirectly, C3b. Emit **one** multi-source `Identity` per
  `RegionOut`/`ThetaOut`, and one per `ThetaIn` argument list. In the backward scan all outputs
  are then defined, and all sources die, at the same node id. Each source can take its own
  output's name unless it is live past the move or appears twice. `AssignmentSimplifier`
  already sequences the result and emits `SwapAll` for real cycles (§1.3).
* **Expected effect.** C2(iii) and C3c(ii-iii) turn into at most one move per true cycle.
  Swap-shaped loops (`a, b = b, a + b`) go from about 3 moves to 2. Guess: a 10-30 % cut of exit
  copies.
* **Risk.** **Cycles**: correct in principle, but they now go through `find_first_swap`, which
  `unwrap`s on the assumption that every remaining source is also a destination
  (`B/assignment_simplifier.rs:34-52`). A source read twice by a cycle has to be emitted by
  `find_all_assigns` first. Needs a unit test with fan-out plus a cycle. **Exit invariant**: an
  output that cannot take its name would now be *visible*, because it is a parallel move with its
  own destination. It still has no move at `RegionOut` though, so S0 must stay. **Pressure**:
  result values stay live until the end of the region instead of dying at their own identity.
  The count is the same because `O` was held anyway, but the pressure moves earlier. **Limits**:
  neutral.
* **Sketch.** Change `insert_at` in `IR/Visitor/src/control/region_identity.rs:69-80` to build
  one `Identity` with `sources = results` and rewrite `results[i] = Link(identity, i)`.
  `handle_identity` (`LA/reference_finder.rs:131-142`) already handles multiple sources. The
  topological normalizer places the identity as the last node of the region, because it is the
  closing node's only predecessor. **Check** `B/lib.rs:215-220`: it already routes through
  `do_bulk_assignment`.
* **Measure.** S1 exit counters, split into gamma and theta; S3 miniz and region_scope.

### H4. Loop-carried values: tail moves last, one name for the whole theta

* **Mechanism.** Covers C3b. The design already aims at one name `L` per loop-carried value
  (`LA/reference_finder.rs:98-115`). The per-iteration copy `T := L` appears only because a tail
  identity is scheduled *before* the last read of the port. If every tail move is the body's
  final node, which H3 gives for free, then `T` can be `L` whenever the old value is not needed
  after the new value is computed. The only remaining copies are real swaps, and those land in
  the tail parallel move rather than at loop top.
* **Expected effect.** It removes most of C3b. That is a small share of lines but, guessing,
  the largest *dynamic* share, since it runs once per iteration. It is visible in `-joff` timing.
* **Risk.** The same as H3. It also lengthens the live ranges of the new values up to the tail,
  which could push hot loops over 197 live names. Watch S2 `excess_stack` inside `repeat`.
* **Sketch.** Nothing beyond H3, unless H3 alone does not fix it. In that case make
  `TopologicalNormalizer::add_predecessors` (`topological_normalizer.rs:28-35`) visit a
  `ThetaOut`'s identity last. A more targeted option is to give `ThetaIn` ports priority in
  `LA/mod.rs:76-90` pass 2. **Unknown:** how often the DFS already happens to produce the good
  order.
* **Measure.** S1 `ThetaIn` counter weighted by depth; `-joff` timing on a loop-heavy fixture.

### H5. Constants are rematerialized at the use, never carried through a port

* **Mechanism.** Covers C6. Sink a private constant into each region that reads a constant
  `GammaIn` argument, and into the body for a loop-invariant constant `ThetaIn` port. The port
  then dies, and the dead-port eliminator removes it. This is the counterpart to what
  `invariant_port_mover` already does for constant *outputs*
  (`invariant_port_mover.rs:76-113`).
* **Expected effect.** It removes the `P := K` pre-gamma lines and one live name per such
  port. It also **restores the constant folds the ISLE fix gave up**, because the constant is now
  a node inside the region. Guess: small in lines (≤5 %), positive on pressure.
* **Risk.** Correctness risk is none, because constants are pure. There is a code-size risk if
  a region has many readers, but `constant_isolator` would duplicate them anyway.
* **Sketch.** Add a new `IR/Visitor/src/control/constant_sinker.rs`, run in
  `Optimizer::run_round` before ISLE (`pipeline.rs:69-76`). For each `RegionIn_k:p` whose
  argument is `I32/I64/F32/F64/Null`, rewrite the region's readers to a fresh constant node.
  The normalizer places that node next to its reader, inside the region's id range, because
  it has no predecessors. `find_escape` will confirm this. Do the same for `ThetaIn` ports whose
  result is the port itself.
* **Measure.** S2 lines, `P := K` pattern count, port count before and after the dead-port
  eliminator.

### H6. Several preferences per producer, tried in order

* **Mechanism.** Covers C1d and C2(i). Replace `HashMap<Link, Link>` with a short candidate
  list: `HashMap<Link, SmallVec<[Link; 2]>>`, or `Vec<Link>` given the no_std constraint.
  `try_revive_into` tries each in turn. The pass-through port would keep both "last region's
  port" and "its exit identity".
* **Expected effect.** Moderate, around 5-15 % of boundary copies (a guess). It also removes the
  order dependence on node ids.
* **Risk.** None to correctness, because reviving only ever takes a *free* name. Neutral on
  limits.
* **Sketch.** `LA/reference_finder.rs` (every `extend`/`insert` becomes a push),
  `LA/argument_finder.rs:49-67` (the `preferences.get` type), and `LA/mod.rs:67-90` (loop over
  candidates). Put the candidate whose consumer is most deeply nested in a `Repeat` first, which
  is H8's bias in its cheapest form.
* **Measure.** S1 all counters; the diff should be monotone.

### H7. Reserved names: the free list stops handing out wanted names

* **Mechanism.** Covers C1c and part of C2 and C3. When a value with no usable preference pulls
  a name, avoid names that some not-yet-allocated value prefers: a last-region port name, an exit
  output name, a theta `L`. Take any other free name, or a new one, first.
* **Expected effect.** Moderate. It is the classic biased-coloring fix for greedy theft. Guess
  5-10 %.
* **Risk.** It raises the total number of distinct names, so it is the one hypothesis that can
  **push functions toward 197** and into spills. Fall back to a wanted name only when the
  alternative would be a new name beyond some headroom threshold, for example 180.
* **Sketch.** `LA/index_provider.rs` needs a free structure that supports "take any free name
  not in set W", such as a `BTreeSet<u32>` or a bitset; this also fixes the O(n)
  `remove_free_if_found`. `LA/local_provider.rs` needs `pull(start, avoid: &Set)`. `LA/mod.rs`
  maintains W by adding a name when a preference target is assigned and removing it when its
  preferrer is handled. That is computable because each preference target is assigned before
  its preferrer in the backward walk.
* **Measure.** S1, plus S2 max-locals per function (it must not rise past the headroom).

### H8. Spill by cost, not by arrival order

* **Mechanism.** Covers C5. When 197 names are held, spill the held value with the lowest
  weight (use count × 10^loop depth, with long and cold values first) instead of whatever
  arrives next. Every spilled access costs a table index and, since `bda2246`, sits in the same
  hot paths as memory access.
* **Expected effect.** It does not change line counts, but it changes run time wherever spills
  happen. Guess: large on the fixtures that spill (1323+ sites on libjpeg), none elsewhere. It
  is also the precondition for re-enabling forwarding (§5).
* **Risk.** A value's name is shared with its coalesced partners, so demoting one value to
  `Slow` means demoting its whole coalesced group consistently. Otherwise a boundary move
  appears where none existed, and at an exit that is a miscompile (§1.4). That is why it is best
  done inside H9, not bolted onto the current scan.
* **Sketch (standalone variant).** Precompute the weights in a forward pre-pass over
  `graph.nodes()` (for use counts, reuse `LA/scalar_finder.rs`'s walk; for depth, count open
  `ThetaIn`s as `region_scope::find_escape` does). At `LA/local_provider.rs:46-58`, pull `Slow`
  directly only for values below the median weight, and otherwise take a `Fast` name while
  *demoting* the coldest held value's whole name class. That needs a name→links map.
* **Measure.** S2 `excess_stack[` count, weighted by depth; `-joff` and JIT timing on
  libjpeg/lodepng.

### H9. Two-pass allocation: intervals first, then coalesce by interference, then assign

* **Mechanism.** This is the general form of H1, H6, H7 and H8. Pass 1 computes an exact
  interval per link: exact thanks to §1.1, as `[def_id, last_use_id]` extended through inlined
  expressions the way `ArgumentFinder` does. It also builds the affinity graph (every
  boundary and identity pair, weighted by loop depth) and value classes (H1). Pass 2 does
  conservative coalescing (Briggs/George, or simply "merge if the unions of intervals are
  disjoint, or are the same value"), heaviest affinity first. Pass 3 runs a linear scan over the
  coalesced classes, with spill choice by weight.
* **Expected effect.** It should reach upstream's 8-9 % region, since upstream's number comes
  from a region-recursive allocator (`upstream-review.md:20`). That is the one comparison
  point; **how upstream's allocator works internally is unknown** beyond "recursive, per region".
* **Risk.** It is a rewrite of `LA/mod.rs`, and every boundary emission must be re-derived.
  Exit coalescing has to be *forced*: those affinities are constraints, not preferences, unless
  a fallback move is added at `RegionOut`/`ThetaOut`. Adding one (`B/lib.rs:117-119`,
  `:137-142`) is probably wise here anyway. Compile memory is a concern because intervals are
  per link. There are more links than nodes, but still far fewer than the dead-port bitset that
  once cost 846 MB (commit `aa08225`).
* **Sketch.** New `LA/liveness.rs` (intervals, weights, value classes), a new
  `LA/coalescer.rs` (union-find over links), and `LA/mod.rs::handle_function` running the scan
  over class representatives. Keep `IndexProvider`/`LocalProvider` for the name and spill
  mechanics.
* **Measure.** Everything in §3. Land it only if it beats the best H1-H8 combination on S2 and
  S3.

### H10. Reusing locals across sibling regions: already done

The backward walk frees every name of region *k+1* at its `RegionIn` (`LA/mod.rs:116`,
`LA/index_provider.rs:83-93`) before entering region *k*, so siblings already share the same
pool. The exit and entry partners are also aligned across siblings (§1.2). **Expected gain from
more sibling reuse: none.** It is listed so nobody spends an experiment on it. The only
sibling-related waste is C1c, which is H7's job.

### H11. Sinking a live-through value's copy into the branch that needs it

With H2 (no move into dead ports) and H1 (no move at all for live-through values), there is
nothing left to sink. For a value that is *not* live through, the copy already exists only in
regions that use the port, once H2 is in. **The expected marginal gain after H1 and H2 is
≈ 0**, so it should not be its own experiment.

---

## 5. Recommended order and interactions

Principle, from the project's standing direction: one change per experiment, measured with
S1-S3 on the same three fixtures, and a verdict recorded before the next change is layered on.

1. **S0 + S1 + S2 baseline.** Without the category split every later number is a guess, as
   they are in this note. Run it on the tree *after* the concurrent ISLE and region_scope fix
   lands, because that fix changes the baseline.
2. **H2.** Trivial, zero risk, calibrates the counters.
3. **H1.** The biggest expected win. It lowers pressure, and it is the precondition for step 6.
4. **H3 then H4.** The exit parallel move, then the loop tail order. Measure `-joff` time here,
   since this is where per-iteration copies go away.
5. **H5.** Independent of the others and can run in parallel with 3-4 in its own worktree. It
   also restores the constant-through-port folds lost by the ISLE fix.
6. **Re-enable general gamma invariant motion.** Drop `is_rematerializable` from
   `invariant_port_mover.rs:106-108` and measure. The commit's own analysis
   (`invariant_port_mover.rs:94-104`) names two costs: the extra consumers become copies, which
   H1 makes free for live-through values, and wider live ranges cause spills, which H1 does not
   fix. **Prediction:** after H1 the copy regression disappears and a spill regression of
   unknown size remains. If it is significant, it waits for step 8.
7. **H6, then H7.** Mop-up of C1c, C1d and C2(i). Keep H7 only if S2 max-locals stays under the
   headroom.
8. **H8, or H9 if H1-H7 leave a gap of more than about 2× to upstream's 8-9 %.** H9 subsumes H6,
   H7 and H8. Doing H1-H7 first is not wasted, because each of them is a spec for one piece of
   H9 and gives a number to beat.
9. **Re-enable store-to-load forwarding** (`simplify_global/table/memory`,
   `IR/Visitor/src/isle/mod.rs:98-104`). Its measured cost was *spills* (1323 → 1874) and 29 %
   run time, not copies. It is gated on H8/H9. H1-H4 help only where the forwarded value crosses
   a boundary. An alternative that needs no allocator change is a guard that forwards only
   within one region and within a bounded id distance. **Unknown** whether that keeps any of the
   benefit; the note in `mod.rs` says the ungated version saved no calls on lodepng.
10. **Re-enable the `iNN.isle` reassociation rules.** The working tree already restores them as
    part of the concurrent fix, so this is not gated on this note. H1 does make their "value
    stays live across the boundary" cost disappear for the gamma case.

**Interactions to watch:**

| | H1 | H2 | H3/H4 | H5 | H6 | H7 | H8/H9 |
|---|---|---|---|---|---|---|---|
| pressure (names alive) | ↓ | ↓ | ≈/↑ in bodies | ↓ | ≈ | ↑ (distinct names) | managed |
| needs scope invariant | **yes** | no | yes (exit) | no | no | no | yes |
| touches exit invariant §1.4 | no | no | **yes** | no | no | no | **yes** |

* H3 with H7: both grow the number of distinct or simultaneous names, so run them separately
  and watch S2 max-locals.
* H1 and H6 overlap on state renames. Do H1 first, since it is strictly stronger for equal
  values.
* Step 6 without H1 reproduces the measured regression (`upstream-review.md:21`) and should not
  be attempted.

---

## 6. Honest unknowns

* **The category split is not measured.** C1a being the largest class under `-o` is an
  inference from the invariant-motion comment and the +76 % figure, not a count.
* **Current totals are not known.** The 24 % / 35 % figures predate `aa08225` (constant
  isolation, restricted motion, forwarding off) and `bda2246`. The commit says `-o` is now
  smaller than no `-o`, but gives no copy share.
* **Upstream's allocator internals.** Only its output statistics are known here.
* **Run-time value of fewer copies with the JIT on.** It could be near zero where traces
  compile. The spill and loop-top classes (C5, C3b) are the ones most likely to matter.
* **Whether the DFS already orders tail identities well in practice** (H4). This can be checked
  from S1's `ThetaIn` counter without writing any allocator code.
* **`SwapAll` correctness with fan-out plus a cycle** (H3). I derived this from reading
  `find_first_swap`, and it has no test yet.
