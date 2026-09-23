# Notes Index

This directory holds the working notes that explain where Spider is actually winning, where it is still rough, and which experiments matter right now.

## Start here

1. [lua-no-ffi-overview.md](lua-no-ffi-overview.md)
2. [lua-no-ffi-measurements.md](lua-no-ffi-measurements.md)
3. [windows-ffi-machine-instructions.md](windows-ffi-machine-instructions.md)

## Status and bug tracking

- [lua-no-ffi-status.md](lua-no-ffi-status.md)
- [lua-no-ffi-known-bugs.md](lua-no-ffi-known-bugs.md)
- [problem_lua_limits.md](problem_lua_limits.md)

## Hypothesis notes (read-only studies, no measurements)

- [hypotheses/register-allocation.md](hypotheses/register-allocation.md) - where the boundary copies come from and how to remove them
- [hypotheses/target-lowering.md](hypotheses/target-lowering.md) - lowering runtime helpers into the IR
- [hypotheses/i64-representation.md](hypotheses/i64-representation.md) - legalising i64 into i32 pairs
- [hypotheses/paged-memory.md](hypotheses/paged-memory.md) - memory footprint after the packed-word transition
- [hypotheses/nan-and-f64-bits.md](hypotheses/nan-and-f64-bits.md) - the remaining NaN sign and payload failures
- [hypotheses/giant-functions.md](hypotheses/giant-functions.md) - LuaJIT jump-range and local limits on huge functions
- [hypotheses/code-size.md](hypotheses/code-size.md) - shrinking the generated Lua
- [hypotheses/compiler-performance.md](hypotheses/compiler-performance.md) - compiler speed and memory, self-hosting first
- [hypotheses/verification.md](hypotheses/verification.md) - catching the bug classes the spec suite misses

## Performance studies

- [lua-no-ffi-performance-hypotheses.md](lua-no-ffi-performance-hypotheses.md)
- [lua-no-ffi-upvalue-strategies.md](lua-no-ffi-upvalue-strategies.md)

## Upstream

- [upstream-review.md](upstream-review.md)

## Important open problems

- [lua-no-ffi-plmpeg-open-problem.md](lua-no-ffi-plmpeg-open-problem.md)
- [lua-no-ffi-smollm2-open-problem.md](lua-no-ffi-smollm2-open-problem.md)

## Related fixture documentation

- [../../tests/manual/self-hosting-luanoffi-builder/README.md](../../tests/manual/self-hosting-luanoffi-builder/README.md)
- [../../tests/manual/real-world-plmpeg/README.md](../../tests/manual/real-world-plmpeg/README.md)
- [../../tests/manual/real-world-plmpeg-stream/README.md](../../tests/manual/real-world-plmpeg-stream/README.md)
- [../../tests/manual/real-world-h264bsd-mp4/README.md](../../tests/manual/real-world-h264bsd-mp4/README.md)
- [../../tests/manual/real-world-libjpeg-turbo-mjpeg/README.md](../../tests/manual/real-world-libjpeg-turbo-mjpeg/README.md)
- [../../tests/manual/real-world-binjgb/README.md](../../tests/manual/real-world-binjgb/README.md)
