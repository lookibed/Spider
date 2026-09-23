# NaN Bits and `f64` in `lua-no-ffi` — A Hypothesis Study

Status: **research only.** Nothing was built, run or measured for this note. Every claim is either
a code reading (file and line given), a count taken with `grep` over `Conformance/Suite/*.wast`, or
an explicitly labelled hypothesis with a cheap falsifying experiment. Counts of *failing*
assertions are **predictions** from reading the runtime, not a test log; §1.4 says how to confirm
them.

Written: `2026-09-23`.

Companion notes: [`lua-no-ffi-performance-hypotheses.md`](../lua-no-ffi-performance-hypotheses.md)
(§5.2, §11.4: why `f32` stays a bit pattern and what `frexp` costs),
[`lua-no-ffi-known-bugs.md`](../lua-no-ffi-known-bugs.md) "Known limitations",
[`lua-no-ffi-status.md`](../lua-no-ffi-status.md) (the 280/312 figure),
[`target-lowering.md`](target-lowering.md) (where ISLE rewrites live).

---

## 0. The one-paragraph version

The 32 failing cases are **8 `.wast` files × 4 LuaJIT variants**, and inside those 8 files about
**90 assertions** fail. Only **13** of them keep the NaN inside one function (a constant fed to
`reinterpret`, a constant stored and read back as `i64`, `i64 → f64 → neg → i64`). Those 13 can be
fixed at compile time with ISLE rules that are *faster* than today's code. The other **77** move a
non-canonical NaN across a Lua call boundary as an `f64` value: a parameter, a return value or a
loaded value. A Lua number cannot carry those bits, and LuaJIT without FFI cannot read a NaN's sign
or its top payload bits, so no trick on numbers alone can pass them (§4 H5). The one mechanism
that covers all 90 is a **NaN box**. Every NaN except `0x7FF8000000000000` becomes a small table
with arithmetic metamethods. Every NaN number stands for exactly `+canonical`. The non-bitwise
helpers pass their operands through an `x * 1` probe that turns a box back into a plain NaN. On the
non-NaN path under the JIT the probe should cost nothing, because LuaJIT folds `x * 1` to `x` and
the number type guard is already there. In the interpreter it costs one `MULVN` per operand. That
cost must be measured before this becomes the default. Recommendation (§5): land the compile-time
rules and the `frexp`-free `into_bits_f64` now, since both are pure wins. Land the NaN box behind a
measurement gate. Document the API-level consequences as permanent.

---

## 1. What fails, and why

### 1.1 The mechanism of loss

Four places turn bits into a Lua number or back, and all four canonicalise NaNs:

| Place | Code | NaN behaviour |
| --- | --- | --- |
| `from_bits_f64(lo, hi)` | `Targets/LuaNoFFI/Printer/runtime/builtin/buffer.lua:700-746` | `exponent == 0x7FF and mantissa ~= 0` → `return 0 / 0`: sign and payload dropped |
| `into_bits_f64(x)` | `buffer.lua:749-796` | `x ~= x` → `return 0, 0x7FF80000`: every NaN reports `+canonical` |
| `f64` constants in generated code | `Targets/LuaNoFFI/Printer/src/expression.rs:418-425` | printed as `from_bits_f64(lo, hi)`: exact bits in the source, lost at run time |
| Harness arguments and results | `Conformance/tests/luanoffi.rs:194-206, 344-356`; `harness/luanoffi.start.lua` `hn_assert_equal_f64` | arguments go through `from_bits_f64`, results through `into_bits_f64`, and the result must satisfy `type(source) == "number"` |

Every `f64` operation is a runtime helper call (`expression.rs:615-719` prints `rt_{intrinsic}(...)`
for every `Number*` node), so a change of value representation stays inside
`core/f64.lua` and `buffer.lua` and does not touch generated code.

`f32` is not affected. It is carried as a `binary32` bit pattern (`core/f32.lua`), and
`abs`/`neg`/`copysign` are `bit32` masks (`f32.lua:1-15, 162-170`). Loads and stores move the word
unchanged (`core/memory.lua:139-143, 209-213`). Reinterpret is the identity
(`f32.lua:276-278`, `i32.lua:359-362`). Arithmetic returns `0x7FC00000` for any NaN, which is a
legal arithmetic NaN. That is why `f32.wast` (466 `nan:0x` assertions) and `f32_bitwise.wast` pass
(`lua-no-ffi-performance-hypotheses.md` §11.4).

### 1.2 Classification of the failing assertions

The counts come from `grep` and a small classifier over the `.wast` text. An assertion is predicted
to fail when its expected `f64` NaN is not `0x7FF8000000000000`, or when a `-nan` feeds the sign
operand of `copysign`. The **Boundary** column says whether the NaN has to cross a Lua call as an
`f64` value.

| File | Failing (pred.) | Lines | Category | Boundary |
| --- | ---: | --- | --- | --- |
| `address.wast` | 1 | 592 `64_good5` | **Memory round trip**: `f64.load` of `nan:0xc000000000001`, returned | return |
| `conversions.wast` | 8 | 633, 640-642 (`f64.reinterpret_i64`), 663, 672-674 (`i64.reinterpret_f64`) | **Reinterpret round trip**: sign (`0xfff8…`) and payload (`0x7ff4…`, `-1`) | return / param |
| `f64_bitwise.wast` | 35 | 16 × `copysign(num, -nan)`, 16 × `copysign(±nan, ±num)` expecting `-nan`, 2 × `copysign(±nan, -nan)`, 1 × `neg(nan)` (l. 369) | **Sign of NaN lost**, and **copysign with a NaN second operand** | param + return |
| `float_exprs.wast` | 16 | 1090-1103, 1169-1182 (`*_to_abs` with `nan:0x4000000000000` or `-nan`: 12 of 16); 2346+ `f64.nonarithmetic_nan_bitpattern` (4) | sign and payload through `select`/`if`/`neg`; `i64 → f64 → neg → i64` | 12 boundary, **4 internal** |
| `float_literals.wast` | 6 | 163, 165-169 (`i64.reinterpret_f64 (f64.const -nan / nan:0x…)`) | **Reinterpret of a constant** | **internal** |
| `float_memory.wast` | 12 | per `f64` module (3 modules): `f64.load` → NaN × 3, `i64.load` after `f64.store (f64.const nan:…)` × 1 | **Memory round trip of NaN patterns** | 9 return, **3 internal** |
| `float_misc.wast` | 8 | 638-639, 643-644, 650-653 | payload through `abs`/`neg`/`copysign` | param + return |
| `select.wast` | 4 | 203, 209, 235, 241 (`nan:0x20304` passed through `select`) | **payload lost** on a pure pass-through | param + return |
| **Total** | **90** | | | **77 boundary / 13 internal** |

The same classification by root cause:

| Root cause | Assertions | Example |
| --- | ---: | --- |
| Sign of a NaN lost (`-nan` ↔ `nan`), payload canonical | ~40 | `f64_bitwise` `neg(nan)`; `copysign(1, -nan)`; `conversions:640` |
| Payload lost (`nan:0x…` ≠ `0x8000000000000`) | ~30 | `select:203`; `float_misc:638`; `address:592` |
| Signalling NaN made quiet or canonical | ~12 | `float_memory` `0x7ff4…`; `conversions:641` |
| Pattern not representable as a LuaJIT number at all (tag collision, §4 H5) | 2-3 | `conversions:633` (`-1` = `0xFFFFFFFFFFFFFFFF`), `float_literals:166` |
| Constant NaN turned into `0/0` before a bitwise consumer | 9 (included above) | `float_literals:163`; `float_memory` `f64.store` |

What already passes and must keep passing: every `nan:canonical` and `nan:arithmetic` assertion,
because arithmetic may canonicalise; every `x ~= x`-style NaN check (`float_exprs:185,197`); traps
and saturating conversions on NaN (`conversions:129-160, 328-357`); `copysign(x, +nan)`; `abs(±nan)`
and `neg(-nan)` with a plain NaN; and `float_exprs:2346+` `canonical_nan_bitpattern` and
`no_fold_*` on `0x7ff4…`. The last group matters. It requires that **arithmetic on a signalling
NaN reports a quiet NaN**, so any scheme that keeps the bits alive through arithmetic breaks it
(§4 H10b).

### 1.3 What the spec actually demands (the target semantics)

| Operation | Must preserve NaN bits? |
| --- | --- |
| `f64.load`, `f64.store`, `local`/`global`/param/result/`select` | **yes, bit-exact** |
| `f64.reinterpret_i64`, `i64.reinterpret_f64` | **yes, bit-exact** |
| `f64.neg`, `f64.abs`, `f64.copysign` | **yes**: they touch only the sign bit and never canonicalise |
| `+ - * /`, `sqrt`, `min`/`max`, `ceil`/`floor`/`trunc`/`nearest`, `promote`/`demote` | no. Result is canonical if every NaN input is canonical, otherwise any arithmetic (quiet) NaN, **sign nondeterministic** |
| Comparisons, `trunc`/`trunc_sat` to integer | only NaN-ness matters |

So a correct design needs exact bits for transport and the three sign operations, NaN-ness for
everything else, and it may return `0x7FF8000000000000` from all arithmetic. That is the full
contract, and every hypothesis below is judged against it.

### 1.4 Confirming the classification (cheap)

Run `cargo test -p conformance --test luanoffi -- address conversions f64_bitwise float_exprs
float_literals float_memory float_misc select --nocapture` once and `grep -c "should equal"` per
file. Prediction: 1 / 8 / 35 / 16 / 6 / 12 / 8 / 4. A mismatch means the classifier in §1.2 missed
a case. Fix the table before implementing anything.

---

## 2. Two structural facts that shape every hypothesis

1. **The boundary dominates.** 77 of 90 failures pass the NaN into or out of an exported function
   as an `f64` value. Compile-time analysis cannot reach them. Only a run-time representation that
   is not a plain Lua number can.
2. **Every `f64` op is already a helper call** (§1.1). The JIT inlines these helpers and
   specialises them on the recorded operand types. A check that a *number* operand is a number is
   free in a trace, because the type guard exists already. A check on the NaN value (`x ~= x`) is
   one `ucomisd` + `jp`. In the interpreter every added bytecode costs about 1 ns. That is the
   budget.

---

## 3. Cost model used below

"Fast path" means a non-NaN `f64` flowing through the operation. For each hypothesis the note gives
the JIT cost (IR instructions added to a trace) and the interpreter cost (`luajit -joff`,
bytecodes added), separately. The standing direction is that `lua-no-ffi` speed is the priority,
so a hypothesis that adds any IR to the JIT fast path of `+ - * /`, loads or comparisons is
rejected outright.

---

## 4. Hypotheses

### H1. Compile-time bit folds in ISLE (constants, and reinterprets on both ends)

**Mechanism.** `IR/Visitor/isle/fNN.isle` is **empty** today (0 lines), so no `f64` rule exists.
Add rules that work on `f64::to_bits()`, never on float values:

- `I64ReinterpretF64(F64 c)` → `I64 (bits c)`, and `F64ReinterpretI64(I64 k)` → `F64 (from_bits k)`
  (the printer already writes exact bits, `expression.rs:418-425`).
- `I64ReinterpretF64(F64ReinterpretI64 x)` → `x`, and the mirror rule.
- `I64ReinterpretF64(F64Neg(F64ReinterpretI64 x))` → `I64Xor x 0x8000000000000000`, and the same
  for `abs` (`I64And …7FFF…`) and `copysign` (and/or of sign masks). These fire only when *both*
  ends are bit-typed. `i64` ops allocate a table in this target (`into_bits_i64`,
  `buffer.lua:561-563`), so rewriting a float `neg` whose result feeds arithmetic into an `i64` xor
  would be a slowdown.
- `F64Store(p, F64 c)` → `I64Store(p, I64 (bits c))`. Better still, lower it to two `i32` word
  stores, which avoids the `i64` table.

**Fixes.** `float_literals` 6 (the **whole file** passes, **+4 cases**), `float_memory` 3 (the
`i64.load` after `f64.store`; the file still fails on the 9 boundary ones), and
`float_exprs.nonarithmetic_nan_bitpattern` 4 (the file still fails on `_to_abs`). Predicted suite:
**284/312**.

**Fast-path cost.** Negative or zero. Every rule removes a `from_bits_f64`/`into_bits_f64` pair,
and `into_bits_f64` calls `math.frexp`, which is NYI and **stitches the trace**
(`lua-no-ffi-performance-hypotheses.md` §1 line 65, §5.2 line 325).

**Code size.** About 60 lines of ISLE plus two raw bit helpers in
`IR/Visitor/src/isle/context.rs` (next to `get_f64`/`add_f64`, lines 172-181). Generated code gets
smaller.

**Sketch.** `IR/Visitor/isle/fNN.isle` (new `SimplifyF64` decl, wired in the same way as
`SimplifyI32`), `types.fNN.isle` (extractors for the unary, binary and transmute nodes),
`context.rs` (`f64_bits`, `f64_from_bits` externs). Check that constant deduplication in
`constant_isolator.rs` keys `F64` constants by bits and not by `==`. With `==`, two NaN constants
never merge, which is harmless, but `-0.0` and `0.0` would merge.

**Measure.** Unit: compile `float_literals.wast` and grep the output for `from_bits_f64` in the
`f64.*nan` functions (expect none). Suite count. A `-jv` run on a store loop to confirm the
`stitch math.frexp` line is gone for constant stores.

### H2. NaN box: every NaN except `+canonical` is a table with metamethods (the full fix)

**Mechanism.**

- Abstract semantics: a Lua **number** NaN *means* `0x7FF8000000000000`, whatever its hardware
  bits are. We can never observe those bits (H5), so this definition is sound. A **box**
  `setmetatable({lo, hi}, NAN_MT)` holds any other NaN bit pattern exactly.
- `from_bits_f64`: in the existing NaN branch (`buffer.lua:727-736`), `lo == 0 and hi ==
  0x7FF80000` returns `0 / 0`, and anything else returns `nan_box(lo, hi)`. That branch is never
  taken on the fast path.
- `into_bits_f64`: replace `if source ~= source` with `local v = source * 1; if v ~= v then if
  type(source) == "table" then return source[1], source[2] end return 0, 0x7FF80000 end`, then
  continue with `v`. For a box, `source * 1` calls `__mul`, which returns `0 / 0`.
- `NAN_MT` has `__add __sub __mul __div __mod __pow` → `return 0 / 0` (arithmetic NaN,
  spec-legal), `__unm` → a box with the sign flipped (exact, and `f64.neg` of a box needs no helper
  change), and `__tostring` → `"nan"`.
- **Probe canonicalisation** in every non-bitwise helper (`core/f64.lua`): comparisons
  (`rt_less_than_f64(l, r) return l * 1 < r * 1`, and so on; this is required because Lua 5.1
  raises an error on `table < number`, and `box == box` is `true` by `rawequal`), `min`/`max`,
  `sqrt`/`ceil`/`floor`/`truncate`/`nearest`, the eight `truncate`/`saturate_f64_to_*`, and
  `rt_narrow_f64` (`into_bits_f32` would otherwise error on `source < 0`).
- Sign operations get an explicit NaN branch, because a **number** NaN must turn into a box when
  its sign changes:
  - `neg`: `if source ~= source then return NEG_CANONICAL_BOX end return -source`. A box is not
    `~=` itself, so it takes `-source` and `__unm`.
  - `abs`: `local v = source * 1; if v ~= v then return nan_abs(source) end return math_abs(v)`.
  - `copysign`: probe both operands. The fast path keeps today's `r < 0 or (r == 0 and 1/r < 0)`
    and adds one `r == r` test on the positive fall-through. `nan_sign(rhs)` reads `hi` from a box
    and returns `+` for a number NaN.
- Harness: `hn_assert_equal_f64` and `hn_is_f64_nan_*` accept `getmetatable(source) == NAN_MT` as
  an `f64`. `spectest.print_f64` formats a box as `nan`.

**Fixes.** All 90, predicted **312/312**. The harness `from_bits_f64` arguments become boxes, the
helpers carry them, and `into_bits_f64` reports them exactly. The `0x7FFFFFFF…`/`-1` patterns that
cannot exist as LuaJIT numbers are fine too, because a box is never a number.

**Fast-path cost.**
- JIT: `x * 1` folds to `x`. This is a LuaJIT fold rule (`simplify_nummuldiv_k`, "x * 1 ==> x"),
  but **must be verified** with `-jdump=i`. `type(source) == "table"` sits only on the NaN branch.
  `neg`, `abs` and `copysign` gain one `ucomisd`/`jp` guard each. `+ - * /`, loads and stores:
  **no change**, since the type guards that would divert a box already exist.
- Interpreter: one `MULVN` per probed operand (comparisons: 2), one `ISNE`-style compare in
  `neg`/`abs`. Estimated at **≤ 5 %** of a comparison helper call under `-joff`, and it has to be
  measured.
- NaN path (not the fast path, but a cliff): one table allocation per non-canonical NaN produced,
  and arithmetic on a box goes through a metamethod, which ends the trace (side exit). Programs
  that keep **canonical** NaN as a "missing value" marker are unaffected, because `0x7FF8…` stays
  a number. Programs that keep NaN-boxed data in `f64` slots and do arithmetic on it would slow
  down. Few programs do this; C code compiled to wasm moves such data as `i64`.

**Code size.** About 60 runtime lines (a `nan_box` section, `NAN_MT`, three sign helpers, one
probe line per helper) and about 15 harness lines. Generated code does not change.

**Sketch.** `buffer.lua` (new `SECTION nan_box`; `from_bits_f64` and `into_bits_f64` `NEEDS
nan_box`), `core/f64.lua` (probes and sign helpers), `Conformance/tests/harness/luanoffi.start.lua`
(accept boxes), `Conformance/tests/luanoffi.rs:76` (add `nan_box` to `CHUNK_SECTIONS` if the
harness names `NAN_MT`). Document the host contract in `lua-no-ffi-known-bugs.md`: an exported
function may return an `f64` NaN as a table. Offer a runtime `rt_f64_to_number` for embedders.

**Measure.** (a) A micro-benchmark with the §0 method of the performance note (min of 5, 2M ops,
JIT and `-joff`) of `rt_less_than_f64`, `rt_absolute_f64`, `rt_copy_sign_f64`, `into_bits_f64`
and `from_bits_f64`, old against new. (b) `-jdump=i` on a compare loop: expect **no `MUL`** in the
IR. (c) `-jv` over the chipmunk and `plmpeg` fixtures: expect no new aborts. (d) End-to-end A/B on
the §6.4 fixtures against HEAD. (e) The suite (312 expected) and the self-hosting fixture.
**Gate:** JIT delta ≤ 1 % on every fixture, `-joff` ≤ 3 %.

### H3. Box only at the boundary; plain numbers inside (a cheaper cousin of H2)

**Mechanism.** Keep numbers everywhere, but box a non-canonical NaN only in the two places that
create one: the harness or host argument path, and `from_bits_f64` inside `rt_load_f64` and
`rt_transmute_i64_to_f64`. Each helper that would receive a box then has to deal with it anyway.
That is all of H2, only described differently: a box that enters any function must survive `neg`,
`select`, comparisons and so on. A real "boundary only" variant would unbox on function entry. It
would lose the 77 boundary cases, which are the ones that matter, and would still need exported
functions to box their `f64` returns, a cost paid on *every* `f64` return (an `x ~= x` per return
value).

**Verdict.** It collapses into H2 or it fixes nothing. It is recorded so that nobody tries it
again.

### H4. `f64` in word memory as two words; materialise a number only for arithmetic

**Mechanism.** Memory is now a packed array of signed 32-bit words (commit `bda2246`). Add a
helper `rt_copy_f64(dst, dofs, src, sofs)` (two `buffer_read_i32` and two `buffer_write_i32`, no
float conversion, no table), and ISLE rules:
`F64Store(p, F64Load q)` → `CopyF64(p, q)`;
`I64ReinterpretF64(F64Load p)` → `I64Load p`; `F64Store(p, F64ReinterpretI64 x)` → `I64Store(p, x)`;
`F64Store(p, F64Neg(F64Load q))` → copy with `hi ~ 0x80000000`, and the same for `abs`.
This extends the existing store → load forwarding precedent in `IR/Visitor/isle/memory.isle`.

**Fixes (suite).** None beyond H1, because the suite's round trips cross the harness boundary.
**Fixes (real code).** Struct copies and `memmove`-by-double of NaN-carrying data (JS-engine
values, sentinels) become bit-exact **without** H2. With H2 in place, the same copies stop
allocating boxes.

**Fast-path cost.** Strongly negative. A `load → store` of a double today runs `from_bits_f64`
(about 10 arithmetic ops and `2 ^ e`) and then `into_bits_f64` (`frexp`, NYI, stitches the trace).
After the rewrite it is 4 word ops.

**Code size.** Smaller generated code, plus one 10-line helper.

**Measure.** Count `F64Store(F64Load)` pairs in the fixtures (a static grep of the Json target
output). Micro-benchmark a 1M-double copy loop, old against new, under JIT and `-joff`. Run `-jv`
to confirm the stitch is gone.

### H5. What LuaJIT 2.1 actually exposes about NaN bits (the honest inventory)

From the LuaJIT 2.1 sources, as remembered and **not re-read for this note**. Each row needs a
2-line probe script before anyone relies on it.

| Channel | What it reveals | Confidence |
| --- | --- | --- |
| `tostring`, `%g`, `%a`, `%e`, `%f` | nothing. `lj_strfmt_wfnum` prints the sign only for `inf`; NaN prints as `nan` (2.0 used `sprintf` and printed `-nan`) | high; matches what the task observed |
| comparisons, `math.min/max`, `math.floor/ceil/abs/sqrt/fmod/frexp/modf` | nothing. `abs` clears the sign, the others propagate or return NaN | high |
| `%d`, `%x`, `tonumber`, `math.floor` → integer | nothing; the conversion yields the "integer indefinite" value | high |
| **`bit.tobit(x)` / any `bit.*` on a NaN** | **the low 32 payload bits.** `tobit` is `x + 2^52 + 2^51` followed by a read of the low word, and x86 or ARM add propagates the NaN operand's payload | medium. **Probe:** `bit.tobit(from_bytecode_nan)` |
| NaN sign and payload bits 32-50 | **nothing.** No operation turns them into a non-NaN | high |
| Constructing a NaN with a chosen payload | only by `loadstring` of **hand-patched bytecode** (`bcread_knum` copies `lo/hi` raw). The parser refuses to fold `0/0` into a constant | medium; fragile, and version- and `GC64`-dependent |
| Representable NaN numbers | not all: negative NaNs whose top bits overlap the type tags (non-`GC64`: `hi ≥ 0xFFFFFFF2`; `GC64`: roughly `hi ≥ 0xFFF98000`) would be read as GC objects, and LuaJIT canonicalises on FFI entry for that reason | high in kind, approximate in bounds |

**Conclusion.** There is no read channel for the sign, so no scheme on numbers can pass
`f64_bitwise`. The `bit.tobit` leak is a **hazard** (garbage bits if the runtime ever applies `bit`
to an `f64` NaN; today every `force_i32` call sits after a NaN check), not a tool. It is recorded
here so that H10b is not reinvented.

**Fixes.** None directly. **Cost.** None. **Measure.** One 20-line probe script (`tostring(-(0/0))`,
`bit.tobit` on a bytecode-crafted NaN, `string.format("%a", …)`) run under the pinned LuaJIT
2.1.0-beta3, once with `GC64` and once without.

### H6. Type-directed printing: ISLE proves a value flows only through bitwise ops

**Mechanism.** Generalise H1 and H4 from local patterns to "bit islands": connected sets of `f64`
values whose producers are all bit sources (load, reinterpret, constant) and whose consumers are
all bit sinks (store, reinterpret, `neg`/`abs`/`copysign`, `select`, `phi`, locals). Lower an
island to integer ops at word level and never materialise a number. In this IR it can be done
without a new type: push reinterprets through sign ops
(`F64Neg(F64ReinterpretI64 x)` → `F64ReinterpretI64(I64Xor x SIGN)`) until they cancel. The trap is
that the islands have to be *closed* on both ends, or the rewrite swaps a 1-instruction float
`neg` for an allocating `i64` xor.

**Fixes.** The same 13 internal cases as H1, plus intra-function `select`/`if` round trips in real
code. No boundary cases.

**Fast-path cost.** Zero or negative when the islands are closed. A positive and possibly large
cost if the closedness check is wrong, because `i64` values are tables.

**Code size.** Medium. It needs a use-set query in ISLE (whether all uses are bit sinks), and ISLE
cannot express that locally. It would be a small Rust pass beside
`IR/Visitor/src/control/region_scope.rs`.

**Verdict.** It adds nothing to the suite count beyond H1 and H4. Defer it until a real fixture
shows `f64` bit islands that span control flow.

**Measure.** Count islands in fixtures with a throwaway pass that only logs them. If fewer than a
handful per fixture exist, drop the idea.

### H7. Restrict the guarantee to the spec's real per-operation requirements

**Mechanism.** No code: adopt §1.3 as the documented contract, and implement exactly that. A NaN
number means `+canonical`. Arithmetic always reports `0x7FF8000000000000`, which is legal for every
input. Only transport and the three sign ops are exact. This is what makes H2 cheap: H2 never
needs to keep bits alive through arithmetic, which is where H10b and "last-NaN" schemes break.

**Fixes.** It turns 3 would-be deviations into non-deviations: a NaN from arithmetic whose sign is
reported as `+`, a sNaN input made quiet by arithmetic, and host-supplied NaN numbers read as
`+canonical`.

**Cost.** Zero. **Measure.** None. Run the `float_exprs` `canonical_nan_bitpattern` and `no_fold_*`
assertions as regression guards (§1.2).

### H8. `f32` NaN payloads under the bit-pattern representation

**Mechanism and state.** Already exact (§1.1). Two edges need a check once H2 lands:
`rt_narrow_f64(box)` has to go through the `* 1` probe, because `into_bits_f32` would otherwise hit
`source < 0` on a table (`buffer.lua:655`), and `rt_widen_f32` of a non-canonical `f32` NaN returns
`0 / 0` (`from_bits_f32`, `buffer.lua:617-620`). The second is legal (`promote` of a NaN is an
arithmetic NaN; `conversions:560-563` expect `nan:canonical`/`nan:arithmetic`), so it should **not**
return a box. A box would cost an allocation for nothing.

**Fixes.** None needed. **Cost.** Zero. **Measure.** `f32.wast`, `f32_bitwise.wast`,
`conversions.wast` stay green under H2.

### H9. `f64.store` fast path: NaN test by `x ~= x` first, and `into_bits_f64` without `frexp`

**Mechanism.** `into_bits_f64` already starts with `x ~= x` (`buffer.lua:750`), so the NaN test is
free, and H2 only reshapes it (`v = x * 1; if v ~= v`). The real cost on this path is further down:
`math.frexp` (NYI, a trace stitch on every `f64.store` and `i64.reinterpret_f64`), `2 ^ (e + 52)`,
and two `%` per word. Replace them the way `into_bits_f32` was replaced (§11.4): take the exponent
from `math.log` with a one-step correction, look up a precomputed `F64_POWERS[e]` table (`2^-1074
.. 2^1023`), and split the mantissa with one exact division. On the read side, `from_bits_f64`
(`buffer.lua:700-746`) can use the same table instead of `2 ^ (exponent - 1023)` and `2 ^ -1074`.

**Fixes.** No suite case. It is the vehicle H2 rides on, and a straight speed win.

**Fast-path cost.** Strongly negative. §5.2 of the performance note measured the `f32` analogue at
`8.81x` under the JIT.

**Code size.** About 30 lines, plus a 2098-entry table built at load time (as `F32_POWERS` is).

**Measure.** Micro-benchmark `into_bits_f64` and `from_bits_f64` over 2M random doubles plus every
edge (`±0`, subnormals, `2^-1074`, `DBL_MAX`, `±inf`, NaN): old against new, bit-exact against an
FFI `double` reference (reference harness only; skip NaNs, §11.4). Run `-jv` to confirm no
`stitch`.

### H10. Rejected on reading

- **H10a. "Last NaN" shadow register.** `from_bits_f64` records the bits of the NaN it just made,
  and `into_bits_f64` reports them for any NaN. It breaks the rule that arithmetic on canonical
  inputs yields a canonical NaN as soon as a payload NaN has been loaded earlier, and it gives
  wrong bits when two NaNs are live at once. Rejected.
- **H10b. NaN registry keyed by the `bit.tobit` low word** (build payload NaNs by crafted
  bytecode, index = low word). It keeps NaNs as numbers, with no cost anywhere, which sounds ideal.
  It fails in three ways. There is no sign channel, so `neg`/`copysign` still need a NaN branch.
  Arithmetic keeps the low word, so `0x7ff4… + 0` reports the signalling pattern, which breaks the
  currently passing `float_exprs` `no_fold_*` and `arithmetic_nan_bitpattern` checks and most of
  `f64.wast`'s `nan:arithmetic` cases. And bytecode crafting is version- and `GC64`-fragile, and a
  pattern that collides with a tag crashes the VM. Rejected.
- **H10c. Carry every `f64` as two words, as `f32` is carried.** It is exact by construction, but
  every `+ - * /` would pay a `from_bits` and an `into_bits`. For `f32` that representation is
  already measured as the slow side (§5.2), and `f64` is where numeric programs live. Rejected on
  speed. H2 buys the same exactness for NaNs alone.
- **H10d. Relax the harness** to compare NaN-ness only for `f64`. It would hide real regressions,
  such as a `copysign` sign bug on non-NaN inputs being masked by a NaN in the other operand.
  Rejected.

---

## 5. Recommendation

| Step | What | Suite after (pred.) | Fast path | Risk |
| --- | --- | ---: | --- | --- |
| 1 | **H9**: `frexp`-free `into_bits_f64`, table-driven `from_bits_f64` | 280 | faster (removes a stitch per store) | low. Bit-exact test as in §11.4 |
| 2 | **H1** + **H4** as ISLE rules in `fNN.isle`/`memory.isle` | **284** | faster (fewer conversions) | low. The rules are bit-level identities |
| 3 | **H2** NaN box with `* 1` probes, under **H7** semantics | **312** (pred.) | JIT: 0 (verify the fold); `-joff`: ≤ 3 % (verify) | medium. Every `f64` helper is touched, and boxes reach host code |
| — | H3, H5 (as a mechanism), H6 (for now), H10a-d | — | — | recorded, not built |

Implement steps 1 and 2 unconditionally. Implement step 3 and **keep it only if** the §4 H2 gate
holds (JIT ≤ 1 % on every fixture, `-joff` ≤ 3 %, no new trace aborts). If the gate fails, do not
revert H2. First try narrowing the probes to the helpers that the fixtures actually call with
`f64` operands of unknown type, since comparisons are the likely hot spot.

**Permanent, documented deviations** (for `lua-no-ffi-known-bugs.md` "Known limitations"):

1. Arithmetic, `sqrt`, rounding, `min`/`max` and `promote`/`demote` always return the canonical
   NaN `0x7FF8000000000000`, with the sign `+`. This is legal wasm, and it is the only NaN LuaJIT
   lets us produce without bytecode tricks.
2. A NaN number handed in by the host is read as `+canonical`, whatever its hardware bits. LuaJIT
   cannot observe them (§4 H5).
3. With H2: an exported function may return an `f64` NaN as a **table** (a "NaN box"), not a
   number. Embedders who need a number call `rt_f64_to_number`. Non-canonical NaN values are slow:
   they allocate, and their arithmetic runs through metamethods outside the trace.
4. Without H2 (if the gate fails): sign and payload of `f64` NaNs are not preserved across function
   boundaries or through `neg`/`abs`/`copysign`/`select`/loads. This is exactly the 77 boundary
   assertions of §1.2, and the suite would stay at 284/312.
