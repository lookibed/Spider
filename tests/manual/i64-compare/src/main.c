typedef int i32;

extern i32 hash_i64_mix(i32 iterations);
extern i32 hash_i64_div(i32 iterations);

int main(void) {
	return hash_i64_mix(512) ^ hash_i64_div(512);
}
