# `lua-no-ffi` Chipmunk Profile Breakdown

This note isolates the `Chipmunk2D` slowdown into smaller workload classes.

The goal is to distinguish between:

- raw memory/state overhead
- expensive math helper overhead
- branch-heavy scalar state updates
- simple body stepping
- collision-heavy stepping
- collision + constraint stepping

Targets compared:

- `wasmtime`
- Spider `lua-no-ffi`
- Spider `lua-jit`

## Profiling Fixture

The fixture lives under:

- [tests/manual/chipmunk-profile/README.md](/D:/Backups/Spider/tests/manual/chipmunk-profile/README.md)

Single-export benchmark modules were used for the timing runs. That matters because one earlier combined profiling module exceeded the `lua-jit` target's loadable-size/upvalue limits, which would have polluted the comparison with a structural codegen limit instead of a runtime cost.

## Default Inputs

- `memory_walk`: `400`
- `math_shim`: `400`
- `branch_state`: `400`
- `space_freefall`: `120`
- `space_collision`: `120`
- `space_full`: `120`

## Result Integrity

All three engines matched on numeric output for the single-export benchmark modules:

- `wasmtime`
- `lua-no-ffi`
- `lua-jit`

That means the timing comparison here is about execution cost, not semantic drift.

## Timing Table

| Workload | Meaning | `wasmtime` avg | `lua-no-ffi` avg | `lua-jit` avg | `lua-no-ffi` slowdown | `lua-jit` slowdown |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `memory_walk` | pointer-ish state mutation over a struct array | `84.49 ms` | `155.16 ms` | `207.84 ms` | `1.84x` | `2.46x` |
| `math_shim` | `sqrt/sin/cos/acos/atan2/exp/pow` heavy scalar math | `19.08 ms` | `40.11 ms` | `71.86 ms` | `2.10x` | `3.77x` |
| `branch_state` | branch-heavy scalar state updates without Chipmunk | `21.33 ms` | `33.74 ms` | `46.17 ms` | `1.58x` | `2.16x` |
| `space_freefall` | Chipmunk body stepping without shapes/collisions/constraints | `92.57 ms` | `254.88 ms` | `171.14 ms` | `2.75x` | `1.85x` |
| `space_collision` | Chipmunk stepping with shapes and collisions, no constraints | `52.01 ms` | `615.43 ms` | `896.75 ms` | `11.83x` | `17.24x` |
| `space_full` | Chipmunk stepping with collisions and constraints | `32.68 ms` | `764.46 ms` | `1226.99 ms` | `23.39x` | `37.55x` |

## What This Suggests

### 1. Memory-only and math-only are not enough to explain the full gap

The isolated synthetic costs are noticeable, but not catastrophic:

- `memory_walk`: about `1.84x`
- `math_shim`: about `2.10x`
- `branch_state`: about `1.58x`

That means the `Chipmunk2D` explosion is not coming from just one raw primitive like "table-backed memory is slow" or "shim math is slow".

### 2. The real jump starts when collision machinery enters the hot path

The biggest cliff appears here:

- `space_freefall`: `2.75x`
- `space_collision`: `11.83x`
- `space_full`: `23.39x`

That strongly suggests the dominant cost is in the combination of:

- collision detection
- contact graph/state churn
- many tiny memory accesses
- branch-heavy solver logic
- repeated inner-loop helper calls

### 3. Constraints add a second major multiplier

Going from collision-only to full collision + constraints nearly doubles the `lua-no-ffi` slowdown again:

- `space_collision`: `11.83x`
- `space_full`: `23.39x`

So the bottleneck is not just broadphase/narrowphase collision. The constraint solver is a major second contributor.

### 4. `lua-jit` is usually slower than `lua-no-ffi` on these kernels

For this profiling set:

- `memory_walk`: `lua-jit` is about `1.34x` slower than `lua-no-ffi`
- `math_shim`: about `1.79x` slower
- `branch_state`: about `1.37x` slower
- `space_collision`: about `1.46x` slower
- `space_full`: about `1.61x` slower

The one exception is `space_freefall`, where `lua-jit` is faster.

That suggests the FFI-backed target is not automatically winning on these workloads. The likely reason is not "FFI is bad", but that the current `lua-jit` target is paying for its own representation or tracing shape in hot loops.

## Current Best Hypothesis

The current strongest interpretation is:

- pure memory cost matters
- pure math helper cost matters
- but the real `Chipmunk2D` cliff is the interaction of collision + constraint stepping with many tiny helper-driven operations

In other words:

the dominant slowdown is probably not one single primitive, but the way `lua-no-ffi` executes a very branchy, pointer-heavy, mutation-heavy hot loop with lots of small float and memory operations.

## Practical Takeaway

If we want to improve `Chipmunk2D`-class workloads, the most promising places to investigate next are:

1. memory access strategy in hot collision/solver paths
2. helper-call density in branch-heavy stepping code
3. code shape that affects LuaJIT trace quality
4. why the current `lua-jit` target loses to `lua-no-ffi` on most of these benchmark slices
