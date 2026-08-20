# Windows FFI Machine Instructions

The old `ffi`-centric Spider story used to be much less comfortable on Windows.

That is no longer the right one-line description.

## Current status

The legacy `lua-jit` / `ffi` route is still part of Spider, and Windows support for that path was extended through a machine-instructions-based implementation path.

The practical meaning is:

- Windows is no longer treated as "the place where the old `ffi` path simply does not matter."
- The project can keep the classic `ffi` target alive as a comparison baseline while `lua-no-ffi` becomes the main bet.

## Why this note matters

This is important for the README story because Spider does not need to frame the transition as:

- old `ffi` target is dead
- only `lua-no-ffi` matters

The stronger story is:

- `lua-no-ffi` is now the primary direction
- the classic `ffi` route is still supported
- even the Windows side of that route has been moved forward instead of being abandoned

## Read next

- [lua-no-ffi-overview.md](lua-no-ffi-overview.md)
- [lua-no-ffi-measurements.md](lua-no-ffi-measurements.md)
