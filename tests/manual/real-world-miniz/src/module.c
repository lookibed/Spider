#include "../../real-world-miniz/upstream/miniz.h"

typedef unsigned int u32;

static unsigned char input_buffer[8192];
static unsigned char compressed_buffer[16384];
static unsigned char output_buffer[8192];

static void fill_input(void) {
    u32 i = 0;
    for (i = 0; i < (u32)sizeof(input_buffer); i++) {
        unsigned char value = (unsigned char)(((i * 17u) ^ (i >> 3) ^ (i * i)) & 0xFFu);
        if ((i & 63u) < 24u) {
            value = (unsigned char)(value ^ 0x5Au);
        } else if ((i & 63u) < 48u) {
            value = (unsigned char)(value + 37u);
        } else {
            value = (unsigned char)(value ^ (unsigned char)(i & 0x1Fu));
        }
        input_buffer[i] = value;
    }
}

static int fold_bytes(const unsigned char *data, mz_ulong size) {
    u32 hash = 0x811C9DC5u;
    mz_ulong i = 0;

    for (i = 0; i < size; i++) {
        hash ^= data[i];
        hash *= 16777619u;
        hash = (hash << 5) | (hash >> 27);
    }

    return (int)hash;
}

int miniz_roundtrip_hash(int level) {
    mz_ulong compressed_size = sizeof(compressed_buffer);
    mz_ulong output_size = sizeof(output_buffer);
    int status = MZ_OK;
    mz_ulong i = 0;
    u32 hash = 0;

    fill_input();

    status = mz_compress2(
        compressed_buffer,
        &compressed_size,
        input_buffer,
        (mz_ulong)sizeof(input_buffer),
        level
    );
    if (status != MZ_OK) {
        return -1000 - status;
    }

    status = mz_uncompress(
        output_buffer,
        &output_size,
        compressed_buffer,
        compressed_size
    );
    if (status != MZ_OK) {
        return -2000 - status;
    }

    if (output_size != (mz_ulong)sizeof(input_buffer)) {
        return -3000 - (int)output_size;
    }

    for (i = 0; i < output_size; i++) {
        if (output_buffer[i] != input_buffer[i]) {
            return -4000 - (int)i;
        }
    }

    hash = (u32)fold_bytes(output_buffer, output_size);
    hash ^= (u32)compressed_size;
    hash ^= (u32)mz_crc32(MZ_CRC32_INIT, input_buffer, (size_t)sizeof(input_buffer));
    hash ^= (u32)mz_adler32(MZ_ADLER32_INIT, input_buffer, (size_t)sizeof(input_buffer));

    return (int)hash;
}

int miniz_probe_compressed_size(int level) {
    mz_ulong compressed_size = sizeof(compressed_buffer);
    int status = MZ_OK;

    fill_input();
    status = mz_compress2(
        compressed_buffer,
        &compressed_size,
        input_buffer,
        (mz_ulong)sizeof(input_buffer),
        level
    );
    if (status != MZ_OK) {
        return -1000 - status;
    }

    return (int)compressed_size;
}

int miniz_probe_crc32(void) {
    fill_input();
    return (int)mz_crc32(MZ_CRC32_INIT, input_buffer, (size_t)sizeof(input_buffer));
}

int miniz_probe_adler32(void) {
    fill_input();
    return (int)mz_adler32(MZ_ADLER32_INIT, input_buffer, (size_t)sizeof(input_buffer));
}

int miniz_probe_fold_hash(void) {
    fill_input();
    return fold_bytes(input_buffer, (mz_ulong)sizeof(input_buffer));
}

int miniz_probe_fold_prefix(int count) {
    fill_input();
    if (count < 0) {
        return -1;
    }
    if ((u32)count > (u32)sizeof(input_buffer)) {
        count = (int)sizeof(input_buffer);
    }
    return fold_bytes(input_buffer, (mz_ulong)count);
}

int miniz_probe_fold_step(int seed, int byte_value) {
    u32 hash = (u32)seed;
    hash ^= (u32)(byte_value & 0xFF);
    hash *= 16777619u;
    hash = (hash << 5) | (hash >> 27);
    return (int)hash;
}
