# `lua-no-ffi` Performance Hypotheses

A hypothesis-driven measurement series on the memory and value representations used by the
`lua-no-ffi` target, and a transition plan derived from the numbers.

Written: `2026-09-21`. Host: `LuaJIT 2.1.0-beta3`, `x64`, `Linux` (WSL2), 16 logical cores.

This note is **research only**. Nothing in `Targets/`, `IR/` or `Sources/` was changed to produce it.
All experiments are reproducible from the scripts listed in the [Appendix](#appendix-scripts-and-raw-data).

---

## 0. Method and noise

- Every timing is `os.clock()` (CPU seconds) taken as the **minimum of N runs**, `N >= 5` for
  micro-benchmarks and `N >= 3..7` for fixtures, each run in a **fresh `luajit` process** so that
  one design cannot pollute another design's traces.
- Memory is reported two ways: `collectgarbage("count")` after a full collection (Lua heap only)
  and max RSS from `/usr/bin/time -f "%e %M"` (whole process).
- Warm-up runs the identical kernel over the identical region at least once before timing, so the
  reported figures are steady-state JIT numbers unless the row says `JIT off`.
- **The machine was shared with other agents.** Load average moved between `~3` and `~37` during
  the session. Repeating an identical sweep reproduced most rows within `±3%`, but individual rows
  drifted up to `±35%`, and absolute times in a sweep taken under load `37` are roughly `2x` the
  same sweep under load `3`. **Ratios inside one sweep are stable; absolute times across sweeps are
  not.** Every table below therefore also carries a ratio column, and comparisons are only made
  within a single sweep.
- Correctness is checked before speed: `scratchpad/perf/verify.lua` drives `3000` random aligned
  32-bit stores, `3000` random byte stores and `15000` random loads (byte, aligned word, unaligned
  word) per design against an independent byte-array reference. All candidate designs pass.
  Every macro and end-to-end run below also compares its result against `wasmtime`.

### 0.1 Designs under test

| Id | Name | Layout |
| --- | --- | --- |
| `D0` | `d0_ffi` | **Reference only.** `ffi.new("uint8_t[?]")` with `uint32_t*` / `uint8_t*` views. Not a candidate. |
| `D1` | `d1_overlay` | Today's design: base string `__s`, logical length `__n`, overlay table `__d` of bytes keyed 1-based. |
| `D2` | `d2_bytes` | Dense byte array, `table.new(n, 0)`, slots `1..n` pre-zeroed. |
| `D3` | `d3_words` | Packed `u32` words, `w[rshift(addr,2)+1]`, **unsigned** load contract (`x < 0 and x + 2^32 or x`). |
| `D3s` | `d3s_words_signed` | Same storage, **signed** (`bit.tobit`) load contract, no fix-up. |
| `D3a` | `d3a_words_arith` | Same storage, byte split/merge with `%` and `math.floor` instead of the `bit` library. |
| `D4` | `d4_halves` | Packed `u16` halves. |
| `D5` | `d5_pack6` | 6 bytes per slot (48 bits inside a double). |
| `D7` | `d7_pages` / `d7s_pages_signed` | 64 KiB pages, each a `u32` word table; `p[rshift(a,16)+1][...]`. |

`D5` also stands in for "two `u32` per double": that is impossible without loss, because two `u32`
need 64 bits and a double carries only 53 exact integer bits. `6` bytes (48 bits) is the largest
byte-aligned packing that fits.

---

## 1. Environment and capability probe

**Hypothesis (H8, H9, H17):** `string.buffer`, `table.new` and `string.pack` may or may not exist
on this LuaJIT and would change the design space.

| Facility | Result | Consequence |
| --- | --- | --- |
| `jit.version` | `LuaJIT 2.1.0-beta3` | – |
| `require("table.new")` | **available** | Usable for exact preallocation. |
| `require("table.clear")` | **available** | Usable for `memory.fill`-style resets. |
| `require("string.buffer")` | **absent** (`module 'string.buffer' not found`) | **H8 rejected**: `string.buffer` is 2.1-rolling only. Depending on it would break every 2.1.0-beta3 host, which is the version this project actually ships against. |
| `string.pack` | `nil` | **H17 partly rejected**: no `string.pack`/`string.unpack` float punning. |
| `math.frexp` / `math.ldexp` | present, but **NYI for the JIT** | Confirmed with `luajit -jv`: `[TRACE 1 ... stitch math.frexp]`. Every `frexp` call splits the trace. This is the single most expensive thing in the current float path. |
| `require("ffi")` | available | Used **only** as a reference baseline. |
| `require("bit")` | available | – |

Script: `scratchpad/perf/probe.lua`.

---

## 2. Memory representation, micro-benchmarks

**Setup.** 1 MiB region, filled through each design's own 32-bit store with a deterministic
non-zero pattern, then swept sequentially. `10.5M` accesses for the 32-bit and byte kernels,
`5.2M` for the 64-bit kernels, `10 MiB` moved for `copy`, `20 MiB` for `fill`. Accessors are
emitted **inline** into each kernel by `gen.py`, so no design pays a call overhead the others do
not. Every design carries the same bounds check (`a < 0 or a + size > n`).

Sweep: `scratchpad/perf/out/mem_final.tsv` (single internally consistent run, min-of-5, taken
under high host load — read the ratio columns).

| Kernel | `D1` overlay | `D2` bytes | `D3s` words | `D3` words (unsigned) | `D3a` words (arith) | `D4` halves | `D5` pack6 | `D7s` pages | `D0` ffi |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `load_i32` aligned | `0.0408` | `0.0360` | **`0.0177`** | `0.0522` | `0.0310` | `0.0276` | `0.1077` | `0.0173` | `0.0106` |
| | `1.00x` | `1.13x` | **`2.31x`** | `0.78x` | `1.32x` | `1.48x` | `0.38x` | `2.36x` | `3.86x` |
| `store_i32` aligned | `0.0350` | `0.0350` | **`0.0165`** | `0.0124` | `0.0213` | `0.0184` | `0.4702` | `0.0328` | `0.0187` |
| | `1.00x` | `1.00x` | **`2.12x`** | `2.81x` | `1.64x` | `1.90x` | `0.07x` | `1.07x` | `1.87x` |
| `load_u8` | `0.0147` | `0.0146` | `0.0263` | `0.0252` | `0.0491` | `0.0250` | `0.0958` | `0.0348` | `0.0134` |
| | `1.00x` | `1.01x` | **`0.56x`** | `0.58x` | `0.30x` | `0.59x` | `0.15x` | `0.42x` | `1.10x` |
| `store_u8` | `0.0163` | `0.0117` | `0.0419` | `0.0414` | `0.0861` | `0.0645` | `0.1221` | `0.0469` | `0.0085` |
| | `1.00x` | `1.39x` | **`0.39x`** | `0.39x` | `0.19x` | `0.25x` | `0.13x` | `0.35x` | `1.92x` |
| `load_i32` unaligned | `0.0411` | `0.0424` | `0.0680` | `0.0669` | `0.0710` | `0.0451` | `0.1426` | `0.0775` | `0.0309` |
| | `1.00x` | `0.97x` | **`0.60x`** | `0.61x` | `0.58x` | `0.91x` | `0.29x` | `0.53x` | `1.33x` |
| `load_i64` (2 words) | `0.0895` | `0.0941` | **`0.0281`** | `0.0716` | `0.0436` | `0.0421` | `0.2436` | `0.0503` | `0.0225` |
| | `1.00x` | `0.95x` | **`3.18x`** | `1.25x` | `2.05x` | `2.13x` | `0.37x` | `1.78x` | `3.99x` |
| `store_i64` | `0.0787` | `0.0960` | **`0.0316`** | `0.0270` | `0.0547` | `0.0535` | `0.9595` | `0.0360` | `0.0187` |
| | `1.00x` | `0.82x` | **`2.49x`** | `2.91x` | `1.44x` | `1.47x` | `0.08x` | `2.19x` | `4.22x` |
| `copy` 10 MiB bulk | `0.0087` | `0.0101` | **`0.0021`** | `0.0021` | `0.0021` | `0.0043` | `0.1376` | `0.0086` | `0.0002` |
| | `1.00x` | `0.87x` | **`4.21x`** | `4.15x` | `4.23x` | `2.03x` | `0.06x` | `1.02x` | `39.6x` |
| `fill` 20 MiB | `0.0123` | `0.0066` | **`0.0014`** | `0.0014` | `0.0018` | `0.0038` | `0.2455` | `0.0121` | `0.0003` |
| | `1.00x` | `1.86x` | **`8.62x`** | `8.68x` | `6.78x` | `3.28x` | `0.05x` | `1.02x` | `41.1x` |

`D7s`'s `copy`/`fill` rows are pessimistic: the harness resolves the page per element. A real
paged runtime hoists the page lookup per 64 KiB block and lands near `D3s`.

### Verdicts

| Hypothesis | Verdict |
| --- | --- |
| **H2** dense byte array beats the overlay | **Weak accept for speed, reject overall.** `D2` matches or slightly beats `D1` on every kernel (`0.82x`–`1.86x`) but costs the same `8 B/byte`. It is a simplification, not a win. |
| **H3** packed 32-bit words win | **Accept, with a caveat.** `2.1x`–`8.6x` on aligned 32/64-bit access, bulk copy and fill; `0.39x`–`0.60x` on byte access and unaligned words. Since C-generated wasm is 57–66% aligned `i32`/`i64` traffic (§6.3), the mix favours words. |
| **H3-unsigned** the `u32` load contract is free | **Rejected, and it is the single biggest trap.** `D3` differs from `D3s` only by `x < 0 and x + 2^32 or x` on the load path, and pays `2.95x` on `load_i32` (`0.0522` vs `0.0177`). The branch is taken for ~half of all real values, which turns one trace into a side-trace pair. |
| **H4** 16-bit halves are a good middle ground | **Rejected.** `D4` is worse than `D3s` on every 32/64-bit kernel and on `store_u8`, its only advantage being unaligned loads, while costing `2x` the memory of `D3s`. |
| **H5** 6-bytes-per-slot / 53-bit packing | **Rejected decisively.** `0.05x`–`0.38x` everywhere. `addr / 6` and `addr % 6` cost a real division on every access, and a 32-bit store touches two slots with a read-modify-write per byte. "Two `u32` per double" is arithmetically impossible (64 > 53 bits). |
| **H7** pages vs a flat array | **Accept for growth, mild speed cost.** `D7s` is within `1.07x`–`2.36x` of `D1` and `0.45x`–`0.73x` of `D3s` on hot loads; see §4 and §6.4 for the decisive numbers. |
| **H10** `bit` ops beat `%`/`math.floor` for byte splitting | **Accept.** `D3a` is `1.6x`–`1.9x` slower than `D3s` on byte work and `1.75x` on aligned loads, with identical storage. The one place arithmetic ties is bulk `copy`, where neither is used per byte. |

### 2.1 Interpreter (`luajit -joff`)

Generated modules are large; hot functions that exceed trace limits or run once fall back to the
interpreter, so this column matters.

| Kernel | `D1` | `D2` | `D3s` | `D7s` | `D0` ffi |
| --- | ---: | ---: | ---: | ---: | ---: |
| `load_i32` | `0.0260` | `0.0155` | **`0.0126`** | `0.0203` | `0.0283` |
| `store_i32` | `0.0346` | `0.0331` | **`0.0122`** | `0.0283` | `0.0271` |
| `load_u8` | `0.0530` | **`0.0278`** | `0.0979` | `0.1476` | `0.0970` |
| `store_u8` | `0.0487` | **`0.0307`** | `0.1520` | `0.2080` | `0.0933` |
| `load_i64` | `0.0275` | `0.0173` | **`0.0137`** | `0.0225` | `0.0299` |

Two notes. First, the word design's interpreter penalty on byte access (`1.8x`–`3.1x` vs `D1`) is
larger than under the JIT, because each `bit.*` call is a real interpreter call. Second, **FFI is
the slowest design in the interpreter** — cdata indexing has no interpreter fast path. That is a
useful sanity check on how much of the FFI target's advantage is JIT-only.

---

## 3. Access path: helper call vs inline, and the bounds check

**Hypothesis (H11):** the generated code calls `rt_load_i32`/`buffer_read_u32` through an upvalue;
inlining the expression would be faster.

1 MiB word memory, `10.5M` accesses (`4` reps = `1.05M` with the JIT off).
Script: `scratchpad/perf/bench_misc.lua`.

| Variant | JIT on | ratio | JIT off | ratio |
| --- | ---: | ---: | ---: | ---: |
| fully inline expression | `0.00849` | `1.00x` | `0.01702` | `1.00x` |
| call through an upvalue (what the printer emits today) | `0.00852` | `1.00x` | `0.03004` | `0.57x` |
| call through a table field (`runtime.load(...)`) | `0.00848` | `1.00x` | `0.03547` | `0.48x` |
| inline, **no bounds check** | `0.00725` | `1.17x` | `0.01082` | `1.57x` |
| inline store | `0.00969` | `1.00x` | `0.02048` | `1.00x` |
| upvalue store | `0.01223` | `0.79x` | `0.03462` | `0.59x` |

**Verdict (H11): accept, but only for the interpreter.** Under the JIT the trace recorder inlines
the helper completely and the three call forms are indistinguishable (`<0.5%` apart). With the JIT
off, an upvalue call costs `1.77x` and a table-field call `2.08x`. Stores are the exception even
under the JIT: the upvalue store is `1.26x` slower, because the extra argument and the `destination[1]`
indirection survive.

**Corollary:** the bounds check costs `17%` under the JIT and `57%` in the interpreter. Eliminating
provably-in-range checks is worth roughly as much as the entire helper-call overhead, and much less
than picking the right representation — so it is a later optimisation, not a first one.

---

## 4. Footprint and growth

### 4.1 Footprint by design and write density (H20)

Memory of the declared size is created, then `10%` / `50%` / `100%` of bytes are written at a
regular stride. `luaKB` is `collectgarbage("count")` delta.
Script: `scratchpad/perf/footprint.lua`; raw: `scratchpad/perf/out/footprint.tsv`.

| Design | 16 MiB @10% | @50% | @100% | 64 MiB @10% | @50% | @100% |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `D1` overlay | `3.00x` | `8.00x` | `8.00x` | `3.00x` | `8.00x` | `8.00x` |
| `D2` bytes | `8.00x` | `8.00x` | `8.00x` | `8.00x` | `8.00x` | `8.00x` |
| `D3s` words | **`2.00x`** | **`2.00x`** | **`2.00x`** | **`2.00x`** | **`2.00x`** | **`2.00x`** |
| `D4` halves | `4.00x` | `4.00x` | `4.00x` | `4.00x` | `4.00x` | `4.00x` |
| `D7` pages (eager) | `2.00x` | `2.00x` | `2.00x` | `2.00x` | `2.00x` | `2.00x` |
| `D0` ffi | `1.00x` | `1.00x` | `1.00x` | `1.00x` | `1.00x` | `1.00x` |

Absolute worst case measured: `D1`/`D2` at `64 MiB`, `100%` written = `524 MB` Lua heap,
`527 MB` RSS. `D3s` at the same point = `131 MB` / `133 MB`.

Two findings that correct the assumption in the brief:

- The overlay's cost per written byte is **`8 B`, not `16–40 B`**, once the overlay is dense.
  LuaJIT's rehash promotes a densely populated integer-keyed table into the **array part**
  (`8 B` per `TValue`) regardless of insertion order — writing the pattern in descending address
  order produced exactly the same `8.00x` as ascending.
- At `10%` density the overlay stays in the **hash part** and costs `3.00x` of the *whole* memory,
  i.e. about `30 B` per written byte, and its peak RSS during rehash is higher than its final size
  (`297 MB` vs `197 MB` at 64 MiB/10%).
- A dense overlay can be worse than `8x` in practice: LuaJIT sizes the array part to a power of two,
  so a `4.12 MiB` memory grown incrementally produced a `65.7 MB` overlay = **`16x`** (§6.2).
  `table.new` avoids that rounding, which is why the word array measured exactly `2.07x` there.

### 4.2 Growth cost and `table.new` (H9, H21)

Building a zeroed memory of the target size five ways.
Script: `scratchpad/perf/bench_misc.lua grow <kind> <MiB>`.

| Strategy | 16 MiB build | Lua KB | max RSS | 64 MiB build | Lua KB | max RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| word array, `table.new` preallocated | **`0.0209 s`** | `32804` | `35456` | **`0.0824 s`** | `131108` | `133632` |
| word array, incremental growth | `0.0231 s` | `32805` | `35584` | `0.0927 s` | `131109` | `133632` |
| word array, double-and-copy realloc | `0.0417 s` | `32805` | **`68096`** | `0.1666 s` | `131111` | **`264576`** |
| 64 KiB pages, appended | `0.0215 s` | `32817` | `36352` | `0.0859 s` | `131157` | `137728` |
| byte overlay, dense | `0.0908 s` | `131109` | `133760` | `0.3834 s` | `524325` | `527104` |

**Verdict (H9): weak accept.** `table.new` is `10%` faster to build than incremental growth and
avoids the power-of-two rounding waste seen in §6.2; it does not change the steady-state size when
the array is grown to a power-of-two boundary anyway.

**Verdict (H21):** `memory.grow` is free in the overlay design (only `__n` changes) but every byte
later written costs `8 B`. For a flat word array, growth is a realloc-and-copy with a **`2x` peak
RSS spike** (`68 MB` while building a `33 MB` array) and `2x` the build time. For pages, growth is
appending `pages` new tables: same cost as a fresh build, no spike, no copy.

---

## 5. Value representations

### 5.1 `i64` (H12, H13, H14, H15, H22)

Kernels: `hash` = `xorshift64*` (shift/xor/64-bit multiply); `counter` = increment + compare;
`call` = a real, non-inlined function call taking and returning the value each iteration;
`escape` = the value is stored into a table every iteration (what the printer does when it spills
an `i64` local or calls `rt_store_i64`).
Script: `scratchpad/perf/bench_i64.lua`.

| Kernel | `T1` `{lo,hi}` table | `T2` two numbers | `T3` single double | `T4` ffi `int64_t` |
| --- | ---: | ---: | ---: | ---: |
| `hash`, JIT on, 1M | `0.0486` | `0.0484` (`1.00x`) | n/a | `0.0020` (`24.3x`) |
| `counter`, JIT on, 5M | `0.1392` | **`0.0267`** (`5.21x`) | `0.0274` (`5.08x`) | `0.0886` (`1.57x`) |
| `call`, JIT on, 5M | `0.0282` | **`0.0147`** (`1.92x`) | n/a | n/a |
| `escape`, JIT on, 5M | `0.1356` | **`0.0151`** (`9.01x`) | n/a | n/a |
| `hash`, JIT off, 200k | `0.1303` | `0.0951` (`1.37x`) | n/a | `0.0686` (`1.90x`) |
| `counter`, JIT off, 1M | `0.0557` | `0.0075` (`7.42x`) | `0.0044` (`12.7x`) | `0.0902` (`0.62x`) |
| `call`, JIT off, 1M | `0.0684` | `0.0222` (`3.08x`) | n/a | n/a |
| `escape`, JIT off, 1M | `0.0653` | `0.0257` (`2.55x`) | n/a | n/a |

Allocation totals, `1M` iterations, **GC stopped** so nothing is collected mid-run (H22):

| Kernel | `T1` table | `T2` two numbers | `T4` ffi `int64_t` |
| --- | ---: | ---: | ---: |
| `hash` | `0.2 KB` | `0.0 KB` | `0.1 KB` |
| `counter` | **`54 633 KB`** (`~55 B`/op) | `0.3 KB` | `15 610 KB` (`~16 B`/op) |
| `call` | `5 208 KB` | `0.0 KB` | n/a |
| `escape` | **`55 990 KB`** | `1.1 KB` | n/a |

**Verdict (H12 vs H13): `{lo, hi}` tables are rejected; two plain numbers win.**

The interesting nuance is *why* the `hash` kernel ties. LuaJIT 2.1's **allocation sinking**
eliminates the `{lo, hi}` table entirely when it never escapes the trace — `0.2 KB` allocated over
`1M` iterations. So in a self-contained arithmetic loop the table is free. It stops being free the
moment the value **escapes**: crossing an un-inlined call (`1.9x`, `5.2 MB`), being stored into a
table (`9.0x`, `56 MB`), or surviving a trace exit (`counter`: `5.2x`, `55 MB`). Generated wasm
modules escape `i64` values constantly — every function boundary, every `rt_store_i64`, every
spilled local. The `9.01x` `escape` row is the representative one, not the `1.00x` `hash` row.

**Verdict (H14, single 52-bit double): rejected.** `T3` is not measurably faster than `T2`
under the JIT (`0.0274` vs `0.0267`) and cannot represent the upper 11 bits at all. A hybrid
("small in a double, large in a table") would need a type test on every operation, which is
strictly more work than just carrying two numbers.

**Verdict (H15, `int64_t` cdata): rejected even as an aspiration, and instructive.** It is `24x`
faster on the pure-arithmetic `hash` kernel, but **`1.6x` slower than `T2`** on `counter` under the
JIT and `12x` slower in the interpreter, because every `uint64_t` arithmetic result allocates a
`16 B` cdata box. FFI `int64_t` is not a free win; it is a win only for dense 64-bit arithmetic.

### 5.2 `f32` (H16, H17)

Today an `f32` value is carried through the whole program as a `u32` **bit pattern**: `rt_load_f32`
returns raw bits, and every arithmetic op does `from_bits_f32` → native op → `into_bits_f32`.

Kernel: `2M` iterations of `acc = acc * step; acc = acc + 1.0` with f32 semantics.
Scripts: `scratchpad/perf/bench_f32.lua`, `scratchpad/perf/bench_f32b.lua`.

| Representation | JIT on (2M) | ratio | JIT off (200k) | ratio |
| --- | ---: | ---: | ---: | ---: |
| `f1` bits between ops (**today**) | `0.1470` | `1.00x` | `0.0630` | `1.00x` |
| `f2` double + `frexp`/`ldexp` rounding per op | `0.0924` | `1.59x` | `0.0191` | `3.31x` |
| **`f6` double + Veltkamp-split rounding per op** | **`0.0110`** | **`13.4x`** | **`0.0114`** | **`5.55x`** |
| `f4` double + `ffi` `float` cast per op (reference) | `0.0082` | `17.9x` | `0.0324` | `1.94x` |
| `f3` double, never rounded (**incorrect**, speed ceiling) | `0.0027` | `54.5x` | `0.0012` | `54.7x` |

The Veltkamp split is the key result. A correctly-rounded double → binary32 → double round trip
needs no `frexp` at all:

```lua
local SPLIT          = 2 ^ 29 + 1
local MIN_NORMAL_F32 = 2 ^ -126
local SUB_MAGIC      = 1.5 * 2 ^ -97        -- 1.5 * 2^52 * 2^-149
local OVERFLOW_F32   = 2 ^ 128 - 2 ^ 103    -- first double that rounds to inf

local function round_f32(x)
	local ax = x < 0 and -x or x
	if ax < MIN_NORMAL_F32 then return (x + SUB_MAGIC) - SUB_MAGIC end
	if ax >= OVERFLOW_F32 then
		if ax ~= ax then return x end
		return x < 0 and -math.huge or math.huge
	end
	local c = x * SPLIT
	return c - (c - x)
end
```

Verified bit-exactly against a real `float` cast on `320 024` values — `300 000` random doubles
spanning `2^-200 .. 2^200`, `20 000` concentrated in the subnormal band, plus hand-picked edges
(`0`, `-0.0`, `2^-149`, `2^-150`, `2^-126`, `16777217`, `2^128 - 2^104`, `2^128 - 2^103`,
`±inf`, `NaN`): **`0` mismatches**. It is fully JIT-compilable: no NYI call, one predictable branch.

Bit-pattern conversion at memory boundaries, `2M` conversions:

| Function | JIT on | ratio | JIT off | ratio |
| --- | ---: | ---: | ---: | ---: |
| `into_bits_f32`, `frexp` (**today**) | `0.1696` | `1.00x` | `0.0188` | `1.00x` |
| `into_bits_f32`, `log2`-based exponent | **`0.0366`** | **`4.64x`** | `0.0232` | `0.81x` |
| `into_bits_f32`, `ffi` (reference) | `0.0026` | `66.4x` | – | – |
| `into_bits_f64`, `frexp` (**today**) | `0.0364` | `1.00x` | `0.0136` | `1.00x` |
| `into_bits_f64`, `log2`-based exponent | `0.0349` | `1.04x` | `0.0216` | `0.63x` |
| `into_bits_f64`, `ffi` (reference) | `0.0014` | `26.6x` | – | – |

**Verdict (H16/H17):**
- **Reject** carrying `f32` as a bit pattern between operations. It is `13.4x` slower than
  necessary under the JIT.
- **Reject** the `frexp`/`ldexp` rounding variant (H17 as stated): correct, but `8.5x` slower than
  the split and NYI for the JIT.
- **Accept** carrying `f32` as a double rounded with the Veltkamp split after each operation, with
  bit conversion only at the memory boundary. This is within `1.34x` of a real hardware `float`
  cast and needs no FFI.
- **Reject** "keep `f32` as an unrounded double" (the `f3` row): `54x` faster but wrong; it would
  fail conformance on every `f32.add` that needs rounding. It is worth keeping as an opt-in
  `--fast-math` switch, not as the default.
- **Accept** replacing `frexp` with the `log2`-based exponent in `into_bits_f32` (`4.64x` under the
  JIT). For `into_bits_f64` the same change is worth only `1.04x` and costs `1.6x` in the
  interpreter — **not worth doing** on its own.

A latent bug found while writing the reference: scaling a subnormal double by `2 ^ 1074` overflows
to `inf`, because `2 ^ 1074` is not representable. Any future rewrite of `into_bits_f64` must scale
in two steps (`x * 2 ^ 537 * 2 ^ 537`). The current `into_bits_f64` is safe only because `frexp`
bounds the exponent first.

### 5.3 `i32` normalisation (H18)

`20M` iterations of `x = <normalise>(x * 3 + 7)`.

| Strategy | JIT on (20M) | ratio | JIT off (2M) | ratio |
| --- | ---: | ---: | ---: | ---: |
| `bit.tobit(x)` | `0.0785` | `1.00x` | `0.0240` | `1.00x` |
| `bit.bor(x, 0)` (**today**) | `0.0780` | `1.01x` | `0.0246` | `0.98x` |
| `x % 2^32` | `0.0824` | `0.95x` | `0.0302` | `0.80x` |
| lazy: normalise only when the value can exceed `2^50` | `0.0482` | `1.63x` | `0.0147` | `1.64x` |
| unsigned: `bor(x,0)` then `y < 0 and y + 2^32` | `0.1658` | `0.47x` | `0.0397` | `0.61x` |

**Verdict (H18):** the *operator* barely matters — `tobit`, `bor(x,0)` and `% 2^32` are within
`6%` under the JIT. The **representation** matters enormously: keeping values unsigned costs
`2.12x` in this loop, and `2.95x` on the memory load path (§2), because the sign fix-up is a
50/50 branch that splits every trace. Lazy normalisation is worth a further `1.63x` and is a valid
follow-on optimisation once the signed contract is in place.

---

## 6. Macro and end-to-end

### 6.1 Per-design macro kernels

CRC-32 (table-driven, table held in linear memory), Adler-32, a byte-wise `memcpy` loop, and an
aligned 32-bit sum, over a 4 MiB region. All designs return identical checksums.
Raw: `scratchpad/perf/out/macro_final.tsv`.

| Kernel | `D1` overlay | `D2` bytes | `D3s` words | `D4` halves | `D7s` pages | `D0` ffi |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `crc32` (12.6 MB) | `0.0574` | `0.0575` | `0.0601` | `0.0564` | `0.0605` | `0.0556` |
| `adler32` (12.6 MB) | `0.0845` | `0.0849` | `0.0871` | `0.0878` | `0.0929` | `0.0842` |
| `memcpy` byte loop (6 MB) | `0.0170` | `0.0149` | `0.0299` | `0.0432` | `0.0399` | `0.0091` |
| `sum32` (10.5M words) | `0.0426` | `0.0397` | **`0.0160`** | `0.0261` | `0.0240` | `0.0156` |

**Verdict:** in an *idealised* harness where every design gets an equally short access path, a
byte-serial kernel is dominated by its own arithmetic and the representation is nearly irrelevant
(`crc32`, `adler32` all within `10%`). The representation shows up on word-wide traffic (`2.7x`)
and, in the wrong direction, on byte-wise copy (`0.57x`). This is the honest floor of what a memory
representation can buy — and it is much smaller than what the *real* runtime gains, because the
real runtime's overlay path is far from idealised (§6.2).

### 6.2 End-to-end: the same generated module, two runtimes

A C kernel (`scratchpad/perf/kernel.c`, 4 MiB static array, CRC-32 / Adler-32 / byte `memcpy` /
`u32` sum) was compiled to wasm with `clang --target=wasm32 -O2` and then compiled by
`spider-cli -t lua-no-ffi`. The generated module was then **mechanically patched**
(`scratchpad/perf/patch_words.py`): the `buffer_*` runtime sections were replaced by a packed
32-bit word implementation with **identical section names and signatures**, so the generated module
body is byte-for-byte untouched. Two variants: `words_u` keeps today's *unsigned* `buffer_read_u32`
contract, `words_s` returns the signed bit pattern.

All four exports return **identical values** under `wasmtime`, the current runtime, `words_u` and
`words_s`.

| Kernel | current overlay | `words_u` (drop-in) | `words_s` (signed) | Lua heap: overlay → words | max RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `bench_crc32` (20 reps) | `0.678 s` | `1.144 s` (`0.59x`) | **`0.445 s`** (`1.53x`) | `65 660 KB` → `8 549 KB` (**`7.68x` less**) | `68 348` → `11 008 KB` |
| `bench_adler32` (20) | `0.548 s` | `0.520 s` (`1.05x`) | **`0.410 s`** (`1.34x`) | same | same |
| `bench_memcpy` (60) | `0.382 s` | `0.660 s` (`0.58x`) | `0.639 s` (`0.60x`) | same | same |
| `bench_sum32` (60) | `0.245 s` | `0.177 s` (`1.39x`) | **`0.087 s`** (`2.84x`) | same | same |

Two conclusions:

- The **unsigned contract must go**. `words_u` is `2.57x` slower than `words_s` on `crc32` and
  `1.69x` *slower than the current overlay*. A "drop-in" word memory that preserves the unsigned
  `buffer_read_u32` contract is a performance regression, not a win.
- The `4.12 MiB` memory costs `65.7 MB` as an overlay (**`16x`**, because LuaJIT rounded the array
  part up to the next power of two) and `8.5 MB` as a `table.new`-sized word array (`2.07x`).

### 6.3 `wasmtime` anchor and the static access mix

Same kernel, same rep counts. `wt_work` subtracts a measured `--invoke <fn> 0` startup
(`0.01–0.03 s`).

| Kernel | reps | `wasmtime` work | `lua-no-ffi` today | slowdown |
| --- | ---: | ---: | ---: | ---: |
| `bench_crc32` | 30 | `0.310 s` | `1.035 s` | `3.3x` |
| `bench_adler32` | 30 | `0.330 s` | `0.773 s` | `2.3x` |
| `bench_memcpy` | 100 | `0.050 s` | `0.552 s` | `11.0x` |
| `bench_sum32` | 100 | `0.020 s` | `0.276 s` | `13.8x` |

The `memcpy`/`sum32` rows flatter `wasmtime`: LLVM vectorises both, which no pure-Lua design can
match. They bracket the realistic range rather than defining a target.

Static access mix in the generated fixtures (`grep -c` on helper names) — this is what decides
whether the word design's word-side win outweighs its byte-side loss:

| Fixture | `i32` loads | `u8`/`s8` loads | `u16`/`s16` loads | `i64` loads | `i32` stores | `i8` stores | `i16` stores | `i64` stores |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `miniz` | `507` (61%) | `215` (26%) | `107` (13%) | `0` | `476` (66%) | `120` (17%) | `66` (9%) | `56` (8%) |
| `lodepng` | `1480` (57%) | `1013` (39%) | `73` (3%) | `35` (1%) | `898` (42%) | `748` (35%) | `103` (5%) | `401` (19%) |

### 6.4 Real fixtures

The same mechanical patch was applied to the checked-in generated modules for `chipmunk`,
`lodepng`, `miniz` and `tinyexpr`. Four memory variants were compared, interleaved round-robin,
min of 5, so host load drifts hit every variant equally. **Every variant produces bit-identical
results** to the unmodified module.

- `1-overlay` — unmodified, today's design.
- `2-flatwords` — one flat `table.new` word array, signed contract (`patch_words.py`).
- `3-eagerpages` — 64 KiB word pages, all pages allocated up front (`patch_pages_eager.py`).
- `4-lazypages` — 64 KiB word pages allocated on first touch, reads of untouched pages served from
  a shared zero page (`patch_pages.py`).

Raw: `scratchpad/perf/out/final2.tsv`.

| Fixture / variant | time | speed-up | Lua heap | max RSS |
| --- | ---: | ---: | ---: | ---: |
| `chipmunk` `chipmunk_hash_scene(60)` | | | | |
| &nbsp;&nbsp;overlay | `0.8289 s` | `1.00x` | `5 399 KB` | `14 440 KB` |
| &nbsp;&nbsp;**flat words** | **`0.0181 s`** | **`45.9x`** | `10 056 KB` | `15 488 KB` |
| &nbsp;&nbsp;eager pages | `0.0317 s` | `26.1x` | `10 187 KB` | `16 628 KB` |
| &nbsp;&nbsp;lazy pages | `0.3158 s` | `2.62x` | **`1 868 KB`** | **`8 780 KB`** |
| `lodepng` roundtrip + decode + png hash | | | | |
| &nbsp;&nbsp;overlay | `0.4050 s` | `1.00x` | `9 600 KB` | `22 984 KB` |
| &nbsp;&nbsp;**flat words** | **`0.1043 s`** | **`3.88x`** | `35 636 KB` | `46 568 KB` |
| &nbsp;&nbsp;eager pages | `0.1693 s` | `2.39x` | `34 472 KB` | `54 412 KB` |
| &nbsp;&nbsp;lazy pages | `0.2814 s` | `1.44x` | **`4 014 KB`** | **`12 020 KB`** |
| `miniz` crc32+adler32+fold+fold_prefix, per probe set | | | | |
| &nbsp;&nbsp;overlay | `0.728 ms` | `1.00x` | **`606 KB`** | `3 328 KB` |
| &nbsp;&nbsp;flat words | `0.705 ms` | `1.03x` | `2 631 KB` | `5 120 KB` |
| &nbsp;&nbsp;eager pages | `0.817 ms` | `0.89x` | `2 790 KB` | `5 760 KB` |
| &nbsp;&nbsp;lazy pages | `0.771 ms` | `0.94x` | `600 KB` | **`3 200 KB`** |
| `tinyexpr` `tinyexpr_hash(256)` | | | | |
| &nbsp;&nbsp;overlay | `7.595 ms` | `1.00x` | **`984 KB`** | `5 316 KB` |
| &nbsp;&nbsp;flat words | `1.749 ms` | `4.34x` | `1 679 KB` | `5 760 KB` |
| &nbsp;&nbsp;**eager pages** | **`1.628 ms`** | **`4.67x`** | `1 627 KB` | `5 356 KB` |
| &nbsp;&nbsp;lazy pages | `2.775 ms` | `2.74x` | `1 230 KB` | `5 552 KB` |

Reading these numbers:

- **`chipmunk` is the headline.** It is the fixture the measurement note records at `691x` slower
  than `wasmtime`. Swapping only the memory representation makes it **`45.9x` faster** with no
  change to the generated code. The reason is visible in §4.1: `chipmunk`'s memory is written
  sparsely, so its overlay lives in the table's **hash part**, and each `f64` load is eight hash
  lookups with `nil` tests and a `string.byte` fallback.
- **Byte-serial workloads are a wash.** `miniz`'s probe set is CRC-32 + Adler-32 + FNV folds over an
  8 KiB static buffer; there the overlay is small, dense and array-backed, and the word design buys
  `1.03x`. It does not lose either.
- **The memory direction flips with density.** On the dense 4 MiB kernel (§6.2) words use `7.7x`
  *less* memory. On these fixtures — which declare much more linear memory than they touch — flat
  words use `1.9x`–`3.7x` *more*. The break-even write density is roughly `12–25%`.
- **Lazy page materialisation is expensive under LuaJIT.** `4-lazypages` gives the best footprint
  everywhere (`2.9x` less than the overlay on `chipmunk`, `2.4x` less on `lodepng`) but costs
  `17.5x` versus flat words on `chipmunk` and `2.7x` on `lodepng`. The cost is *not* the two-level
  indirection: `3-eagerpages` uses the identical `p[pi][wi]` addressing and lands within
  `1.2x`–`1.8x` of the flat array. The cost is the `pg or zero` fallback on the read path, which
  the trace recorder has to treat as a diamond. A demand-paging variant using an `__index`
  metamethod instead of the `or` (`patch_pages3.py`) was also measured and is *worse*
  (`chipmunk` `0.376 s`), so the branch is not the whole story — a metatable on the page table
  defeats specialisation too.

---

## 7. Ranked recommendation

### 7.1 Memory

1. **Packed 32-bit words in one flat array, signed payload, `table.new`-preallocated.**
   `mem.__w[bit.rshift(addr, 2) + 1]` holding the `bit.tobit` form of the word.
   Evidence: `2.1x`–`8.6x` on aligned 32/64-bit access and bulk copy/fill (§2); `1.53x`–`2.84x`
   end-to-end on the same generated module (§6.2); `3.9x`–`45.9x` on real fixtures (§6.4);
   `7.7x` less memory when memory is densely written (§6.2); `2.00x` of declared size at any
   density (§4.1).
2. **Eager 64 KiB word pages** for memories above a threshold (suggested: declared minimum
   `> 64 MiB`, or whenever `memory.grow` is present in the module). Same footprint as (1), within
   `1.2x`–`1.8x` of its speed, but `memory.grow` appends pages instead of reallocating and copying,
   which removes the `2x` peak-RSS spike measured in §4.2. This also sidesteps LuaJIT's practical
   ceiling on a single table's array part.
3. **Keep the byte overlay only as a compatibility fallback**, if at all. It is never the fastest
   and only wins on footprint when write density is below ~`15%` — a case the lazy-page variant
   also covers, and covers better.

Rejected outright: dense byte array (`D2`, same memory as today, no speed win), 16-bit halves
(`D4`, dominated by `D3s` on both axes), 6-byte packing (`D5`, `0.05x`–`0.38x`), arithmetic byte
splitting (`D3a`, `1.6x`–`1.9x` slower than `bit` at identical storage), lazy pages as the default
(`D7`-lazy, `2.7x`–`17.5x` slower than flat words).

### 7.2 Values

1. **`i32`: one signed, normalised representation everywhere.** Loads return the `bit.tobit`
   bit pattern, not an unsigned magnitude. This is the highest-leverage single change in the whole
   note — it is worth `2.57x` end-to-end (§6.2) and is a prerequisite for the memory change rather
   than an independent optimisation.
2. **`i64`: two plain Lua numbers `(lo, hi)`**, carried as two locals, passed as two arguments and
   returned as two values. `1.9x`–`9.0x` under the JIT depending on how far the value escapes,
   `2.5x`–`7.4x` in the interpreter, and it removes `~55 B` of allocation per `i64` operation
   (§5.1). The `{lo, hi}` table is free only in loops where LuaJIT can sink it, which real
   generated code rarely offers.
3. **`f32`: a double, rounded with the Veltkamp split after each operation**, with `u32` bit
   conversion only at loads and stores. `13.4x` under the JIT, `5.6x` in the interpreter, bit-exact
   on `320 024` verification cases (§5.2).
4. **`f32` bit conversion: replace `frexp` with a `log2`-based exponent** in `into_bits_f32`
   (`4.64x` under the JIT). Do **not** do the same to `into_bits_f64` (`1.04x` under the JIT,
   `0.63x` in the interpreter).
5. **`f64`: leave as a native Lua number.** Already optimal.

### 7.3 Expected overall effect

| Axis | Today | After | Evidence |
| --- | --- | --- | --- |
| Sparse-memory, float-heavy workloads (`chipmunk`, `plmpeg`, `binjgb`, `h264bsd`) | `691x` slower than `wasmtime` | `~15x` | `45.9x` from memory alone (§6.4), before the `f32`/`f64` and `i64` changes |
| Codec workloads (`lodepng`, `libjpeg`) | `3.0x`–`3.3x` | `~1x`–`1.5x` | `3.88x` (§6.4) |
| Expression/parser workloads (`tinyexpr`) | `1.05x` | `~0.3x` | `4.34x` (§6.4) |
| Byte-serial archive kernels (`miniz` probes) | `2.4x` | `~2.3x` | `1.03x` (§6.4) — no gain, no loss |
| Byte-wise `memcpy` loops | – | **`0.60x` (a regression)** | §6.2 |
| Memory, densely-written | `8x`–`16x` of the wasm memory | `2.0x` | §4.1, §6.2 |
| Memory, sparsely-written, memory declared ≫ touched | `3x` of declared | `2.0x` of declared | §4.1, §6.4 |

---

## 8. Correctness risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| **Signedness contract change.** `buffer_read_u32` currently returns `0 .. 2^32-1`; the proposal returns `-2^31 .. 2^31-1`. Any consumer that compares two `i32` values with raw `<`/`==` would break if the two sides disagreed. | High, but already latent | The runtime already normalises: `rt_equal_i32` uses `force_i32` on both sides, and `rt_less_than_u32`/`rt_divide_u32`/`rt_remainder_u32` call `force_u32` first. Moving to signed everywhere makes the existing mixed-signedness situation *more* consistent, and lets many `force_*` calls be dropped afterwards. The host boundary (module exports) must decide one convention and the fixture harnesses must follow it — the checked-in `main.lua` files already apply their own `to_signed32`. |
| **Unaligned access** becomes `1.6x`–`1.9x` more expensive and is no longer a single table read. A bug in the two-word merge would be silent. | High | `verify.lua` already covers `5000` random unaligned loads per design. Wasm carries a static alignment hint per load/store; the printer should emit the aligned fast path when the hint allows it and a generic helper otherwise, and the two paths must be differentially tested. |
| **`memory.grow` semantics.** A flat word array must be reallocated and copied; a partially failed grow must leave the memory untouched. | Medium | Compute the new size, allocate, copy, then swap `__w` and `__n` in one step. Never mutate `__n` before the new array exists. |
| **`memory.copy` overlap.** The word fast path is only valid when source and destination share alignment and do not overlap in the wrong direction. | Medium | The reference implementation in `patch_words.py` takes the word path only when `band(dst,3) == 0 and band(src,3) == 0 and (dst ~= src or dst_offset <= offset)`, falling back to a directional byte loop otherwise. |
| **53-bit precision.** No candidate relies on more than 32 bits per slot, so the `2^53` boundary is never approached by the memory design. It *is* approached by any "`i64` in one double" scheme. | Low | H14 is rejected; the `(lo, hi)` pair keeps every intermediate below `2^53`. |
| **`f32` rounding edge cases.** The Veltkamp split must be exact for subnormals, the overflow boundary and `NaN`. | Medium | Verified bit-exactly on `320 024` cases including `2^-149`, `2^-150`, `2^128 - 2^104`, `2^128 - 2^103`, `±0`, `±inf`, `NaN`. `x * (2^29 + 1)` cannot overflow for float-range inputs (`3.4e38 * 5.4e8 = 1.8e47`). |
| **`2 ^ 1074` overflows to `inf`.** Any rewrite of `into_bits_f64` that scales subnormals in one step is wrong. | Medium | Scale as `x * 2 ^ 537 * 2 ^ 537`. Found while writing the reference implementation; the current runtime is safe only because `frexp` bounds the exponent. |
| **LuaJIT address-space limit.** A non-`GC64` LuaJIT can address roughly `1–2 GB`. A `64 MiB` wasm memory costs `524 MB` today. | Medium | The word design brings that to `131 MB`, a `4x` larger safe ceiling. This is a robustness argument, not only a performance one. |
| **Memory footprint regression on sparse memories.** Modules that declare far more memory than they touch get `1.9x`–`3.7x` *more* resident memory (§6.4). | Medium | Threshold the paged variant on declared size; or measure per-fixture and make it a CLI flag. |
| **Byte-copy loop regression (`0.60x`).** C code that copies byte-by-byte without going through `memcpy`/`memory.copy` gets slower. | Medium | Route `memory.copy`/`memory.fill` through the word fast path (already `4.2x`/`8.6x` faster than today, §2). Accept the residual regression for hand-rolled byte loops. |

---

## 9. Incremental migration plan

Each step is independently testable and independently revertable. Conformance (`cargo test -p conformance --test luanoffi`) gates every step.

**Step 1 — `i32` becomes signed end to end.** *No memory change yet.*
- `Targets/LuaNoFFI/Printer/runtime/builtin/buffer.lua`: `buffer_read_u32` / `buffer_read_u16` /
  `buffer_read_u8` return the `bit.tobit` form.
- `Targets/LuaNoFFI/Printer/runtime/core/i32.lua`: drop the now-redundant `force_i32` in
  `rt_equal_i32` / `rt_not_equal_i32`; keep `force_u32` in the unsigned comparison, division and
  remainder helpers (they already accept signed input).
- `Targets/LuaNoFFI/Printer/runtime/core/i64.lua`: `into_bits_i64` stops applying `% 2^32`.
- `Targets/LuaNoFFI/Printer/src/expression.rs` (the `buffer_read_u32` emission site, line ~855) and
  `Targets/LuaNoFFI/Printer/src/library/names_finder.rs` (`LoadType::*` → helper names): no name
  changes, but any place that assumes an unsigned load result must be audited.
- Host boundary: decide and document whether exports return signed or unsigned, and align the
  `tests/manual/*/main.lua` harnesses.
- Expected: neutral to `1.1x` on its own; unblocks Step 2, which is worth `2.57x` without it.

**Step 2 — packed 32-bit word memory.**
- Rewrite in `builtin/buffer.lua`: `buffer_create`, `buffer_resize`, `buffer_byte`,
  `buffer_read_u8/u16/u32`, `buffer_write_u8/u16/u32`, `buffer_writestring`, `buffer_copy`,
  `buffer_fill`, `buffer_len`, `ensure_dirty` (which disappears), `buffer_meta` (which disappears).
  `core/memory.lua` needs no change: `rt_load_*`/`rt_store_*` keep their signatures.
- `Targets/LuaNoFFI/Printer/src/library/sections.rs`: add the `table.new` dependency to the
  `buffer_create` section and drop the `ensure_dirty` / `buffer_meta` sections.
- Reference implementations, already validated against `wasmtime` on four fixtures, are in
  `scratchpad/perf/patch_words.py`.
- `rt_memory_grow` in `core/memory.lua`: allocate-copy-swap, never resize in place.
- Expected: `1.0x`–`45.9x` depending on fixture; footprint `2.00x` of declared memory.

**Step 3 — aligned fast path driven by the wasm alignment hint.**
- The printer already knows each access's static alignment. Emit `buffer_read_u32_aligned`
  (a single word read, no shift, no merge) when `align >= 2`, and keep the generic helper for the
  rest. Same for stores. Touches `Targets/LuaNoFFI/Printer/src/expression.rs` and
  `library/names_finder.rs`.
- Expected: removes the `sh == 0` branch from the majority of accesses.

**Step 4 — `f32` as a rounded double.**
- `core/f32.lua`: every `rt_*_f32` stops doing `from_bits` / `into_bits` and operates on doubles,
  applying `round_f32` (Veltkamp) to the result. `rt_absolute_f32` / `rt_negate_f32` /
  `rt_copy_sign_f32` become sign manipulation on doubles.
- `core/memory.lua`: `rt_load_f32` / `rt_store_f32` become the only conversion points
  (`from_bits_f32` / `into_bits_f32`).
- `builtin/buffer.lua`: replace `frexp` with the `log2` exponent in `into_bits_f32`.
- `Targets/LuaNoFFI/Printer/runtime/assembly/f32.lua` and the `transmute_f32_to_i32` path need
  auditing, since they currently assume the bit-pattern representation.
- Expected: `13.4x` on `f32`-heavy code; large effect on `float-compare`, `chipmunk`, `plmpeg`.

**Step 5 — `i64` as two values.**
- The largest change, and the only one that touches the IR/printer deeply:
  `Targets/LuaNoFFI/Printer/src/expression.rs` and the statement printer must widen every `i64`
  local into two Lua locals, every `i64` parameter into two parameters, and every `i64` return into
  two return values. `core/i64.lua` loses `from_bits_i64` / `into_bits_i64` entirely and every
  `rt_*_i64` takes and returns `(lo, hi)`.
- Expected: `1.9x`–`9.0x` on `i64`-heavy code, and removal of `~55 B` of allocation per `i64` op.
  Do this last: it has the widest blast radius and the narrowest fixture coverage.

**Step 6 — optional, threshold-driven paged memory.**
- Only worth doing if a fixture appears with a very large declared memory, or if `memory.grow` is
  hot. Keep pages **eager**; lazy pages are a `2.7x`–`17.5x` regression.

**Step 7 — optional, later.** Lazy `i32` normalisation (`1.63x` on the normalisation itself) and
provable bounds-check elimination (`1.17x` under the JIT, `1.57x` in the interpreter).

---

## 10. Hypotheses rejected, and why

| # | Hypothesis | Why rejected |
| --- | --- | --- |
| H2 | A dense byte array (`table.new`, `1..n`) beats the overlay | Same `8 B`/byte footprint, and only `0.82x`–`1.86x` on speed. Not worth a migration on its own. |
| H4 | 16-bit halves are a useful compromise | Dominated by 32-bit words on every kernel except unaligned loads, at `2x` the memory. |
| H5 | 6 bytes per slot / 53-bit packing | `0.05x`–`0.38x`. `addr/6`, `addr%6` and multi-slot read-modify-write kill it. "Two `u32` per double" is arithmetically impossible. |
| H8 | `string.buffer` | Not present on `LuaJIT 2.1.0-beta3`, which is the version this project targets. Rolling-release only; depending on it would break portability. |
| H10-inverse | `%` / `math.floor` are competitive with `bit.*` | `1.6x`–`1.9x` slower at identical storage. |
| H11 (JIT) | Helper calls cost real time under the JIT | Within `0.5%` of inline for loads; the trace recorder inlines them. Only true with the JIT off (`1.8x`–`2.1x`) and for stores (`1.26x`). |
| H12 | `{lo, hi}` tables are always catastrophic | Not always: LuaJIT sinks them completely when they do not escape a trace (`1.00x` on the `xorshift` kernel, `0.2 KB` allocated over 1M ops). They are catastrophic *when they escape* (`9.01x`, `56 MB`) — which is the real case. |
| H14 | A single 52-bit double is a viable `i64` | Not faster than a `(lo, hi)` pair (`0.0274` vs `0.0267`) and cannot represent 11 of the 64 bits. |
| H15 | `int64_t` cdata is the speed ceiling to aim for | It is `24x` faster on dense 64-bit arithmetic but `1.6x` **slower** than two plain numbers on a scalar counter loop under the JIT and `12x` slower in the interpreter, because every result allocates a `16 B` box. Not an unambiguous target. |
| H17 | `frexp`/`ldexp`-based `f32` rounding | Correct but `8.5x` slower than the Veltkamp split, because `math.frexp` is NYI for the JIT and stitches every trace. |
| H17b | `string.pack`-based float punning | `string.pack` is `nil` on this LuaJIT. |
| H18-unsigned | Keeping `i32` unsigned and normalising lazily | `2.12x` in a normalisation loop and `2.95x` on the memory load path. The sign fix-up is a 50/50 branch. |
| H7-lazy | Lazy page materialisation gives the best of both | Best footprint, but `2.7x`–`17.5x` slower than a flat array. Both the `pg or zero` form and an `__index` metamethod form were measured; both lose. The two-level indirection itself is cheap (`eagerpages` is within `1.2x`–`1.8x` of flat). |
| – | "A word memory is a drop-in replacement" | `words_u` (word storage, unsigned contract) is `1.69x` **slower than today** on `bench_crc32`. The signedness change is not optional. |

---

## Appendix: scripts and raw data

Everything lives under
`/tmp/claude-0/-root-Spider/c6f348bf-867e-4c32-8375-2847a3346875/scratchpad/perf/` (session scratch,
not checked in).

| File | Purpose |
| --- | --- |
| `probe.lua` | Capability probe (§1). |
| `gen.py` | Generates `designs/*.lua`; every accessor is emitted inline into every kernel. |
| `designs/d1_overlay.lua` | Hand-written; mirrors the shipped `buffer.lua` read/write paths. |
| `designs/d{0,2,3,3s,3a,4,5,7,7s}_*.lua` | Generated designs. |
| `verify.lua` | Randomised correctness check of all designs against a byte-array reference. |
| `run_mem.lua`, `sweep_mem.sh`, `loopbase.lua` | Micro-benchmark driver, sweep, empty-loop baseline. |
| `footprint.lua` | Footprint by design × size × density (§4.1). |
| `bench_misc.lua` | Helper-vs-inline, `i32` normalisation, growth strategies (§3, §4.2, §5.3). |
| `bench_i64.lua` | `i64` representations and allocation totals (§5.1). |
| `bench_f32.lua`, `bench_f32b.lua` | `f32`/`f64` representations, `round_f32` and bit-conversion verification (§5.2). |
| `kernel.c`, `kernel.wasm`, `kernel_gen.lua` | The C macro kernel, its wasm build, and its `spider-cli -t lua-no-ffi` output. |
| `patch_words.py` | Rewrites a generated module's `buffer_*` sections to a flat word memory (signed or unsigned). |
| `patch_pages_eager.py`, `patch_pages.py`, `patch_pages3.py` | Eager-paged, lazy-paged and `__index`-demand-paged variants. |
| `run_gen_kernel2.lua`, `miniz_probe_set.lua`, `fixture_run.lua` | End-to-end and fixture harnesses. |
| `final2.sh`, `final_fixtures.sh` | Interleaved round-robin fixture comparison. |
| `out/mem_final.tsv`, `out/macro_final.tsv`, `out/footprint.tsv`, `out/endtoend.tsv`, `out/final2.tsv` | Raw results for the tables above. |

`wasmtime` used: `v24.0.1-x86_64-linux`, invoked with `-C cache=n`.
Wasm built with `/root/libclang/bin` on `PATH` for `wasm-ld`:
`clang --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export-all -Wl,--allow-undefined`.
