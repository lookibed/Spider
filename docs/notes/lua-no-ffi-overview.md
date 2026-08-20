# Lua No FFI Overview

`lua-no-ffi` is now the main technical bet in Spider.

## Why this target matters

- It reduces the amount of trust Spider has to place in host `ffi` behavior.
- It gives Spider a route that is easier to carry across constrained or awkward runtimes.
- It forces the compiler to solve generated-code shape problems directly instead of outsourcing them to `ffi`.

## Current sales pitch

The repository can now be read through this lens:

- Spider is not just a Wasm-to-Lua compiler anymore.
- Spider is actively proving that a `lua-no-ffi` backend can compete with, and on tracked fixtures even outperform, the older `ffi`-centric route.
- The original LuaJIT constraints around scope pressure, huge captures, and upvalue-heavy generated closures are no longer accepted as final architectural limits.

That does not mean every edge is solved. It means those limits are now compiler work items, not project-ending assumptions.

## Where to verify the claim

- [lua-no-ffi-measurements.md](lua-no-ffi-measurements.md)
- [../../tests/manual/self-hosting-luanoffi-builder/README.md](../../tests/manual/self-hosting-luanoffi-builder/README.md)

## What changed structurally

The project now includes target-side mitigation work for the problems that used to define the original ceiling:

- large scoped capture sets
- upvalue pressure
- wide generated function bodies
- fixture-driven backend validation instead of toy examples only

## Read next

- For numbers: [lua-no-ffi-measurements.md](lua-no-ffi-measurements.md)
- For legacy Windows `ffi` context: [windows-ffi-machine-instructions.md](windows-ffi-machine-instructions.md)
- For real current blockers: [lua-no-ffi-plmpeg-open-problem.md](lua-no-ffi-plmpeg-open-problem.md) and [lua-no-ffi-smollm2-open-problem.md](lua-no-ffi-smollm2-open-problem.md)
