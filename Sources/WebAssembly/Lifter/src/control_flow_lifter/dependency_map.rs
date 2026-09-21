use alloc::vec::Vec;
use ir_graph::Link;
use web_assembly_liveness::references::{Reference, ReferenceType};

pub struct DependencyMap {
	buffer: Vec<(Reference, Link)>,

	mutable_count: usize,
}

impl DependencyMap {
	pub const fn new() -> Self {
		Self {
			buffer: Vec::new(),

			mutable_count: 0,
		}
	}

	pub fn fill_keys(&mut self, keys: &[Reference]) {
		self.mutable_count = keys.iter().filter(|key| key.kind.is_mutable()).count();

		let keys = keys.iter().map(|&key| (key, Link::DANGLING));

		self.buffer.clear();
		self.buffer.extend(keys);
	}

	fn position(&self, kind: ReferenceType, id: u16) -> usize {
		self.buffer
			.binary_search_by_key(&Reference { kind, id }, |data| data.0)
			.unwrap()
	}

	pub fn get(&self, kind: ReferenceType, id: u16) -> Link {
		let position = self.position(kind, id);

		self.buffer[position].1
	}

	pub fn set(&mut self, kind: ReferenceType, id: u16, value: Link) {
		let position = self.position(kind, id);

		self.buffer[position].1 = value;
	}

	/// The number of references the map holds.
	pub const fn count(&self) -> usize {
		self.buffer.len()
	}

	/// The number of mutable references the map holds.
	///
	/// The key set only changes in [`Self::fill_keys`], so the count is tallied there and
	/// read back in constant time by the callers that size a buffer from it.
	pub const fn mutable_count(&self) -> usize {
		self.mutable_count
	}

	pub fn get_all_into(&self, target: &mut Vec<Link>) {
		let iter = self.buffer.iter().map(|data| data.1);

		target.extend(iter);
	}

	pub fn get_mutable_into(&self, target: &mut Vec<Link>) {
		let iter = self
			.buffer
			.iter()
			.filter_map(|(Reference { kind, .. }, link)| kind.is_mutable().then_some(link));

		target.extend(iter);
	}

	pub fn set_all_from<I>(&mut self, values: I)
	where
		I: IntoIterator<Item = Link>,
	{
		self.buffer
			.iter_mut()
			.zip(values)
			.for_each(|(reference, value)| reference.1 = value);
	}

	pub fn set_mutable_from<I>(&mut self, values: I)
	where
		I: IntoIterator<Item = Link>,
	{
		self.buffer
			.iter_mut()
			.filter(|(Reference { kind, .. }, _)| kind.is_mutable())
			.zip(values)
			.for_each(|(reference, value)| reference.1 = value);
	}
}
