typedef int i32;

extern i32 hash_f32(i32 iterations);
extern i32 hash_f64(i32 iterations);

int main(void) {
	return hash_f32(2048) ^ hash_f64(2048);
}
