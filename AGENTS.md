# AGENTS.md - Spider Compiler Development Guide

This document provides guidelines for agentic coding agents working on the Spider compiler.

## Project Overview

Spider is an experimental compiler that compiles WebAssembly binaries to Luau or LuaJIT source files. The project is written in Rust and uses a modular architecture with separate targets (Luau, LuaJIT, LuaNoFFI, Json).

## Build Commands

### Full Build
```bash
# Release build
cargo build --release

# Debug build
cargo build
```

### Running Tests
```bash
# Run all tests
cargo test

# Run specific test binary (conformance tests use datatest-stable)
cargo test -p conformance --test luau
cargo test -p conformance --test luajit

# Run a single test by name
cargo test -p conformance --test luajit -- test_name_here

# Run tests in a specific crate
cargo test -p luajit-builder
cargo test -p luajit-printer

# Run tests with output
cargo test -- --nocapture
```

### Linting and Formatting
```bash
# Run clippy lints
cargo clippy

# Check formatting
cargo fmt --check

# Auto-format code
cargo fmt

# Run all checks (fmt + clippy + test)
cargo check
```

### Working with Targets
The workspace includes multiple targets:
- `Targets/Luau/*` - Luau target
- `Targets/LuaJIT/*` - LuaJIT target  
- `Targets/LuaNoFFI/*` - LuaJIT without FFI target
- `Targets/Json/*` - JSON output target

Build specific target:
```bash
cargo build -p luajit-printer
cargo build -p luanoffi-printer
```

## Code Style Guidelines

### General Principles

1. **Strict Linting**: This project uses very strict linting rules. Most lints are set to `deny` or `forbid`. Run `cargo clippy` frequently.

2. **No Unsafe Code**: `unsafe_op_in_unsafe_fn` is set to `deny`. Avoid unsafe code.

3. **No Std Crates**: Many crates use `#![no_std]` with `extern crate alloc`. Use `alloc::` imports instead of `std::`.

### Documentation

- Use `///` doc comments for public API documentation
- Document all public structs, enums, and functions
- Include `# Panics` and `# Errors` sections for functions that can fail

Example:
```rust
/// The root tree node for a Luau module.
pub struct LuauTree {
    /// The environment variable name.
    pub environment: Name,
}
```

### Naming Conventions

- **Types (structs, enums)**: `PascalCase` (e.g., `LuauTree`, `Expression`)
- **Functions and variables**: `snake_case` (e.g., `build_tree`, `parse_source`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `MAX_STACK_SIZE`)
- **Modules**: `snake_case` (e.g., `mod expression;`)

### Imports

- Use absolute paths starting from crate root for external imports
- Use `self::` for relative imports from current crate
- Group imports: external crates first, then std, then alloc, then self

Example:
```rust
use alloc::vec::Vec;
use alloc::sync::Arc;

use ir_graph::DataFlowGraph;
use hashbrown::HashMap;

use self::{
    expression::Name,
    statement::{Export, Sequence},
};
```

### Error Handling

- Use `expect()` with descriptive messages for unwraps:
  ```rust
  let value = result.expect("expression should be set only once");
  ```

- Use `#[must_use]` attribute on functions that return important values:
  ```rust
  #[must_use]
  pub fn new() -> Self { ... }
  ```

### Struct and Enum Patterns

- Use field initialization shorthand where appropriate:
  ```rust
  // Good
  Self { field1, field2, field3 }
  
  // Avoid when clear from context
  Self { field1: field1, field2: field2 }
  ```

- Use `Box<T>` for heap allocation in no_std context
- Use `Option<T>` and `Result<T, E>` for nullable/error types

### Control Flow

- Prefer `match` over `if let` for complex pattern matching
- Use early returns to reduce nesting
- Avoid `while true` (set to `forbid`)

### Testing Patterns

- Tests are located in `Conformance/tests/` using `datatest-stable`
- Test functions should be descriptive:
  ```rust
  #[test]
  fn test_i32_addition_overflow() { ... }
  ```

## Project Structure

```
Spider/
├── CLI/                    # Command-line interface
├── Conformance/            # WebAssembly conformance tests
├── IR/                    # Intermediate Representation
│   ├── Graph/             # IR data flow graph
│   └── Visitor/           # Visitor pattern implementation
├── Sources/               # Input sources
│   ├── TuringMachine/     # Turing machine support
│   └── WebAssembly/       # WebAssembly lifting
├── Targets/               # Output targets
│   ├── Json/              # JSON output
│   ├── Luau/              # Luau target
│   ├── LuaJIT/            # LuaJIT target
│   └── LuaNoFFI/          # LuaJIT without FFI
└── Cargo.toml             # Workspace configuration
```

## Common Development Tasks

### Adding a New Target

1. Create new directory under `Targets/`
2. Add Cargo.toml with appropriate name (e.g., `luanoffi-tree`)
3. Create Tree, Builder, Printer modules (copy from existing target)
4. Update workspace `Cargo.toml` members
5. Add target to CLI arguments in `CLI/src/arguments.rs`
6. Add target handling in `CLI/src/targets/`
7. Create appropriate runtime files (for Lua targets)

### Modifying Runtime Files

Runtime files (`.lua`) are stored in `Targets/*/Printer/runtime/` and are embedded into the binary using `include_str!()`. After modifying:
1. Rebuild with `cargo build --release`
2. Test output with CLI

## Important Files

- `Cargo.toml` - Workspace configuration, lints, dependencies
- `CLI/src/main.rs` - Entry point
- `CLI/src/arguments.rs` - CLI argument definitions
- `Targets/*/Printer/src/library/sections.rs` - Runtime section parsing

## Running the CLI

```bash
# Build first
cargo build --release

# Run with WebAssembly file
./target/release/spider-cli.exe input.wasm -t luau > output.lua

# Available targets: json, luau, lua-jit, lua-no-ffi
./target/release/spider-cli.exe input.wasm -t lua-jit
```
