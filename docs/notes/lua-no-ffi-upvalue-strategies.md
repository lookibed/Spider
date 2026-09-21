# LuaJIT Upvalue Pressure in `lua-no-ffi`: Diagnosis, Experiments, Decision

This note records an experiment series run against the 60 upvalue limit that
kept `tests/manual/real-world-gltf-rs` (553 KB of Rust compiled WebAssembly)
from loading at all. It supersedes the "60 upvalues" half of
`docs/notes/problem_lua_limits.md`.

Everything below was measured with `luajit 2.1.0-beta3` on this machine.
Measurement scripts live outside the repository; they are reproduced inline
where they are short enough to matter.

---

## 1. Diagnosis

### 1.1 The failure

```
$ luajit tests/manual/real-world-gltf-rs/generated/gltf_rs.lua
luajit: .../gltf_rs.lua:50445: function at line 49985 has more than 60 upvalues
```

Line 49985 is the *body* of one WebAssembly function, printed inside its scope
wrapper:

```lua
	excess_stack[stack_top - 1][1] = (function()
		local loc_4610_ = module_locals[58];      -- 41 scoped dependencies
		...
		local loc_4650_ = module_locals[5];
		return rt_function_type((function(loc_4651_, loc_4652_, loc_4653_)
			...
			loc_4657_ = bit32_or(loc_4746_ - 960, 0);          -- runtime helper
			loc_4698_ = buffer_read_u32(loc_4650_[1], ...);    -- runtime helper
			if rt_greater_than_equal_u32(loc_4699_, loc_4700_) -- runtime helper
```

The body captures **two** kinds of outer value, and only one of them was ever
counted:

| Captured value | Where it is declared | Counted by the old heuristic? |
|---|---|---|
| scoped dependency (`loc_4610_` …) | a `local` of the scope wrapper | yes |
| runtime helper (`bit32_or`, `rt_load_i32_from_u8`, …) | a `local` of `module()` | **no** |
| `excess_stack` | a `local` of `module()` | no |

`module()` for `gltf_rs` binds **93** runtime helpers as locals. The guard was
`PACKED_SCOPED_DEPENDENCIES_THRESHOLD = 48` applied to the dependency count
alone, so a body with 41 dependencies and 20 distinct helpers sailed past the
check and then blew the limit at 61+.

That is the whole of the reported bug. Instrumenting the printer to emit its
own estimate next to each scope and correlating it with LuaJIT's own count
(`jit.util.funcinfo(proto).upvalues`, walked over every prototype through
`jit.util.funck`) showed the estimate

```
upvalues(body) = dependencies + distinct runtime helpers [+ 1 for excess_stack]
```

is **exact** on 4 800 scopes across all 28 fixtures: the measured difference was
0 everywhere except `gltf_rs`, where it is 1 (that module spills locals to
`excess_stack`).

### 1.2 The second leak, which nobody had reported yet

The same instrumentation showed that the *wrapper* is usually worse off than
the body it returns. With

```lua
(function()
	local a = loc_1819_; local b = loc_1820_; ...   -- 39 sources
	return rt_function_type((function(...) ... end), "key")
end)()
```

the wrapper's own upvalue list is every source local **plus**, transitively,
every runtime helper the inner body names, plus `rt_function_type`. For
`cgltf`:

```
proto line 5228 (wrapper): upvalues=58
  bit32_or buffer_read_u32 from_bits_f64 into_bits_i64 loc_1763_ loc_1819_ …
  loc_1867_ rt_equal_i32 rt_function_type … rt_table_get_function
proto line 5231 (body):    upvalues=54
```

58 of 60. `cgltf` was two slots from the same crash for a completely different
reason, and no amount of dependency packing would have helped, because packing
happens *inside* that wrapper.

### 1.3 Upvalue distribution across the corpus

Measured on the output of the unmodified compiler, over every
`tests/manual/*/generated/*.wasm`. `max` is the largest upvalue count of any
prototype in the module, `mean` the average over all prototypes.

| fixture | protos | max | mean |
|---|---:|---:|---:|
| chipmunk-profile.branch_state | 45 | 27 | 2.27 |
| chipmunk-profile.chipmunk_profile | 560 | 35 | 8.19 |
| chipmunk-profile.math_shim | 58 | 29 | 3.50 |
| chipmunk-profile.memory_walk | 49 | 25 | 2.55 |
| chipmunk-profile.space_collision | 542 | 35 | 8.04 |
| chipmunk-profile.space_freefall | 542 | 35 | 8.04 |
| chipmunk-profile.space_full | 542 | 35 | 8.04 |
| float-compare.float_hash | 39 | 15 | 1.54 |
| hash-compare.hash_loop | 19 | 7 | 1.11 |
| i64-compare.i64_hash | 53 | 19 | 3.96 |
| real-archive-secret.secret_reader | 158 | 40 | 6.47 |
| real-world-binjgb.binjgb | 395 | 53 | 7.72 |
| real-world-cgltf.cgltf | 240 | **58** | 7.87 |
| real-world-chipmunk.chipmunk | 552 | 32 | 8.02 |
| **real-world-gltf-rs.gltf_rs** | — | **fails to load** | — |
| real-world-h264bsd-mp4.h264mp4 | 554 | 48 | 9.78 |
| real-world-libjpeg-turbo-mjpeg | 1136 | 51 | 10.26 |
| real-world-libjpeg-turbo | 1128 | 51 | 10.27 |
| real-world-lodepng.lodepng | 460 | 56 | 8.39 |
| real-world-lodepng.lodepng_diag | 385 | 56 | 9.38 |
| real-world-miniz-file.miniz_file | 261 | 45 | 9.31 |
| real-world-miniz-full.miniz_full | 209 | 44 | 8.62 |
| real-world-miniz.miniz | 119 | 33 | 6.96 |
| real-world-plmpeg-stream.plmpeg | 168 | 31 | 6.86 |
| real-world-plmpeg.plmpeg | 414 | 33 | 7.20 |
| real-world-tinyexpr.tinyexpr | 225 | 26 | 5.32 |
| real-world-wasm3.wasm3 | 1518 | 34 | 9.57 |
| self-hosting-luanoffi-builder | 576 | 54 | 12.17 |

The shape of this table decides the whole question: the **mean is 5–12** and
only five modules come anywhere near 60. Whatever we do about the outliers must
not touch the other 99.8 % of printed functions, because those already generate
the fastest code we know how to generate.

Per scope demand, same corpus (printer's own counters):

| fixture | scopes | max dependencies | max distinct helpers | max sum |
|---|---:|---:|---:|---:|
| real-world-gltf-rs | 696 | 81 | 45 | **111** |
| self-hosting-luanoffi-builder | 238 | 49 | 40 | 89 |
| real-world-lodepng | 186 | 38 | 26 | 56 |
| real-world-cgltf | 79 | 39 | 19 | 57 |
| real-world-binjgb | 134 | 20 | 33 | 53 |
| real-world-libjpeg-turbo | 495 | 36 | 26 | 51 |
| real-world-h264bsd-mp4 | 213 | 25 | 40 | 48 |
| real-world-miniz-file | 86 | 24 | 33 | 44 |
| real-world-wasm3 | 658 | 18 | 19 | 34 |
| real-world-tinyexpr | 51 | 8 | 22 | 25 |

`gltf_rs` needs 111 upvalues for its worst function. Nothing else needs more
than 89, and the benchmark fixtures top out at 56.

---

## 2. Hypotheses

Eight strategies were formulated before any of them was implemented.

**H1 — lower the packing threshold.** Cheapest possible patch: move
`PACKED_SCOPED_DEPENDENCIES_THRESHOLD` from 48 to, say, 32.
*Prediction: does not fix the bug.* The failing body has 41 dependencies and
20 helpers; a body with 10 dependencies and 55 helpers would still fail, and
lowering the threshold makes every mid-sized function pay the table-read cost.
Rejected on the diagnosis alone.

**H2 — budget-aware packing.** Count what the body will actually capture
(dependencies + distinct runtime helpers + fixed extras) and pack only when
that exceeds a budget derived from the real limit.

**H3 — runtime helpers through one `runtime` table.** Emit
`runtime.rt_add_i64(...)` instead of binding 93 locals in `module()`. Collapses
all helper upvalues to one, at the price of a hash lookup per call site.

**H4 — runtime helpers re-localised per function.** Keep the `runtime` table as
the single upvalue but emit `local rt_add_i64 = runtime.rt_add_i64` at the top
of each body. Costs one local per helper — straight into the 200 local limit,
which `lua-no-ffi` already fights.

**H5 — pack everything, always.** One table upvalue per scope holding every
dependency; each use site becomes `t[k]`. Simple and uniform.

**H6 — hybrid / adaptive.** Rank the captures by how often the body reads them,
keep the hot ones as real upvalues, move only the overflow into the table.

**H7 — two level closure with entry re-localisation.** Pack into a table, then
re-bind the packed values to locals once on function entry, so the body still
sees plain locals. Trades upvalues for locals and one table read per call.

**H8 — outline giant functions.** Split one WebAssembly function into several
Lua functions by region, passing state through a table. The only strategy that
also addresses the 200 local and 65535 byte jump limits, and by far the most
invasive.

A ninth idea — putting function cells in one array `F` and calling `F[i](...)`
— is a special case of H5/H6 restricted to one class of dependency, and the
measurements below make it unnecessary.

---

## 3. Micro-benchmarks

Pure Lua, no generated code, `min` of 5 runs. Two shapes: the access patterns
in isolation, and a synthetic "generated WebAssembly function" that mixes five
runtime helper calls with three global cell reads in a loop, called both as one
long loop (JIT friendly) and as many short calls (8 iterations each).

### 3.1 Isolated access patterns

`call/*` is a two argument helper called in a tight loop, `load/*` a memory
load helper, `cell/*` a `t[1]` read out of a global cell. Ratios are against
the upvalue variant of the same row group.

| pattern | JIT on | JIT off |
|---|---:|---:|
| call through upvalue | 1.00x | 1.00x |
| call through `t.field` | 1.48x | 1.37x |
| call through `t[k]` | 1.01x | 1.32x |
| call through local re-bound at entry | 1.00x | 0.87x |
| load helper through upvalue | 1.00x | 1.00x |
| load helper through `t.field` | 0.99x | 1.15x |
| load helper through `t[k]` | 1.02x | 1.09x |
| cell read through upvalue | 1.00x | 1.00x |
| cell read through `t[k][1]` | 0.98x | 1.48x |
| cell read through local re-bound at entry | 0.99x | 0.79x |

Two things to take away. First, a local re-bound at function entry is *faster*
than an upvalue in the interpreter (`MOV` versus `UGET`) and identical once
compiled. Second, with the JIT on and a loop that runs long enough to be
compiled, the loop invariant table load is hoisted and the table forms cost
almost nothing — the residual 1.48x on `t.field` is the one hash lookup that
survives per call in a loop body that does almost nothing else.

### 3.2 Representative function shape

Five helper calls and three cell reads per iteration.

| variant | long loop, JIT | short calls, JIT | long loop, no JIT | short calls, no JIT |
|---|---:|---:|---:|---:|
| A: everything an upvalue | 1.00x | 1.00x | 1.00x | 1.00x |
| B: everything `t[k]` at the use site | **2.68x** | **2.14x** | 1.24x | 1.37x |
| C: `t[k]` re-localised on entry | 0.96x | 1.41x | 0.95x | 1.15x |
| D: helpers through `runtime.field` | 1.64x | 1.58x | 1.54x | 1.44x |

This is the decisive measurement.

* **H5 (always pack, read at the use site) is the most expensive option**, up
  to 2.7x on compiled code — worse with the JIT on than with it off, because
  the repeated guarded table loads are exactly what the trace compiler would
  otherwise have removed. The current `PACKED_SCOPED_DEPENDENCIES_THRESHOLD`
  path is this variant.
* **H3 (`runtime.field`) costs a flat ~1.5x** on helper heavy code, everywhere.
  It would make every generated module slower to fix a problem that five
  modules have.
* **H7 (re-localise on entry) is free for functions that do real work** and
  costs ~1.4x for functions that are called constantly and return immediately,
  where the entry rebinding cannot amortise.

---

## 4. End to end experiments

Three compiler variants were built and every fixture regenerated with each:

* `base` — the compiler as it was: pack all dependencies when a scope has ≥ 48
  of them, read them back at each use site.
* `packall` — H5 taken to its limit: pack every dependency of every scope.
  Included to price the "just always pack" answer end to end.
* `final` — the recommendation of §5: parameter wrapper plus budget driven
  partial packing.

### 4.1 Upvalue ceilings

| fixture | base max | packall max | final max |
|---|---:|---:|---:|
| real-world-gltf-rs | **load error** | 46 | 58 |
| real-world-cgltf | 58 | 20 | 57 |
| self-hosting-luanoffi-builder | 54 | 41 | 57 |
| real-world-lodepng | 56 | 27 | 56 |
| real-world-binjgb | 53 | 34 | 53 |
| real-world-libjpeg-turbo | 51 | 27 | 51 |
| real-world-tinyexpr | 26 | 23 | 25 |
| real-world-wasm3 | 34 | 20 | 34 |

`final` reduces the *mean* upvalue count of every module by roughly 8 % (for
example `tinyexpr` 5.32 → 4.74, `wasm3` 9.57 → 8.39) purely by removing the
redundant wrapper closure, without packing anything in those modules.

Two ceilings go *up* slightly under `final` — `self-hosting` 54 → 57 and
`gltf_rs`'s worst surviving body to 58. That is the budget doing its job: the
old code packed a scope the moment it had 48 dependencies whether or not it was
in danger, and the new code packs only as far as it must, so the modules that
do pack land just under the budget instead of far below it.

### 4.2 Generated size

Bytes of generated Lua, all three variants built from one compiler and one
upstream tree.

| fixture | base | packall | final | final vs base |
|---|---:|---:|---:|---:|
| real-world-tinyexpr | 226 805 | 238 996 | 225 431 | −0.6 % |
| real-world-miniz | 458 037 | 462 571 | 457 223 | −0.2 % |
| real-world-cgltf | 949 276 | 966 176 | 946 296 | −0.3 % |
| real-world-lodepng | 1 487 236 | 1 526 557 | 1 481 515 | −0.4 % |
| real-world-binjgb | 1 620 666 | 1 767 881 | 1 617 025 | −0.2 % |
| real-world-wasm3 | 1 368 036 | 1 471 586 | 1 350 140 | −1.3 % |
| self-hosting-luanoffi-builder | 2 090 175 | 2 211 353 | 2 069 146 | −1.0 % |
| real-world-gltf-rs | 8 078 129 | 8 341 040 | 8 011 284 | −0.8 % |

`final` is smaller everywhere (one closure and one `local` line per WebAssembly
function disappear); `packall` is 1–9 % larger because every use site grows a
`__spider_scoped_dependencies[k]` subscript.

### 4.3 Run time

Wall clock timing of whole runner processes turned out to be useless on this
machine: it was shared with other builds throughout (load average 10–40 on 16
cores) and repeated best-of-five runs of the *same* generated file disagreed by
up to 30 %. Two runs of the same A/B/C sweep put `final` 16 % faster than
`base` on `lodepng` and then 29 % slower.

The measurements below therefore load **all variants into one LuaJIT process**
and alternate their workloads round-robin, taking the minimum per variant, so
every variant sees the same machine weather within the same run
(`exp/paired.lua`). Ratios are against `base`.

| workload | reps | base | budget (`final`) | packall |
|---|---:|---:|---:|---:|
| `tinyexpr_hash(200000)` | 30 | 1.000x (0.544 s) | **0.947x** | — |
| `tinyexpr_hash(200000)` | 30 | 1.000x (0.496 s) | — | **1.047x** |
| `lodepng_roundtrip_hash(1)` x2 | 15 | 1.000x (0.265 s) | **1.019x** | — |
| `miniz_roundtrip_hash(6)` x20 | 20 | 1.000x (1.11 ms) | **0.909x** | 0.982x |

`base` versus `final` is a wash on every fixture, as it must be: outside
`gltf_rs` and the self-hosting fixture, `final` changes only the shape of the
one-time instantiation code, never the closures that run afterwards.

`gltf_rs` cannot be compared against `base` at all, because `base` does not
load. Against `packall`, in one process, twelve alternating runs:

| variant | parse | instantiate | `gltf_compute_hash` | result |
|---|---:|---:|---:|---|
| budget (`final`) | 0.077 s | 0.0027 s | **0.02776 s** | `-659558708` |
| packall | 0.067 s | 0.0029 s | 0.02823 s (1.017x) | `-659558708` |

For this benchmark the five packed bodies are not on the hot path, so the two
agree. The microbenchmark in §3.2 is what prices the case where they would be,
and `tinyexpr` (1.047x for `packall` over a fixture that needs no packing at
all) is the corpus-level version of the same tax.

Whole-process wall clock, best of 3–6 under the load described above, kept only
because it is what the reproduction steps produce and because it records the
`base` failure:

| fixture | base | budget (`final`) | packall |
|---|---|---|---|
| tinyexpr (500k) | 1.61 s | 1.74 s | 1.84 s |
| miniz | 0.09 s | 0.09 s | 0.11 s |
| lodepng v1 | 0.69 s | 0.58 s | 0.64 s |
| chipmunk 400/400/400/120 | 6.03 s | 6.14 s | 6.42 s |
| binjgb 6 frames | 4.04 s | 3.61 s | 3.97 s |
| gltf-rs | **fails to load** | 0.11 s | 0.11 s |

Read the spread, not the individual cells.

### 4.4 Load time

`parse` is `loadfile`, `instantiate` is calling the chunk and then the returned
`module` function, both best of 5.

| fixture | parse | instantiate |
|---|---:|---:|
| real-world-tinyexpr | 0.0020 s | 0.0001 s |
| real-world-miniz | 0.0035 s | 0.0001 s |
| real-world-cgltf | 0.0080 s | 0.0003 s |
| real-world-binjgb | 0.0107 s | 0.0012 s |
| real-world-lodepng | 0.0109 s | 0.0005 s |
| real-world-gltf-rs | 0.0770 s | 0.0027 s |

Parsing an 8 MB module costs 77 ms, which is the dominant fixed cost of
`gltf_rs` and is unaffected by any of the strategies (`packall` parses in
0.067 s, `final` in 0.077 s, both within the noise of a loaded machine).

### 4.5 Correctness

Every runner produces the same values under `base` and `final`:

| runner | result |
|---|---|
| `tinyexpr/main.lua` | Hash 141480662, Error 6 |
| `miniz/main.lua` | 58679047 / 2152 / 2035028898 / 1263729890 / 828487727 |
| `lodepng/main.lua lua-no-ffi 1` | -998874337 / 6518 / 496467531 / 496461629 / -1526580224 |
| `chipmunk-profile/main.lua lua-no-ffi 40 40 40 12` | identical under both |
| `binjgb/main.lua lua-no-ffi 4` | identical under both |
| `cgltf/main.lua` | Hash -834878637, identical under both |
| `wasm3/main.lua` | `ERROR code=-4` under both (a pre-existing failure) |
| `gltf-rs/main.lua` | Hash -659558708 — **`base` cannot load the module at all** |

`cargo test -p conformance --test luanoffi` stays at 280 / 312.

One measurement artefact worth recording: loading two `lodepng` modules into a
single LuaJIT process segfaults, because each instantiates its own linear memory
as a Lua table. Each module is correct on its own; this is the harness running
out of room, not a miscompile.

---

## 5. Recommendation

Adopt **H2 + H6 with the wrapper fix**, which is what `final` measures:

1. **Bind scope dependencies as parameters, not locals.**

   ```lua
   -- before
   loc_821_[1] = (function()
   	local loc_0_ = loc_866_;
   	local loc_1_ = loc_872_;
   	return rt_function_type((function(...) ... end), "key")
   end)();

   -- after
   loc_821_[1] = (function(loc_0_, loc_1_)
   	return rt_function_type((function(...) ... end), "key")
   end)(loc_866_, loc_872_);
   ```

   The sources are now evaluated in the `module` body, where they are plain
   locals, so the wrapper stops capturing them. This removes one closure and
   one call per WebAssembly function, shrinks every module, and fixes §1.2
   outright: `cgltf`'s worst prototype drops from 58 to 57, and the worst
   prototype of a module is now always its body rather than its wrapper.

   Dependency sources are loaded independently of one another by the builder
   (`Targets/LuaNoFFI/Builder/src/data_handler.rs`, `load_dependencies`), so
   evaluating them all before the call is equivalent to the old sequential
   `local` bindings.

2. **Decide packing from the real demand, not from the dependency count.**
   `Captures::of(function)` (new, `Targets/LuaNoFFI/Printer/src/captures.rs`)
   walks the body once and reports the distinct runtime helpers it names and
   how often it reads each local. The budget is

   ```
   CAPTURE_BUDGET = LUA_MAX_UPVALUES (60) - RESERVED_UPVALUES (3) = 57
   ```

   where the reserve covers `excess_stack` (the only uncounted capture ever
   observed) plus two slots of margin.

3. **Pack only the overflow, coldest first.** When
   `dependencies + helpers > 57`, sort the dependencies by how many times the
   body reads them and move the least used `demand + 1 - 57` of them into one
   table upvalue. The hot dependencies stay real upvalues.

### Why this and not the others

* It is **a no-op for every module that was not in danger**. Across the whole
  corpus exactly **6 scopes** pack (5 in `gltf_rs`, 1 in
  `self-hosting-luanoffi-builder`); zero in `tinyexpr`, `miniz`, `lodepng`,
  `chipmunk`, `binjgb`, `libjpeg-turbo`, `wasm3`, `plmpeg`, `h264bsd`. Those
  modules are byte identical to `base` apart from the wrapper rewrite, which
  §4.2/§4.3 show is neutral-to-positive.
* `packall` (H5) is a 2.1–2.7x slowdown in the shape that matters (§3.2) and
  makes every module 1–9 % larger, to buy headroom nothing needs.
* `runtime.field` (H3) is a flat ~1.5x tax on all helper calls in all modules.
* Re-localising on entry (H7) is attractive — free or better for real work —
  but it spends locals, and the modules that need packing are exactly the ones
  already spilling locals to `excess_stack` (the builder caps fast locals at
  197 in `local_allocator/local_provider.rs`). With partial packing touching
  only 6 scopes corpus-wide, there is nothing left for it to buy. It stays on
  the shelf as the answer if a future module has a *hot* over-budget function.
* Outlining (H8) remains the only real answer to the other two limits, and
  should be revisited on its own terms rather than as an upvalue fix.

### What it costs

* One extra traversal of each function body at print time (`Captures::of`).
  Regenerating all 28 fixtures still takes ~6 s end to end.
* `gltf_rs`'s five packed bodies read 55–58 of their dependencies through
  `__spider_scoped_dependencies[k]` instead of an upvalue. By §3.2 that is up
  to 2.7x *on those five functions* if they turn out to be hot; §4.3 shows the
  `gltf_compute_hash` benchmark does not notice.
* `RESERVED_UPVALUES = 3` is calibrated against measurement, not proof. If a
  future lifter change makes a body capture something new from `module()` —
  another `module_locals`-style table, say — the reserve has to grow with it.

---

## 6. What is still unsolved

* **A body that names more than ~56 distinct runtime helpers cannot be fixed
  by dependency packing**, because the helpers are `module()` locals and every
  emission site writes the name literally (`write!(out, "rt_{intrinsic}(")`,
  31 sites across `expression.rs` and `statement.rs`). The observed maximum is
  45 (`gltf_rs`), so there is real headroom, but it is headroom and not a
  guarantee. The fix, if it is ever needed, is to route every helper name
  through one printer method so it can be redirected to
  `__spider_scoped_dependencies[k]` or `runtime.<name>` per function; H3's
  measured cost says do that per function and only when over budget.
* **The scope wrapper still captures the helpers its body uses** plus
  `rt_function_type`, so a wrapper needs `helpers + 2` upvalues. Same headroom,
  same fix.
* **200 locals per function** is untouched by this work. The `module_locals`
  spill and the builder's 197 local cap remain the only defences, and
  `docs/notes/lua-no-ffi-known-bugs.md` bug #2 is still the accounting to fix.
* **65 535 byte jump range** is untouched, and only outlining (H8) addresses
  it.
* A latent hazard predates this work: `print_function_body` propagates a
  leading `local_a = local_b` copy by aliasing `local_a` to `local_b`'s printed
  name. If `local_a` were later reassigned, the generated code would write back
  into the packed dependency table. No fixture currently emits such a write
  (`grep -c '^\s*__spider_scoped_dependencies\[[0-9]*\] = '` is 0 everywhere),
  but nothing enforces it.

---

## 7. Reproducing

```bash
export CARGO_TARGET_DIR=/tmp/spider-target
cargo build --release -p spider-cli

# regenerate a fixture
target/release/spider-cli tests/manual/real-world-gltf-rs/generated/gltf_rs.wasm \
	-t lua-no-ffi > tests/manual/real-world-gltf-rs/generated/gltf_rs.lua

# upvalue census: walk every prototype of a chunk
cat > /tmp/upvals.lua <<'LUA'
local u = require("jit.util")
local f = assert(loadfile(arg[1]))
local seen, max = {}, 0
local function walk(pt)
	if seen[pt] then return end
	seen[pt] = true
	local i = u.funcinfo(pt)
	if i.upvalues > max then max = i.upvalues end
	local k = -1
	while true do
		local c = u.funck(pt, k)
		if c == nil then break end
		if type(c) == "proto" then walk(c) end
		k = k - 1
	end
end
walk(f)
print("max upvalues", max)
LUA
luajit /tmp/upvals.lua tests/manual/real-world-gltf-rs/generated/gltf_rs.lua
# -> max upvalues	58

# run it
luajit tests/manual/real-world-gltf-rs/main.lua
```
