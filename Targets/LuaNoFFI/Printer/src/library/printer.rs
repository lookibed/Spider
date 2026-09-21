use std::io::{Result, Write};

use hashbrown::HashSet;

use super::sections::{Section, Sections};

/// The name of the chunk level table holding every printed section binding.
pub const RUNTIME_TABLE: &str = "runtime";

/// The largest number of active locals a single Lua scope may hold.
///
/// Lua allows two hundred of them, so the budget is kept a little below that to
/// leave room for whatever the caller declares around the library.
const MAX_ACTIVE_LOCALS: usize = 190;

/// Prints resolved runtime library sections in dependency order.
///
/// Every section is printed inside its own `do ... end` block so that the
/// locals it declares leave the chunk scope again. Definitions travel between
/// blocks through the [`RUNTIME_TABLE`] table, which means the chunk itself only
/// ever holds that single local no matter how large the library grows.
pub struct Printer {
	references: Vec<&'static str>,
	expanded: HashSet<&'static str>,
}

impl Printer {
	/// Creates a new `Printer`.
	#[must_use]
	pub fn new() -> Self {
		Self {
			references: Vec::new(),
			expanded: HashSet::new(),
		}
	}

	fn recursively_expand(&mut self, name: &'static str, sections: &Sections) {
		if !self.expanded.insert(name) {
			return;
		}

		let Section {
			references,
			mentions,
			..
		} = sections.find(name);

		for &dependency in references {
			self.recursively_expand(dependency, sections);
		}

		for &mention in mentions {
			let Some(owner) = sections.owner(mention) else {
				continue;
			};

			if owner != name {
				self.recursively_expand(owner, sections);
			}
		}

		self.references.push(name);
	}

	/// Resolves the given section names and their transitive dependencies.
	///
	/// A section depends on whatever it declares as `-- NEEDS`, plus whichever
	/// sections declare the locals it mentions; the latter keeps a section that
	/// forgot a `-- NEEDS` line working.
	pub fn resolve(&mut self, names: &[&'static str], sections: &Sections) {
		self.references.clear();
		self.expanded.clear();

		for &name in names {
			self.recursively_expand(name, sections);
		}
	}

	/// Writes a `local a, b = runtime.a, runtime.b` statement for the names.
	fn print_local_list(names: &[&'static str], indent: &str, out: &mut dyn Write) -> Result<()> {
		if names.is_empty() {
			return Ok(());
		}

		write!(out, "{indent}local ")?;

		for (position, &name) in names.iter().enumerate() {
			if position != 0 {
				write!(out, ", ")?;
			}

			write!(out, "{name}")?;
		}

		write!(out, " =")?;

		for (position, &name) in names.iter().enumerate() {
			if position != 0 {
				write!(out, ",")?;
			}

			write!(out, " {RUNTIME_TABLE}.{name}")?;
		}

		writeln!(out)
	}

	fn print_section(
		section: &Section,
		exported: &HashSet<&'static str>,
		out: &mut dyn Write,
	) -> Result<()> {
		let Section {
			defines,
			mentions,
			name,
			contents,
			..
		} = section;

		let imports = mentions
			.iter()
			.copied()
			.filter(|mention| exported.contains(mention))
			.collect::<Vec<_>>();

		assert!(
			imports.len() + defines.len() < MAX_ACTIVE_LOCALS,
			"`{name}` needs more locals than a Lua scope allows"
		);

		writeln!(out, "do -- SECTION {name}")?;

		Self::print_local_list(&imports, "\t", out)?;

		if !contents.is_empty() {
			writeln!(out, "{contents}")?;
		}

		for &define in defines {
			writeln!(out, "\t{RUNTIME_TABLE}.{define} = {define}")?;
		}

		writeln!(out, "end\n")
	}

	/// Writes all resolved sections to the writer.
	///
	/// Each section becomes one `do ... end` block, preceded by the declaration
	/// of the table its definitions are published in.
	///
	/// # Errors
	///
	/// Returns any IO errors that the `out` produces during the process.
	///
	/// # Panics
	///
	/// Panics if a single section would exceed the Lua limit on active locals.
	pub fn print(&self, sections: &Sections, out: &mut dyn Write) -> Result<()> {
		let mut exported = HashSet::new();

		writeln!(out, "local {RUNTIME_TABLE} = {{}}\n")?;

		for &name in &self.references {
			let section = sections.find(name);

			Self::print_section(section, &exported, out)?;

			exported.extend(section.defines.iter().copied());
		}

		Ok(())
	}

	/// Writes chunk level bindings for every local the given sections declare.
	///
	/// Sections are printed inside their own scope, so code printed after the
	/// library that refers to a section local by name needs it bound again. The
	/// list should stay short, since every name becomes an active local.
	///
	/// # Errors
	///
	/// Returns any IO errors that the `out` produces during the process.
	///
	/// # Panics
	///
	/// Panics if a section was not resolved, or if the bindings would exceed
	/// the Lua limit on active locals.
	pub fn print_bindings(
		&self,
		names: &[&'static str],
		sections: &Sections,
		out: &mut dyn Write,
	) -> Result<()> {
		let mut bindings = Vec::new();

		for &name in names {
			assert!(
				self.expanded.contains(name),
				"`{name}` was not resolved before its bindings were printed"
			);

			bindings.extend(sections.find(name).defines.iter().copied());
		}

		assert!(
			bindings.len() < MAX_ACTIVE_LOCALS,
			"library bindings need more locals than a Lua scope allows"
		);

		Self::print_local_list(&bindings, "", out)?;

		if !bindings.is_empty() {
			writeln!(out)?;
		}

		Ok(())
	}
}

impl Default for Printer {
	fn default() -> Self {
		Self::new()
	}
}

#[cfg(test)]
mod tests {
	use super::{Printer, Sections};

	fn print(names: &[&'static str]) -> String {
		let sections = Sections::with_built_ins();
		let mut printer = Printer::new();
		let mut out = Vec::new();

		printer.resolve(names, &sections);
		printer.print(&sections, &mut out).expect("library prints");

		String::from_utf8(out).expect("library is text")
	}

	#[test]
	fn prelude_wraps_every_section() {
		let source = print(&["memory_copy", "rotate_left_i64", "truncate_f32"]);
		let blocks = source.matches("\ndo -- SECTION ").count();
		let exports = source.matches("\n\truntime.").count();

		assert!(source.starts_with("local runtime = {}\n\ndo -- SECTION "));
		assert!(source.ends_with("end\n\n"));
		assert!(blocks > 16, "only {blocks} sections were printed");
		assert!(exports >= blocks, "only {exports} names were exported");
	}

	#[test]
	fn sections_import_and_export_their_names() {
		let source = print(&["bit32_countlz"]);

		assert!(source.contains("\tlocal bit32_countlz_impl = runtime.bit32_countlz_impl\n"));
		assert!(source.contains("\truntime.bit32_countlz = bit32_countlz\n"));
		assert!(source.contains("\truntime.bit32_countlz_impl = bit32_countlz_impl\n"));
	}

	#[test]
	fn sections_pull_in_undeclared_dependencies() {
		let source = print(&["truncate_f32"]);

		assert!(source.contains("do -- SECTION math_modf\n"));
		assert!(source.contains("\tlocal from_bits_f32, into_bits_f32, math_modf ="));
	}

	#[test]
	fn bindings_are_printed_for_every_name() {
		let sections = Sections::with_built_ins();
		let mut printer = Printer::new();
		let mut out = Vec::new();

		printer.resolve(&["bit32"], &sections);
		printer
			.print_bindings(&["bit32"], &sections, &mut out)
			.expect("bindings print");

		let source = String::from_utf8(out).expect("bindings are text");

		assert_eq!(
			source,
			"local bit32, bit32_countlz_impl, bit32_countrz_impl = runtime.bit32, runtime.bit32_countlz_impl, runtime.bit32_countrz_impl\n\n"
		);
	}
}
