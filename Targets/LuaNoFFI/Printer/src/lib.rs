//! Prints `LuaNoFFI` trees.

extern crate alloc;

mod expression;
mod print;
mod statement;

/// Runtime library section management.
pub mod library;

use alloc::sync::Arc;
use std::io::{Result, Write};

use hashbrown::HashMap;
use luanoffi_tree::{LuaNoFFITree, expression::Name};

use self::print::Print as _;

/// Prints a `LuaNoFFI` tree into a writer.
pub struct LuaNoFFIPrinter {
	names: HashMap<Name, Arc<str>>,
	exact_names: HashMap<Name, Arc<str>>,
	depth: u16,
	runtime_names: Vec<&'static str>,
}

impl LuaNoFFIPrinter {
	/// Creates a new `LuaNoFFIPrinter`.
	#[must_use]
	pub fn new() -> Self {
		Self {
			names: HashMap::new(),
			exact_names: HashMap::new(),
			depth: 0,
			runtime_names: Vec::new(),
		}
	}

	/// Writes the current indentation level to the writer.
	///
	/// # Errors
	///
	/// Returns any IO errors that the `out` produces during the process.
	pub fn tab(&self, out: &mut dyn Write) -> Result<()> {
		(0..self.depth).try_for_each(|_| write!(out, "\t"))
	}

	/// Returns the name associated with the given `Name`, if any.
	pub fn get_name(&self, name: Name) -> Option<&str> {
		self.names.get(&name).map(Arc::as_ref)
	}

	/// Returns the exact name associated with the given `Name`, if any.
	pub fn get_exact_name(&self, name: Name) -> Option<&str> {
		self.exact_names.get(&name).map(Arc::as_ref)
	}

	/// Associates an exact printed name with a `Name`.
	pub fn set_exact_name(&mut self, name: Name, value: Arc<str>) {
		self.exact_names.insert(name, value);
	}

	/// Removes the exact printed name associated with a `Name`, if any.
	pub fn take_exact_name(&mut self, name: Name) -> Option<Arc<str>> {
		self.exact_names.remove(&name)
	}

	/// Removes all exact printed names.
	pub fn clear_exact_names(&mut self) {
		self.exact_names.clear();
	}

	/// Increases the indentation level by one.
	pub const fn indent(&mut self) {
		self.depth = self.depth.wrapping_add(1);
	}

	/// Decreases the indentation level by one.
	pub const fn outdent(&mut self) {
		self.depth = self.depth.wrapping_sub(1);
	}

	/// Replaces the runtime helper list used while printing the tree.
	pub fn set_runtime_names(&mut self, mut runtime_names: Vec<&'static str>) {
		runtime_names.sort_unstable();
		runtime_names.dedup();
		self.runtime_names = runtime_names;
	}

	/// Returns the runtime helper section names directly referenced by the tree.
	pub fn runtime_names(&self) -> &[&'static str] {
		&self.runtime_names
	}

	/// Prints the tree into the writer.
	///
	/// # Errors
	///
	/// Returns any IO errors that the `out` produces during the process.
	pub fn print(&mut self, tree: &LuaNoFFITree, out: &mut dyn Write) -> Result<()> {
		tree.print(self, out)
	}
}

impl Default for LuaNoFFIPrinter {
	fn default() -> Self {
		Self::new()
	}
}
