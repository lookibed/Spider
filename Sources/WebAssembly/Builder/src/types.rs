//! WebAssembly type information for function signatures and block types.

use alloc::{string::String, sync::Arc, vec::Vec};
use core::fmt::Write as _;
use wasmparser::{
	BlockType, CompositeInnerType, FuncType, RecGroup, SectionLimited, SubType, ValType,
};

/// Keeps only the characters that are safe inside a generated string literal.
///
/// The textual form of a reference type may contain quotes or other delimiters, and the
/// key only has to stay structural rather than readable, so anything else is folded away.
const fn sanitize(character: char) -> char {
	if character.is_ascii_alphanumeric() || matches!(character, ',' | '-' | '>' | '.' | '_') {
		character
	} else {
		'_'
	}
}

fn write_value_types(key: &mut String, types: &[ValType]) {
	for (index, kind) in types.iter().enumerate() {
		if index != 0 {
			key.push(',');
		}

		write!(key, "{kind}").expect("writing into a string should not fail");
	}
}

/// Returns the structural key identifying `kind` amongst all function types.
///
/// Two function types share a key if and only if they are structurally equal, which makes
/// the key usable for the type check of an indirect call, even across modules.
fn build_function_key(kind: &FuncType) -> Arc<str> {
	let mut key = String::new();

	write_value_types(&mut key, kind.params());

	key.push_str("->");

	write_value_types(&mut key, kind.results());

	key.chars().map(sanitize).collect::<String>().into()
}

/// WebAssembly type information.
pub struct Types {
	definitions: Vec<SubType>,
	keys: Vec<Arc<str>>,
	functions: Vec<u32>,
}

impl Types {
	#[must_use]
	/// Creates a new empty type collection.
	pub const fn new() -> Self {
		Self {
			definitions: Vec::new(),
			keys: Vec::new(),
			functions: Vec::new(),
		}
	}

	/// Clears all stored type information.
	pub fn clear(&mut self) {
		self.definitions.clear();
		self.keys.clear();
		self.functions.clear();
	}

	/// Adds sub types from a recursion group section.
	pub fn add_sub_types(&mut self, section: SectionLimited<'_, RecGroup>) {
		for group in section.into_iter().map(Result::unwrap) {
			self.definitions.extend(group.into_types());
		}

		self.keys.clear();
		self.keys.extend(self.definitions.iter().map(
			|sub_type| match &sub_type.composite_type.inner {
				CompositeInnerType::Func(kind) => build_function_key(kind),

				CompositeInnerType::Array(_)
				| CompositeInnerType::Struct(_)
				| CompositeInnerType::Cont(_) => Arc::from(""),
			},
		));
	}

	#[must_use]
	/// Returns the structural key for the function type at the given index.
	///
	/// # Panics
	///
	/// Panics if the type index is out of range.
	pub fn get_type_key(&self, kind: u32) -> Arc<str> {
		Arc::clone(&self.keys[usize::try_from(kind).unwrap()])
	}

	/// Adds a function type index.
	pub fn add_function(&mut self, function: u32) {
		self.functions.push(function);
	}

	/// Adds function type indices from a section.
	pub fn add_functions(&mut self, section: SectionLimited<'_, u32>) {
		self.functions
			.extend(section.into_iter().map(Result::unwrap));
	}

	#[must_use]
	/// Returns the type index for a function.
	///
	/// # Panics
	///
	/// Panics if the function index is out of range.
	pub fn get_function_index(&self, function: u32) -> u32 {
		self.functions[usize::try_from(function).unwrap()]
	}

	#[must_use]
	/// Returns the sub type at the given index.
	///
	/// # Panics
	///
	/// Panics if the type index is out of range.
	pub fn get_type(&self, kind: u32) -> &SubType {
		&self.definitions[usize::try_from(kind).unwrap()]
	}

	#[must_use]
	/// Returns the function type for a function.
	pub fn get_function_type(&self, function: u32) -> &FuncType {
		let index = self.get_function_index(function);

		self.get_type(index).unwrap_func()
	}

	#[must_use]
	/// Returns the parameter count for a block type.
	pub fn get_parameter_count(&self, block_type: BlockType) -> usize {
		match block_type {
			BlockType::Empty | BlockType::Type(_) => 0,
			BlockType::FuncType(kind) => self.get_type(kind).unwrap_func().params().len(),
		}
	}

	#[must_use]
	/// Returns the result count for a block type.
	pub fn get_result_count(&self, block_type: BlockType) -> usize {
		match block_type {
			BlockType::Empty => 0,
			BlockType::Type(_) => 1,
			BlockType::FuncType(kind) => self.get_type(kind).unwrap_func().results().len(),
		}
	}
}

impl Default for Types {
	fn default() -> Self {
		Self::new()
	}
}
