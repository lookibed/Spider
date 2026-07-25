#include <stdio.h>

int miniz_roundtrip_hash(int level);
int miniz_probe_compressed_size(int level);
int miniz_probe_crc32(void);
int miniz_probe_adler32(void);

int main(void) {
    printf("miniz_roundtrip_hash(6) = %d\n", miniz_roundtrip_hash(6));
    printf("miniz_probe_compressed_size(6) = %d\n", miniz_probe_compressed_size(6));
    printf("miniz_probe_crc32() = %d\n", miniz_probe_crc32());
    printf("miniz_probe_adler32() = %d\n", miniz_probe_adler32());
    return 0;
}
