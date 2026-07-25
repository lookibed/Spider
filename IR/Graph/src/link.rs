/// A link from one node's output port to another node's input.
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq, PartialOrd, Ord)]
pub struct Link(
	/// The node identifier.
	pub u32,
	/// The port index.
	pub u16,
);

impl Link {
	/// Packs this link into a `usize` for use as an index.
	#[must_use]
	pub const fn into_usize(self) -> usize {
		((self.0 as usize) << u16::BITS) | (self.1 as usize)
	}

	/// A sentinel value representing a dangling link.
	pub const DANGLING: Self = Self(u32::MAX, u16::MAX);
}
