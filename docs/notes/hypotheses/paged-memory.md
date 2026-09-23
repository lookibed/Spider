# Paged Word Memory for `lua-no-ffi`: A Design Study

Written: `2026-09-23`, against HEAD `bda2246` ("Store lua-no-ffi memory as packed 32-bit words").

**This is a thinking note only.** No code was changed, and nothing was built, run or timed to write it.
Every speed or footprint figure below is either quoted from
[`lua-no-ffi-performance-hypotheses.md`](../lua-no-ffi-performance-hypotheses.md) (cited as
"the study, §N") or labelled **predicted**. The predictions are there to be falsified by the
measurement plans. Claims about LuaJIT internals (alias analysis, `table.new` sizing, allocator
thresholds) come from reading LuaJIT 2.1 and are marked *(verify)* where a `-jdump` or a look at the
source should confirm them before anyone relies on them.

---

## 0. The short version

- The regression is real but narrow. `binjgb` declares `67 305 472` bytes (1027 wasm pages), touches
  a small fraction, and the dense word array costs `134 MB` plus LuaJIT's `200%` GC headroom, giving
  `292 MB` RSS (study §11.6). `lodepng` (16.1 MiB declared) goes to `2.04x` RSS. `chipmunk`
  (4.1 MiB) goes to `1.36x`. `miniz` (1.1 MiB) goes *down*.
- Paging fixes the footprint, but every two-level design so far measured costs **`1.2x`–`1.8x`
  on hot paths**, and that cost does not come from the materialisation branch. Eager pages, which
  have no such branch, already pay it (study §6.4: `chipmunk` `0.0317 s` vs flat `0.0181 s`). So
  "copy-on-write pages with no nil check" (P1/P2) can win back the gap between lazy and eager pages
  (`2.7x`–`17.5x` → `1.2x`–`1.8x`) but **not** the gap between eager pages and flat.
- The design that keeps the flat hot path intact is **P5, a high-water flat array**: the word array
  is materialised only up to a high-water mark `__h`, and the check that an access lies inside
  `__h` *replaces* the bounds check it already pays (`index + 4 > buf.__n` becomes
  `index + 4 > buf.__h`). The out-of-range branch that today calls `buffer_trap()` instead calls a
  slow path that either extends the materialised prefix or traps. **The laziness sits on a guard
  that is always true in steady state, not on the data path.** That is the difference from the
  rejected `pg or zero` design. The hot-path IR does not change at all: same loads, same guards,
  different field name.
- P5 relies on wasm heaps being *prefix-dense*. wasm-ld and emscripten lay out data, then the stack,
  then an upward-growing `sbrk` heap, so the touched set is roughly a prefix. **Stage 0 of the plan
  measures that before any code is written.** If a fixture touches high addresses sparsely, P1
  (copy-on-write 64 KiB pages over a shared zero page) is the fallback for large memories only.
- `memory.grow` becomes O(1) under P5 (only `__n` moves) and O(new pages) under P1, instead of
  O(new words) today.

Recommendation: **Stage 0 touch map → Stage 1 P5 (plus P7, P10, P11) → Stage 2 P1 only if Stage 0
shows sparse high touches → Stage 3 page/bounds caching after target lowering.** See §4.

---

## 1. The access paths today, and what each one costs

All paths live in `Targets/LuaNoFFI/Printer/runtime/builtin/buffer.lua` (sections `buffer_*`) and
`runtime/core/memory.lua` (sections `rt_load_*`, `rt_store_*`, `rt_memory_*`). A memory object is
`{ [1] = buf, maximum = <bytes> }` (`rt_memory_new`, `memory.lua:6-16`). `buf` is
`setmetatable({ __n = <bytes>, __w = <word array> }, buffer_meta)`, and
`__w[rshift(a, 2) + 1]` holds the `bit.tobit` form of bytes `a & ~3 .. (a & ~3) + 3`, little endian.
The array is `table.new(floor(n / 4) + 2, 0)` and fully zero-filled (`buffer_create`, `:111-120`).
The two slack words let an unaligned straddle of the last word read `__w[slot + 1]` without a
bounds test of its own.

### 1.1 How the printer reaches them

| Wasm op | Printed as | Where |
| --- | --- | --- |
| `i32.load` | `buffer_read_i32(ref[1], base, off)`. **Not** inline Lua: a direct call to the buffer helper that skips the `rt_load_i32` wrapper. | `Printer/src/expression.rs:853-878`, `library/names_finder.rs:426` |
| every other load | `rt_load_<kind>(ref, base, off)` | same |
| every store | `rt_store_<kind>(ref, base, off, value)` | `Printer/src/statement.rs:582-604` |
| `memory.fill` / `memory.copy` / `memory.grow` / `memory.size` / data drop | `rt_memory_*` calls | `statement.rs:606-660`, `expression.rs:880-910` |
| memory creation | `rt_memory_new({ [off] = "bytes", ... }, minimum, maximum)` | `expression.rs:833-851` |

Data segments on the fixtures are not written straight into the linear memory. Each segment becomes
its own small `rt_memory_new` buffer (for example `binjgb`: `44 680` and `8` bytes). Start-up then
copies it into the main memory with `rt_memory_copy` and drops it (`binjgb.lua:34595-34679`). The
main memory itself is created empty: `rt_memory_new({ }, 67305472, 4294967295)`.

Declared main-memory sizes of the fixtures this note cares about (read from the checked-in
generated modules):

| Fixture | declared bytes | wasm pages | `memory.grow` call sites | notes |
| --- | ---: | ---: | ---: | --- |
| `binjgb` | `67 305 472` | 1027 | 0 | the regression |
| `lodepng` | `16 908 288` | 258 | 0 | `lodepng_diag` variant: `2 228 224` |
| `gltf-rs` | `5 308 416` | 81 | 1 | host writes through `memory[1][i]` |
| `self-hosting-luanoffi-builder` | `5 308 416` | 81 | 0 | key fixture |
| `chipmunk` | `4 325 376` | 66 | 0 | the hot-path canary |
| `miniz` | `1 179 648` | 18 | 0 | small, dense, byte-serial |
| `tinyexpr` | `393 216` | 6 | 0 | tiny |

### 1.2 Cost per access (JIT steady state, IR-level)

"Field load" means an `HREFK` + `HLOAD` on `buf.__n` or `buf.__w`. "Array load/store" means an
`AREF` + `ALOAD`/`ASTORE` with the implicit array-bounds (`ABC`) guard. All helpers are inlined by
the trace recorder (study §3: helper vs inline within `0.5%` under the JIT, `1.8x`–`2.1x` in the
interpreter).

| Path | Code | Per access | Measured (study §2, flat words vs overlay) |
| --- | --- | --- | --- |
| aligned `i32` load | `buffer_read_i32` `:354-370` | `ref[1]` array load, `__n` field load, 2 compare guards (`base < 0`, `index + 4 > n`), `__w` field load, `rshift`/`+1`/`band`/`lshift`, `shift == 0` guard, 1 array load | `2.31x` faster than overlay; `load_i32` aligned `0.0177` |
| unaligned `i32` load | same, `shift ~= 0` | + 1 array load, `rshift`, `lshift`, `bor`, `32 - shift` | `0.60x` of overlay |
| aligned `i32` store | `rt_store_i32` → `buffer_write_i32` `:453-476` | as the load, plus `tobit`, 1 array store | `2.12x` |
| unaligned `i32` store | same, `shift ~= 0` | 2 read-modify-writes: 2 array loads, 2 array stores, ~8 bit ops | – |
| `u8`/`s8` load | `rt_load_i32_from_u8` → `buffer_byte` `:97-105` | bounds, `__n`, `__w`, 1 array load, `rshift`/`band`/`lshift` x2, +`s8` sign branch | `0.56x` |
| `u8` store | `buffer_write_u8` `:399-412` | read-modify-write: 1 array load, 1 array store, ~6 bit ops | `0.39x` |
| `u16` load/store | `:316-332`, `:421-441` | as `u8`, plus a `shift == 24` branch: the halfword straddles two words | – |
| `i64` load | `rt_load_i64` `memory.lua:124-137` | `buffer_check` (2 guards) + 2 full `buffer_read_i32` (each with its own bounds check) + `into_bits_i64` (2 `%`, 1 `TNEW`, sunk only if non-escaping) | `3.18x` |
| `i64` store | `rt_store_i64` `:196-206` | 2 array loads from the `{lo, hi}` table, `buffer_check`, 2 full `buffer_write_i32` | `2.49x` |
| `f64` load/store | `buffer_read_f64` `:383-390`, `buffer_write_f64` `:489-496` | the two-word `i32` path plus `from_bits_f64`/`into_bits_f64`. `into_bits_f64` still calls NYI `math.frexp` and **stitches the trace** (study §11.8 item 4) | – |
| `f32` load/store | `buffer_read_i32`/`buffer_write_i32` + `from_bits_f32`/`into_bits_f32` | one word + conversion | – |
| `buffer_check` | `:132-136` | 2 guards, 1 field load; used before every two-word access | – |
| `memory.copy` | `buffer_copy` `:166-245` | shared alignment: byte head, then 1 array load + 1 array store **per word**, then byte tail. Otherwise a byte RMW loop, with direction chosen for overlap | `copy` `4.21x` |
| `memory.fill` | `buffer_fill` `:255-290` | byte head, 1 array store per word, byte tail | `fill` `8.62x` |
| data segment | `buffer_writestring` `:507-553` | `string.byte(s, p, p+3)` + 3 `lshift` + `bor` + 1 array store per word | – |
| `memory.grow` | `rt_memory_grow` → `buffer_resize` `:142-152` | zero-fills **every new word** (O(new words)), then publishes `__n` | – |
| creation | `buffer_create` | `table.new(D/4+2)` + zero-fill of all D/4 words. Study §4.2: **`0.0824 s` per 64 MiB**, `0.0209 s` per 16 MiB | – |
| host | `buffer_meta.__index` / `__newindex` `:51-77` | a metamethod call per byte; never on the generated-code path, because `__n`/`__w` are raw fields | – |

One detail matters for every design below, so here it is up front. LuaJIT forwards and hoists a
load only if no intervening store may alias it. In `lj_opt_mem.c`, `HLOAD`s (`buf.__n`, `buf.__w`)
are checked only against `HSTORE`s, so the memory's own word stores (`ASTORE`s into `__w`) never
invalidate them. `ALOAD`s are checked against `ASTORE`s, and two array stores on two tables the
trace did not allocate itself are "may alias" *(verify with `-jdump`)*. Consequences:

- `ref[1]` (the memory wrapper's array slot) is **re-loaded after every memory store** in a trace,
  and so are the `__n`/`__w` loads that hang off the re-loaded `buf`. This is a cost today, and it is
  why target-lowering H6 wants to drop the wrapper.
- Any page **directory** kept as an array (every paged design) is re-loaded after every memory
  store in the same trace. That is one of the plausible reasons eager pages measured `1.2x`–`1.8x`
  slower than flat even without a materialisation branch.

---

## 2. Hypotheses

Notation: `D` = declared bytes, `H` = high-water mark (highest byte ever touched, rounded up),
`T` = distinct touched bytes rounded up to the page size `P`, `f = T / D`. The Lua heap cost of one
materialised wasm byte is `2 B` (one 8-byte `TValue` per 4 bytes). Resident size is roughly
`(live Lua heap) x (1 + pause/100)` at worst before a cycle completes. The default `pause = 200`
explains `binjgb`'s `292 MB` over a `134 MB` array.

Speed is quoted relative to **flat words** (the shipped design) unless stated otherwise.

### P1 — Copy-on-write pages over one shared zero page, with an explicit store-side check

**Mechanism.** `buf.__p` is a dense, 0-based directory with one slot per 64 KiB page. At creation
**every slot points at one shared `ZERO` table** (16 384 zero words). Reads never test anything:
`__p[rshift(a, 16)][band(rshift(a, 2), 0x3FFF)]`. Stores do
`local pg = p[pi]; if pg == ZERO then pg = materialise(buf, pi) end; pg[wi] = v`.
`materialise` allocates `table.new(16384, 0)`, zero-fills it and writes it into `p[pi]`. A page
never returns to `ZERO` (but see P12).

**Why this avoids the rejected lazy design's trace splitting.** The rejected design
(study §6.4, `4-lazypages`) kept a *sparse* directory and read `p[pi] or zero`. That puts a
**value-dependent fork on the read path**. The `ALOAD` of `p[pi]` gets a type guard (table vs
`nil`), and it fails whenever the address moves between a touched and an untouched page. After
`hotexit` failures LuaJIT records a side trace. Side traces rejoin at the root's head, not at the
merge point, so each such load duplicates the rest of the iteration, and k such loads per iteration
can need up to 2^k side traces until `maxside` blacklists the loop back to the interpreter. A
sparse integer-keyed directory can also fall out of the array part into the hash part (study §4.1
shows the density threshold), which turns every `p[pi]` into an `HREF` chain walk. The
`__index` variant (`patch_pages3.py`) replaced the fork with a metamethod call on every read of
an untouched page, which is worse.

P1 changes the shape so that neither can happen:

1. The directory is **dense and every slot holds a table**, so the directory load's type guard
   always passes and has one outcome. Reads do not care whether they hit `ZERO` or a real page.
   There is **no fork on the read path at all**.
2. The store-side `pg == ZERO` test is a pointer-equality guard. It fails **at most once per page
   for the lifetime of the program**: after materialisation that page never compares equal to
   `ZERO` again. So the exit is transient, not a steady-state diamond. At worst one cold side trace
   exists per store site that swept fresh pages, and it is not re-entered once the working set is
   materialised.

**Expected speed.** Loads: identical IR to `3-eagerpages`, so study §6.4's `0.57x`–`0.86x` of flat
(chipmunk `0.57x`, lodepng `0.62x`, miniz `0.86x`, tinyexpr `1.07x`). Stores: one extra
`EQ` guard per store (**predicted** `0.95x`–`1.0x` of eager). Versus lazy: **predicted `3x`–`10x`
faster than `4-lazypages`**, i.e. the whole lazy-to-eager gap closes. Interpreter: one more `ISEQ`
per store, negligible next to the `bit.*` calls.

**Footprint.** `2T + 8(D/P) + 2P` (materialised pages + directory + the zero page).
`binjgb` at a guessed `f = 5%`: `6.7 MB + 8 KB + 128 KB` vs `134 MB`.

**Correctness risks.**
- **Writing into `ZERO` corrupts every untouched page at once.** Every write path must go through
  the check: `buffer_write_u8/u16/i32`, the second word of the unaligned `i32`/`u16` stores, the
  `copy`/`fill`/`writestring` word loops, and `buffer_meta.__newindex`. A missed path is silent.
  Mitigation: the differential harness (study §11.3) must end every run by asserting that `ZERO`
  is still all zeros, and must include stores to never-touched pages from every writer.
- **Page edges.** An unaligned `i32` or a `u16` at `shift == 24` in the last word of a page
  (`wi == 16383`) needs word `0` of page `pi + 1`. Compute the second word as `w2 = w + 1` and
  split it again. Do not use `wi + 1`, and do not add a "same page?" branch: that is a fork again.
  The directory needs one extra trailing slot (pointing at `ZERO`) to replace today's two slack
  words.
- Two-word `i64`/`f64` accesses already go through two independent `buffer_read_i32` calls with
  `offset` and `offset + 4`, so each resolves its own page. `buffer_check` stays in front.
- `copy`/`fill`/`writestring` must walk per segment: the inner word loop runs to
  `min(words left in the src page, words left in the dst page, words left)`. Source and destination
  page boundaries do not coincide when `dst ~= src (mod 64 KiB)`. `copy` from `ZERO` into `ZERO`
  and `fill(0)` into `ZERO` can skip the segment entirely. The backwards (`memmove`) byte path
  needs the same per-byte page resolution.
- `memory.grow`: append `ZERO` to the directory, then publish `__n` (P7).

**Implementation sketch.** `buffer.lua`: new `buffer_create`, `buffer_resize`, `buffer_byte`, all
`buffer_read_*`/`buffer_write_*`, `buffer_copy`, `buffer_fill`, `buffer_writestring`, and
`buffer_meta`, plus two new sections `buffer_zero_page` and `buffer_materialise`. `memory.lua`:
unchanged, since signatures stay. `expression.rs:853-878`: unchanged while the `i32` load stays a
call. `library/sections.rs`: register the new sections. Selecting it per module is P6.

**Measurement.** Patch mechanically as the study did (swap `buffer_*` sections, keep the module
body byte-identical). Compare flat / eager / P1 / lazy, round-robin, min of 5, variant marker
checked before and after each run (study §11.5). Record in-process kernel time for
`chipmunk_hash_scene(60)`, `lodepng_roundtrip_hash(0)`, `binjgb_decode_hash(16)` and the `miniz`
roundtrip. Record whole-process max RSS, Lua heap after a full collection, pages materialised, and
`luajit -jv` counts of side traces and aborts (the direct evidence that the fork is gone). Success:
P1 within `1.1x` of eager on every row, and `binjgb` RSS under `40 MB`.

### P2 — Copy-on-write through a write-directory of `__newindex` stubs: no branch in the source

**Mechanism.** Two directories. `__p` (reads) is exactly P1's: every slot is `ZERO` or the real
page. `__q` (writes) holds, for an untouched page, a **per-page empty stub**
`setmetatable({ __i = pi }, STUB_META)` whose `__newindex` materialises page `pi`, patches
`__p[pi]` and `__q[pi]`, and performs the write. For a materialised page, `__q[pi]` is the page
itself. Stores become `q[pi][wi] = v`, with no source-level test. Read-modify-write stores read
`p[pi][wi]` and write `q[pi][wi]`.

**Why it can be cheaper than P1.** A JIT store into a table already carries guards: the array
bounds check against `asize`, plus a non-nil-old-value or no-metatable guard that stops
`__newindex` from being skipped *(verify with `-jdump`)*. An empty stub has `asize = 0`, so the
**existing** bounds guard is what fails on first touch. Steady-state stores pay nothing beyond a
normal store: no extra `EQ`. This is *not* the rejected `__index` design. There the metatable was on
the directory, and a metamethod ran on **every read** of an untouched page. Here a metamethod runs
**once per page, on its first write**.

**Expected speed.** Stores **predicted** equal to eager pages. Loads equal to P1. The cost is a
second directory load on read-modify-write stores (`u8`, `u16`, unaligned), and one more
directory to re-load after aliasing stores (§1.2).

**Footprint.** P1 + `~80 B x D/P` of stubs (`binjgb`: ~80 KB).

**Risks.** Everything in P1, plus: the stub must never be *read* (a read returns `nil`, and the
`bit.*` arithmetic then raises a confusing error instead of the right value). `copy`/`fill` loops
that write through `q` in bulk trigger the metamethod once, then must re-fetch `q[pi]` for the
rest of the segment. `rawset` anywhere on a write path would bypass materialisation.

**Measurement.** As P1, plus an A/B of P1 vs P2 on a store-heavy kernel (`lodepng` has `898`
`i32` store sites and `748` `i8` store sites). Keep P2 only if it beats P1 by more than the noise
band on stores and does not lose on RMW stores.

### P3 — A two-level address split of one shift and one mask, 0-based

**Mechanism.** LuaJIT's array part includes slot `0`. `table.new(n, 0)` allocates `n + 1` slots,
`0..n` *(verify in `lib_table.c`/`lj_tab_new_ah`)*, and `t[0]` is then an array access, not a hash
access. So pages can be 0-based:
`pi = rshift(a, 16)`, `wi = band(rshift(a, 2), 0x3FFF)`. That is three bit ops and **no `+1`**
anywhere, against flat's `rshift` + `+1`. The same trick applies to flat words
(`__w[rshift(a, 2)]`), saving one `ADD` per access there too. The flat saving is independent of
paging and worth folding into whatever lands.

**Expected speed.** Flat: **predicted** `1.00x`–`1.03x` (one integer add per access, visible
mostly in the interpreter). Paged: removes 2 of the adds that `3-eagerpages` paid.

**Risk.** Without `table.new` (the `pcall` fallback in `buffer_new_table`), slot `0` of a plain
`{}` lives in the hash part until a rehash. That is slower but still correct. Any code that
iterates `1..#w` or uses `#` on the word array breaks; none does today.

**Measurement.** A micro A/B of flat 1-based vs 0-based `load_i32`/`store_i32`, JIT on and off,
min of 5.

### P4 — Page size: 4 KiB vs 64 KiB vs 1 MiB

| | 4 KiB | **64 KiB** | 1 MiB |
| --- | --- | --- | --- |
| words/page | 1 024 | 16 384 | 262 144 |
| array bytes/page | 8 KiB | 128 KiB | 2 MiB |
| directory for 64 MiB | 16 384 slots, 128 KiB | 1 024 slots, 8 KiB | 64 slots, 512 B |
| split | `rshift(a,12)`, `band(rshift(a,2),0x3FF)` | `rshift(a,16)`, `band(…,0x3FFF)` | `rshift(a,20)`, `band(…,0x3FFFF)` |
| allocator | dlmalloc bins | ~at the `lj_alloc` 128 KiB mmap threshold *(verify)*: each page its own `mmap`, freed back to the OS on `munmap` | one `mmap` each |
| waste per touched region | ≤ 8 KiB | ≤ 128 KiB | ≤ 2 MiB |
| first-touch exits for 64 MiB | ≤ 16 384 | ≤ 1 024 | ≤ 64 |
| `memory.grow` unit | 16 per wasm page | **1 per wasm page** | 1 per 16 wasm pages, partial last page |
| `copy`/`fill` segment overhead | every 1 024 words | every 16 384 | negligible |

The address split costs the same at every size, so the choice is footprint granularity versus
first-touch exits and directory size. 64 KiB matches the wasm page, so `memory.grow` appends whole
pages and no page is ever partial. 4 KiB only pays off for scattered small touches. Emscripten and
wasm-ld heaps are prefix-dense, so that granularity buys little and multiplies first-touch exits by
16. 1 MiB would leave a partial final page for most declared sizes (1027 wasm pages is not a
multiple of 16), and it wastes up to 2 MiB per region. Small data-segment buffers (8 bytes, 44 KB)
should never be paged at any `P` (P6).

LuaJIT array limit: `LJ_MAX_ASIZE` is about `2^27` slots in LuaJIT 2.1 *(verify in `lj_def.h`)*,
i.e. **a flat word array tops out near 512 MiB–1 GiB of wasm memory**, below
`rt_memory_grow`'s 2 GiB cap. Pages lift that ceiling. It matters for no current fixture, but
it is a correctness limit, not a speed one.

**Measurement.** Only if P1 lands: sweep `P` ∈ {4, 16, 64, 256} KiB on `binjgb` and `lodepng`,
recording RSS, pages materialised, first-touch exits (count them in `materialise`) and kernel
time.

### P5 — High-water flat: the lazy part rides on the bounds guard (headline hypothesis)

**Mechanism.** Keep the single flat word array and every hot-path expression. Add one raw field,
`__h`: the number of bytes whose words are materialised (a multiple of 4, `≤ __n`, with the two
slack words kept materialised *beyond* `__h`). Every accessor's bounds test changes from
`index + size > buf.__n` to `index + size > buf.__h`, and its body from `buffer_trap()` to
`buffer_extend(buf, index + size)`, which:

```lua
-- cold path only
local function buffer_extend(buf, need)
	if need > buf.__n then buffer_trap() end          -- the real bound, unchanged semantics
	local h = buf.__h
	local target = max(need, min(buf.__n, h + max(h, 65536)))  -- geometric, >= one wasm page
	-- zero-fill words (h/4 .. target/4 + 1), 0-based or 1-based as P3 decides
	rawset(buf, "__h", round_up_4(target))
end
```

then falls through to the unchanged fast code. `__w` stays the **same table object**. LuaJIT grows
its array part in place, so no reference taken earlier goes stale. Creation writes
`__h = 0` (or the end of the highest data segment) and zero-fills nothing.

**Why it keeps flat speed.** In steady state the JIT sees exactly today's trace: an `HLOAD` of a
field (`__h` instead of `__n`), two compare guards, the same word arithmetic, the same
`ALOAD`/`ASTORE`. The extension branch is the trap branch that already exists. It was a guard exit
to `error()`, and now it is a guard exit to a function that returns. It fails `O(log(H / 64 KiB))`
times in total thanks to geometric growth. The rejected lazy design forked on *which page the value
lived in*, per access. P5 forks only on *whether the prefix is long enough yet*, and after warm-up
the answer is always yes. No value-dependent branch, no directory, no second table load, no new
aliasing.

**Expected speed.** **Predicted `0.98x`–`1.00x` of flat** on every kernel (the only change is a
different constant key). Start-up is faster: `binjgb` skips the `0.08 s` zero-fill of 64 MiB
(study §4.2), about `5%` of its `1.63 s` whole-process run.

**Footprint.** Array `asize` is what LuaJIT's resize picks. Extending by writing past the end
goes through `lj_tab_newkey` → `rehash`, which sizes the array part to a **power of two**
*(verify in `lj_tab.c`)*. That gives `2 x nextpow2(H)` bytes, bounded by `4H`. Two refinements:

- cap: when `nextpow2(H)` would exceed `D`, rebuild once with `table.new(D/4 + 2)` and copy, which is
  exactly flat's footprint and never worse;
- if the power-of-two waste shows up in Stage 0 numbers, extend by rebuilding with `table.new` at a
  `1.5x` target and copying. That has a transient `old + new` peak, which is the spike study §4.2
  measured for double-and-copy, so it should be used only if the rounding waste is measured to
  matter. On Linux `lj_alloc` may `mremap` large blocks instead of copying *(verify
  `LJ_ALLOC_MREMAP`)*, which would make in-place growth cheaper still.

`binjgb` at a guessed `H = 4 MiB`: `8 MB` array vs `134 MB`. At `H = D` it degrades to flat, never
past it. **P5's footprint depends on `H`, not `T`**: one live byte near the top of memory
materialises everything below it. Stage 0 exists to check that `H` is small on the real fixtures.

**Correctness risks.**
- **Trap semantics.** An access that is out of bounds of `__n` must still trap *before any write*.
  `buffer_extend` checks `__n` first, and extension alone never changes observable contents
  (only zeros appear), so a trapping multi-word access that extended first would still be sound. It
  cannot happen anyway, because the `__n` test runs first.
- **Slack.** The unaligned straddle read of `slot + 1` must stay inside the materialised array.
  Keep two words materialised past `__h`, exactly like today's `+ 2`.
- **Every checker must use `__h`.** That covers `buffer_byte`, `read_u16`, `read_i32`,
  `write_u8/u16/i32`, `buffer_check`, `buffer_copy` (both ranges), `buffer_fill`,
  `buffer_writestring` and `buffer_meta`. A checker that still compares against `__n` would read
  `nil` (arithmetic error) or write past the array, creating hash-part entries. **The failure is
  loud** (a Lua error on `nil` arithmetic), unlike P1's silent `ZERO` corruption.
- `memory.size` keeps reading `__n`; `memory.grow` moves only `__n` (P7).
- The target-lowering study's bounds-check merging (its §4.3) assumes only `grow`/`drop` change
  the bound. Under P5, `__h` also grows on any slow-path hit. It **only ever grows**, so a stale,
  hoisted `__h` is conservative: the access takes the slow path, which re-reads the live fields and
  succeeds. Merged or hoisted checks must call `buffer_extend`, never `buffer_trap` directly.

**Implementation sketch.** `buffer.lua` only: `buffer_create` (`__h`, no fill), a new
`buffer_extend` section, the check lines of every accessor, `buffer_check`, the heads of
`copy`/`fill`/`writestring`, `buffer_resize` (P7), `buffer_meta` (P10). `memory.lua`: no change.
`expression.rs`: no change. `sections.rs`: add `buffer_extend` and its `NEEDS` edges.
About 60 lines touched, and the section graph keeps its names.

**Measurement.** Stage 0 first (§4). Then flat vs P5, round-robin, min of 5, marker-checked. Record
the same four kernels, whole-process time and RSS, and the number of `buffer_extend` calls and
final `__h` per fixture. Success: every kernel within `±3%` of flat (inside noise), `binjgb` RSS
`≤ 2.5 x (10 MB + 2H)`, and `chipmunk`, the canary with the most `f64` traffic, unchanged.

### P6 — Hybrid: flat below a threshold, paged above, chosen statically by the printer

**Mechanism.** The printer already sees each `MemoryNew`'s `minimum`, `maximum` and whether the
module contains `MemoryGrow` (`expression.rs:833-851`, `names_finder.rs`). Choose a runtime
*flavour* per module: if the main memory's `minimum ≥ 16 MiB` (and/or `grow` is present with a
large `maximum`), emit the paged `buffer_*` sections under **the same section names**, loaded
from a sibling `buffer_paged.lua` (`sections.rs:174-200` adds one `include_str!` and a flag on
`Sections::with_built_ins`). Otherwise emit flat. The decision is made per module, so no
accessor ever dispatches at run time. A runtime `if buf.__p then … else … end` would also compile
to a well-predicted guard per trace, but it bloats every inlined accessor and makes
`buffer_copy` between a flat data-segment buffer and a paged main memory a four-way product.

**Expected speed.** Flat fixtures are unchanged by construction. Paged fixtures get P1's
`0.57x`–`0.86x` hot path. At 16 MiB, `lodepng` falls into the paged side and would **lose `~1.6x`**
(study §6.4, eager pages vs flat on `lodepng`). That is the argument against P6 with P1 behind it,
and the argument for P5, which needs no threshold. With P5 as the base, P6 reduces to "P5 always;
P1 only above, say, 256 MiB or when Stage 0 finds a sparse high-touch module".

**Footprint.** Flat below the threshold (`2D`), P1 above.

**Risks.** Data-segment buffers are created under the same flavour, so every `copy` is
flavour-homogeneous. Two code paths must both pass the differential harness and conformance.
Conformance memories are small, so the paged flavour needs a forcing flag (an env var or CLI
option, e.g. `--paged-memory`), or it is never tested.

**Measurement.** Same as P1, with `lodepng` at both 16.1 MiB (`lodepng`) and 2.2 MiB
(`lodepng_diag`) to show the threshold's effect on one program.

### P7 — `memory.grow` in O(1) or O(new pages) instead of O(new words)

**Mechanism.** Today `buffer_resize` zero-fills every new word before publishing `__n`
(`buffer.lua:142-152`). Under P5, grow is `rawset(buf, "__n", size)` and nothing else: the new
region is materialised on demand by `buffer_extend`. Under P1, it appends `ZERO` references,
`D_new / 64 KiB` of them, then publishes `__n`.

**Expected speed.** O(1) or O(pages). Only `gltf-rs` has a live `memory.grow` call site among the
measured fixtures. The effect shows in whole-process time only when a module grows by large
amounts.

**Risk.** A grow must still fail cleanly: the `maximum` and `2^31` checks in `rt_memory_grow`
stay, and the publication of `__n` stays last.

**Measurement.** `gltf-rs` whole-process time and RSS, plus a synthetic loop that grows 1 page
10 000 times.

### P8 — GC interaction

**Facts.**
1. `gc_traverse_tab` walks the **whole array part** on every cycle's propagate phase, testing
   each slot for a collectable value. The slots are all numbers, so nothing is marked, but 16.8 M
   slots are still visited per cycle *(verify cost; predicted `10`–`30 ms` per cycle)*. A single
   table is traversed in one step, so that is also a latency spike.
2. The generated code allocates heavily: every escaping `i64` is a `{lo, hi}` table (study §5.1,
   `~55 B/op`), and `binjgb` has `338` `i64` load sites and `438` store sites. With `pause = 200`, a
   cycle starts after about `live` more bytes are allocated, so a `134 MB` live set lets
   `~134 MB` of garbage pile up. That is the difference between the `134 MB` array and the
   `292 MB` RSS.
3. Number stores into a table trigger no write barrier, so the word array never goes back to
   gray. Its cost is traversal once per cycle, not per store.

**Hypotheses.**
- (a) Shrinking the live set (P5/P1) cuts **both** the RSS headroom and the per-cycle traversal
  time proportionally. That is the main lever, and it needs no GC tuning.
- (b) `collectgarbage("setpause", 110)` in the generated module would trim headroom to `10%`,
  **but it is global to the host's Lua state**, would silently retune the host's GC, and makes
  cycles `~2x` more frequent, each traversing the full array under flat. **Do not emit it from the
  runtime.** Document it as a host-side knob, e.g. in `host_main.lua` for `binjgb` to show the
  bound.
- (c) Under P1, `ZERO` is one shared table traversed once per cycle; materialised pages are
  separate tables, each traversed in its own incremental step, which bounds the per-step latency to
  one page (128 KiB).
- (d) Non-`GC64` LuaJIT builds keep the whole GC heap in the low 2 GB of address space. The
  `2.1.0-beta3` build this project targets may be non-`GC64` *(verify `jit.status()` or the build
  flags)*. `292 MB` is then a significant slice of a hard ceiling, which makes this a robustness
  issue and not only a footprint one.

**Measurement.** For `binjgb` under flat and under P5: `collectgarbage("count")` sampled every
frame, the number of completed cycles (read the `count` drop), and max RSS at
`setpause` ∈ {200, 150, 110} set **by the harness**. For flat only: time a forced
`collectgarbage("collect")` with the memory live vs dropped, which isolates the traversal cost.

### P9 — Keep the inline path a single table read: cache the page (or the bounds) in a local

**Mechanism.** Today no access is inline: `buffer_read_i32(ref[1], base, off)` is a call that
the JIT inlines. Once target lowering lands (target-lowering H6–H8: split `BoundsCheck` from
`LoadWord`, and make `__w`/`__n` IR values), a basic block with several accesses off one base
`b` with static offsets `o1..ok` can be lowered as:

```lua
-- paged (P1): one directory read, one guard, k single-table reads
if band(b, 0xFFFF) + maxo + 4 > 0x10000 or b < 0 or b + maxo + 4 > m.__h then
	-- generic per-access path (straddles a page or needs extend/trap)
else
	local pg = dir[rshift(b, 16)]
	local w = band(rshift(b, 2), 0x3FFF)
	x1 = pg[w + o1/4] ; x2 = pg[w + o2/4] ; ...
end
```

For flat (P5), the same block needs one merged bounds guard and one `__w`, which is target-lowering
H7/H8 unchanged except that the guard calls `buffer_extend`. The page-crossing guard is
**always true except when `b` sits within `maxo` bytes of a page end** (probability about
`maxo / 65536`), so it is a guard and not a diamond. Holding `pg` in a Lua local also removes
the directory re-load after aliasing stores (§1.2), because a local is an SSA value the JIT never
reloads.

**Expected speed.** **Predicted:** pages with caching reach `0.9x`–`1.0x` of flat in blocks with
two or more accesses per base (struct field runs, `i64`/`f64` two-word pairs, which are the
`chipmunk` pattern). Single isolated accesses stay at P1's cost. The flat design gains the same
bounds merging, so the relative gap shrinks without closing.

**Risks.** Everything in target-lowering §3.4–§3.6 (state ports, live ranges), plus the local
budget (Lua's 200 locals; target-lowering §5.3). The block must end the cached `pg` at any store
that could materialise a page, since that changes `dir[pi]`. Only a store to a `ZERO` page does,
and such a store takes the generic path anyway.

**Measurement.** After target lowering stage 1: `grep -c` of `dir[` / `__w` in `chipmunk.lua`
before and after, `-jdump` of the `chipmunk` hot loop to confirm one directory load per block, and
kernel time.

### P10 — The host interface: `memory[1][address + 1]` through `buffer_meta`

**Mechanism.** The hosts capture `wasm.memory[1]` once (`binjgb/host_main.lua:310`, and the same in
`cgltf`, `plmpeg`, `h264bsd`, `libjpeg-turbo`, `lodepng`, `smollm2`) and index it byte-wise
(`host_main.lua:75-85`, `gltf-rs/main.lua:30`). So **the buffer's identity must survive grow**,
which is true for every design here, since all mutate in place. `buffer_meta` must learn the new
layout:
- P5: `__index` returns `0` for `__h ≤ k - 1 < __n` without extending (host reads of untouched
  memory must not materialise it); `__newindex` calls `buffer_extend` and then writes.
- P1/P2: `__index` goes through the directory (works on `ZERO`); `__newindex` must CoW.

**Why it is not a hot-path risk.** `__n`, `__h`, `__w`, `__p` are raw fields of `buf`, so the
generated code never consults the metatable (study §11.2 item 3). Host byte loops, such as
`binjgb`'s ROM upload of `write_bytes` into `memory`, run at metamethod speed today and stay
there. A host fast path, e.g. an exported `buffer_writestring` wrapper, is a separate
improvement.

**Measurement.** The differential harness's metatable byte view case (study §11.3), extended
with reads and writes beyond `__h` (P5) and into `ZERO` pages (P1). `gltf-rs`, `binjgb` and
`lodepng` outputs must stay bit-identical.

### P11 — Data segments and zero-fill: skip work on memory that is already zero

**Mechanism.** Start-up today = `buffer_create` of the main memory (a full zero-fill), plus a
`buffer_create` + `writestring` of each segment buffer, plus a `copy` into main memory, plus `drop`.
Under P5, the main-memory zero-fill disappears, and the `copy` extends `__h` to the end of the
highest segment. Under P1, only the data pages materialise. In both, two zero-aware shortcuts are
free:
- `memory.fill(dst, 0, n)` over `[__h, __n)` (P5) or over `ZERO` pages (P1) is a no-op for that
  part. `calloc` and `memset(p, 0, n)` on fresh heap are the common case.
- `memory.copy` whose source range is entirely unmaterialised writes zeros, so it only needs to
  handle the part of the destination that is materialised.

**Expected speed.** `binjgb` whole-process: minus `~0.08 s` of creation (study §4.2), about `5%`.
`lodepng`: minus `~0.02 s`, about `10%` of `0.19 s`. Hot kernels are unaffected.

**Risks.** The skip is only valid for a zero fill value, and for P1 only for a whole-page `ZERO`
segment. Partial pages still write, because a materialised page's bytes are not known to be zero.

**Measurement.** Whole-process time of `binjgb`, `lodepng` and `miniz` (miniz's `3.33x` in study
§11.5 is start-up dominated, which makes it the sensitive fixture here) and `luajit -e` start-up
alone (`require` the module, no export call).

### P12 — Reclaim: a zeroed page returns to `ZERO` (P1 only)

**Mechanism.** When `memory.fill(…, 0, …)` covers a whole materialised page, point the
directory slot back at `ZERO` and let the page be collected. No other path can detect a page going
back to zero cheaply. **Predicted** effect: none on the current fixtures, because emulators and
decoders do not `memset` whole 64 KiB spans after use. This is recorded so it is not re-invented;
do not build it without a fixture that needs it.

---

## 3. Side-by-side

| | hot load vs flat | hot store vs flat | removes the lazy fork? | footprint | grow | start-up | silent-corruption risk | code size |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| flat (shipped) | `1.00x` | `1.00x` | n/a | `2D` | O(new words) | O(D) | – | – |
| lazy pages (rejected) | `0.06x`–`0.37x` | same | – | `2T` | O(pages) | O(D/P) | medium | medium |
| eager pages | `0.57x`–`0.86x` | same | n/a | `2D` | O(pages) | O(D) | low | medium |
| **P1** CoW, explicit check | `≈ eager` | `≈ 0.95 x eager` | **yes** | `2T + 8D/P + 2P` | O(pages) | O(D/P) | **high** (`ZERO`) | medium |
| **P2** CoW, stubs | `≈ eager` | `≈ eager` | **yes** | P1 + `80 B · D/P` | O(pages) | O(D/P) | high | medium+ |
| **P5** high-water flat | **`≈ 1.00x`** | **`≈ 1.00x`** | **yes, and no directory** | `2·nextpow2(H) ≤ 4H` (`≤ 2D` with the cap) | **O(1)** | **O(1)** | low (loud failures) | small |
| P1 + P9 caching | `0.9x`–`1.0x` in multi-access blocks | same | yes | as P1 | O(pages) | O(D/P) | high | large (needs lowering) |

Non-flat speeds in the eager, P1, P2 and P5 rows are predictions or reuse study §6.4's
eager-page numbers. Only the flat, lazy and eager rows are measured.

---

## 4. Recommendation and staged plan

**Recommendation: build P5 (high-water flat) first, together with P3's 0-based slot for flat,
P7, P10 and P11. Keep P1 (64 KiB copy-on-write pages over a shared zero page, explicit
`pg == ZERO` check on stores) as a second tier, justified only by data. Build P9 when target
lowering reaches memory accesses.** P5 is the only design here whose hot path is the same IR as
the shipped one. Its risk is concentrated in cold code, and its failures are loud. P1 is the right
answer only for modules whose touched set is not a prefix, and its hot-path cost is the eager-page
cost that the study has already measured and that `chipmunk` would notice.

### Stage 0 — Touch map. No runtime change; decides between P5 and P1.

Add a throwaway harness line to each fixture's runner (not the runtime): after the kernel, scan
`memory[1].__w` and report `D`, the highest non-zero word (`H`, a lower bound, because stores of
zero are invisible), and the number of non-zero 4 KiB, 64 KiB and 1 MiB pages (`T` at each `P`).
Fixtures: `binjgb` (16 frames and the full run), `lodepng` 0/1, `chipmunk` 60/600, `miniz`,
`gltf-rs`, self-hosting. **Decision rule:** if `2·nextpow2(H) ≤ 1.5 × 2T(64 KiB)` on every fixture
(i.e. the prefix is dense), P5 alone suffices; if any fixture has `H ≫ T` (e.g. a stack or arena
near the top), plan Stage 2. Also record, as the baseline for later stages: `-jv` side-trace and
abort counts, GC cycle counts and max RSS at `setpause` 200 and 110 (P8), and start-up time (P11).

### Stage 1 — P5 + P3 (flat slot 0) + P7 + P10 + P11

1. `buffer.lua`: `buffer_create` without fill; `__h`; the `buffer_extend` section; every
   `index + k > buf.__n` → `> buf.__h` with `buffer_extend`; `buffer_check`; `copy`/`fill`/
   `writestring` heads, and the zero-skip in `fill`/`copy`; `buffer_resize` → publish `__n` only;
   `buffer_meta` read-as-zero / extend-on-write. Optionally 0-based slots (`rshift(a, 2)`, no
   `+1`) in the same change or as a separate commit. The separate commit is better because it is
   separately measurable.
2. `library/sections.rs`: register `buffer_extend` and its `NEEDS` edges. `memory.lua`,
   `expression.rs`, `statement.rs`: no change.
3. Correctness: rebuild the study's differential harness (`bufcheck/verify.lua`, study §11.3; the
   scratch copy no longer exists). Add cases for accesses that straddle `__h` at every width,
   unaligned straddles of the last materialised word, copies and fills from and into the
   unmaterialised tail, host reads and writes beyond `__h`, grow followed by an access in the grown
   region, and the `16` must-trap-without-partial-write bounds cases. Then
   `cargo test -p conformance --test luanoffi` must give the **same `280/312` and the same failure
   set** as `bda2246`. Every fixture gate must print bit-identical values, the self-hosting fixture
   first.
4. Measurement, per study §11.5's protocol (separate worktrees, round-robin, min of 5, variant
   markers): kernels `chipmunk_hash_scene(60/600)`, `lodepng_roundtrip_hash(0)`,
   `binjgb_decode_hash(16)`, `miniz_roundtrip_hash(6)`; whole-process time and RSS for all fixtures;
   `buffer_extend` hits and final `__h`. **Accept** if every kernel is within noise of `bda2246`
   and `binjgb` RSS drops to the range Stage 0 predicts from `H`.
5. Commit by area: runtime change; harness; notes (§11-style results appended to this file).

### Stage 2 — P1, only if Stage 0 or Stage 1 shows `H ≫ T` somewhere

64 KiB pages, 0-based, explicit `pg == ZERO` store check (P1), P2 only if a store-heavy A/B beats
P1 beyond noise. Selected per module by the printer (P6) behind a threshold chosen from the data,
**not** 16 MiB by default. A default of 16 MiB would put `lodepng` on the `~1.6x` slower side for
no footprint reason if P5 already fixed it. Add a forcing flag so conformance can run the paged
flavour. Gate: `-jv` must show no growth in side traces relative to eager pages. That is the
direct test of the "no fork" claim.

### Stage 3 — P9, after target lowering reaches memory

Merge bounds checks per base and block (target-lowering H7), with the merged guard calling
`buffer_extend`. Hoist `__w`/`__h` (target-lowering H8), where a stale `__h` is conservative under
P5. Drop the `ref[1]` wrapper so `buf` stops being re-loaded after every aliasing store. If Stage 2
happened, cache `pg` per block with the page-crossing guard.

### Not recommended

- A `collectgarbage("setpause")` call emitted by the runtime (P8b): it is global host state.
- 4 KiB or 1 MiB pages without Stage 0 evidence (P4).
- P12 reclaim without a fixture that frees and zeroes whole pages.
- Any design that puts a value-dependent test (`or zero`, `nil` checks, metamethods) on the
  **read** path. That is the property that made lazy pages lose, and P1, P2 and P5 all avoid it.

---

## 5. Open questions this note could not settle from the code

1. Is `binjgb`'s touched set a prefix? Stage 0. Everything about P5's footprint depends on it.
2. Does LuaJIT 2.1.0-beta3 treat an `ALOAD` of a directory as aliased by an `ASTORE` into a page
   (§1.2)? One `-jdump` of a two-access loop under eager pages answers it, and it may be the bulk
   of eager pages' `1.2x`–`1.8x`.
3. Does array-part growth by writing past the end round to a power of two on this build, and does
   `lj_alloc` `mremap` it (P5 footprint and growth cost)?
4. Is the shipped LuaJIT build `GC64` (P8d)?
5. `LJ_MAX_ASIZE` on this build, which is the hard ceiling for flat and P5 memories (P4).
