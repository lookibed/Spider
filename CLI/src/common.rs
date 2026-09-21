use ir_graph::DataFlowGraph;
use ir_visitor::pipeline::Optimizer;

pub fn run_all_optimizations(graph: &mut DataFlowGraph, omega: u32) -> u32 {
	Optimizer::new().run(graph, omega)
}

pub fn run_post_process(graph: &mut DataFlowGraph, omega: u32) {
	Optimizer::new().run_post_process(graph, omega);
}
