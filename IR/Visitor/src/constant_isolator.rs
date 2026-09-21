//! Constant isolation.

use alloc::vec::Vec;
use ir_graph::{DataFlowGraph, Link, Node};

/// Returns a private copy of `node` when it is a constant.
///
/// A constant is the only kind of node that can be duplicated for free: it reads nothing,
/// writes nothing, and every copy of it produces the same value.
const fn clone_constant(node: &Node) -> Option<Node> {
	match *node {
		Node::Null => Some(Node::Null),
		Node::I32(value) => Some(Node::I32(value)),
		Node::I64(value) => Some(Node::I64(value)),
		Node::F32(value) => Some(Node::F32(value)),
		Node::F64(value) => Some(Node::F64(value)),

		Node::Apply(_)
		| Node::Fence(_)
		| Node::GammaIn(_)
		| Node::GammaOut(_)
		| Node::GlobalGet(_)
		| Node::GlobalNew(_)
		| Node::GlobalSet(_)
		| Node::Host(_)
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
		| Node::Trap => None,
	}
}

/// Gives every consumer of a constant its own private copy.
///
/// Sharing one constant between distant consumers forces the backend to keep it in a
/// local for the whole span between them. A private copy per consumer collapses each of
/// those live ranges down to a single use, which frees the local for something else.
pub struct ConstantIsolator {
	claimed: Vec<bool>,
}

impl ConstantIsolator {
	/// Creates a new constant isolator.
	#[must_use]
	pub const fn new() -> Self {
		Self {
			claimed: Vec::new(),
		}
	}

	fn isolate(&mut self, graph: &mut DataFlowGraph, link: &mut Link) {
		let Ok(index) = usize::try_from(link.0) else {
			return;
		};

		// Copies appended by this pass are already private, so they are not tracked.
		let Some(claimed) = self.claimed.get_mut(index) else {
			return;
		};

		let Some(copy) = clone_constant(graph.get(link.0)) else {
			return;
		};

		if *claimed {
			*link = Link(graph.add_node(copy), 0);
		} else {
			*claimed = true;
		}
	}

	/// Runs constant isolation on the graph.
	///
	/// # Panics
	///
	/// Panics if the graph length overflows a `u32`; if this happens, it is a bug.
	pub fn run(&mut self, graph: &mut DataFlowGraph) {
		let len = graph.len();

		self.claimed.clear();
		self.claimed.resize(len, false);

		for id in 0..len.try_into().unwrap() {
			let mut node = core::mem::take(graph.get_mut(id));

			node.for_each_mut_argument(|link| self.isolate(graph, link));

			*graph.get_mut(id) = node;
		}
	}
}

impl Default for ConstantIsolator {
	fn default() -> Self {
		Self::new()
	}
}
