use alloc::{format, sync::Arc};
use std::io::{Result, Write};

use luanoffi_tree::expression::{
	BooleanToInteger, Call, Expression, Function, GlobalGet, GlobalNew, Import,
	IntegerBinaryOperation, IntegerBinaryOperator, IntegerCompareOperation, IntegerConvertToNumber,
	IntegerExtend, IntegerNarrow, IntegerTransmuteToNumber, IntegerType, IntegerUnaryOperation,
	IntegerWiden, LoadType, Local, Location, MemoryGrow, MemoryLoad, MemoryNew, MemorySize, Name,
	NumberBinaryOperation, NumberCompareOperation, NumberNarrow, NumberTransmuteToInteger,
	NumberTruncateToInteger, NumberUnaryOperation, NumberWiden, RefIsNull, Scoped, TableGet,
	TableGrow, TableNew, TableSize,
};
use luanoffi_tree::statement::Statement;

use crate::{LuaNoFFIPrinter, captures::Captures, library::NeedsName as _, print::Print};

/// `LuaJIT` refuses to compile a function that needs more upvalues than this.
const LUA_MAX_UPVALUES: usize = 60;

/// Upvalues a printed body may spend on captures the analysis does not count.
///
/// Measured over every fixture in `tests/manual`, the only uncounted capture a
/// body takes is `excess_stack`, which it reads when it spills locals onto the
/// slow stack; `stack_top` is a local of the body itself whenever the body has
/// a stack. The remaining two slots are margin.
const RESERVED_UPVALUES: usize = 3;

/// How many dependencies and runtime helpers a body may bind as upvalues
/// before the printer starts packing dependencies into a table.
const CAPTURE_BUDGET: usize = LUA_MAX_UPVALUES - RESERVED_UPVALUES;

const PACKED_SCOPED_DEPENDENCIES_NAME: &str = "__spider_scoped_dependencies";

pub fn fmt_delimited<T, I>(
	items: I,
	printer: &mut LuaNoFFIPrinter,
	out: &mut dyn Write,
) -> Result<()>
where
	T: Print,
	I: IntoIterator<Item = T>,
{
	let mut iter = items.into_iter();

	if let Some(first) = iter.next() {
		first.print(printer, out)?;

		iter.try_for_each(|item| {
			write!(out, ", ")?;
			item.print(printer, out)
		})
	} else {
		Ok(())
	}
}

pub fn fmt_stack_enter(size: u16, printer: &LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
	if size == 0 {
		return Ok(());
	}

	printer.tab(out)?;
	writeln!(out, "local stack_top = excess_stack.top + {size}")?;

	printer.tab(out)?;
	writeln!(out, "excess_stack.top = stack_top")
}

pub fn fmt_stack_leave(size: u16, printer: &LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
	if size == 0 {
		return Ok(());
	}

	printer.tab(out)?;
	writeln!(out, "excess_stack.top = stack_top - {size}")
}

fn print_function_body(
	function: &Function,
	dependency_bindings: Option<&[(Name, usize)]>,
	printer: &mut LuaNoFFIPrinter,
	out: &mut dyn Write,
) -> Result<()> {
	let Function {
		locals,
		stack,
		code,
		returns,
		..
	} = function;

	fmt_stack_enter(*stack, printer, out)?;

	if let Some(bindings) = dependency_bindings {
		let mut previous = bindings
			.iter()
			.map(|(name, index)| {
				let taken = printer.take_exact_name(*name);
				printer.set_exact_name(
					*name,
					Arc::from(format!("{PACKED_SCOPED_DEPENDENCIES_NAME}[{}]", index + 1)),
				);
				(*name, taken)
			})
			.collect::<Vec<_>>();

		fmt_locals(locals, printer, out)?;
		let mut body_index = 0;

		while let Some(Statement::Assign(assign)) = code.list.get(body_index) {
			let Local::Fast { name: destination } = assign.destination else {
				break;
			};

			let source = if let Expression::Local(Local::Fast { name }) = &assign.source {
				*name
			} else {
				break;
			};

			let exact = if let Some(exact) = printer.get_exact_name(source) {
				exact.to_owned()
			} else {
				break;
			};

			let previous_destination = printer.take_exact_name(destination);
			printer.set_exact_name(destination, Arc::from(exact));
			previous.push((destination, previous_destination));
			body_index += 1;
		}

		code.list[body_index..]
			.iter()
			.try_for_each(|statement| statement.print(printer, out))?;
		fmt_stack_leave(*stack, printer, out)?;

		if !returns.is_empty() {
			printer.tab(out)?;
			write!(out, "return ")?;
			fmt_delimited(returns, printer, out)?;
			writeln!(out)?;
		}

		for (name, restored) in previous {
			if let Some(restored) = restored {
				printer.set_exact_name(name, restored);
			}
		}

		return Ok(());
	}

	fmt_locals(locals, printer, out)?;
	code.print(printer, out)?;
	fmt_stack_leave(*stack, printer, out)?;

	if !returns.is_empty() {
		printer.tab(out)?;
		write!(out, "return ")?;
		fmt_delimited(returns, printer, out)?;
		writeln!(out)?;
	}

	Ok(())
}

impl Print for Name {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		if let Some(exact) = printer.get_exact_name(*self) {
			return write!(out, "{exact}");
		}

		let Self { id } = self;
		let prefix = printer.get_name(*self).unwrap_or("loc");

		write!(out, "{prefix}_{id}_")
	}
}

pub fn fmt_locals(
	names: &[Name],
	printer: &mut LuaNoFFIPrinter,
	out: &mut dyn Write,
) -> Result<()> {
	if names.is_empty() {
		return Ok(());
	}

	// Registers start out unassigned: the lifter seeds every WebAssembly local
	// with an explicit typed constant (`0`, `into_bits_i64(0, 0)`, `nil`, ...),
	// so a blanket `= 0` here would be wrong for `i64` and reference locals.
	printer.tab(out)?;
	write!(out, "local ")?;

	fmt_delimited(names.iter().copied(), printer, out)?;

	writeln!(out)
}

impl Print for Local {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		match self {
			Self::Fast { name } => name.print(printer, out),
			Self::Slow { offset } => {
				write!(out, "excess_stack[stack_top - {offset}]")
			}
		}
	}
}

/// Opens the call that registers a function value's WebAssembly type, if it has one.
fn print_function_type_open(key: Option<&str>, out: &mut dyn Write) -> Result<()> {
	if key.is_some() {
		write!(out, "rt_function_type(")?;
	}

	Ok(())
}

/// Closes the call opened by [`print_function_type_open`].
fn print_function_type_close(key: Option<&str>, out: &mut dyn Write) -> Result<()> {
	if let Some(key) = key {
		write!(out, ", \"{key}\")")?;
	}

	Ok(())
}

impl Print for Function {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { arguments, key, .. } = self;

		print_function_type_open(key.as_deref(), out)?;

		write!(out, "(function(")?;

		fmt_delimited(arguments, printer, out)?;

		writeln!(out, ")")?;

		printer.indent();
		print_function_body(self, None, printer, out)?;

		printer.outdent();

		printer.tab(out)?;
		write!(out, "end)")?;

		print_function_type_close(key.as_deref(), out)
	}
}

/// Chooses the dependencies that have to move into a table upvalue.
///
/// A printed body captures one upvalue per scoped dependency and one per
/// runtime helper it names, plus a handful of fixed captures. When that demand
/// fits in [`CAPTURE_BUDGET`] nothing is packed, so the common case keeps every
/// dependency in a plain upvalue. Otherwise only the overflow moves into the
/// table, least used dependency first, so that the hot captures stay upvalues.
fn packed_scoped_dependencies(
	dependencies: &[(Name, Expression)],
	function: &Function,
) -> Vec<(Name, usize)> {
	let captures = Captures::of(function);
	let demand = dependencies.len() + captures.runtime_len();

	if demand <= CAPTURE_BUDGET {
		return Vec::new();
	}

	// The table itself costs one upvalue, hence the extra slot.
	let excess = (demand + 1 - CAPTURE_BUDGET).min(dependencies.len());

	let mut order = (0..dependencies.len()).collect::<Vec<_>>();

	order.sort_by_key(|&index| captures.local_uses(dependencies[index].0));
	order.truncate(excess);
	order.sort_unstable();

	order
		.into_iter()
		.enumerate()
		.map(|(slot, index)| (dependencies[index].0, slot))
		.collect()
}

/// Prints a function whose `packed` dependencies live in a table upvalue.
fn print_packed_function(
	function: &Function,
	packed: &[(Name, usize)],
	printer: &mut LuaNoFFIPrinter,
	out: &mut dyn Write,
) -> Result<()> {
	print_function_type_open(function.key.as_deref(), out)?;

	write!(out, "(function(")?;
	fmt_delimited(&function.arguments, printer, out)?;
	writeln!(out, ")")?;

	printer.indent();
	print_function_body(function, Some(packed), printer, out)?;
	printer.outdent();

	printer.tab(out)?;
	write!(out, "end)")?;

	print_function_type_close(function.key.as_deref(), out)
}

impl Print for Scoped {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			dependencies,
			function,
		} = self;

		if dependencies.is_empty() {
			return function.print(printer, out);
		}

		let packed = packed_scoped_dependencies(dependencies, function);

		// The dependencies arrive as parameters so that the enclosing `module`
		// body evaluates the sources. Binding them with `local` instead would
		// make this wrapper capture every source as an upvalue of its own, and
		// a wrapper is as constrained by the sixty upvalue limit as the body it
		// returns.
		write!(out, "(function(")?;

		fmt_delimited(dependencies.iter().map(|(name, _)| *name), printer, out)?;

		writeln!(out, ")")?;

		printer.indent();

		if !packed.is_empty() {
			printer.tab(out)?;
			write!(out, "local {PACKED_SCOPED_DEPENDENCIES_NAME} = {{ ")?;

			fmt_delimited(packed.iter().map(|(name, _)| *name), printer, out)?;

			writeln!(out, " }}")?;
		}

		printer.tab(out)?;
		write!(out, "return ")?;

		if packed.is_empty() {
			function.print(printer, out)?;
		} else {
			print_packed_function(function, &packed, printer, out)?;
		}

		writeln!(out)?;

		printer.outdent();
		printer.tab(out)?;
		write!(out, "end)(")?;

		fmt_delimited(dependencies.iter().map(|(_, source)| source), printer, out)?;

		write!(out, ")")
	}
}

impl Print for Import {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			environment,
			namespace,
			identifier,
		} = self;

		write!(out, "assert(")?;

		environment.print(printer, out)?;

		let escaped_namespace = namespace.as_bytes().escape_ascii();
		let escaped_identifier = identifier.as_bytes().escape_ascii();

		write!(
			out,
			"[\"{escaped_namespace}\"][\"{escaped_identifier}\"], '`{escaped_namespace}.{escaped_identifier}` should be present')"
		)
	}
}

impl Print for i32 {
	fn print(&self, _printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		write!(out, "{self}")
	}
}

impl Print for i64 {
	fn print(&self, _printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let bits = u64::from_ne_bytes(self.to_ne_bytes());
		let lo = bits & 0xFFFF_FFFF;
		let hi = bits >> 32_u32;

		write!(out, "into_bits_i64({lo}, {hi})")
	}
}

impl Print for f32 {
	fn print(&self, _printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let bits = u32::from_ne_bytes(self.to_ne_bytes());
		let bits = if bits >= 0x8000_0000 {
			i64::from(bits) - 0x1_0000_0000
		} else {
			i64::from(bits)
		};

		write!(out, "{bits} --[[ {self}_f32 ]]")
	}
}

impl Print for f64 {
	fn print(&self, _printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let bits = u64::from_ne_bytes(self.to_ne_bytes());
		let lo = bits & 0xFFFF_FFFF;
		let hi = bits >> 32_u32;

		write!(out, "from_bits_f64({lo}, {hi}) --[[ {self}_f64 ]]")
	}
}

impl Print for Call {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			function,
			arguments,
		} = self;

		function.print(printer, out)?;

		write!(out, "(")?;

		fmt_delimited(arguments, printer, out)?;

		write!(out, ")")
	}
}

impl Print for BooleanToInteger {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		write!(out, "(")?;

		source.print(printer, out)?;

		write!(out, " and 1 or 0)")
	}
}

impl Print for RefIsNull {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		write!(out, "(")?;

		source.print(printer, out)?;

		write!(out, ") == nil")
	}
}

impl Print for IntegerUnaryOperation {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for IntegerBinaryOperation {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		use IntegerBinaryOperator::{Add, Subtract};
		use IntegerType::I32;

		let Self {
			lhs,
			rhs,
			kind,
			operator,
		} = self;

		match (*kind, *operator) {
			(I32, Add) => {
				write!(out, "bit32_or(")?;
				lhs.print(printer, out)?;
				write!(out, " + ")?;
				rhs.print(printer, out)?;
				write!(out, ", 0)")
			}
			(I32, Subtract) => {
				write!(out, "bit32_or(")?;
				lhs.print(printer, out)?;
				write!(out, " - ")?;
				rhs.print(printer, out)?;
				write!(out, ", 0)")
			}
			_ => {
				let intrinsic = self.needs_name();

				write!(out, "rt_{intrinsic}(")?;

				lhs.print(printer, out)?;

				write!(out, ", ")?;

				rhs.print(printer, out)?;

				write!(out, ")")
			}
		}
	}
}

impl Print for IntegerCompareOperation {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { lhs, rhs, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		lhs.print(printer, out)?;

		write!(out, ", ")?;

		rhs.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for IntegerNarrow {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for IntegerWiden {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for IntegerExtend {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for IntegerConvertToNumber {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for IntegerTransmuteToNumber {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for NumberUnaryOperation {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for NumberBinaryOperation {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { lhs, rhs, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		lhs.print(printer, out)?;

		write!(out, ", ")?;

		rhs.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for NumberCompareOperation {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { lhs, rhs, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		lhs.print(printer, out)?;

		write!(out, ", ")?;

		rhs.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for NumberNarrow {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for NumberWiden {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for NumberTruncateToInteger {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for NumberTransmuteToInteger {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source, .. } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for Location {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { reference, offset } = self;

		reference.print(printer, out)?;

		write!(out, ", ")?;

		offset.print(printer, out)
	}
}

impl Print for GlobalNew {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { initializer } = self;

		write!(out, "{{ ")?;

		initializer.print(printer, out)?;

		write!(out, " }}")
	}
}

impl Print for GlobalGet {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		source.print(printer, out)?;

		write!(out, "[1]")
	}
}

impl Print for TableNew {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			initializer,
			minimum,
			maximum,
		} = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}({{ ")?;

		for (expression, offset) in initializer {
			write!(out, "[{offset}] = ")?;

			expression.print(printer, out)?;

			write!(out, ", ")?;
		}

		write!(out, "}}, {minimum}, {maximum})")
	}
}

impl Print for TableGet {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source, key } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		if let Some(key) = key {
			write!(out, ", \"{key}\"")?;
		}

		write!(out, ")")
	}
}

impl Print for TableSize {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		source.print(printer, out)?;

		write!(out, ".minimum")
	}
}

impl Print for TableGrow {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			initializer,
			size,
		} = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		destination.print(printer, out)?;

		write!(out, ", ")?;

		initializer.print(printer, out)?;

		write!(out, ", ")?;

		size.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for MemoryNew {
	fn print(&self, _printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			initializer,
			minimum,
			maximum,
		} = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}({{ ")?;

		for (data, offset) in initializer {
			write!(out, "[{offset}] = \"{}\", ", data.escape_ascii())?;
		}

		write!(out, "}}, {minimum}, {maximum})")
	}
}

impl Print for MemoryLoad {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		use LoadType::I32;

		let Self {
			source: Location { reference, offset },
			offset: static_offset,
			kind,
		} = self;

		if matches!(kind, I32) {
			write!(out, "buffer_read_i32(")?;
			reference.print(printer, out)?;
			write!(out, "[1], ")?;
		} else {
			let intrinsic = self.needs_name();

			write!(out, "rt_{intrinsic}(")?;
			reference.print(printer, out)?;
			write!(out, ", ")?;
		}

		offset.print(printer, out)?;
		write!(out, ", {static_offset})")
	}
}

impl Print for MemorySize {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for MemoryGrow {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { destination, size } = self;

		let intrinsic = self.needs_name();

		write!(out, "rt_{intrinsic}(")?;

		destination.print(printer, out)?;

		write!(out, ", ")?;

		size.print(printer, out)?;

		write!(out, ")")
	}
}

impl Print for Expression {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		match self {
			Self::Function(function) => function.print(printer, out),
			Self::Scoped(scoped) => scoped.print(printer, out),
			Self::Import(import) => import.print(printer, out),
			Self::Trap => write!(out, "error('unreachable code')"),
			Self::Null => write!(out, "nil"),
			Self::Local(local) => local.print(printer, out),
			Self::I32(i32) => i32.print(printer, out),
			Self::I64(i64) => i64.print(printer, out),
			Self::F32(f32) => f32.print(printer, out),
			Self::F64(f64) => f64.print(printer, out),
			Self::Call(call) => call.print(printer, out),
			Self::BooleanToInteger(boolean_to_integer) => boolean_to_integer.print(printer, out),
			Self::RefIsNull(ref_is_null) => ref_is_null.print(printer, out),
			Self::IntegerUnaryOperation(integer_unary_operation) => {
				integer_unary_operation.print(printer, out)
			}
			Self::IntegerBinaryOperation(integer_binary_operation) => {
				integer_binary_operation.print(printer, out)
			}
			Self::IntegerCompareOperation(integer_compare_operation) => {
				integer_compare_operation.print(printer, out)
			}
			Self::IntegerNarrow(integer_narrow) => integer_narrow.print(printer, out),
			Self::IntegerWiden(integer_widen) => integer_widen.print(printer, out),
			Self::IntegerExtend(integer_extend) => integer_extend.print(printer, out),
			Self::IntegerConvertToNumber(integer_convert_to_number) => {
				integer_convert_to_number.print(printer, out)
			}
			Self::IntegerTransmuteToNumber(integer_transmute_to_number) => {
				integer_transmute_to_number.print(printer, out)
			}
			Self::NumberUnaryOperation(number_unary_operation) => {
				number_unary_operation.print(printer, out)
			}
			Self::NumberBinaryOperation(number_binary_operation) => {
				number_binary_operation.print(printer, out)
			}
			Self::NumberCompareOperation(number_compare_operation) => {
				number_compare_operation.print(printer, out)
			}
			Self::NumberNarrow(number_narrow) => number_narrow.print(printer, out),
			Self::NumberWiden(number_widen) => number_widen.print(printer, out),
			Self::NumberTruncateToInteger(number_truncate_to_integer) => {
				number_truncate_to_integer.print(printer, out)
			}
			Self::NumberTransmuteToInteger(number_transmute_to_integer) => {
				number_transmute_to_integer.print(printer, out)
			}
			Self::GlobalNew(global_new) => global_new.print(printer, out),
			Self::GlobalGet(global_get) => global_get.print(printer, out),
			Self::TableNew(table_new) => table_new.print(printer, out),
			Self::TableGet(table_get) => table_get.print(printer, out),
			Self::TableSize(table_size) => table_size.print(printer, out),
			Self::TableGrow(table_grow) => table_grow.print(printer, out),
			Self::MemoryNew(memory_new) => memory_new.print(printer, out),
			Self::MemoryLoad(memory_load) => memory_load.print(printer, out),
			Self::MemorySize(memory_size) => memory_size.print(printer, out),
			Self::MemoryGrow(memory_grow) => memory_grow.print(printer, out),
		}
	}
}
