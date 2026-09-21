/// A link from one node's output port to another node's input.
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq, PartialOrd, Ord)]
pub struct Link(
	/// The node identifier.
	pub u32,
	/// The port index.
	pub u16,
);

impl Link {
	/// Packs this link into a `u64` key.
	///
	/// The key is unique for every distinct link on every platform, since a `u64` is wide
	/// enough to hold both the node identifier and the port index side by side.
	#[must_use]
	pub const fn into_u64(self) -> u64 {
		((self.0 as u64) << u16::BITS) | (self.1 as u64)
	}

	/// Packs this link into a `usize` for use as an index.
	///
	/// # Panics
	///
	/// Panics if the key does not fit in a `usize`. This is impossible where a `usize` is at
	/// least 64 bits wide, and on narrower platforms it can only happen for node identifiers
	/// that no `usize` indexed container could address anyway.
	#[must_use]
	pub fn into_usize(self) -> usize {
		usize::try_from(self.into_u64()).expect("link key should be addressable as an index")
	}

	/// A sentinel value representing a dangling link.
	pub const DANGLING: Self = Self(u32::MAX, u16::MAX);
}

#[cfg(test)]
mod tests {
	use super::Link;

	/// The mask a `usize` sized key would be truncated to on a 32-bit platform.
	const NARROW_MASK: u64 = 0xFFFF_FFFF;

	#[test]
	fn key_is_wide_enough_for_every_link() {
		let key = Link::DANGLING.into_u64();

		assert_eq!(key >> u16::BITS, u64::from(u32::MAX));
		assert_eq!(key & u64::from(u16::MAX), u64::from(u16::MAX));
	}

	#[test]
	fn key_round_trips_both_fields() {
		let link = Link(0xDEAD_BEEF, 0x1234);
		let key = link.into_u64();

		assert_eq!(key >> u16::BITS, u64::from(link.0));
		assert_eq!(key & 0xFFFF, u64::from(link.1));
	}

	#[test]
	fn keys_do_not_collide_across_port_width() {
		let low = Link(0, 0);
		let high = Link(0x1_0000, 0);

		assert_ne!(low.into_u64(), high.into_u64());

		// Truncating the key to the width of a 32-bit `usize` is what used to make these
		// two links share a key, so the narrowing must be rejected rather than silent.
		assert_eq!(low.into_u64() & NARROW_MASK, high.into_u64() & NARROW_MASK);

		// Where the key is addressable the index must keep them apart, and where it is not
		// the conversion panics instead of quietly folding them together.
		assert_ne!(low.into_usize(), high.into_usize());
	}
}
