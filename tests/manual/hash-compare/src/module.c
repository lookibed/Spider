typedef unsigned int u32;
typedef int i32;

static u32 rotl32(const u32 value, const u32 shift) {
	return (value << shift) | (value >> (32U - shift));
}

i32 hash_loop(const i32 seed, const i32 iterations) {
	u32 state = (u32)seed ^ 0x9E3779B9U;
	i32 index = 0;

	while (index < iterations) {
		state = rotl32(state, 5U);
		state = state + (u32)index * 0x45D9F3BU;
		state = state ^ (state >> 13U);

		if (((u32)index & 7U) == 0U) {
			state = state ^ 0x27D4EB2DU;
		} else {
			state = state + 0x165667B1U;
		}

		state = rotl32(state ^ 0x85EBCA6BU, 7U);
		index = index + 1;
	}

	return (i32)state;
}
