typedef unsigned int u32;
typedef int i32;

static u32 rotl32(const u32 value, const u32 shift) {
	return (value << shift) | (value >> (32U - shift));
}

i32 hash_f32(const i32 iterations) {
	float lhs = 0.75f;
	float rhs = -13.5f;
	u32 hash = 0x13579BDFU;
	i32 index = 0;

	while (index < iterations) {
		float mixed = ((float)((index & 15) - 7)) * 0.125f;
		lhs = lhs * 1.125f + mixed;
		rhs = rhs / 1.03125f - lhs * 0.5f;

		if (lhs > rhs) {
			lhs = lhs - rhs * 0.25f;
		} else {
			rhs = rhs + lhs * 0.75f;
		}

		hash = rotl32(hash ^ (u32)((i32)(lhs * 1024.0f)), 3U);
		hash = hash + ((u32)((i32)(rhs * 256.0f)) ^ (u32)index ^ 0x45D9F3BU);
		index = index + 1;
	}

	return (i32)hash;
}

i32 hash_f64(const i32 iterations) {
	double lhs = 0.75;
	double rhs = -13.5;
	u32 hash = 0x2468ACE1U;
	i32 index = 0;

	while (index < iterations) {
		double mixed = ((double)((index & 31) - 11)) * 0.0625;
		lhs = lhs * 1.03125 + mixed;
		rhs = rhs / 1.015625 - lhs * 0.375;

		if (lhs < rhs) {
			rhs = rhs - lhs * 0.5;
		} else {
			lhs = lhs + rhs * 0.125;
		}

		hash = rotl32(hash ^ (u32)((i32)(lhs * 2048.0)), 5U);
		hash = hash + ((u32)((i32)(rhs * 512.0)) ^ (u32)(index * 3) ^ 0x27D4EB2DU);
		index = index + 1;
	}

	return (i32)hash;
}
