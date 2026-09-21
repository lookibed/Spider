//! Analysis of the values a printed function body reads from enclosing scopes.
//!
//! Every WebAssembly function is printed as a closure nested inside `module`,
//! so each runtime helper it names and each scoped dependency it reads costs
//! one `LuaJIT` upvalue. `LuaJIT` refuses to compile a function that needs
//! more than sixty of them, so the printer has to know the demand before it
//! decides how to bind the captured values.

use core::ops::ControlFlow;

use hashbrown::HashMap;
use luanoffi_tree::{
	expression::{Expression, Function, Local, Name},
	statement::Statement,
	visitor::Visitor,
};

use crate::library::NeedsName as _;

/// The upvalue demand of a single printed function body.
pub struct Captures {
	runtime: HashMap<&'static str, usize>,
	locals: HashMap<Name, usize>,
}

impl Captures {
	/// Analyses the body of `function`.
	///
	/// # Panics
	///
	/// Panics if the visitor traversal fails; if this happens, it is a bug.
	#[must_use]
	pub fn of(function: &Function) -> Self {
		let mut this = Self {
			runtime: HashMap::new(),
			locals: HashMap::new(),
		};

		function
			.accept(&mut this)
			.continue_value()
			.expect("capture analysis must not fail");

		this
	}

	/// Returns how many distinct runtime helpers the body names.
	///
	/// Each of them is a `module` local, so each costs one upvalue.
	#[must_use]
	pub fn runtime_len(&self) -> usize {
		self.runtime.len()
	}

	/// Returns how many times the body reads `name`.
	#[must_use]
	pub fn local_uses(&self, name: Name) -> usize {
		self.locals.get(&name).copied().unwrap_or(0)
	}
}

impl Visitor for Captures {
	type Output = ();

	fn visit_expression(&mut self, expression: &Expression) -> ControlFlow<Self::Output> {
		let name = expression.needs_name();

		if !name.is_empty() {
			*self.runtime.entry(name).or_insert(0) += 1;
		}

		if let Expression::Local(Local::Fast { name: local }) = expression {
			*self.locals.entry(*local).or_insert(0) += 1;
		}

		ControlFlow::Continue(())
	}

	fn visit_statement(&mut self, statement: &Statement) -> ControlFlow<Self::Output> {
		let name = statement.needs_name();

		if !name.is_empty() {
			*self.runtime.entry(name).or_insert(0) += 1;
		}

		ControlFlow::Continue(())
	}
}
