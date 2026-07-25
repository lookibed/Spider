typedef unsigned int u32;
typedef int i32;
typedef unsigned long long u64;
typedef long long i64;

static u64 rotl64(const u64 value, const u32 shift) {
	return (value << shift) | (value >> (64U - shift));
}

static i32 fold_i64(const u64 value) {
	u32 lo = (u32)value;
	u32 hi = (u32)(value >> 32U);

	return (i32)(lo ^ hi);
}

i32 hash_i64_mix(const i32 iterations) {
	u64 state = 0x123456789ABCDEF0ULL;
	i32 index = 0;
	u32 hash = 0x6D2B79F5U;

	while (index < iterations) {
		u64 mixed = ((u64)(u32)index << 33U) ^ ((u64)(u32)(index * 17) << 7U) ^ 0x9E3779B97F4A7C15ULL;
		state = rotl64(state ^ mixed, 11U);
		state = state * 0xD6E8FEB86659FD93ULL;

		if ((index & 3) == 0) {
			state = state + 0xA0761D6478BD642FULL;
		} else {
			state = state ^ rotl64(state, 17U);
		}

		hash = (u32)((hash << 5) | (hash >> 27U));
		hash = hash ^ (u32)fold_i64(state);
		hash = hash + (u32)index;
		index = index + 1;
	}

	return (i32)hash;
}

i32 hash_i64_div(const i32 iterations) {
	i64 signed_state = -0x123456789ABCDELL;
	u64 unsigned_state = 0xFEDCBA9876543210ULL;
	i32 index = 0;
	u32 hash = 0x1B873593U;

	while (index < iterations) {
		i64 signed_divisor = ((i64)(index & 15) + 3);
		u64 unsigned_divisor = (u64)(u32)((index & 31) + 5);
		i64 signed_term = signed_state / signed_divisor;
		i64 signed_rem = signed_state % signed_divisor;
		u64 unsigned_term = unsigned_state / unsigned_divisor;
		u64 unsigned_rem = unsigned_state % unsigned_divisor;

		signed_state = signed_term - (signed_rem << 9) + (i64)(index * 13);
		unsigned_state = rotl64(unsigned_term ^ (unsigned_rem << 11), 7U) + 0x9E3779B97F4A7C15ULL;

		if (signed_state < 0) {
			hash = hash ^ (u32)fold_i64((u64)signed_state);
		} else {
			hash = hash + (u32)fold_i64((u64)signed_state);
		}

		hash = hash ^ (u32)fold_i64(unsigned_state);
		hash = (hash << 3) | (hash >> 29U);
		index = index + 1;
	}

	return (i32)hash;
}

i32 probe_div_s64(void) {
	i64 value = -0x123456789ABCDELL;
	i64 result = value / 3LL;

	return fold_i64((u64)result);
}

i32 probe_rem_s64(void) {
	i64 value = -0x123456789ABCDELL;
	i64 result = value % 3LL;

	return fold_i64((u64)result);
}

i32 probe_div_u64(void) {
	u64 value = 0xFEDCBA9876543210ULL;
	u64 result = value / 5ULL;

	return fold_i64(result);
}

i32 probe_rem_u64(void) {
	u64 value = 0xFEDCBA9876543210ULL;
	u64 result = value % 5ULL;

	return fold_i64(result);
}

static i64 hash_i64_div_signed_term_0(void) {
	i64 signed_state = -0x123456789ABCDELL;
	i64 signed_divisor = 3LL;

	return signed_state / signed_divisor;
}

static i64 hash_i64_div_signed_rem_0(void) {
	i64 signed_state = -0x123456789ABCDELL;
	i64 signed_divisor = 3LL;

	return signed_state % signed_divisor;
}

static u64 hash_i64_div_unsigned_term_0(void) {
	u64 unsigned_state = 0xFEDCBA9876543210ULL;
	u64 unsigned_divisor = 5ULL;

	return unsigned_state / unsigned_divisor;
}

static u64 hash_i64_div_unsigned_rem_0(void) {
	u64 unsigned_state = 0xFEDCBA9876543210ULL;
	u64 unsigned_divisor = 5ULL;

	return unsigned_state % unsigned_divisor;
}

static void hash_i64_div_trace_at(
	const i32 target_index,
	i64* const out_signed_term,
	i64* const out_signed_rem,
	i64* const out_signed_state,
	u64* const out_unsigned_term,
	u64* const out_unsigned_rem,
	u64* const out_unsigned_state,
	u32* const out_hash_after_signed,
	u32* const out_hash_after_unsigned
) {
	i64 signed_state = -0x123456789ABCDELL;
	u64 unsigned_state = 0xFEDCBA9876543210ULL;
	u32 hash = 0x1B873593U;
	i32 index = 0;

	while (1) {
		i64 signed_divisor = ((i64)(index & 15) + 3);
		u64 unsigned_divisor = (u64)(u32)((index & 31) + 5);
		i64 signed_term = signed_state / signed_divisor;
		i64 signed_rem = signed_state % signed_divisor;
		u64 unsigned_term = unsigned_state / unsigned_divisor;
		u64 unsigned_rem = unsigned_state % unsigned_divisor;
		u32 hash_after_signed;
		u32 hash_after_unsigned;

		signed_state = signed_term - (signed_rem << 9) + (i64)(index * 13);
		unsigned_state = rotl64(unsigned_term ^ (unsigned_rem << 11), 7U) + 0x9E3779B97F4A7C15ULL;

		if (signed_state < 0) {
			hash = hash ^ (u32)fold_i64((u64)signed_state);
		} else {
			hash = hash + (u32)fold_i64((u64)signed_state);
		}

		hash_after_signed = hash;
		hash = hash ^ (u32)fold_i64(unsigned_state);
		hash = (hash << 3) | (hash >> 29U);
		hash_after_unsigned = hash;

		if (index == target_index) {
			*out_signed_term = signed_term;
			*out_signed_rem = signed_rem;
			*out_signed_state = signed_state;
			*out_unsigned_term = unsigned_term;
			*out_unsigned_rem = unsigned_rem;
			*out_unsigned_state = unsigned_state;
			*out_hash_after_signed = hash_after_signed;
			*out_hash_after_unsigned = hash_after_unsigned;
			return;
		}

		index = index + 1;
	}
}

i32 probe_hash_i64_div_signed_term_0(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64((u64)signed_term);
}

i32 probe_hash_i64_div_signed_rem_0(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64((u64)signed_rem);
}

i32 probe_hash_i64_div_signed_state_1(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64((u64)signed_state);
}

i32 probe_hash_i64_div_unsigned_term_0(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return (i32)(u32)unsigned_term;
}

i32 probe_hash_i64_div_unsigned_rem_0(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return (i32)(u32)(unsigned_term >> 32U);
}

i32 probe_hash_i64_div_unsigned_state_1(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return (i32)(u32)unsigned_state;
}

i32 probe_hash_i64_div_hash_after_signed_0(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return (i32)(u32)(unsigned_state >> 32U);
}

i32 probe_hash_i64_div_hash_after_unsigned_0(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return (i32)hash_after_unsigned;
}

i32 probe_hash_i64_div_signed_term_at(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64((u64)signed_term);
}

i32 probe_hash_i64_div_signed_rem_at(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64((u64)signed_rem);
}

i32 probe_hash_i64_div_signed_state_at(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64((u64)signed_state);
}

i32 probe_hash_i64_div_unsigned_term_at(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64(unsigned_term);
}

i32 probe_hash_i64_div_unsigned_rem_at(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64(unsigned_rem);
}

i32 probe_hash_i64_div_unsigned_state_at(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return fold_i64(unsigned_state);
}

i32 probe_hash_i64_div_hash_after_signed_at(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return (i32)hash_after_signed;
}

i32 probe_hash_i64_div_hash_after_unsigned_at(const i32 index) {
	i64 signed_term;
	i64 signed_rem;
	i64 signed_state;
	u64 unsigned_term;
	u64 unsigned_rem;
	u64 unsigned_state;
	u32 hash_after_signed;
	u32 hash_after_unsigned;

	hash_i64_div_trace_at(index, &signed_term, &signed_rem, &signed_state, &unsigned_term, &unsigned_rem, &unsigned_state, &hash_after_signed, &hash_after_unsigned);

	return (i32)hash_after_unsigned;
}
