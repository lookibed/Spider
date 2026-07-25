typedef int i32;

extern i32 hash_loop(i32 seed, i32 iterations);

int main(void) {
	return hash_loop(123456789, 200000);
}
