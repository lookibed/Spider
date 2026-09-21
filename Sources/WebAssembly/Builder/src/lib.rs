//! WebAssembly control flow builder for converting operators into structured IR.

#![no_std]

extern crate alloc;

mod code_builder;
mod expression_builder;
mod post_order_sorter;
mod stack_builder;
mod types;

use wasmparser::{BlockType, OperatorsReader};
use web_assembly_graph::ControlFlowGraph;
use web_assembly_structurer::ControlFlowStructurer;

use self::{expression_builder::ExpressionBuilder, post_order_sorter::PostOrderSorter};

pub use self::types::Types;

/// Builds a structured control flow graph from WebAssembly operators.
pub struct ControlFlowBuilder {
	expression_builder: ExpressionBuilder,
	post_order_sorter: PostOrderSorter,
	control_flow_structurer: ControlFlowStructurer,
}

impl ControlFlowBuilder {
	#[must_use]
	/// Creates a new control flow builder.
	pub const fn new() -> Self {
		Self {
			expression_builder: ExpressionBuilder::new(),
			post_order_sorter: PostOrderSorter::new(),
			control_flow_structurer: ControlFlowStructurer::new(),
		}
	}

	/// Builds and restructures the control flow graph from WebAssembly operators.
	pub fn run(
		&mut self,
		graph: &mut ControlFlowGraph,
		types: &Types,
		function_type: BlockType,
		locals: u16,
		operators: OperatorsReader<'_>,
	) {
		self.expression_builder
			.run(graph, types, function_type, locals, operators);

		self.post_order_sorter.run(&mut graph.basic_blocks, 0);

		let exit = graph.add_no_operation();

		self.control_flow_structurer.run(graph, 0, exit);
		self.post_order_sorter.run(&mut graph.basic_blocks, 0);
	}
}

impl Default for ControlFlowBuilder {
	fn default() -> Self {
		Self::new()
	}
}

#[cfg(test)]
mod tests {
	use wasmparser::{BlockType, FunctionBody, Parser, Payload, Result};
	use wast::{Wat, parser::ParseBuffer};
	use web_assembly_graph::ControlFlowGraph;

	use super::{ControlFlowBuilder, Types};

	/// Returns the number of locals declared by `body`.
	fn count_locals(body: &FunctionBody<'_>) -> u16 {
		let locals = body
			.get_locals_reader()
			.unwrap()
			.into_iter()
			.map(Result::unwrap)
			.map(|(count, _)| count)
			.sum::<u32>();

		locals.try_into().unwrap()
	}

	/// Builds the control flow graph of every function in the module `source` and
	/// returns how many were built.
	#[expect(
		clippy::wildcard_enum_match_arm,
		reason = "catch-all for the sections a module may hold"
	)]
	fn build_functions(source: &str) -> usize {
		let buffer = ParseBuffer::new(source).unwrap();
		let mut module = wast::parser::parse::<Wat<'_>>(&buffer).unwrap();
		let binary = module.encode().unwrap();

		let mut types = Types::new();
		let mut builder = ControlFlowBuilder::new();
		let mut built = 0;

		for payload in Parser::new(0).parse_all(&binary).map(Result::unwrap) {
			match payload {
				Payload::TypeSection(section) => types.add_sub_types(section),
				Payload::FunctionSection(section) => types.add_functions(section),
				Payload::CodeSectionEntry(body) => {
					let function = types.get_function_index(built.try_into().unwrap());
					let locals = count_locals(&body);
					let operators = body.get_operators_reader().unwrap();
					let mut graph = ControlFlowGraph::new();

					builder.run(
						&mut graph,
						&types,
						BlockType::FuncType(function),
						locals,
						operators,
					);

					assert!(!graph.basic_blocks.is_empty(), "graph should hold blocks");

					built += 1;
				}

				_ => {}
			}
		}

		built
	}

	/// The stack depth runs past the end of a level once the code is dead, so the
	/// level of a block that yields a result must not overflow on its way out.
	#[test]
	fn dead_block_result_does_not_overflow() {
		let built = build_functions(
			r#"(module
				(func (export "dead")
					unreachable
					block (result i32)
						i32.const 0
					end
					drop))"#,
		);

		assert_eq!(built, 1, "the module should hold one function");
	}

	/// A block may take more parameters than the dead stack holds, so its base
	/// must not underflow either.
	#[test]
	fn dead_block_parameters_do_not_underflow() {
		let built = build_functions(
			r#"(module
				(type $triple (func (param i32 i32 i32) (result i32 i32 i32)))
				(func (export "dead")
					unreachable
					i32.const 0
					i32.const 0
					block (type $triple)
					end
					drop
					drop
					drop))"#,
		);

		assert_eq!(built, 1, "the module should hold one function");
	}
}
