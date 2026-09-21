//! ISLE-based peephole optimizations.

mod context;
mod internal;

use ir_graph::{DataFlowGraph, Link, Node, simple::Identity};

use self::internal::{
	constructor_SimplifyGlobal, constructor_SimplifyI32, constructor_SimplifyMemory,
	constructor_SimplifyTable,
};

fn replace_with_identity(graph: &mut DataFlowGraph, destination: u32, sources: &[Link]) {
	let sources = sources.iter().copied().collect();

	*graph.get_mut(destination) = Node::Identity(Identity { sources });
}

/// Moves the `source` node into `destination`, leaving a [`Node::Trap`] behind.
///
/// This is only sound when `source` was created while applying the rule, as such a node is
/// not referenced by anything else yet. Moving out of a node that other nodes read from
/// would silently turn their operand into a trap.
fn replace_with_direct(graph: &mut DataFlowGraph, destination: u32, source: u32) {
	let source = core::mem::take(graph.get_mut(source));

	*graph.get_mut(destination) = source;
}

/// Returns the identifier the next node added to `graph` would be given.
fn next_id(graph: &DataFlowGraph) -> u32 {
	// A graph can never hold more than `u32::MAX` nodes, so the saturation is unreachable
	// and only there to keep the function free of panics.
	u32::try_from(graph.len()).unwrap_or(u32::MAX)
}

fn replace_node(graph: &mut DataFlowGraph, destination: u32, sources: &[Link], added: u32) {
	if let &[source] = sources
		&& source.1 == 0
		&& source.0 >= added
	{
		replace_with_direct(graph, destination, source.0);
	} else {
		replace_with_identity(graph, destination, sources);
	}
}

/// Simplifies an I32 operation at the given node ID.
pub fn simplify_i32(graph: &mut DataFlowGraph, id: u32) -> bool {
	let added = next_id(graph);

	constructor_SimplifyI32(graph, Link(id, 0)).is_some_and(|source| {
		replace_node(graph, id, &[source], added);

		true
	})
}

/// Simplifies a global operation at the given node ID.
pub fn simplify_global(graph: &mut DataFlowGraph, id: u32) -> bool {
	let added = next_id(graph);

	constructor_SimplifyGlobal(graph, Link(id, 0)).is_some_and(|sources| {
		replace_node(graph, id, &sources.as_fixed(), added);

		true
	})
}

/// Simplifies a table operation at the given node ID.
pub fn simplify_table(graph: &mut DataFlowGraph, id: u32) -> bool {
	let added = next_id(graph);

	constructor_SimplifyTable(graph, Link(id, 0)).is_some_and(|sources| {
		replace_node(graph, id, &sources.as_fixed(), added);

		true
	})
}

/// Simplifies a memory operation at the given node ID.
pub fn simplify_memory(graph: &mut DataFlowGraph, id: u32) -> bool {
	let added = next_id(graph);

	constructor_SimplifyMemory(graph, Link(id, 0)).is_some_and(|sources| {
		replace_node(graph, id, &sources.as_fixed(), added);

		true
	})
}

/// Simplifies the node at the given ID, reporting whether a rule matched.
///
/// Every rule set is rooted at a single node kind, so only the one rule set that can
/// possibly match is tried. Dispatching here keeps the cost of a sweep proportional to
/// the nodes a rule could rewrite rather than to the number of rule sets.
///
/// [`simplify_global`], [`simplify_table`] and [`simplify_memory`] are deliberately left
/// out. They all forward a stored value straight to a later load, which trades one load
/// for keeping the stored value live over the whole span between the two. This backend
/// has no register allocator, so those extra live ranges push functions past the Lua
/// local limit and into the spill table. Measured on `libjpeg_turbo_mjpeg`, forwarding
/// raised spill sites from 1323 to 1874, and on `lodepng` it made the generated code 29%
/// slower while saving no calls at all. They remain available to callers that want them.
pub fn simplify(graph: &mut DataFlowGraph, id: u32) -> bool {
	match *graph.get(id) {
		// `SimplifyI32` is rooted at `I32Add` and `I32Sub`.
		Node::IntegerBinaryOperation(_) => simplify_i32(graph, id),
		Node::Apply(_)
		| Node::F32(_)
		| Node::F64(_)
		| Node::Fence(_)
		| Node::GammaIn(_)
		| Node::GammaOut(_)
		| Node::GlobalGet(_)
		| Node::GlobalNew(_)
		| Node::GlobalSet(_)
		| Node::Host(_)
		| Node::I32(_)
		| Node::I64(_)
		| Node::Identity(_)
		| Node::Import(_)
		| Node::IntegerCompareOperation(_)
		| Node::IntegerConvertToNumber(_)
		| Node::IntegerExtend(_)
		| Node::IntegerNarrow(_)
		| Node::IntegerTransmuteToNumber(_)
		| Node::IntegerUnaryOperation(_)
		| Node::IntegerWiden(_)
		| Node::LambdaIn(_)
		| Node::LambdaOut(_)
		| Node::MemoryCopy(_)
		| Node::MemoryDrop(_)
		| Node::MemoryFill(_)
		| Node::MemoryGrow(_)
		| Node::MemoryLoad(_)
		| Node::MemoryNew(_)
		| Node::MemorySize(_)
		| Node::MemoryStore(_)
		| Node::Null
		| Node::NumberBinaryOperation(_)
		| Node::NumberCompareOperation(_)
		| Node::NumberNarrow(_)
		| Node::NumberTransmuteToInteger(_)
		| Node::NumberTruncateToInteger(_)
		| Node::NumberUnaryOperation(_)
		| Node::NumberWiden(_)
		| Node::OmegaIn(_)
		| Node::OmegaOut(_)
		| Node::RefIsNull(_)
		| Node::RegionIn(_)
		| Node::RegionOut(_)
		| Node::TableCopy(_)
		| Node::TableDrop(_)
		| Node::TableFill(_)
		| Node::TableGet(_)
		| Node::TableGrow(_)
		| Node::TableNew(_)
		| Node::TableSet(_)
		| Node::TableSize(_)
		| Node::ThetaIn(_)
		| Node::ThetaOut(_)
		| Node::Trap => false,
	}
}

#[cfg(test)]
mod tests {
	use ir_graph::{
		DataFlowGraph, Link, Node,
		simple::{IntegerBinaryOperation, IntegerBinaryOperator, IntegerType},
	};

	use super::simplify_i32;

	fn add_i32(graph: &mut DataFlowGraph, lhs: Link, rhs: Link) -> u32 {
		graph.add_node(Node::IntegerBinaryOperation(IntegerBinaryOperation {
			lhs,
			rhs,
			kind: IntegerType::I32,
			operator: IntegerBinaryOperator::Add,
		}))
	}

	#[test]
	fn folded_constant_is_moved_into_the_destination() {
		let mut graph = DataFlowGraph::new();
		let lhs = graph.add_node(Node::I32(2));
		let rhs = graph.add_node(Node::I32(3));
		let destination = add_i32(&mut graph, Link(lhs, 0), Link(rhs, 0));

		assert!(simplify_i32(&mut graph, destination));

		let Node::I32(value) = *graph.get(destination) else {
			panic!("destination should hold the folded constant")
		};

		assert_eq!(value, 5_i32);
	}

	#[test]
	fn existing_source_is_not_moved_out_of() {
		// The graph is deliberately not in topological order, so the operand of the
		// addition lives at a higher identifier than the addition itself.
		let mut graph = DataFlowGraph::new();
		let zero = graph.add_node(Node::I32(0));
		let destination = add_i32(&mut graph, Link(2, 0), Link(zero, 0));
		let operand = graph.add_node(Node::Null);

		// A second reader of the operand, which a move would leave reading a trap.
		let other = add_i32(&mut graph, Link(operand, 0), Link(operand, 0));

		assert_eq!(operand, 2);
		assert!(simplify_i32(&mut graph, destination));

		let Node::Identity(identity) = graph.get(destination) else {
			panic!("destination should forward to the operand")
		};

		assert_eq!(identity.sources.as_slice(), [Link(operand, 0)]);

		let Node::Null = *graph.get(operand) else {
			panic!("operand should be left alone")
		};

		let Node::IntegerBinaryOperation(_) = *graph.get(other) else {
			panic!("the other reader should be left alone")
		};
	}
}
