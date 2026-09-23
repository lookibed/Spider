//! Region scope validation.
//!
//! Every node lives in exactly one region, and the only way for it to read a value from
//! an enclosing region is through the port of the node that opens its own region. The
//! target builders depend on this: they give a boundary port and the producer feeding it
//! the same local whenever they can, and a region's entry moves are free to overwrite any
//! other local. A node that reads straight past its boundary therefore names a local that
//! may already have been overwritten by the time the region runs, which the local
//! allocator cannot see and the builders silently mis-sequence.
//!
//! Nothing in the pipeline is allowed to create such a link, so the check is only run
//! behind a debug assertion.

use alloc::vec::Vec;
use ir_graph::{
	DataFlowGraph, Link, Node,
	control::{LambdaIn, OmegaIn, RegionIn, ThetaIn},
};

/// Returns the identifier range of the region a node opens, if it opens one.
///
/// The range runs from the opening node to its paired closing node, which holds for every
/// graph the [`TopologicalNormalizer`] has ordered: a region's body only depends on the
/// region's own ports and on nodes the traversal has already placed, so nothing outside
/// the region is numbered in between.
///
/// [`TopologicalNormalizer`]: crate::topological_normalizer::TopologicalNormalizer
const fn opened_range_of(node: &Node, id: u32) -> Option<(u32, u32)> {
	let output = match *node {
		Node::LambdaIn(LambdaIn { output, .. })
		| Node::OmegaIn(OmegaIn { output })
		| Node::RegionIn(RegionIn { output, .. })
		| Node::ThetaIn(ThetaIn { output, .. }) => output,

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
		| Node::IntegerBinaryOperation(_)
		| Node::IntegerCompareOperation(_)
		| Node::IntegerConvertToNumber(_)
		| Node::IntegerExtend(_)
		| Node::IntegerNarrow(_)
		| Node::IntegerTransmuteToNumber(_)
		| Node::IntegerUnaryOperation(_)
		| Node::IntegerWiden(_)
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
		| Node::OmegaOut(_)
		| Node::RefIsNull(_)
		| Node::RegionOut(_)
		| Node::TableCopy(_)
		| Node::TableDrop(_)
		| Node::TableFill(_)
		| Node::TableGet(_)
		| Node::TableGrow(_)
		| Node::TableNew(_)
		| Node::TableSet(_)
		| Node::TableSize(_)
		| Node::ThetaOut(_)
		| Node::Trap => return None,
	};

	Some((id, output))
}

/// Finds a node that reads a value produced outside of its own region.
///
/// Returns the reader and the link that escapes, or [`None`] when every node stays within
/// its region. The graph must be in topological order, which is what
/// [`opened_range_of`] relies on to know where a region ends.
///
/// A node that opens a region is checked against the region enclosing it, since its own
/// arguments, such as the initial values of a loop, are read before the region is entered.
#[must_use]
pub fn find_escape(graph: &DataFlowGraph) -> Option<(u32, Link)> {
	let mut open = Vec::new();
	let mut escape = None;

	for (node, id) in graph.nodes().zip(0_u32..) {
		while open.last().is_some_and(|&(_, end)| end < id) {
			open.pop();
		}

		if let Some(&(start, end)) = open.last() {
			node.for_each_argument(|link| {
				if escape.is_none() && !(start..=end).contains(&link.0) {
					escape = Some((id, link));
				}
			});
		}

		if escape.is_some() {
			break;
		}

		if let Some(range) = opened_range_of(node, id) {
			open.push(range);
		}
	}

	escape
}

/// Panics if any node reads a value produced outside of its own region.
///
/// # Panics
///
/// Panics when the graph contains such a link; if this happens, it is a bug in whichever
/// pass produced it.
pub fn assert_scoped(graph: &DataFlowGraph) {
	if let Some((id, Link(producer, port))) = find_escape(graph) {
		panic!("node {id} reads {producer}:{port} from outside of its own region");
	}
}

#[cfg(test)]
mod tests {
	use alloc::vec;
	use ir_graph::{
		DataFlowGraph, Link, Node,
		control::{GammaIn, GammaOut, RegionIn, RegionOut},
		simple::{IntegerBinaryOperation, IntegerBinaryOperator, IntegerType},
	};

	use super::find_escape;

	// A gamma with a single region, whose body adds the region's only port to itself.
	// The outer value the port carries lives at `outer`.
	fn gamma_graph() -> (DataFlowGraph, u32, u32) {
		let mut graph = DataFlowGraph::new();
		let outer = graph.add_node(Node::I32(1));
		let condition = graph.add_node(Node::I32(0));

		let gamma_in = graph.add_node(Node::GammaIn(GammaIn {
			output: 0,
			arguments: vec![Link(outer, 0)],
			condition: Link(condition, 0),
		}));

		let region_in = graph.add_node(Node::RegionIn(RegionIn {
			input: gamma_in,
			output: 0,
		}));

		let inner = graph.add_node(Node::IntegerBinaryOperation(IntegerBinaryOperation {
			lhs: Link(region_in, 0),
			rhs: Link(region_in, 0),
			kind: IntegerType::I32,
			operator: IntegerBinaryOperator::Add,
		}));

		let region_out = graph.add_node(Node::RegionOut(RegionOut {
			input: region_in,
			output: 0,
			results: vec![Link(inner, 0)],
		}));

		let gamma_out = graph.add_node(Node::GammaOut(GammaOut {
			input: gamma_in,
			regions: vec![region_out],
		}));

		graph.get_mut(gamma_in).as_mut_gamma_in().unwrap().output = gamma_out;
		graph.get_mut(region_in).as_mut_region_in().unwrap().output = region_out;
		graph
			.get_mut(region_out)
			.as_mut_region_out()
			.unwrap()
			.output = gamma_out;

		(graph, outer, inner)
	}

	#[test]
	fn a_port_read_is_within_the_region() {
		let (graph, _, _) = gamma_graph();

		assert!(find_escape(&graph).is_none());
	}

	#[test]
	fn an_outer_read_escapes_the_region() {
		let (mut graph, outer, inner) = gamma_graph();

		let Node::IntegerBinaryOperation(operation) = graph.get_mut(inner) else {
			panic!("the inner node should be an operation")
		};

		operation.lhs = Link(outer, 0);

		assert_eq!(find_escape(&graph), Some((inner, Link(outer, 0))));
	}
}
