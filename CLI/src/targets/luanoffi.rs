use std::io::Write;

use ir_graph::DataFlowGraph;
use luanoffi_builder::LuaNoFFIBuilder;
use luanoffi_printer::{
	LuaNoFFIPrinter,
	library::{NamesFinder, Printer as LibraryPrinter, Sections as LibrarySections},
};
use luanoffi_tree::LuaNoFFITree;

fn build_tree(graph: &DataFlowGraph) -> LuaNoFFITree {
	let mut builder = LuaNoFFIBuilder::new();

	builder.run(graph)
}

fn print_library(tree: &LuaNoFFITree, out: &mut dyn Write) -> std::io::Result<()> {
	let mut printer = LibraryPrinter::new();
	let mut references = Vec::new();

	NamesFinder::new(&mut references).run(tree);

	let sections = LibrarySections::with_built_ins();

	printer.resolve(&references, &sections);
	printer.print(&sections, out)?;
	out.flush()
}

fn print_tree(tree: &LuaNoFFITree, out: &mut dyn Write) -> std::io::Result<()> {
	let mut printer = LuaNoFFIPrinter::new();
	let mut references = Vec::new();

	NamesFinder::new(&mut references).run(tree);
	printer.set_runtime_names(references);

	printer.print(tree, out)?;
	out.flush()
}

pub fn print(graph: &DataFlowGraph, out: &mut dyn Write) {
	let tree = build_tree(graph);

	print_library(&tree, out).expect("library should print");
	print_tree(&tree, out).expect("source should print");
}
