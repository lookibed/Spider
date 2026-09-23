//! The optimizer driver shared by every front end.
//!
//! Keeping the pass order in one place means the conformance suites exercise the same
//! pipeline the command line tool does, rather than a copy of it that can drift.

use ir_graph::{DataFlowGraph, Link};

use crate::{
	constant_isolator::ConstantIsolator,
	control::{
		dead_port_eliminator::DeadPortEliminator, invariant_port_mover::InvariantPortMover,
		region_identity, region_scope,
	},
	isle,
	topological_normalizer::TopologicalNormalizer,
};

/// The most optimizer rounds we run before giving up on reaching a fixed point.
///
/// Every round either shrinks the graph or rewrites it into a canonical form, so a well
/// behaved rule set settles within a handful of rounds. The bound only exists so that a
/// rule which oscillates cannot hang the compiler.
const MAX_OPTIMIZER_ROUNDS: u32 = 64;

/// Runs every optimization pass until the graph stops changing.
pub struct Optimizer {
	topological_normalizer: TopologicalNormalizer,
	invariant_port_mover: InvariantPortMover,
	dead_port_eliminator: DeadPortEliminator,
	constant_isolator: ConstantIsolator,
}

impl Optimizer {
	/// Creates a new optimizer.
	#[must_use]
	pub fn new() -> Self {
		Self {
			topological_normalizer: TopologicalNormalizer::new(),
			invariant_port_mover: InvariantPortMover::new(),
			dead_port_eliminator: DeadPortEliminator::new(),
			constant_isolator: ConstantIsolator::new(),
		}
	}

	/// Applies every ISLE peephole rule until none of them match.
	///
	/// # Panics
	///
	/// Panics if the graph length overflows a `u32`; if this happens, it is a bug.
	fn run_isle(graph: &mut DataFlowGraph) -> bool {
		let mut applied = false;
		let len = graph.len();

		for id in (0..len.try_into().unwrap()).rev() {
			while isle::simplify(graph, id) {
				applied = true;
			}
		}

		applied
	}

	/// Runs a single round, reporting whether the graph changed.
	///
	/// The passes are ordered producer to consumer so that each one sees what the
	/// previous one produced within the same round: motion first lifts values out of
	/// regions, which leaves ports that no longer carry anything, elimination then
	/// removes those ports, and the peephole rewriter runs last on the smaller graph.
	fn run_round(&mut self, graph: &mut DataFlowGraph, omega: u32) -> bool {
		let mut changed = self.invariant_port_mover.run(graph);

		changed |= self.dead_port_eliminator.run(graph, Link(omega, 0));
		changed |= Self::run_isle(graph);

		changed
	}

	/// Optimizes the graph, returning the new identifier of its omega node.
	///
	/// # Panics
	///
	/// In a debug build, panics if a pass leaves a node reading a value from outside of
	/// its own region; if this happens, it is a bug in that pass.
	pub fn run(&mut self, graph: &mut DataFlowGraph, mut omega: u32) -> u32 {
		for _ in 0..MAX_OPTIMIZER_ROUNDS {
			omega = self.topological_normalizer.run(graph, omega);

			// The check needs the topological order the normalizer just established, so
			// it validates what the previous round produced, and the last round is
			// covered by the one in `run_post_process`.
			if cfg!(debug_assertions) {
				region_scope::assert_scoped(graph);
			}

			if !self.run_round(graph, omega) {
				break;
			}

			// Identities are only ever introduced by the rewrites above, so they are
			// cleaned up once per round rather than once per pass.
			region_identity::remove(graph);
		}

		omega
	}

	/// Prepares the optimized graph for the target builders.
	///
	/// Constant isolation runs only here. It deliberately undoes the sharing that common
	/// subexpression style rewrites rely on, so it has to come after every pass that
	/// wants constants shared and before the builders that care about live ranges.
	///
	/// # Panics
	///
	/// In a debug build, panics if a pass leaves a node reading a value from outside of
	/// its own region; if this happens, it is a bug in that pass.
	pub fn run_post_process(&mut self, graph: &mut DataFlowGraph, omega: u32) {
		region_identity::insert(graph);

		self.constant_isolator.run(graph);

		self.topological_normalizer.run(graph, omega);

		if cfg!(debug_assertions) {
			region_scope::assert_scoped(graph);
		}
	}
}

impl Default for Optimizer {
	fn default() -> Self {
		Self::new()
	}
}
