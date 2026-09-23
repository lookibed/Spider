# Generated Code Size in `lua-no-ffi`: A Hypothesis Study

Status: **research only.** No compiler, LuaJIT, test or benchmark was run for this note. The
numbers come from text statistics (Python/`grep`/`awk` over the existing generated
samples, which are gitignored artifacts dated 2026-09-21) and from reading the printer. Every
"after" figure is a **text simulation** of the output a printer change would produce (regex
rewrite of the existing `.lua`), not the output of a modified compiler. Anything that needs a
run to settle is marked **unknown** or **guess**.

Written: `2026-09-23`.

Companion notes: [`register-allocation.md`](register-allocation.md) (boundary copies, the
largest structural category below), [`target-lowering.md`](target-lowering.md) (helpers turned
into operators), [`giant-functions.md`](giant-functions.md) (jump range, H5 constant spill
indices), [`i64-representation.md`](i64-representation.md),
[`paged-memory.md`](paged-memory.md) (P9, P11), [`../problem_lua_limits.md`](../problem_lua_limits.md),
[`../lua-no-ffi-measurements.md`](../lua-no-ffi-measurements.md) (size table).

Paths: `P/` = `Targets/LuaNoFFI/Printer/src/`, `B/` = `Targets/LuaNoFFI/Builder/src/`,
samples live in `tests/manual/<fixture>/generated/`.

---

## 0. The short version

* The module body is dominated by **lexical overhead, not by semantics**: `loc_N_` identifiers
  are 30-34 % of the bytes, leading tabs 23 %, helper names (`rt_load_i32_from_u8` ...)
  11-14 %, spaces 6 %, `;` 1.3 %. The runtime prelude is only 2-6 % on real fixtures.
* **A pure-printer "compact mode"** (short bijective names for locals and helpers, no
  indentation, no trailing `;`, no cosmetic spaces) takes the simulated output to
  **28-39 % of today's size** (miniz 459 KB -> 142 KB, lodepng 1.48 MB -> 443 KB, binjgb
  1.62 MB -> 452 KB, gltf_rs 8.0 MB -> 2.44 MB). It changes no bytecode, so run time and all
  LuaJIT limits are unaffected; only readability of the output is lost (keep the pretty mode
  for development).
* **One cheap targeted fix**: `binjgb`'s single data-segment literal is 168 KB, 80 % of it
  `\x00` runs. Splitting active segments at zero runs and using shortest decimal escapes
  gives 168 KB -> 28 KB (**-8.7 % of the whole file**).
* The biggest **structural** category is plain copies `a = b;`: **27-38 % of all lines,
  19-25 % of bytes**, plus constant moves `a = N;` at 6-9 %. Those are owned by the local
  allocator (register-allocation H1/H2/H5) and are the only size lever that also shrinks
  bytecode, helps the 16-bit jump range and speeds the interpreter.
* Folding statements into multiple assignment **looks** attractive for source size but costs
  `n - 1` extra `MOV`s and `n - 1` frame slots in LuaJIT bytecode; recommended only for
  `SwapAll` cycles. `if not x` for `x == 0` is **wrong in Lua** (0 is truthy); the valid form
  is folding `not (a ~= b)` into `a == b`.
* For distribution, gzip already removes most lexical redundancy (gzip of today's output is
  11-15 % of raw); compact mode still cuts the gzip size by 25-30 %.

---

## 1. Byte budget

### 1.1 Method

`budget.py`-style scan (see the appendix): the file is split at `\nlocal function module(`
into the runtime prelude and the module body; body lines are measured lexically (leading
tabs, `--` comments, string literals, `loc_\d+_`, helper-name tokens, spill syntax, spaces
outside indentation, `;`, newlines) and, separately, by statement shape (normalised first
token, so `loc_1_ = loc_2_;` and `loc_3_ = 17;` land in their own buckets). Lexical categories
are disjoint from one another; statement-shape categories overlap the lexical ones (a copy
line's bytes are also counted in tabs and identifiers). Percentages are of the whole file.

### 1.2 Lexical budget

| Category | miniz 459 KB | lodepng 1.48 MB | binjgb 1.62 MB | Notes |
| --- | ---: | ---: | ---: | --- |
| Runtime prelude (`do -- SECTION ... end`) | 5.6 % | 1.9 % | 2.2 % | 26-36 KB; ~1.9 KB of it comments, 9-13 KB section glue |
| Leading tabs (body) | 23.1 % | 23.7 % | 22.6 % | lodepng: 1 472 lines at depth >= 30, max 56; gltf_rs max 42 |
| `loc_N_` identifiers | 31.7 % | 34.1 % | 30.0 % | 18 k / 58 k / 59 k uses, avg 8.0-8.7 bytes; only 610 / 3 426 / 2 186 distinct names |
| Helper names (`rt_*`, `bit32_*`, `buffer_*`, `into_bits_*`) | 13.7 % | 13.6 % | 11.0 % | 4.8 k / 15.2 k / 14.0 k uses, avg 13 bytes; 39-59 distinct |
| `bit32_or(` + `, 0)` wrapper text | 4.0 % | 3.8 % | 3.2 % | 1.4 k / 4.4 k / 4.0 k adds and subs |
| Spaces outside indentation | 6.3 % | 6.1 % | 5.8 % | ` = `, `, `, ` + ` |
| Newlines | 2.3 % | 2.2 % | 2.1 % | one statement per line |
| Trailing `;` | 1.5 % | 1.3 % | 1.3 % | only `Assign`/`GlobalSet`/`TableSet` print one (`P/statement.rs`) |
| Numeric literals | 2.7 % | 2.5 % | 3.3 % | |
| String literals (data segments, import names) | 2.8 % | 2.8 % | **10.7 %** | binjgb: one 168 KB literal, 134 KB of it in `\x00` runs of >= 16 |
| `module_locals[N]` | 0 | 1.2 % | 0.9 % | module body over 200 locals (`P/statement.rs` `use_table_backed_module_locals`) |
| `excess_stack[stack_top - N]` | 0 | 0.7 % | 0.4 % | slow-stack spills |
| `--[[ x_f32 ]]` / `--[[ x_f64 ]]` comments | 0 | 0 | 0 | float-heavy fixtures only: chipmunk 388, wasm3 247 occurrences, <= ~1 % |
| Blank lines | ~0 | ~0 | ~0 | |
| Remainder: keywords, parens, operators | ~9 % | ~8 % | ~8 % | `then`/`end`/`else`/`(`/`)`/`[1]` ... |

### 1.3 Statement-shape budget (whole lines incl. their tabs)

| Shape | miniz | lodepng | binjgb |
| --- | ---: | ---: | ---: |
| `L = L;` plain copy | **21.0 %** (3 055 lines, 28 % of lines) | **19.2 %** (8 803, 27 %) | **25.2 %** (12 626, 38 %) |
| `L = N;` constant move | 9.0 % | 7.9 % | 6.0 % |
| `L, L = L, L;` (`SwapAll`) | 1.9 % | 3.3 % | 2.6 % |
| `L = bit32_or(...)` | 8.2 % | 8.1 % | 3.7 % |
| `L = buffer_read_i32(...)` | 7.2 % | 7.4 % | 4.8 % |
| `rt_store_*(...)` | 10.4 % | 10.8 % | 13.4 % |
| `L = rt_load_*(...)` | 5.1 % | 5.4 % | 7.2 % |
| `if (x) < K` / `elseif (x) > K` (br_table binary tree) | 2.8 % | 1.4 % | 4.5 % |
| bare `else` / `end` | 5.4 % | 5.7 % | 4.2 % |
| `if not (...)` | 2.1 % | 2.3 % | 1.3 % |
| `local` declaration lines | 1.0 % | 1.7 % | 1.0 % |

Copy-run lengths (consecutive `a = b;` lines): miniz has 585 singletons, 306 pairs, and 31 runs
of 8+; lodepng 193 runs of 8+, binjgb 310. Only 144 / 317 / 222 copies are immediately
overwritten by the next statement (dead stores the printer could see); almost all others are
entry moves into region ports (the class register-allocation.md §2 describes). The prologue
copies of scoped dependencies are negligible (0.0-0.2 %).

### 1.4 What the lexical view says

Roughly **three quarters of the bytes are naming and layout** (ids + helper names + tabs + spaces
+ `;` = 75-79 %, minus what compact names still need). Only about a quarter is "content"
(operators, constants, keywords, structure). That is why the purely lexical hypotheses below
dominate the percentages, while the structural ones (copies) dominate bytecode.

---

## 2. Simulated cumulative effect of the printer-only changes

Regex rewrite of the existing outputs, applied cumulatively to the module body (prelude left
as is). Names are assigned module-wide by frequency from a bijective base-52/62 alphabet
(`[A-Za-z][A-Za-z0-9]*`), skipping Lua keywords and the globals/fixed names the body uses.

| Step (cumulative) | miniz | lodepng | binjgb | gltf_rs | chipmunk |
| --- | ---: | ---: | ---: | ---: | ---: |
| today | 100 % | 100 % | 100 % | 100 % (8.01 MB) | 100 % |
| data segments: zero-run split + decimal escapes | 99.2 | 99.7 | **91.3** | 99.9 | 99.9 |
| + short local names | 73.5 | 73.1 | 67.0 | 70.8 | 69.7 |
| + short helper aliases | 61.0 | 60.5 | 57.0 | 62.6 | 55.3 |
| + indentation capped at 8 tabs *(alternative)* | 54.1 | 51.2 | 48.9 | 53.1 | 55.0 |
| + indentation dropped | 37.9 | 36.8 | 34.5 | 37.5 | 46.6 |
| + trailing `;` dropped | 36.5 | 35.5 | 33.1 | 36.1 | 45.4 |
| + cosmetic spaces dropped | **30.9** | **30.0** | **27.9** | **30.5** | **39.4** |
| gzip -6, today -> final | 55 -> 39 KB | 182 -> 134 KB | 127 -> 91 KB | 872 -> 605 KB | 94 -> 77 KB |

---

## 3. Hypotheses

Legend: **Where** = P (printer only), T (Tree shape or Tree-level pass), B (Builder/allocator),
IR. **Size** = expected change of the whole file, measured by simulation where possible.
**Run time** = effect on bytecode / JIT / interpreter, which is what matters for the fork.

### S1. Short bijective local names — P, **-26 to -33 %**, run time neutral

`impl Print for Name` (`P/expression.rs`) prints `loc_{id}_`. Replace with a bijective
encoding of `id` (or, better, of a frequency rank computed by a visitor pre-pass: the
`Captures` visitor in `P/captures.rs` is the template) into `[A-Za-z][A-Za-z0-9]*`: ids below
52 get 1 char, below 3 224 get 2 chars, which covers all of miniz, lodepng and binjgb; gltf_rs
(18 739 distinct) needs 3 for the tail.

* Correctness: a bijection from `Name` to text preserves today's scoping exactly, because the
  printer already relies on `Name` identity for scoping; whatever shadowing is (not) happening
  today stays the same. The only new hazard is **collision with non-`Name` identifiers**:
  Lua keywords (`do`, `if`, `in`, `or`, `end`, `for`, `nil`, `not`, `and`...), the fixed names
  the printer emits (`runtime`, `module`, `export`, `excess_stack`, `stack_top`,
  `module_locals`, the `for i` loop variable, `__spider_*`), and globals referenced from the
  body (`assert` in `Import`, `error` in `Trap`, plus any global a runtime section reads at
  call time is irrelevant because sections are outside `module`). Every helper binding contains
  `_`, so an underscore-free alphabet can never hit one. Keep one `RESERVED` list and assert on
  it in debug builds.
* Run time: local names exist only in debug info (`varinfo`), so bytecode is identical;
  prototypes get slightly smaller; lexing interns shorter strings. **Neutral.**
* Keep `loc_N_` under a `--readable` (or default-in-debug) switch; tests and humans grep it.

### S2. Short helper aliases — P, **-9 to -12 %** on top of S1, run time neutral

Module-level bindings are `local rt_x = runtime.rt_x` (`P/statement.rs`
`runtime_binding_name`). Print `local Q = runtime.rt_x` and use `Q` at every call site.
Allocate helper aliases from the same pool as S1 (disjoint, highest frequency first, so
`bit32_or`, `buffer_read_i32`, `rt_store_i32`, `rt_load_i32_from_u8` get 1-char names).

* Printer work: about 25 sites write `"rt_{intrinsic}("` or a literal helper name directly
  (`bit32_or(`, `buffer_read_i32(`, `rt_function_type(`, `into_bits_i64(`, `from_bits_f64(`).
  Route them through one `printer.helper(section) -> &str`.
* Upvalue accounting (`P/captures.rs`, `CAPTURE_BUDGET`) counts sections, not spellings:
  unchanged.
* Run time neutral (upvalue slots are the same).

### S3. Indentation: drop in compact mode (or cap) — P, **-15 to -23 %** (cap at 8: -7 to -9 %)

`LuaNoFFIPrinter::tab` writes `depth` tabs. Compact mode writes none; a "semi-pretty" mode caps
at 8. Lua is whitespace-insensitive; line numbers are unchanged because newlines stay, so
tracebacks still point at the same statement. Run time: zero (lexer skips whitespace).
Implementation is one `if` in `tab()`.

### S4. Drop `;` and cosmetic spaces — P, `;` -1.3 to -1.5 %, spaces -5 to -6 %

* `;` is printed after `Assign`, `GlobalSet`, `TableSet`. It is only needed when the **next**
  statement starts with `(` (LuaJIT reports "ambiguous syntax" for `a = b` newline `(f)(x)`;
  on a single line it would silently parse as a call). The printer can track "last statement
  ended with an expression" and emit `;` lazily before a statement whose first token is `(`
  (only a `Call` whose callee is a parenthesised `Function`/`Scoped` can start that way).
* Spaces: ` = ` -> `=`, `, ` -> `,`, ` + ` -> `+`. Hazard: **never let `-` touch `-`**:
  `x - -5` without spaces is `x--5`, a comment, i.e. a silent miscompile. Today's output has
  no ` - -` but 927 ` + -` in gltf_rs, so a naive rule is one constant-fold away from the bug;
  emit a space whenever the next char is `-` (or print `x - 5` for `x + -5`, which is also a
  byte shorter). Keep spaces between keyword/identifier tokens.
* Run time: zero.

### S5. Statement fusion into multiple assignment — P (safety analysis on the Tree), source -0.7 % without indentation / -4 % with it, **bytecode worse**

Merging runs of `a = b;` into `a, c, e = b, d, f`:

* Semantics: Lua evaluates all right-hand sides first, and assignment order among targets is
  undefined. Safe only if no target of the group is read by a later source **or index
  expression** in the group (`excess_stack[stack_top - N]` reads `stack_top`), there are no
  duplicate targets, and every source is side-effect free and cannot observe the targets
  (a call can read a captured `{ nil }` box; a load can trap after an earlier assignment
  should have happened). In practice: only locals and constants.
* Bytecode: LuaJIT's `parse_assignment` puts every RHS except the last into a fresh register
  and then `MOV`s them into the targets, so `n` fused copies become `2n - 1` instructions
  instead of `n`, and take `n - 1` extra frame slots (`LJ_MAX_SLOTS` = 250, with up to 197
  locals already live in big functions). That burns the 16-bit jump range that giant
  functions are already short of (giant-functions.md §2.1) and costs the interpreter a little;
  the JIT folds `MOV`s away.
* Size: once S3 drops indentation, fusion saves only `;\n` per statement (~0.7 %).
* **Verdict: do not do it in general.** Do it only for `SwapAll` (§S5a).

**S5a. One rotate instead of pairwise swaps** — P. `SwapAll` of a k-cycle prints k-1 swaps
`a, b = b, a` (3 instructions each, `P/statement.rs` `impl Print for SwapAll`). A single
`a, b, c = b, c, a` is `2k - 1` instructions vs `3(k - 1)`: equal at k = 2, better from k = 3,
and shorter text. Swap lines are 1.9-3.3 % of bytes; expected -0.5 to -1 %.

### S6. Remove the copies themselves — B (register-allocation.md H1, H2, H5), **-10 to -15 %** (guess), run time **positive**

Copies are 19-25 % of bytes and 27-38 % of lines; constant moves another 6-9 %. Unlike S1-S4
this also removes bytecode, frees locals (fewer `module_locals`/`excess_stack` spills), and
widens jump-range headroom. If H1 (live-through sharing) + H2 (dead-port moves) + H5 (constant
rematerialisation) remove half of them, the file shrinks another 10-15 % and bytecode by a
similar or larger fraction. This is the only size hypothesis with a real run-time upside;
its risk profile is the allocator's (see that note §3, the region-scope invariant).
Printer-visible leftovers: 144 / 317 / 222 immediately-overwritten copies could be dropped by a
peephole, but that belongs in the allocator (dead-port moves), not in the printer.

### S7. Short and folded `i32` wrap: `bit32_or(x + K, 0)` — P (T for chains), -0.8 % after S2 / -3 % alone, run time neutral-to-positive

* Spell the wrap as a one-argument helper bound to `bit.tobit`: `W(x+K)` instead of
  `bit32_or(x + K, 0)`. The trace recorder produces the same `TOBIT`-based IR for both (the
  `BOR x 0` folds away), and the interpreter's fast function takes one argument fewer.
  **Guess** that it is at least neutral; confirm on miniz.
* Fold nested adds/subs into one wrap: `bit32_or(bit32_or(x + a, 0) + b, 0)` ->
  `bit32_or(x + (a + b), 0)`, and more generally print a whole `I32 Add/Sub` tree with a single
  wrap. Valid because operands are within `(-2^32, 2^32)` and doubles are exact below 2^53, so
  any tree of up to 2^20 terms wraps identically once. The narrow regex finds 20 / 129 / 18 /
  884 two-level constant chains in miniz / lodepng / binjgb / gltf_rs (a lower bound). Size
  gain small (< 0.5 %), but each fold removes a call: positive for the interpreter and for
  bytecode count. Best done in the IR (ISLE reassociation, which a32b931 just restored) with a
  printer fallback on `IntegerBinaryOperation` trees.

### S8. Hoist `mem[1]` and address expressions — P/T, < 0.3 %

`buffer_read_i32(m[1], ...)` appears 506 / 1 477 / 992 times; hoisting `m[1]` saves 3 bytes
each and needs invalidation after `memory.grow` and any call. **Not a size lever**; its value is
run time and is owned by paged-memory.md P9 and target-lowering.md.

### S9. Negation and comparisons — T/P, -0.3 to -0.5 % (negation) / -2 to -3 % (operators, before S2)

* `if not x` for `if x == 0` is **invalid**: in Lua `0` is truthy. Rejected as stated.
* Valid: `if not (rt_not_equal_i32(a, b))` -> `if rt_equal_i32(a, b)` and likewise for the four
  ordered comparisons (746 in lodepng, 411 in binjgb): pure printer peephole on
  `print_if_false` / `fmt_repeat_condition` when the condition is an `IntegerCompareOperation`
  (invert the operator). Saves `not (` + `)`; equal bytecode (`ISF`/`IST` vs inverted compare).
* Bigger: print i32 comparisons as operators (`a ~= b`, `a < b`) where the builder can prove
  both operands are normalised signed i32 (results of `bit32_or`, loads, bit ops, constants).
  2 609 comparison helpers in lodepng, 1 396 in binjgb; 1 369 / 626 are `== 0` / `~= 0`. Needs a
  normalisation fact in the Tree (arguments from the host are not normalised, which is why the
  helpers call `force_i32`, `runtime/core/i32.lua:217-225`). Owned by target-lowering.md §7;
  positive run time (no call).

### S10. `do ... end` wrappers and the prelude — P (+ build-time strip), -0.4 to -2 % on big modules, up to -35 % on tiny ones

In the body, `do` appears only for grouped matches (`__spider_match_selector`, 521 uses in
binjgb, 0 elsewhere) and is needed there to scope the selector; keep it. The prelude is the
only place with many wrappers: 73-97 sections, each `do -- SECTION name` + imports +
`runtime.x = x` + `end`, 9-13 KB of glue plus ~1.9 KB of comments per module
(`P/library/printer.rs`). Options, cheapest first:

1. Strip `--` comment lines from runtime sections when `sections.rs` parses them (they are
   `include_str!`-ed, so this is compile-time for the compiler, zero risk). -1.9 KB.
2. Omit the `-- SECTION name` tag in compact mode.
3. Keep the `do` scoping (it is what keeps the chunk under 200 locals, problem_lua_limits.md
   §2), but minify section bodies with the same compact writer as the module (S14).

Matters for small modules (`hash_loop.lua` is 35.7 % runtime text per the measurements note),
negligible for the MB-sized ones.

### S11. Drop debug comments — P, 0 % on the three samples, ~0.5-1 % on float-heavy modules

`--[[ {self}_f32 ]]` and `--[[ {self}_f64 ]]` in `P/expression.rs` are the only comments the body
emits. Drop in compact mode. Zero risk, zero run-time effect.

### S12. Deduplicate identical functions — IR (or T), 0-2.2 %

Normalised-text hashing of every `rt_function_type((function ...` body (names renumbered by
first appearance, `module_locals[N]` and type keys masked): miniz 0 duplicates, lodepng 13
duplicate bodies (1.0 %), binjgb 1 (0.1 %), gltf_rs 79 (2.2 %, Rust monomorphisations). Real
identity also requires the same scoped dependencies (captures) and the same type key where
`call_indirect` checks it. Wasm-level identical-code folding (like `wasm-opt
--merge-similar-functions`) is the clean place. Low gain; after everything else. Run time
neutral (fewer prototypes, slightly faster load, possibly shared traces).

### S13. Compact data-segment encoding — P, **binjgb -8.7 %**, others -0.3 to -0.8 %

`MemoryNew::print` writes `data.escape_ascii()`, i.e. `\xNN` (4 bytes) for every
non-printable byte and every byte >= 0x80.

* Split **active** segments at zero runs (>= 32 bytes) into several `[offset] = "..."` entries:
  memory is created zeroed (`buffer_create` fills every word with `0`). Correctness condition:
  a zero run may be skipped only if no earlier segment in the same initializer wrote that range
  (wasm applies active segments in order, a later zero overwrites an earlier nonzero). The
  printer sees all pieces of one `MemoryNew` and can check overlap locally. Passive segments
  (`memory.init`) must keep their zeros.
* Shortest decimal escapes: `\0`..`\255`, padded to 3 digits only when the next byte is a digit.
  Portable to every Lua (`\x` is a LuaJIT/5.2 extension).
* Raw bytes >= 0x80 would save more on text-heavy segments but make the file non-UTF-8, which
  breaks editors, diffs and some loaders: keep escaped. Raw `\r`/`\n` are not allowed in short
  strings anyway; long brackets `[[...]]` mangle a leading newline and `\r\n`.
* Decoding at load (base64/RLE) is unnecessary once zero runs are skipped: 168 KB -> 28 KB of
  source for binjgb in simulation.
* Adds a handful of string constants to the module function (well below the 65 536 constant
  limit); run time neutral, init time slightly better (fewer bytes to write).

### S14. A compact writer instead of a Lua minifier post-pass — P, bundles S3 + S4 + S11

An external Lua minifier (luasrcdiet, luamin) on 1-8 MB inputs is slow, adds a toolchain
dependency, may not know LuaJIT syntax extensions, and its renaming would have to rediscover
scopes the printer already knows. A **streaming `Write` adapter** inside the printer that (a)
drops leading tabs at line start, (b) drops `;` at end of line unless the next line starts with
`(`, gets S3 + S4-`;` with no AST reasoning and no risk to strings (it only acts at line
boundaries, and multi-line strings are never emitted). S1/S2 are done at the name source, not
in the adapter. Spaces (S4) are better removed at the `write!` sites, where the token kinds are
known, than by a lexer in the adapter.

### S15. Flatter control flow — P, < 1 % size, run time neutral

* `else` whose body is exactly one `if` -> `elseif` (removes one nesting level and one `end`):
  measured 33 / 81 / 31 / 708 opportunities, saving 0.0-0.7 % of tabs. Small because arms
  usually start with a copy.
* br_table matches with <= 3-4 arms: print `if s == 0 then ... elseif s == 1 then ... else ...
  end` instead of the range guard `(s) >= 0 and (s) < n` plus a binary tree
  (`P/statement.rs` `print_match`). Saves the guard and one to two nesting levels; equal or
  fewer comparisons for small `n`. Binary-tree scaffold lines are 1.4-4.5 % of bytes today.
* Matches whose every arm is `x = constant` to the same `x`: a lookup `x = K[s]` from a table
  built once. Measured rare (0-0.5 %) in these samples; not worth a special case yet.
* All of these reduce nesting depth, which also moves away from LuaJIT's 200 syntax-level
  limit (`LJ_MAX_XLEVEL`), today at depth 56 at worst.

### S16. Shorter spill syntax — P, -1 to -2 % before S1/S2

`excess_stack[stack_top - N]` (0.4-0.7 %) and `module_locals[N]` (0.9-1.2 %): in compact mode
name the tables `S`/`M` and the top `T` through the same reserved-name allocator. Constant spill
indices (giant-functions.md H5) remove the subtraction too, which is a bytecode win.

### S17. Constants: `into_bits_i64(lo, hi)` literals — T, 0.3-0.5 %

1 288 / 7 142 / 6 867 / 22 210 bytes. Hoisting each distinct constant into a module-level local
would also save a table allocation per evaluation; belongs to i64-representation.md (H-A makes
it moot).

---

## 4. Classification, risks, limits

### 4.1 Who owns what

| Hypothesis | Printer only | Tree/Builder/IR | Size (whole file) | Run time |
| --- | --- | --- | --- | --- |
| S13 data segments | yes | | binjgb -8.7 %, others < 1 % | neutral |
| S1 short local names | yes | | -26 to -33 % | neutral |
| S2 helper aliases | yes | | -9 to -12 % (after S1) | neutral |
| S3 no indentation | yes | | -15 to -23 % | neutral |
| S4 `;`, spaces | yes | | -6 to -8 % | neutral |
| S11 float comments | yes | | 0-1 % | neutral |
| S14 compact writer | yes | | vehicle for S3/S4 | neutral |
| S5a swap rotate | yes | | -0.5 to -1 % | slightly positive |
| S15 flatter control flow | yes | | < 1 % | neutral |
| S16 spill names | yes | (H5 constant indices: B) | -1 to -2 % | neutral / positive with H5 |
| S10 prelude | yes (+ `sections.rs`) | | big modules < 2 %, tiny up to -35 % | neutral |
| S9 negation fold | yes | | -0.3 to -0.5 % | neutral |
| S9 comparisons as operators | | T (normalisation facts) | -2 to -3 % | positive |
| S7 wrap spelling | yes | | -0.8 % | neutral (guess) |
| S7 add-chain folding | fallback | IR | < 0.5 % | positive |
| S6 copy removal | | B | -10 to -15 % (guess) | **positive** |
| S12 dedupe | | IR | 0-2 % | neutral |
| S5 general fusion | yes | | -0.7 % | **negative** (bytecode) |
| S8 `mem[1]` hoist | | T | < 0.3 % | perf item, not size |

### 4.2 Correctness risks

* **Name collisions** (S1, S2, S16): keywords, printer-fixed names, body-referenced globals
  (`assert`, `error`), the `for i` loop in the table-backed module locals. One reserved list,
  underscore-free generated names (so no helper can collide), debug assertion.
* **Shadowing**: a bijective `Name -> text` map preserves today's behaviour exactly; the risk is
  only in schemes that reuse short strings per function (not proposed: the Name ids are already
  reused across functions by the allocator, 610-3 426 distinct in total).
* **Multiple assignment** (S5, S5a): parallel evaluation, undefined target order, index
  expressions evaluated with pre-assignment values, calls and traps observing partial state.
  `SwapAll` is already parallel by construction, so S5a is safe.
* **`--` created by removing spaces** (S4): a silent miscompile; must be impossible by
  construction.
* **Statement starting with `(`** once `;` or newlines are dropped (S4, S14).
* **Data segment overlap** (S13): skip zeros only where no earlier active segment wrote.
* **Tooling**: conformance tests or scripts that grep the output for `rt_`/`loc_` names, the
  chipmunk profiler notes that read generated line/function names, and humans debugging
  tracebacks. Keep a pretty mode, and optionally emit a name map (`id -> loc_N_`,
  `alias -> helper`) next to the output in compact mode.

### 4.3 LuaJIT limits

* **Jump range (16-bit, bytecode count)** and **constants per function (`BCMAX_D`)** depend on
  bytecode, not text: S1-S4, S10, S11, S13, S14, S16 are neutral. S6, S7-chains, S9-operators,
  S15-flat chains *reduce* bytecode (help). S5 *increases* it (hurts). S13 adds a few string
  constants at module level only.
* **60 upvalues**: helper aliasing changes spellings, not the count; adding a `bit.tobit` alias
  (S7) is one more section and is counted by `Captures` automatically.
* **200 locals / 250 frame slots**: S5 temporaries eat frame slots in functions already near
  197 locals; S6 frees locals.
* **Syntax nesting (`LJ_MAX_XLEVEL` 200)**: S15 and S7-chains reduce depth.
* **Line info**: LuaJIT stores 1, 2 or 4 bytes of line delta per instruction depending on the
  prototype's line span (< 256, < 65 536, otherwise). The `module` function spans the whole
  file (gltf_rs: 187 k lines -> 4 bytes/instruction). Keeping one statement per line (as all
  proposals do) keeps this unchanged; putting many statements per line would save prototype
  memory but ruin tracebacks. Not proposed.

### 4.4 Load time: an honest unknown

The size table motivates this note with load time, but the measurements note says tinyexpr
"spends most of its half second loading a 229 KB module". LuaJIT lexes and parses at tens of
MB/s (**guess**), which would put 229 KB at a few ms; the rest is likely `module()`
instantiation (e.g. `buffer_create` filling `size / 4` words: binjgb declares 64 MiB, i.e. 16 M
word writes), not parsing. Before claiming a load-time win, split the two (§5 step 2). Text-only
changes (S1-S4) reduce lexing only; S6/S7/S9 reduce parse, bytecode emission and later JIT work.

---

## 5. Cheap measurement plan

1. **Budget script** (the appendix): run on miniz, lodepng, binjgb, gltf_rs, chipmunk before
   and after each change; report bytes, lines, gzip -6. Seconds per run.
2. **Load split**, one tiny Lua driver per fixture, median of 20: `t0` = `loadstring(src)` only
   (lex + parse + bytecode), `t1` = calling the chunk (prelude), `t2` = `module(env)`
   (instantiation, memory init). This decides whether size is a load-time issue at all.
3. **Bytecode**: `luajit -bl` listing, or `#string.dump(f)` per prototype, to count
   instructions of the `module` function and the largest wasm function: S5/S6/S7/S9 must be
   judged on instruction counts and jump-range headroom, not bytes.
4. **Correctness gate** for every printer change: `cargo test -p conformance --test luajit` for
   the `lua-no-ffi` target, the self-hosting fixture (`tests/manual/self-hosting-luanoffi-builder`),
   and the miniz/lodepng/binjgb round-trip hashes.
5. **Run time**: the existing benchmark rows (miniz, lodepng, binjgb, chipmunk) only for S5a,
   S6, S7, S9; S1-S4/S10-S16 need only a spot check that the kernel time did not move beyond
   noise.

### Recommended order

1. **S13** (zero-run split + decimal escapes): tiny, local, -8.7 % on binjgb.
2. **Compact mode = S1 + S2 + S14(S3 + S4-`;`) + S11 + S16 + S4-spaces**, behind a CLI flag,
   default on for release output once the self-hosting fixture and conformance pass: ~-60 to
   -70 %.
3. **S5a** and the **S9 negation fold** (printer peepholes, small, bytecode-neutral or better).
4. **S6** via the register-allocation plan, then **S9-operators / S7-chains** via target
   lowering: the only items that shrink bytecode and help speed.
5. **S15**, **S10**, **S12**, **S17** as opportunistic follow-ups. **Do not** do S5.

---

## Appendix: the scan

A Python scan over the generated `.lua` files, reading only. Split at
`"\nlocal function module("`; for body lines count `^\t*` (tabs), `--\[\[.*?\]\]` and `--.*$`
(comments), `"(?:\\.|[^"\\])*"` (strings), `loc_\d+_` (ids), `\b(rt|buffer|bit32|into|from)_\w+`
(helpers), `module_locals\[\d+\]`, `excess_stack\[[^\]]*\]`, trailing `;`, spaces after the
indentation; classify whole lines with `loc_\d+_ = loc_\d+_;`, `loc_\d+_ = -?\d+;`, etc. The
compact-mode simulation applied, cumulatively: data-segment re-encoding (unescape, split at
`\x00{32,}`, shortest decimal escapes), frequency-ranked renaming of `loc_\d+_` and then helper
tokens from a keyword-free `[A-Za-z][A-Za-z0-9]*` pool, `^\t+` removal (or capping at 8),
`;$` removal, and space removal around `= , + - * / < > ~=` outside string literals. Duplicate
functions were found by hashing each `return rt_function_type((function(` ... `end)` block
with names renumbered by first appearance.
