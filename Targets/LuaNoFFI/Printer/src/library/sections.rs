/// A parsed runtime library section.
pub struct Section {
	/// The section dependency references.
	pub references: Box<[&'static str]>,
	/// The names the section body declares as top level locals.
	pub defines: Box<[&'static str]>,
	/// Every identifier mentioned anywhere in the section body, sorted.
	pub mentions: Box<[&'static str]>,
	/// The section name.
	pub name: &'static str,
	/// The section source contents.
	pub contents: &'static str,
}

impl Section {
	const SECTION_HEADER: &str = "-- SECTION ";
	const NEEDS_HEADER: &str = "-- NEEDS ";
	const LOCAL_HEADER: &str = "local ";
	const FUNCTION_HEADER: &str = "local function ";

	const fn is_name_start(source: char) -> bool {
		source == '_' || source.is_ascii_alphabetic()
	}

	const fn is_name_part(source: char) -> bool {
		source == '_' || source.is_ascii_alphanumeric()
	}

	fn is_name(source: &str) -> bool {
		let mut characters = source.chars();

		characters.next().is_some_and(Self::is_name_start) && characters.all(Self::is_name_part)
	}

	fn parse_definition(line: &'static str, definitions: &mut Vec<&'static str>) {
		if let Some(rest) = line.strip_prefix(Self::FUNCTION_HEADER) {
			let end = rest
				.find(|source: char| !Self::is_name_part(source))
				.unwrap_or(rest.len());
			let name = &rest[..end];

			if Self::is_name(name) {
				definitions.push(name);
			}

			return;
		}

		let Some(rest) = line.strip_prefix(Self::LOCAL_HEADER) else {
			return;
		};

		let names = match rest.split_once('=') {
			Some((names, _)) => names,
			None => rest,
		};

		for name in names.split(',').map(str::trim) {
			if Self::is_name(name) {
				definitions.push(name);
			}
		}
	}

	/// Finds every top level local declared by the section body.
	///
	/// Only lines that start at the first column are inspected, since any
	/// deeper declaration is scoped to a nested block instead.
	fn parse_definitions(contents: &'static str) -> Box<[&'static str]> {
		let mut definitions = Vec::new();

		for line in contents.lines() {
			Self::parse_definition(line, &mut definitions);
		}

		definitions.into()
	}

	/// Finds every identifier mentioned by the section body.
	///
	/// Comments and strings are deliberately scanned too; the result is only
	/// ever used to widen the set of imported names, so a superset is safe
	/// whereas a missing name would silently turn into a global lookup.
	fn parse_mentions(contents: &'static str) -> Box<[&'static str]> {
		let mut mentions = Vec::new();
		let mut rest = contents;

		while let Some(start) = rest.find(|source: char| Self::is_name_start(source)) {
			let tail = &rest[start..];
			let end = tail
				.find(|source: char| !Self::is_name_part(source))
				.unwrap_or(tail.len());

			mentions.push(&tail[..end]);

			rest = &tail[end..];
		}

		mentions.sort_unstable();
		mentions.dedup();

		mentions.into()
	}

	fn try_parse_header(
		source: &'static str,
		header: &'static str,
	) -> Option<(&'static str, &'static str)> {
		if !source.starts_with(header) {
			return None;
		}

		let source = &source[header.len()..];
		let end = source.find('\n')?;
		let (data, source) = source.split_at(end);

		Some((data.trim_end(), source.trim_start()))
	}

	fn parse_references(mut source: &'static str) -> (Box<[&'static str]>, &'static str) {
		let mut dependencies = Vec::new();

		while let Some((name, next)) = Self::try_parse_header(source, Self::NEEDS_HEADER) {
			dependencies.push(name);

			source = next;
		}

		(dependencies.into(), source)
	}

	fn parse_contents(source: &'static str) -> (&'static str, &'static str) {
		let end = source.find(Self::SECTION_HEADER).unwrap_or(source.len());
		let (content, source) = source.split_at(end);

		(content.trim(), source)
	}

	/// Tries to parse a section from the given source.
	pub fn try_parse(source: &'static str) -> Option<(Self, &'static str)> {
		let (name, source) = Self::try_parse_header(source, Self::SECTION_HEADER)?;
		let (references, source) = Self::parse_references(source);
		let (contents, source) = Self::parse_contents(source);

		assert!(
			references.is_sorted(),
			"references for `{name}` should be sorted"
		);

		let defines = Self::parse_definitions(contents);
		let mentions = Self::parse_mentions(contents);

		Some((
			Self {
				references,
				defines,
				mentions,
				name,
				contents,
			},
			source,
		))
	}
}

/// A collection of runtime library sections.
pub struct Sections {
	list: Vec<Section>,
	owners: Vec<(&'static str, &'static str)>,
}

impl Sections {
	/// The bit library source.
	pub const BIT_SOURCE: &str = include_str!("../../runtime/builtin/bit.lua");
	/// The bit32 library source (Lua 5.2+ style, implemented via `bit` for `LuaJIT`).
	pub const BIT32_SOURCE: &str = include_str!("../../runtime/builtin/bit32.lua");
	/// The buffer library source (replaces FFI in `LuaNoFFI`).
	pub const BUFFER_SOURCE: &str = include_str!("../../runtime/builtin/buffer.lua");
	/// The math library source.
	pub const MATH_SOURCE: &str = include_str!("../../runtime/builtin/math.lua");

	/// The F32 assembly source.
	pub const F32_ASSEMBLY_SOURCE: &str = include_str!("../../runtime/assembly/f32.lua");

	/// The I32 core source.
	pub const I32_SOURCE: &str = include_str!("../../runtime/core/i32.lua");
	/// The I64 core source.
	pub const I64_SOURCE: &str = include_str!("../../runtime/core/i64.lua");
	/// The F32 core source.
	pub const F32_SOURCE: &str = include_str!("../../runtime/core/f32.lua");
	/// The F64 core source.
	pub const F64_SOURCE: &str = include_str!("../../runtime/core/f64.lua");
	/// The table core source.
	pub const TABLE_SOURCE: &str = include_str!("../../runtime/core/table.lua");
	/// The memory core source.
	pub const MEMORY_SOURCE: &str = include_str!("../../runtime/core/memory.lua");

	/// Creates a new section collection with all built-in sources.
	#[must_use]
	pub fn with_built_ins() -> Self {
		let mut sections = Self {
			list: Vec::new(),
			owners: Vec::new(),
		};

		sections.parse_from(Self::BIT_SOURCE);
		sections.parse_from(Self::BIT32_SOURCE);
		sections.parse_from(Self::BUFFER_SOURCE);
		sections.parse_from(Self::MATH_SOURCE);

		sections.parse_from(Self::F32_ASSEMBLY_SOURCE);

		sections.parse_from(Self::I32_SOURCE);
		sections.parse_from(Self::I64_SOURCE);
		sections.parse_from(Self::F32_SOURCE);
		sections.parse_from(Self::F64_SOURCE);
		sections.parse_from(Self::TABLE_SOURCE);
		sections.parse_from(Self::MEMORY_SOURCE);

		sections.resolve();

		sections
	}

	/// Parses sections from a source string.
	///
	/// # Panics
	///
	/// Panics if there is trailing unparsed data.
	pub fn parse_from(&mut self, mut source: &'static str) {
		while let Some((section, next)) = Section::try_parse(source) {
			self.list.push(section);

			source = next;
		}

		assert!(source.is_empty(), "trailing data in source\n{source}");
	}

	/// Sorts and validates sections, checking for duplicates.
	///
	/// # Panics
	///
	/// Panics if duplicate section names are found, or if two sections declare
	/// the same top level local.
	pub fn resolve(&mut self) {
		self.list.sort_unstable_by_key(|&Section { name, .. }| name);

		for window in self.list.windows(2) {
			let Section { name: lhs, .. } = window[0];
			let Section { name: rhs, .. } = window[1];

			assert_ne!(lhs, rhs, "`{lhs}` section was duplicated");
		}

		self.owners.clear();

		for &Section {
			name, ref defines, ..
		} in &self.list
		{
			self.owners
				.extend(defines.iter().map(|&define| (define, name)));
		}

		self.owners.sort_unstable();

		for window in self.owners.windows(2) {
			let (lhs, lhs_owner) = window[0];
			let (rhs, rhs_owner) = window[1];

			assert_ne!(
				lhs, rhs,
				"`{lhs}` is declared by both `{lhs_owner}` and `{rhs_owner}`"
			);
		}
	}

	/// Finds the section declaring the given top level local, if any.
	#[must_use]
	pub fn owner(&self, name: &str) -> Option<&'static str> {
		let position = self
			.owners
			.binary_search_by_key(&name, |&(define, _)| define)
			.ok()?;
		let (_, owner) = self.owners[position];

		Some(owner)
	}

	/// Finds a section by name.
	///
	/// # Panics
	///
	/// Panics if the section is not found.
	#[must_use]
	pub fn find(&self, name: &'static str) -> &Section {
		let position = self
			.list
			.binary_search_by_key(&name, |&Section { name, .. }| name)
			.unwrap_or_else(|_| panic!("`{name}` is not a section"));

		&self.list[position]
	}
}

#[cfg(test)]
mod tests {
	use super::Sections;

	#[test]
	fn built_ins_include_runtime_contract_sections() {
		let sections = Sections::with_built_ins();

		for name in [
			"transmute_n32",
			"transmute_n64",
			"buffer_write_u32",
			"bit32_lrotate",
			"bit32_rrotate",
			"from_bits_f32",
			"from_bits_f64",
			"into_bits_i64",
			"transmute_i64_to_f64",
			"transmute_f64_to_i64",
		] {
			let _ = sections.find(name);
		}
	}

	#[test]
	fn sections_declare_their_own_locals() {
		let sections = Sections::with_built_ins();

		for (name, defines) in [
			(
				"bit32",
				&["bit32", "bit32_countlz_impl", "bit32_countrz_impl"][..],
			),
			("memory_new", &["rt_memory_new"][..]),
			("load_i32", &["rt_load_i32"][..]),
			("from_bits_f32", &["from_bits_f32"][..]),
			("bit", &["bit"][..]),
		] {
			assert_eq!(&*sections.find(name).defines, defines, "for `{name}`");

			for &define in defines {
				assert_eq!(sections.owner(define), Some(name));
			}
		}
	}

	#[test]
	fn sections_mention_their_dependencies() {
		let sections = Sections::with_built_ins();
		let section = sections.find("bit32_countlz");

		assert!(section.mentions.contains(&"bit32_countlz_impl"));
		assert!(section.mentions.is_sorted());
	}
}
