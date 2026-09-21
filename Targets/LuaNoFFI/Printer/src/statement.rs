mod conditional {
	use std::io::{Result, Write};

	use luanoffi_tree::{expression::Expression, statement::Sequence};

	use crate::{LuaNoFFIPrinter, print::Print as _};

	/// The largest number of arms printed inside a single dispatch statement.
	///
	/// `LuaJIT` encodes every jump offset in sixteen bits, so one control
	/// structure may only reach across about thirty two thousand instructions.
	/// A match with more arms than this is therefore split into several
	/// statements that each dispatch their own range, which keeps every jump
	/// short no matter how large the table grows.
	const MAX_GROUPED_BRANCHES: usize = 512;

	/// The local a grouped match keeps its already evaluated condition in.
	const SELECTOR_NAME: &str = "__spider_match_selector";

	/// The value a nested conditional compares its arms against.
	enum Selector<'source> {
		/// An expression printed again for every comparison.
		Expression(&'source Expression),
		/// A local that already holds the evaluated condition.
		Name(&'source str),
	}

	impl Selector<'_> {
		fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
			match *self {
				Self::Expression(expression) => expression.print(printer, out),
				Self::Name(name) => write!(out, "{name}"),
			}
		}
	}

	fn print_recursive(
		branches: &[Sequence],
		condition: &Selector<'_>,
		start: usize,
		end: usize,
		printer: &mut LuaNoFFIPrinter,
		out: &mut dyn Write,
	) -> Result<()> {
		let center = start + (end - start) / 2;
		let has_minimum = start != center;
		let has_maximum = end != center + 1;

		if has_minimum {
			printer.tab(out)?;
			write!(out, "if (")?;

			condition.print(printer, out)?;

			writeln!(out, ") < {center} then")?;

			printer.indent();
			print_recursive(branches, condition, start, center, printer, out)?;
			printer.outdent();

			printer.tab(out)?;
			write!(out, "else")?;

			if has_maximum {
				write!(out, "if (")?;

				condition.print(printer, out)?;

				writeln!(out, ") > {center} then")?;

				printer.indent();
				print_recursive(branches, condition, center + 1, end, printer, out)?;
				printer.outdent();

				printer.tab(out)?;
				write!(out, "else")?;
			}

			writeln!(out)?;

			printer.indent();
		}

		branches[center].print(printer, out)?;

		if has_minimum {
			printer.outdent();

			printer.tab(out)?;
			writeln!(out, "end")
		} else {
			Ok(())
		}
	}

	/// Prints a match whose arms do not fit into a single control structure.
	///
	/// The condition is evaluated once into a local, the default arm is
	/// dispatched on its own, and the remaining arms are grouped into ranges
	/// that are each tested by a separate statement. Every group falls through
	/// to the next one, so at most one of them ever runs.
	fn print_grouped_match(
		branches: &[Sequence],
		condition: &Expression,
		printer: &mut LuaNoFFIPrinter,
		out: &mut dyn Write,
	) -> Result<()> {
		let len = branches.len() - 1;
		let selector = Selector::Name(SELECTOR_NAME);

		printer.tab(out)?;
		writeln!(out, "do")?;
		printer.indent();

		printer.tab(out)?;
		write!(out, "local {SELECTOR_NAME} = ")?;

		condition.print(printer, out)?;

		writeln!(out)?;

		printer.tab(out)?;
		writeln!(
			out,
			"if {SELECTOR_NAME} < 0 or {SELECTOR_NAME} >= {len} then"
		)?;

		printer.indent();
		branches.last().unwrap().print(printer, out)?;
		printer.outdent();

		printer.tab(out)?;
		writeln!(out, "end")?;

		let mut start = 0;

		while start < len {
			let end = len.min(start + MAX_GROUPED_BRANCHES);

			printer.tab(out)?;
			writeln!(
				out,
				"if {SELECTOR_NAME} >= {start} and {SELECTOR_NAME} < {end} then"
			)?;

			printer.indent();
			print_recursive(branches, &selector, start, end, printer, out)?;
			printer.outdent();

			printer.tab(out)?;
			writeln!(out, "end")?;

			start = end;
		}

		printer.outdent();
		printer.tab(out)?;
		writeln!(out, "end")
	}

	pub fn print_match(
		branches: &[Sequence],
		condition: &Expression,
		printer: &mut LuaNoFFIPrinter,
		out: &mut dyn Write,
	) -> Result<()> {
		let len = branches.len() - 1;

		if len > MAX_GROUPED_BRANCHES {
			return print_grouped_match(branches, condition, printer, out);
		}

		let selector = Selector::Expression(condition);

		printer.tab(out)?;
		write!(out, "if (")?;

		condition.print(printer, out)?;

		write!(out, ") >= 0 and (")?;

		condition.print(printer, out)?;

		writeln!(out, ") < {len} then")?;

		printer.indent();
		print_recursive(branches, &selector, 0, len, printer, out)?;
		printer.outdent();

		printer.tab(out)?;
		writeln!(out, "else")?;

		printer.indent();
		branches.last().unwrap().print(printer, out)?;
		printer.outdent();

		printer.tab(out)?;
		writeln!(out, "end")
	}

	fn print_if_true(
		code: &Sequence,
		condition: &Expression,
		printer: &mut LuaNoFFIPrinter,
		out: &mut dyn Write,
	) -> Result<()> {
		printer.tab(out)?;
		write!(out, "if ")?;

		condition.print(printer, out)?;

		writeln!(out, " then")?;

		printer.indent();
		code.print(printer, out)?;
		printer.outdent();

		printer.tab(out)?;
		writeln!(out, "end")
	}

	fn print_if_false(
		code: &Sequence,
		condition: &Expression,
		printer: &mut LuaNoFFIPrinter,
		out: &mut dyn Write,
	) -> Result<()> {
		printer.tab(out)?;
		write!(out, "if not (")?;

		condition.print(printer, out)?;

		writeln!(out, ") then")?;

		printer.indent();
		code.print(printer, out)?;
		printer.outdent();

		printer.tab(out)?;
		writeln!(out, "end")
	}

	fn print_if_else(
		on_false: &Sequence,
		on_true: &Sequence,
		condition: &Expression,
		printer: &mut LuaNoFFIPrinter,
		out: &mut dyn Write,
	) -> Result<()> {
		printer.tab(out)?;
		write!(out, "if ")?;

		condition.print(printer, out)?;

		writeln!(out, " then")?;

		printer.indent();
		on_true.print(printer, out)?;
		printer.outdent();

		printer.tab(out)?;
		writeln!(out, "else")?;

		printer.indent();
		on_false.print(printer, out)?;
		printer.outdent();

		printer.tab(out)?;
		writeln!(out, "end")
	}

	pub fn print_if(
		on_false: &Sequence,
		on_true: &Sequence,
		condition: &Expression,
		printer: &mut LuaNoFFIPrinter,
		out: &mut dyn Write,
	) -> Result<()> {
		let false_empty = on_false.list.is_empty();
		let true_empty = on_true.list.is_empty();

		match (false_empty, true_empty) {
			(true, true | false) => print_if_true(on_true, condition, printer, out),
			(false, true) => print_if_false(on_false, condition, printer, out),
			(false, false) => print_if_else(on_false, on_true, condition, printer, out),
		}
	}
}

use std::io::{Result, Write};

use luanoffi_tree::{
	LuaNoFFITree,
	expression::Expression,
	statement::{
		Assign, Call, Export, GlobalSet, Match, MemoryCopy, MemoryDrop, MemoryFill, MemoryStore,
		Repeat, Sequence, Statement, SwapAll, TableCopy, TableDrop, TableFill, TableSet,
	},
};

use crate::{
	LuaNoFFIPrinter,
	expression::{fmt_delimited, fmt_locals, fmt_stack_enter, fmt_stack_leave},
	library::{NeedsName as _, RUNTIME_TABLE},
	print::Print,
};

/// The name a runtime section binds its helper to.
///
/// The library prints every section inside its own scope and publishes the
/// locals it declares in the `RUNTIME_TABLE` table, so the module reads its
/// helpers back from there.
fn runtime_binding_name(section: &str) -> String {
	if section.starts_with("into_bits_")
		|| section.starts_with("from_bits_")
		|| section.starts_with("bit32_")
		|| section.starts_with("buffer_")
	{
		section.to_owned()
	} else {
		alloc::format!("rt_{section}")
	}
}

/// Whether the module body would exceed the Lua limit of 200 active locals.
///
/// The module function declares `environment`, `excess_stack`, one binding per
/// runtime section, `stack_top` when the function has a slow stack, every
/// module local, and `export`.
fn use_table_backed_module_locals(
	printer: &LuaNoFFIPrinter,
	locals: &[luanoffi_tree::expression::Name],
	stack: u16,
) -> bool {
	const LUA_MAX_LOCALS: usize = 200;

	let fixed = 3 + usize::from(stack != 0);

	locals.len() + printer.runtime_names().len() + fixed > LUA_MAX_LOCALS
}

impl Print for Match {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			branches,
			condition,
		} = self;

		if let [on_false, on_true] = branches.as_slice() {
			conditional::print_if(on_false, on_true, condition, printer, out)
		} else {
			conditional::print_match(branches, condition, printer, out)
		}
	}
}

/// Prints the exit test of a `repeat` loop.
///
/// The graph models the test as an integer, so the straightforward printing materializes
/// a `0` or `1` and then compares it against zero on every iteration. When the integer is
/// only there to carry a predicate across the boundary we print the predicate itself,
/// which drops both the conversion and the comparison.
fn fmt_repeat_condition(
	condition: &Expression,
	printer: &mut LuaNoFFIPrinter,
	out: &mut dyn Write,
) -> Result<()> {
	if let Expression::BooleanToInteger(conversion) = condition {
		write!(out, "not (")?;

		conversion.source.print(printer, out)?;

		write!(out, ")")
	} else {
		condition.print(printer, out)?;

		write!(out, " == 0")
	}
}

impl Print for Repeat {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { code, condition } = self;

		printer.tab(out)?;
		writeln!(out, "repeat")?;

		printer.indent();
		code.print(printer, out)?;
		printer.outdent();

		printer.tab(out)?;
		write!(out, "until ")?;

		fmt_repeat_condition(condition, printer, out)?;

		writeln!(out)
	}
}

impl Print for Assign {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			source,
		} = self;

		printer.tab(out)?;
		destination.print(printer, out)?;

		write!(out, " = ")?;

		source.print(printer, out)?;

		writeln!(out, ";")
	}
}

impl Print for SwapAll {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { locals } = self;

		for pair in locals.windows(2) {
			printer.tab(out)?;

			pair[0].print(printer, out)?;

			write!(out, ", ")?;

			pair[1].print(printer, out)?;

			write!(out, " = ")?;

			pair[1].print(printer, out)?;

			write!(out, ", ")?;

			pair[0].print(printer, out)?;

			writeln!(out, ";")?;
		}

		Ok(())
	}
}

impl Print for Call {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			function,
			results,
			arguments,
		} = self;

		printer.tab(out)?;

		if !results.is_empty() {
			fmt_delimited(results, printer, out)?;

			write!(out, " = ")?;
		}

		function.print(printer, out)?;

		write!(out, "(")?;

		fmt_delimited(arguments, printer, out)?;

		writeln!(out, ")")
	}
}

impl Print for GlobalSet {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			source,
		} = self;

		printer.tab(out)?;
		destination.print(printer, out)?;

		write!(out, "[1] = ")?;

		source.print(printer, out)?;

		writeln!(out, ";")
	}
}

impl Print for TableSet {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			source,
		} = self;

		let intrinsic = self.needs_name();

		printer.tab(out)?;
		write!(out, "rt_{intrinsic}(")?;

		destination.print(printer, out)?;

		write!(out, ", ")?;

		source.print(printer, out)?;

		writeln!(out, ");")
	}
}

impl Print for TableFill {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			source,
			size,
		} = self;

		let intrinsic = self.needs_name();

		printer.tab(out)?;
		write!(out, "rt_{intrinsic}(")?;

		destination.print(printer, out)?;

		write!(out, ", ")?;

		source.print(printer, out)?;

		write!(out, ", ")?;

		size.print(printer, out)?;

		writeln!(out, ")")
	}
}

impl Print for TableCopy {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			source,
			size,
		} = self;

		let intrinsic = self.needs_name();

		printer.tab(out)?;
		write!(out, "rt_{intrinsic}(")?;

		destination.print(printer, out)?;

		write!(out, ", ")?;

		source.print(printer, out)?;

		write!(out, ", ")?;

		size.print(printer, out)?;

		writeln!(out, ")")
	}
}

impl Print for TableDrop {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		let intrinsic = self.needs_name();

		printer.tab(out)?;
		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		writeln!(out, ")")
	}
}

impl Print for MemoryStore {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			source,
			offset,
			..
		} = self;

		let intrinsic = self.needs_name();

		printer.tab(out)?;
		write!(out, "rt_{intrinsic}(")?;

		destination.print(printer, out)?;

		write!(out, ", {offset}, ")?;

		source.print(printer, out)?;

		writeln!(out, ")")
	}
}

impl Print for MemoryFill {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			byte,
			size,
		} = self;

		let intrinsic = self.needs_name();

		printer.tab(out)?;
		write!(out, "rt_{intrinsic}(")?;

		destination.print(printer, out)?;

		write!(out, ", ")?;

		byte.print(printer, out)?;

		write!(out, ", ")?;

		size.print(printer, out)?;

		writeln!(out, ")")
	}
}

impl Print for MemoryCopy {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			destination,
			source,
			size,
		} = self;

		let intrinsic = self.needs_name();

		printer.tab(out)?;
		write!(out, "rt_{intrinsic}(")?;

		destination.print(printer, out)?;

		write!(out, ", ")?;

		source.print(printer, out)?;

		write!(out, ", ")?;

		size.print(printer, out)?;

		writeln!(out, ")")
	}
}

impl Print for MemoryDrop {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { source } = self;

		let intrinsic = self.needs_name();

		printer.tab(out)?;
		write!(out, "rt_{intrinsic}(")?;

		source.print(printer, out)?;

		writeln!(out, ")")
	}
}

impl Print for Statement {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		match self {
			Self::Match(inner) => inner.print(printer, out),
			Self::Repeat(repeat) => repeat.print(printer, out),
			Self::Assign(assign) => assign.print(printer, out),
			Self::SwapAll(swap_all) => swap_all.print(printer, out),
			Self::Call(call) => call.print(printer, out),
			Self::GlobalSet(global_set) => global_set.print(printer, out),
			Self::TableSet(table_set) => table_set.print(printer, out),
			Self::TableFill(table_fill) => table_fill.print(printer, out),
			Self::TableCopy(table_copy) => table_copy.print(printer, out),
			Self::TableDrop(elements_drop) => elements_drop.print(printer, out),
			Self::MemoryStore(memory_store) => memory_store.print(printer, out),
			Self::MemoryFill(memory_fill) => memory_fill.print(printer, out),
			Self::MemoryCopy(memory_copy) => memory_copy.print(printer, out),
			Self::MemoryDrop(data_drop) => data_drop.print(printer, out),
		}
	}
}

impl Print for Sequence {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		self.list
			.iter()
			.try_for_each(|statement| statement.print(printer, out))
	}
}

impl Print for Export {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self { identifier, source } = self;

		write!(out, "[\"{}\"] = ", identifier.as_bytes().escape_ascii())?;

		source.print(printer, out)
	}
}

fn fmt_export_list(
	exports: &[Export],
	printer: &mut LuaNoFFIPrinter,
	out: &mut dyn Write,
) -> Result<()> {
	printer.tab(out)?;
	writeln!(out, "local export = {{")?;

	printer.indent();

	exports.iter().try_for_each(|export| {
		printer.tab(out)?;
		export.print(printer, out)?;

		writeln!(out, ",")
	})?;

	printer.outdent();

	printer.tab(out)?;
	writeln!(out, "}}")
}

impl Print for LuaNoFFITree {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		let Self {
			environment,
			locals,
			stack,
			code,
			exports,
		} = self;

		printer.tab(out)?;
		write!(out, "local function module(")?;

		environment.print(printer, out)?;

		writeln!(out, ")")?;

		printer.indent();

		printer.tab(out)?;
		writeln!(out, "local excess_stack = {{ top = 0 }}")?;

		let table_backed_locals = use_table_backed_module_locals(printer, locals, *stack);

		for &name in printer.runtime_names() {
			let binding = runtime_binding_name(name);

			printer.tab(out)?;
			writeln!(out, "local {binding} = {RUNTIME_TABLE}.{binding}")?;
		}

		fmt_stack_enter(*stack, printer, out)?;

		if table_backed_locals {
			printer.tab(out)?;
			writeln!(out, "local module_locals = {{}}")?;
			printer.tab(out)?;
			writeln!(out, "for i = 1, {} do", locals.len())?;
			printer.indent();
			printer.tab(out)?;
			writeln!(out, "module_locals[i] = 0")?;
			printer.outdent();
			printer.tab(out)?;
			writeln!(out, "end")?;

			for (index, &name) in locals.iter().enumerate() {
				printer.set_exact_name(name, alloc::format!("module_locals[{}]", index + 1).into());
			}
		} else {
			fmt_locals(locals, printer, out)?;
		}

		code.print(printer, out)?;

		fmt_export_list(exports, printer, out)?;
		fmt_stack_leave(*stack, printer, out)?;

		printer.tab(out)?;
		writeln!(out, "return export")?;

		if table_backed_locals {
			printer.clear_exact_names();
		}

		printer.outdent();

		printer.tab(out)?;
		writeln!(out, "end")
	}
}
