#![cfg_attr(target_arch = "wasm32", no_std)]

extern crate alloc;

use alloc::{sync::Arc, vec, vec::Vec};

#[cfg(target_arch = "wasm32")]
use core::{
	alloc::{GlobalAlloc, Layout},
	cell::UnsafeCell,
	panic::PanicInfo,
	sync::atomic::{AtomicUsize, Ordering},
};

use ir_graph::{
	DataFlowGraph, Link, Node,
	control::{Export, GammaOut, OmegaIn, OmegaOut},
	simple::{
		GlobalGet, GlobalNew, GlobalSet, IntegerBinaryOperation, IntegerBinaryOperator,
		IntegerCompareOperation, IntegerCompareOperator, IntegerType, NumberType,
	},
};
use luanoffi_builder::LuaNoFFIBuilder;
use luanoffi_tree::{
	LuaNoFFITree,
	expression::{
		BooleanToInteger, Expression, Function, GlobalGet as TreeGlobalGet,
		GlobalNew as TreeGlobalNew, IntegerBinaryOperation as TreeIntegerBinaryOperation,
		IntegerCompareOperation as TreeIntegerCompareOperation,
		IntegerConvertToNumber as TreeIntegerConvertToNumber, IntegerExtend as TreeIntegerExtend,
		IntegerNarrow as TreeIntegerNarrow,
		IntegerTransmuteToNumber as TreeIntegerTransmuteToNumber,
		IntegerUnaryOperation as TreeIntegerUnaryOperation, IntegerWiden as TreeIntegerWiden,
		Local, Location, MemoryGrow as TreeMemoryGrow, MemoryLoad as TreeMemoryLoad,
		MemorySize as TreeMemorySize, Name, NumberBinaryOperation as TreeNumberBinaryOperation,
		NumberCompareOperation as TreeNumberCompareOperation, NumberNarrow as TreeNumberNarrow,
		NumberTransmuteToInteger as TreeNumberTransmuteToInteger,
		NumberTruncateToInteger as TreeNumberTruncateToInteger,
		NumberUnaryOperation as TreeNumberUnaryOperation, NumberWiden as TreeNumberWiden,
		RefIsNull, TableGet as TreeTableGet, TableGrow as TreeTableGrow, TableNew as TreeTableNew,
		TableSize as TreeTableSize,
	},
	statement::{
		Assign, Call as StatementCall, Export as TreeExport, GlobalSet as TreeGlobalSet, Match,
		MemoryCopy, MemoryDrop, MemoryFill, MemoryStore, Repeat, Sequence, Statement, TableCopy,
		TableDrop, TableFill, TableSet,
	},
};

const CASE_COUNT: i32 = 3;

#[cfg(target_arch = "wasm32")]
struct BumpAllocator {
	offset: AtomicUsize,
	buffer: UnsafeCell<[u8; 4 * 1024 * 1024]>,
}

#[cfg(target_arch = "wasm32")]
unsafe impl Sync for BumpAllocator {}

#[cfg(target_arch = "wasm32")]
unsafe impl GlobalAlloc for BumpAllocator {
	unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
		let align_mask = layout.align().wrapping_sub(1);
		let size = layout.size();

		let result = self
			.offset
			.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |offset| {
				let aligned = offset.wrapping_add(align_mask) & !align_mask;
				let end = aligned.checked_add(size)?;
				if end > 4 * 1024 * 1024 {
					None
				} else {
					Some(end)
				}
			});

		match result {
			Ok(offset) => {
				let aligned = offset.wrapping_add(align_mask) & !align_mask;
				unsafe { self.buffer.get().cast::<u8>().add(aligned) }
			}
			Err(_) => core::ptr::null_mut(),
		}
	}

	unsafe fn dealloc(&self, _ptr: *mut u8, _layout: Layout) {}
}

#[cfg(target_arch = "wasm32")]
#[global_allocator]
static ALLOCATOR: BumpAllocator = BumpAllocator {
	offset: AtomicUsize::new(0),
	buffer: UnsafeCell::new([0; 4 * 1024 * 1024]),
};

#[cfg(target_arch = "wasm32")]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
	loop {}
}

fn mix(hash: &mut u32, value: u32) {
	*hash = hash.rotate_left(5) ^ value.wrapping_mul(0x9E37_79B1);
}

fn mix_i32(hash: &mut u32, value: i32) {
	mix(hash, value as u32);
}

fn mix_u16(hash: &mut u32, value: u16) {
	mix(hash, u32::from(value));
}

fn mix_bool(hash: &mut u32, value: bool) {
	mix(hash, if value { 1 } else { 0 });
}

fn mix_bytes(hash: &mut u32, bytes: &[u8]) {
	mix(hash, bytes.len().try_into().unwrap());
	for &byte in bytes {
		mix(hash, u32::from(byte));
	}
}

fn mix_str(hash: &mut u32, value: &str) {
	mix_bytes(hash, value.as_bytes());
}

fn mix_name(hash: &mut u32, name: Name) {
	mix(hash, name.id);
}

fn mix_local(hash: &mut u32, local: Local) {
	if let Some(name) = local.as_fast_name() {
		mix(hash, 0xF001);
		mix_name(hash, name);
	} else if let Some(offset) = local.as_slow_offset() {
		mix(hash, 0xF002);
		mix_u16(hash, offset);
	}
}

fn mix_integer_type(hash: &mut u32, value: ir_graph::simple::IntegerType) {
	let tag = match value {
		ir_graph::simple::IntegerType::I32 => 1,
		ir_graph::simple::IntegerType::I64 => 2,
	};
	mix(hash, tag);
}

fn mix_number_type(hash: &mut u32, value: NumberType) {
	let tag = match value {
		NumberType::F32 => 1,
		NumberType::F64 => 2,
	};
	mix(hash, tag);
}

fn mix_integer_binary_operator(hash: &mut u32, operator: ir_graph::simple::IntegerBinaryOperator) {
	match operator {
		IntegerBinaryOperator::Add => mix(hash, 1),
		IntegerBinaryOperator::Subtract => mix(hash, 2),
		IntegerBinaryOperator::Multiply => mix(hash, 3),
		IntegerBinaryOperator::Divide { signed } => {
			mix(hash, 4);
			mix_bool(hash, signed);
		}
		IntegerBinaryOperator::Remainder { signed } => {
			mix(hash, 5);
			mix_bool(hash, signed);
		}
		IntegerBinaryOperator::And => mix(hash, 6),
		IntegerBinaryOperator::Or => mix(hash, 7),
		IntegerBinaryOperator::ExclusiveOr => mix(hash, 8),
		IntegerBinaryOperator::ShiftLeft => mix(hash, 9),
		IntegerBinaryOperator::ShiftRight { signed } => {
			mix(hash, 10);
			mix_bool(hash, signed);
		}
		IntegerBinaryOperator::RotateLeft => mix(hash, 11),
		IntegerBinaryOperator::RotateRight => mix(hash, 12),
	}
}

fn mix_integer_compare_operator(
	hash: &mut u32,
	operator: ir_graph::simple::IntegerCompareOperator,
) {
	match operator {
		IntegerCompareOperator::Equal => mix(hash, 1),
		IntegerCompareOperator::NotEqual => mix(hash, 2),
		IntegerCompareOperator::LessThan { signed } => {
			mix(hash, 3);
			mix_bool(hash, signed);
		}
		IntegerCompareOperator::GreaterThan { signed } => {
			mix(hash, 4);
			mix_bool(hash, signed);
		}
		IntegerCompareOperator::LessThanEqual { signed } => {
			mix(hash, 5);
			mix_bool(hash, signed);
		}
		IntegerCompareOperator::GreaterThanEqual { signed } => {
			mix(hash, 6);
			mix_bool(hash, signed);
		}
	}
}

fn mix_location(hash: &mut u32, location: &Location) {
	mix_expression(hash, &location.reference);
	mix_expression(hash, &location.offset);
}

fn mix_function(hash: &mut u32, function: &Function) {
	for argument in &function.arguments {
		mix_name(hash, *argument);
	}
	for local in &function.locals {
		mix_name(hash, *local);
	}
	mix_u16(hash, function.stack);
	mix_sequence(hash, &function.code);
	for value in &function.returns {
		mix_expression(hash, value);
	}
}

fn mix_expression(hash: &mut u32, expression: &Expression) {
	match expression {
		Expression::Function(function) => {
			mix(hash, 1);
			mix_function(hash, function.as_ref());
		}
		Expression::Scoped(scoped) => {
			let scoped = scoped.as_ref();
			mix(hash, 2);
			for (name, dependency) in &scoped.dependencies {
				mix_name(hash, *name);
				mix_expression(hash, dependency);
			}
			mix_function(hash, &scoped.function);
		}
		Expression::Import(import) => {
			let import = import.as_ref();
			mix(hash, 3);
			mix_expression(hash, &import.environment);
			mix_str(hash, import.namespace.as_ref());
			mix_str(hash, import.identifier.as_ref());
		}
		Expression::Trap => mix(hash, 4),
		Expression::Null => mix(hash, 5),
		Expression::Local(local) => {
			mix(hash, 6);
			mix_local(hash, *local);
		}
		Expression::I32(value) => {
			mix(hash, 7);
			mix_i32(hash, *value);
		}
		Expression::I64(value) => {
			mix(hash, 8);
			mix(hash, (*value >> 32) as u32);
			mix(hash, *value as u32);
		}
		Expression::F32(value) => {
			mix(hash, 9);
			mix(hash, value.to_bits());
		}
		Expression::F64(value) => {
			mix(hash, 10);
			let bits = value.to_bits();
			mix(hash, (bits >> 32) as u32);
			mix(hash, bits as u32);
		}
		Expression::Call(call) => {
			let call = call.as_ref();
			mix(hash, 11);
			mix_expression(hash, &call.function);
			for argument in &call.arguments {
				mix_expression(hash, argument);
			}
		}
		Expression::BooleanToInteger(inner) => {
			let BooleanToInteger { source } = inner.as_ref();
			mix(hash, 12);
			mix_expression(hash, source);
		}
		Expression::RefIsNull(inner) => {
			let RefIsNull { source } = inner.as_ref();
			mix(hash, 13);
			mix_expression(hash, source);
		}
		Expression::IntegerUnaryOperation(inner) => {
			let TreeIntegerUnaryOperation {
				source,
				kind,
				operator,
			} = inner.as_ref();
			mix(hash, 14);
			mix_expression(hash, source);
			mix_integer_type(hash, *kind);
			mix(hash, *operator as u32);
		}
		Expression::IntegerBinaryOperation(inner) => {
			let TreeIntegerBinaryOperation {
				lhs,
				rhs,
				kind,
				operator,
			} = inner.as_ref();
			mix(hash, 15);
			mix_expression(hash, lhs);
			mix_expression(hash, rhs);
			mix_integer_type(hash, *kind);
			mix_integer_binary_operator(hash, *operator);
		}
		Expression::IntegerCompareOperation(inner) => {
			let TreeIntegerCompareOperation {
				lhs,
				rhs,
				kind,
				operator,
			} = inner.as_ref();
			mix(hash, 16);
			mix_expression(hash, lhs);
			mix_expression(hash, rhs);
			mix_integer_type(hash, *kind);
			mix_integer_compare_operator(hash, *operator);
		}
		Expression::IntegerNarrow(inner) => {
			let TreeIntegerNarrow { source } = inner.as_ref();
			mix(hash, 17);
			mix_expression(hash, source);
		}
		Expression::IntegerWiden(inner) => {
			let TreeIntegerWiden { source } = inner.as_ref();
			mix(hash, 18);
			mix_expression(hash, source);
		}
		Expression::IntegerExtend(inner) => {
			let TreeIntegerExtend { source, kind } = inner.as_ref();
			mix(hash, 19);
			mix_expression(hash, source);
			mix(hash, *kind as u32);
		}
		Expression::IntegerConvertToNumber(inner) => {
			let TreeIntegerConvertToNumber {
				source,
				signed,
				to,
				from,
			} = inner.as_ref();
			mix(hash, 20);
			mix_expression(hash, source);
			mix_bool(hash, *signed);
			mix_number_type(hash, *to);
			mix_integer_type(hash, *from);
		}
		Expression::IntegerTransmuteToNumber(inner) => {
			let TreeIntegerTransmuteToNumber { source, from } = inner.as_ref();
			mix(hash, 21);
			mix_expression(hash, source);
			mix_integer_type(hash, *from);
		}
		Expression::NumberUnaryOperation(inner) => {
			let TreeNumberUnaryOperation {
				source,
				kind,
				operator,
			} = inner.as_ref();
			mix(hash, 22);
			mix_expression(hash, source);
			mix_number_type(hash, *kind);
			mix(hash, *operator as u32);
		}
		Expression::NumberBinaryOperation(inner) => {
			let TreeNumberBinaryOperation {
				lhs,
				rhs,
				kind,
				operator,
			} = inner.as_ref();
			mix(hash, 23);
			mix_expression(hash, lhs);
			mix_expression(hash, rhs);
			mix_number_type(hash, *kind);
			mix(hash, *operator as u32);
		}
		Expression::NumberCompareOperation(inner) => {
			let TreeNumberCompareOperation {
				lhs,
				rhs,
				kind,
				operator,
			} = inner.as_ref();
			mix(hash, 24);
			mix_expression(hash, lhs);
			mix_expression(hash, rhs);
			mix_number_type(hash, *kind);
			mix(hash, *operator as u32);
		}
		Expression::NumberNarrow(inner) => {
			let TreeNumberNarrow { source } = inner.as_ref();
			mix(hash, 25);
			mix_expression(hash, source);
		}
		Expression::NumberWiden(inner) => {
			let TreeNumberWiden { source } = inner.as_ref();
			mix(hash, 26);
			mix_expression(hash, source);
		}
		Expression::NumberTruncateToInteger(inner) => {
			let TreeNumberTruncateToInteger {
				source,
				signed,
				saturate,
				to,
				from,
			} = inner.as_ref();
			mix(hash, 27);
			mix_expression(hash, source);
			mix_bool(hash, *signed);
			mix_bool(hash, *saturate);
			mix_integer_type(hash, *to);
			mix_number_type(hash, *from);
		}
		Expression::NumberTransmuteToInteger(inner) => {
			let TreeNumberTransmuteToInteger { source, from } = inner.as_ref();
			mix(hash, 28);
			mix_expression(hash, source);
			mix_number_type(hash, *from);
		}
		Expression::GlobalNew(inner) => {
			let TreeGlobalNew { initializer } = inner.as_ref();
			mix(hash, 29);
			mix_expression(hash, initializer);
		}
		Expression::GlobalGet(inner) => {
			let TreeGlobalGet { source } = inner.as_ref();
			mix(hash, 30);
			mix_expression(hash, source);
		}
		Expression::TableNew(inner) => {
			let TreeTableNew {
				initializer,
				minimum,
				maximum,
			} = inner.as_ref();
			mix(hash, 31);
			mix(hash, *minimum);
			mix(hash, *maximum);
			for (value, offset) in initializer {
				mix_expression(hash, value);
				mix(hash, *offset);
			}
		}
		Expression::TableGet(inner) => {
			let TreeTableGet { source, .. } = inner.as_ref();
			mix(hash, 32);
			mix_location(hash, source);
		}
		Expression::TableSize(inner) => {
			let TreeTableSize { source } = inner.as_ref();
			mix(hash, 33);
			mix_expression(hash, source);
		}
		Expression::TableGrow(inner) => {
			let TreeTableGrow {
				destination,
				initializer,
				size,
			} = inner.as_ref();
			mix(hash, 34);
			mix_expression(hash, destination);
			mix_expression(hash, initializer);
			mix_expression(hash, size);
		}
		Expression::MemoryNew(memory_new) => {
			mix(hash, 35);
			mix(hash, memory_new.minimum);
			mix(hash, memory_new.maximum);
			for (bytes, offset) in &memory_new.initializer {
				mix_bytes(hash, bytes.as_ref());
				mix(hash, *offset);
			}
		}
		Expression::MemoryLoad(inner) => {
			let TreeMemoryLoad {
				source,
				offset,
				kind,
			} = inner.as_ref();
			mix(hash, 36);
			mix_location(hash, source);
			mix(hash, *offset);
			mix(hash, *kind as u32);
		}
		Expression::MemorySize(inner) => {
			let TreeMemorySize { source } = inner.as_ref();
			mix(hash, 37);
			mix_expression(hash, source);
		}
		Expression::MemoryGrow(inner) => {
			let TreeMemoryGrow { destination, size } = inner.as_ref();
			mix(hash, 38);
			mix_expression(hash, destination);
			mix_expression(hash, size);
		}
	}
}

fn mix_sequence(hash: &mut u32, sequence: &Sequence) {
	mix(hash, sequence.list.len().try_into().unwrap());
	for statement in &sequence.list {
		mix_statement(hash, statement);
	}
}

fn mix_statement(hash: &mut u32, statement: &Statement) {
	match statement {
		Statement::Match(inner) => {
			let Match {
				branches,
				condition,
			} = inner.as_ref();
			mix(hash, 101);
			for branch in branches {
				mix_sequence(hash, branch);
			}
			mix_expression(hash, condition);
		}
		Statement::Repeat(inner) => {
			let Repeat { code, condition } = inner.as_ref();
			mix(hash, 102);
			mix_sequence(hash, code);
			mix_expression(hash, condition);
		}
		Statement::Assign(inner) => {
			let Assign {
				destination,
				source,
			} = inner.as_ref();
			mix(hash, 103);
			mix_local(hash, *destination);
			mix_expression(hash, source);
		}
		Statement::SwapAll(swap) => {
			mix(hash, 104);
			for local in &swap.locals {
				mix_local(hash, *local);
			}
		}
		Statement::Call(inner) => {
			let StatementCall {
				function,
				results,
				arguments,
			} = inner.as_ref();
			mix(hash, 105);
			mix_expression(hash, function);
			for result in results {
				mix_local(hash, *result);
			}
			for argument in arguments {
				mix_expression(hash, argument);
			}
		}
		Statement::GlobalSet(inner) => {
			let TreeGlobalSet {
				destination,
				source,
			} = inner.as_ref();
			mix(hash, 106);
			mix_expression(hash, destination);
			mix_expression(hash, source);
		}
		Statement::TableSet(inner) => {
			let TableSet {
				destination,
				source,
			} = inner.as_ref();
			mix(hash, 107);
			mix_location(hash, destination);
			mix_expression(hash, source);
		}
		Statement::TableFill(inner) => {
			let TableFill {
				destination,
				source,
				size,
			} = inner.as_ref();
			mix(hash, 108);
			mix_location(hash, destination);
			mix_expression(hash, source);
			mix_expression(hash, size);
		}
		Statement::TableCopy(inner) => {
			let TableCopy {
				destination,
				source,
				size,
			} = inner.as_ref();
			mix(hash, 109);
			mix_location(hash, destination);
			mix_location(hash, source);
			mix_expression(hash, size);
		}
		Statement::TableDrop(inner) => {
			let TableDrop { source } = inner.as_ref();
			mix(hash, 110);
			mix_expression(hash, source);
		}
		Statement::MemoryStore(inner) => {
			let MemoryStore {
				destination,
				source,
				offset,
				kind,
			} = inner.as_ref();
			mix(hash, 111);
			mix_location(hash, destination);
			mix_expression(hash, source);
			mix(hash, *offset);
			mix(hash, *kind as u32);
		}
		Statement::MemoryFill(inner) => {
			let MemoryFill {
				destination,
				byte,
				size,
			} = inner.as_ref();
			mix(hash, 112);
			mix_location(hash, destination);
			mix_expression(hash, byte);
			mix_expression(hash, size);
		}
		Statement::MemoryCopy(inner) => {
			let MemoryCopy {
				destination,
				source,
				size,
			} = inner.as_ref();
			mix(hash, 113);
			mix_location(hash, destination);
			mix_location(hash, source);
			mix_expression(hash, size);
		}
		Statement::MemoryDrop(inner) => {
			let MemoryDrop { source } = inner.as_ref();
			mix(hash, 114);
			mix_expression(hash, source);
		}
	}
}

fn build_case_graph(case_id: i32) -> DataFlowGraph {
	let mut graph = DataFlowGraph::new();
	let omega_in = OmegaIn::add_into(&mut graph);

	match case_id {
		0 => build_case_arithmetic(&mut graph, omega_in),
		1 => build_case_global_roundtrip(&mut graph, omega_in),
		2 => build_case_gamma_if(&mut graph, omega_in),
		_ => panic!("invalid case id"),
	}

	graph
}

fn build_case_arithmetic(graph: &mut DataFlowGraph, omega_in: u32) {
	let lhs = Node::add_i32_into(graph, 7);
	let rhs = Node::add_i32_into(graph, 5);
	let sum = IntegerBinaryOperation::add_into(
		graph,
		lhs,
		rhs,
		IntegerType::I32,
		IntegerBinaryOperator::Add,
	);

	let exports = vec![Export {
		identifier: Arc::<str>::from("sum"),
		reference: sum,
	}];

	OmegaOut::add_into(
		graph,
		omega_in,
		Link(omega_in, OmegaIn::STATE_PORT),
		exports,
	);
}

fn build_case_global_roundtrip(graph: &mut DataFlowGraph, omega_in: u32) {
	let initial = Node::add_i32_into(graph, 3);
	let global = GlobalNew::add_into(graph, initial);
	let value = Node::add_i32_into(graph, 11);
	let _write_state = GlobalSet::add_into(graph, global, value);
	let (result, state) = GlobalGet::add_into(graph, global);

	let exports = vec![Export {
		identifier: Arc::<str>::from("global_value"),
		reference: result,
	}];

	OmegaOut::add_into(graph, omega_in, state, exports);
}

fn build_case_gamma_if(graph: &mut DataFlowGraph, omega_in: u32) {
	let lhs = Node::add_i32_into(graph, 10);
	let rhs = Node::add_i32_into(graph, 3);
	let condition = IntegerCompareOperation::add_into(
		graph,
		lhs,
		rhs,
		IntegerType::I32,
		IntegerCompareOperator::GreaterThan { signed: true },
	);

	let gamma = GammaOut::add_if_into(
		graph,
		Vec::new(),
		condition,
		|graph, _| vec![Node::add_i32_into(graph, 0)],
		|graph, _| vec![Node::add_i32_into(graph, 1)],
	);

	let exports = vec![Export {
		identifier: Arc::<str>::from("branch"),
		reference: Link(gamma, 0),
	}];

	OmegaOut::add_into(
		graph,
		omega_in,
		Link(omega_in, OmegaIn::STATE_PORT),
		exports,
	);
}

fn build_case_tree(case_id: i32) -> LuaNoFFITree {
	let graph = build_case_graph(case_id);
	let mut builder = LuaNoFFIBuilder::new();
	builder.run(&graph)
}

fn case_tree(case_id: i32) -> Option<LuaNoFFITree> {
	if !(0..CASE_COUNT).contains(&case_id) {
		return None;
	}

	Some(build_case_tree(case_id))
}

fn hash_tree_export(hash: &mut u32, export: &TreeExport) {
	mix_str(hash, export.identifier.as_ref());
	mix_expression(hash, &export.source);
}

fn hash_tree(tree: &LuaNoFFITree) -> i32 {
	let mut hash = 0x811C_9DC5;

	mix_name(&mut hash, tree.environment);
	mix(&mut hash, tree.locals.len().try_into().unwrap());
	for local in &tree.locals {
		mix_name(&mut hash, *local);
	}
	mix_u16(&mut hash, tree.stack);
	mix_sequence(&mut hash, &tree.code);
	mix(&mut hash, tree.exports.len().try_into().unwrap());
	for export in &tree.exports {
		hash_tree_export(&mut hash, export);
	}

	hash as i32
}

fn hash_code(tree: &LuaNoFFITree) -> i32 {
	let mut hash = 0x1234_5678;
	mix_sequence(&mut hash, &tree.code);
	hash as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn builder_case_count() -> i32 {
	CASE_COUNT
}

#[unsafe(no_mangle)]
pub extern "C" fn builder_run_case_hash(case_id: i32) -> i32 {
	case_tree(case_id).map_or(-1, |tree| hash_tree(&tree))
}

#[unsafe(no_mangle)]
pub extern "C" fn builder_probe_locals(case_id: i32) -> i32 {
	case_tree(case_id)
		.map(|tree| tree.locals.len().try_into().unwrap())
		.unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn builder_probe_stack(case_id: i32) -> i32 {
	case_tree(case_id)
		.map(|tree| i32::from(tree.stack))
		.unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn builder_probe_exports(case_id: i32) -> i32 {
	case_tree(case_id)
		.map(|tree| tree.exports.len().try_into().unwrap())
		.unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn builder_probe_code_hash(case_id: i32) -> i32 {
	case_tree(case_id).map_or(-1, |tree| hash_code(&tree))
}
