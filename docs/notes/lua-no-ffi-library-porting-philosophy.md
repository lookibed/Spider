# Lua-No-FFI Library Porting Philosophy

This document captures the practical philosophy for porting C/C++ libraries through `Spider` to the `lua-no-ffi` target.

It is intentionally narrow and honest. It does not claim that `lua-no-ffi` is a universal way to run arbitrary native libraries unchanged.

The target audience is anyone trying to build portable Lua libraries that can run in environments where:

- `ffi` is unavailable
- the host environment is constrained or sandboxed
- platform APIs differ across runtimes
- the same library should be reusable across multiple Lua targets

## Core Claim

The right way to think about `lua-no-ffi` is:

- not as a replacement for native execution
- not as a replacement for a full WASI host
- not as a promise that arbitrary upstream C code can be carried over unchanged

Instead, treat it as a portability path for validated library cores.

That means:

- port the portable value-producing core
- keep the host boundary explicit
- validate against `wasmtime`
- accept that some libraries are simply bad fits

This claim is much narrower than "compile any C library to pure Lua", but it is also much more defensible.

## What This Philosophy Is Not

This document does not argue that:

- every real C library has a clean separable core
- extracting such a core is always cheap
- WASI is unnecessary
- copying data across the host/module boundary is free
- generated Lua size is not a real problem
- debugging generated Lua is comfortable today

All of those are real concerns.

The philosophy here is not "these problems do not exist".

The philosophy is:

- these problems define the fit criteria
- choose libraries accordingly
- keep the architecture honest about the tradeoffs

## Why "Portable Core + Host Adapter" Still Matters

Even with all the caveats, the core split remains the right default model for `lua-no-ffi`.

Do not try to port a library's original host environment together with the library.

Instead, split the library into:

- `portable core`
- `host adapter layer`

The portable core is the part that should go through:

`library source -> wasm -> Spider -> lua-no-ffi`

The host adapter layer is the part that should be rewritten, shimmed, or re-bound per target Lua environment.

This is still the preferred model because `lua-no-ffi` is valuable precisely in environments where:

- native bindings are unavailable
- host APIs differ
- one fixed platform ABI cannot be assumed

If a port only works by smuggling in a large host model unchanged, it stops being portable in the way `lua-no-ffi` is meant to provide.

## The Honest Limitation

Most real C libraries are not perfectly layered.

Many of them are entangled with:

- `malloc/free`
- libc helpers
- `errno`
- file handles
- logging
- platform typedefs
- callback styles shaped by native host assumptions

Sometimes the core can still be isolated with a thin shim.

Sometimes doing that creates an expensive custom fork.

When the surgery required is deep enough that upstream tracking becomes painful, that library is a weak Spider candidate. This is not a failure of discipline. It is a project-fit signal.

So the rule is not:

- "every library must be surgically reduced to a pure core"

The real rule is:

- "first evaluate whether a stable and maintainable core boundary exists at all"

If that boundary does not exist, forcing the library through `lua-no-ffi` is usually a mistake.

## Where WASI Fits

WASI is not the enemy of this philosophy.

In some cases, `wasm32-wasi` is the more practical way to stay closer to upstream code because it lets the library keep a standardized import surface for:

- I/O
- clocks
- files
- environment access
- other host interactions

This can reduce the amount of source surgery compared with carving out a smaller standalone core.

That said, WASI is not a free answer for `lua-no-ffi`:

- the imports still need a host implementation
- a pure-Lua WASI host can itself become large and slow
- it can move complexity from the library to the runtime without truly removing it
- it can preserve upstream shape while preserving upstream host assumptions too

So the practical recommendation is:

- prefer `portable core + adapters` when the core boundary is reasonably clean
- consider `WASI + explicit host shims` when preserving upstream is more important and the import surface is still manageable
- avoid pretending that either path is universally best

## What Counts As Portable Core

Portable core usually includes:

- parsers
- codecs
- compression/decompression engines
- cryptographic primitives
- math kernels
- physics/logic engines
- interpreters/VMs with explicit host callbacks
- deterministic buffer-to-buffer transforms
- pure state machines over memory and callbacks

These are the best candidates for `lua-no-ffi`.

Real examples already validated in this repo include:

- `TinyExpr` as a parser/evaluator core
- `miniz` as a compression/decompression core

## What Counts As Host Adapter Layer

Host adapter layer usually includes:

- file I/O
- directory/path handling
- sockets/networking integration
- wall clock / timestamps / time zones
- terminal or UI integration
- threads and synchronization primitives
- OS process APIs
- logging sinks
- platform allocators
- environment variable access
- windowing/input bindings
- image/audio/video device I/O

These parts are important, but they are not good candidates for a universal direct Spider port.

They should be treated as adapters around the core, not as part of the core port.

## The Main Rule

Portable logic belongs inside the wasm module.

Environment-specific behavior belongs outside the wasm module.

In practice:

- the wasm module should expose a narrow, stable API
- Lua code should provide the surrounding environment integration
- each host gets its own adapter implementation

This separation is what makes a Spider port reusable instead of one-off.

## Performance Reality: Copying Is A Real Cost

For many useful library shapes, the core API naturally becomes something like:

- `parse_from_bytes(input_ptr, input_len) -> result`
- `decode_buffer(...)`
- `compress_buffer(...)`

This is often the cleanest portability boundary, but it is not free.

In a `Lua -> Wasm memory -> Lua` pipeline, data frequently gets copied:

- from Lua into linear memory
- processed inside the module
- copied back out into Lua-visible data

For some workloads, this is acceptable.

For others, it can dominate the total runtime.

This is especially risky for:

- large streaming inputs
- video and audio processing
- high-throughput cryptography
- workloads with repeated small host/module crossings
- designs that rebuild large contiguous buffers over and over

So "buffer API" is not a universal recommendation. It is a good default only when the expected data movement cost is acceptable for the product.

## Code Size Reality: Generated Lua Has A Price

Another hard limit is output size.

Compiling C to Wasm and then lowering Wasm to pure Lua can produce large source files, especially when the library pulls in:

- libc-style helpers
- memory routines
- error-handling machinery
- extra compiler-lowered support code

This affects:

- generated Lua file size
- load time
- parse time
- memory use
- LuaJIT optimization behavior

For `lua-no-ffi`, this is not a theoretical concern. It is a real fit constraint.

A library can be semantically portable and still be a poor practical candidate because the generated Lua is too large or too slow to load.

That means output size and startup behavior must be measured, not assumed away.

## Debugging Reality: Differential Testing Beats Comfort

Debugging `lua-no-ffi` ports is currently much closer to compiler bring-up than to ordinary library application development.

Generated Lua may be large, and source-level debugging is limited.

Today the reliable strategy is:

- compare against a trusted reference
- add narrow probe exports
- isolate the drifting path
- keep the reproducer as a regression fixture

This is exactly why parity against `wasmtime` is so central in this repo.

Do not assume that a complex library port will be easy to debug once generated.

Assume the opposite, and structure the validation flow accordingly.

## How To Think About A Library Before Porting

Before porting a library, ask:

1. What part of this library produces the actual value?
2. Can that value-producing part run over buffers, state, and callbacks only?
3. Which parts of the code are really just host integration?
4. Can the host-dependent pieces be moved to explicit inputs, outputs, or imports without a deep fork?
5. Can the useful surface area be expressed as a deterministic API?
6. Is the host boundary coarse-grained enough that callback/copy overhead will be tolerable?
7. Is the expected generated Lua size still practical?

If several of these answers are no, the library is probably not a good fit for Spider `lua-no-ffi`.

## Recommended Porting Shape

The recommended architecture is:

1. Audit whether a stable portable core boundary actually exists.
2. Choose between:
   - `portable core + adapters`
   - `WASI + explicit host shims`
3. Compile the chosen core or module to wasm.
4. Expose a small set of stable exports/imports.
5. Verify behavior against `wasmtime`.
6. Transpile with `Spider` to `lua-no-ffi`.
7. Write or refine the Lua adapter layer for the target environment.
8. Measure size, load cost, and runtime cost before calling the port practical.

This keeps the Spider-generated part focused on semantics and portability instead of pretending to be a full host runtime.

## Examples Of Good API Shapes

Prefer APIs like:

- `parse_from_bytes(input_ptr, input_len) -> result`
- `decode_buffer(input_ptr, input_len, output_ptr, output_len) -> status`
- `compress_buffer(...)`
- `step_simulation(state_ptr, dt) -> status`
- `render_to_buffer(...)`
- `process_message(...)`

Avoid APIs that require the ported library to own the whole host boundary, such as:

- open this file path
- enumerate this directory
- read current system time in a tight loop
- write to stdout as a core semantic channel
- open this socket
- spawn this process

Those should be moved into adapters when possible.

If they cannot be moved cleanly, the library may not be a good Spider target.

## How To Handle Common Host Dependencies

### Files

Do not port `fopen()/fread()/fwrite()` as the main API shape unless there is a strong reason to preserve that interface.

Prefer:

- load bytes outside the wasm module
- pass bytes into the core
- retrieve processed bytes or status back out

If preserving upstream structure matters more than a minimal core, a WASI-oriented build with host shims may be the better route.

### Time

Do not let the core depend directly on platform clocks when portability matters.

Prefer:

- pass timestamps into the core
- expose time as an explicit import or argument

If the library needs extremely frequent fine-grained clock access, that is a warning sign. A pure-Lua host bridge may be too expensive.

### Logging

Do not rely on `printf()` as part of the portable API contract.

Prefer:

- status codes
- structured error buffers
- optional host callback imports for logging

### Allocation

Prefer one of two models:

- self-contained linear memory owned by the wasm/core side
- explicit allocator contract when the library truly needs host ownership

For `lua-no-ffi`, a self-contained memory model is usually the safer default.

But if the library's allocator behavior is tightly coupled to its design, forcing a fake simplification can create a brittle fork. Treat allocator strategy as part of the fit analysis.

### Callbacks

Callbacks are acceptable if they are:

- explicit
- narrow
- deterministic
- easy to adapt per host
- infrequent enough not to dominate runtime

Examples:

- read bytes
- write bytes
- log message
- request clock value
- provide configuration/state

If the library fundamentally expects dense host interaction in a hot loop, `lua-no-ffi` is usually the wrong target.

## What To Avoid

Avoid treating Spider as a way to emulate an operating system or a native C runtime wholesale.

That is not the right abstraction boundary for `lua-no-ffi`.

If a library only works when it owns:

- the filesystem
- the socket layer
- platform threads
- signals or `setjmp/longjmp`-heavy host assumptions
- a large native ABI surface

then it is a bad early candidate for universal `lua-no-ffi` porting.

## What "Porting The Whole Library" Should Mean

When the real goal is to ship a useful library, "port the whole library" should mean:

- port the whole portable value-producing surface
- preserve the important algorithms and semantics
- re-create the environment bindings as adapters where appropriate
- stay close enough to upstream that maintenance is still realistic

It should not mean:

- replicate every original native integration detail inside the Spider-generated core

If preserving those details is mandatory, a different strategy may be more honest than `lua-no-ffi`.

## Validation Philosophy

Every serious library port should have a three-stage validation flow:

1. Native or reference behavior
2. `wasmtime` behavior on the wasm core or wasm-with-shims build
3. `Spider -> lua-no-ffi` behavior

Parity should be established between stages 2 and 3.

If possible, add:

- narrow probe exports for debugging
- real-world fixtures based on upstream code
- regression cases for every bug found during bring-up
- explicit measurements for output size and runtime cost

## Practical Success Criteria

A good Spider library port:

- isolates a maintainable portable core cleanly, or justifies a WASI/shim path clearly
- exposes a stable API over data, state, and callbacks
- runs without `ffi`
- matches `wasmtime`
- keeps host assumptions explicit
- can be adapted to multiple Lua environments
- remains realistic to maintain across upstream updates
- does not exceed acceptable size and load-cost limits for the target environment

## Project-Fit Filter

A library is a strong candidate for `lua-no-ffi` when most of the following are true:

- the useful part of the library is algorithmic and deterministic
- host interaction can be coarse-grained
- data copying cost is acceptable
- the module can be validated against `wasmtime`
- the generated Lua size remains practical
- the upstream can be tracked with thin shims instead of a deep long-lived fork

A library is a weak candidate when several of the following are true:

- value depends heavily on host integration rather than portable logic
- it needs dense filesystem, socket, thread, or clock interaction
- correctness depends on complex runtime facilities that are hard to model in pure Lua
- the code only becomes portable after invasive surgery
- startup and size costs dominate the actual workload
- debugging drift would be too expensive for the expected payoff

## Summary

The scalable way to port libraries through Spider is still:

- port the core when a real core exists
- adapt the host explicitly
- use WASI strategically when it preserves maintainability better
- measure copying, size, and runtime costs
- reject libraries that do not fit the model

`lua-no-ffi` should be treated as a portability engine for validated library cores and carefully chosen wasm modules, not as an emulator for arbitrary native host behavior.

That narrower claim is the one this project can honestly defend.
