//! Regression tests for rewrites that cross a region boundary.
//!
//! The ISLE matcher used to resolve operand links through `RegionIn` and `GammaIn` ports,
//! so a rule such as `(N + K1) + K2 => N + (K1 + K2)` could hand a node inside a gamma
//! region an operand produced outside of it. The local allocator only ever keeps a value
//! alive across a region through the region's own ports, so the escaped value held on to
//! a local that a sibling region's result was meant to be coalesced into. That result then
//! landed in a different local and the move into the gamma's output was silently dropped.

#[path = "common/compiler.rs"]
mod compiler;

use core::fmt::Write as _;
use std::{
	io::Write as _,
	path::{Path, PathBuf},
};

use ir_graph::DataFlowGraph;
use ir_visitor::control::region_scope;
use luanoffi_builder::LuaNoFFIBuilder;
use luanoffi_printer::{
	LuaNoFFIPrinter,
	library::{NamesFinder, Printer as LibraryPrinter, Sections as LibrarySections},
};
use wast::{
	Wat,
	parser::{self, ParseBuffer},
};

use compiler::Compiler;

use datatest_stable as _;
use luajit_builder as _;
use luajit_printer as _;
use luanoffi_tree as _;
use luau_builder as _;
use luau_printer as _;
use web_assembly_lifter as _;

// Reduced from `real-world-miniz` under `-o`. With `$c` clear the second branch never
// runs, `$t` stays zero and `$x` is returned unchanged. The empty conditional in front
// only shapes the local allocation: without it the escaped value happens to share a local
// with the output it clobbers and the move survives.
const REASSOCIATED_ACROSS_GAMMA: &str = r#"
(module
	(func (export "f") (param $x i32) (param $c i32) (result i32)
		(local $t i32)
		(if (local.get $c) (then) (else))
		(if (local.get $c)
			(then
				(local.set $t
					(i32.add (i32.add (local.get $x) (i32.const 8)) (i32.const 9)))))
		(if (local.get $t)
			(then (local.set $x (i32.const 0))))
		(local.get $x)))
"#;

fn encode(source: &str) -> Vec<u8> {
	let buffer = ParseBuffer::new(source).expect("source should lex");
	let mut wat = parser::parse::<Wat<'_>>(&buffer).expect("source should parse");

	wat.encode().expect("source should encode")
}

fn print_lua(graph: &DataFlowGraph) -> Vec<u8> {
	let tree = LuaNoFFIBuilder::new().run(graph);

	let mut references = Vec::new();

	NamesFinder::new(&mut references).run(&tree);

	let sections = LibrarySections::with_built_ins();
	let mut library = LibraryPrinter::new();
	let mut out = Vec::new();

	library.resolve(&references, &sections);
	library
		.print(&sections, &mut out)
		.expect("library should print");

	let mut printer = LuaNoFFIPrinter::new();

	printer.set_runtime_names(references);
	printer.print(&tree, &mut out).expect("tree should print");

	writeln!(out, "return module").expect("tree should print");

	out
}

fn get_path_target(name: &str) -> PathBuf {
	let mut path = [env!("CARGO_TARGET_TMPDIR"), "region-scope"]
		.iter()
		.collect::<PathBuf>();

	std::fs::create_dir_all(&path).expect("directory should be created");

	path.push(name);

	path
}

// Runs `calls` against the compiled module and returns what they print, one per line.
fn run_calls(module: &Path, calls: &[&str]) -> String {
	let module = module.to_str().expect("path should be valid UTF-8");
	let mut driver = format!("local m = dofile({module:?})()\n");

	for call in calls {
		writeln!(driver, "print((m.{call}))").expect("driver should be built");
	}

	let path = module.replace(".lua", ".driver.lua");

	std::fs::write(&path, driver).expect("driver should be written");

	let program = std::env::var_os("LUAJIT_PATH").unwrap_or_else(|| "luajit".into());
	let output = std::process::Command::new(program)
		.arg(&path)
		.output()
		.expect("luajit should run");

	assert!(
		output.status.success(),
		"luajit failed: {}",
		String::from_utf8_lossy(&output.stderr)
	);

	String::from_utf8(output.stdout).expect("output should be UTF-8")
}

fn compile_and_run(name: &str, source: &str, optimize: bool, calls: &[&str]) -> String {
	let data = encode(source);
	let graph = Compiler::new().run(&data, optimize);

	assert_eq!(region_scope::find_escape(&graph), None);

	let path = get_path_target(&format!("{name}.O{}.lua", u8::from(optimize)));

	std::fs::write(&path, print_lua(&graph)).expect("module should be written");

	run_calls(&path, calls)
}

#[test]
fn reassociation_does_not_read_across_a_gamma() {
	const CALLS: [&str; 4] = ["f(5, 0)", "f(5, 1)", "f(0, 1)", "f(-17, 1)"];
	const EXPECTED: &str = "5\n0\n0\n-17\n";

	let plain = compile_and_run("reassociation", REASSOCIATED_ACROSS_GAMMA, false, &CALLS);
	let optimized = compile_and_run("reassociation", REASSOCIATED_ACROSS_GAMMA, true, &CALLS);

	assert_eq!(plain, EXPECTED);
	assert_eq!(optimized, EXPECTED);
}
