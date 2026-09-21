use ir_graph::DataFlowGraph;
use ir_visitor::pipeline::Optimizer;
use web_assembly_lifter::WebAssemblyLifter;

pub struct Compiler {
	web_assembly_lifter: WebAssemblyLifter,
	optimizer: Optimizer,
}

impl Compiler {
	pub fn new() -> Self {
		Self {
			web_assembly_lifter: WebAssemblyLifter::new(),
			optimizer: Optimizer::new(),
		}
	}

	pub fn run(&mut self, data: &[u8], optimize: bool) -> DataFlowGraph {
		let mut graph = DataFlowGraph::new();
		let mut omega = self.web_assembly_lifter.run(&mut graph, data);

		if optimize {
			omega = self.optimizer.run(&mut graph, omega);
		}

		self.optimizer.run_post_process(&mut graph, omega);

		graph
	}
}
