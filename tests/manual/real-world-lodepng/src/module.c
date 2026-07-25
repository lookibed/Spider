#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "../upstream/lodepng.h"

extern size_t spider_lodepng_last_error86_pos;
extern size_t spider_lodepng_last_error86_wpos;
extern unsigned spider_lodepng_last_error86_hashpos;
extern unsigned spider_lodepng_last_error86_current_offset;
extern unsigned spider_lodepng_last_error86_prev_offset;
extern unsigned spider_lodepng_last_error86_windowsize;
extern unsigned spider_lodepng_last_error86_length;
extern unsigned spider_lodepng_last_error86_offset;

void shim_reset_heap(void);
size_t shim_heap_size(void);
size_t shim_heap_offset(void);
size_t shim_heap_peak(void);
size_t shim_last_alloc_request(void);
size_t shim_last_alloc_total(void);
size_t shim_last_failed_request(void);
size_t shim_last_failed_total(void);

typedef unsigned int u32;

static unsigned char image_a[64 * 64 * 4];
static unsigned char image_b[64 * 64 * 4];
static unsigned char *host_decoded = 0;
static unsigned host_width = 0;
static unsigned host_height = 0;
static size_t host_decoded_size = 0;
static unsigned char *host_encoded = 0;
static size_t host_encoded_size = 0;

static unsigned choose_width(int variant) {
    return variant != 0 ? 53u : 40u;
}

static unsigned choose_height(int variant) {
    return variant != 0 ? 37u : 28u;
}

static void fill_image(unsigned char *image, unsigned width, unsigned height, u32 seed) {
    unsigned y = 0;
    for (y = 0; y < height; y++) {
        unsigned x = 0;
        for (x = 0; x < width; x++) {
            u32 index = (u32)((y * width + x) * 4u);
            u32 mix = seed
                ^ (u32)(x * 17u)
                ^ (u32)(y * 29u)
                ^ (u32)((x * y) * 7u)
                ^ (u32)(((x << 5u) | (y << 1u)) & 0xFFu);

            image[index + 0] = (unsigned char)(mix & 0xFFu);
            image[index + 1] = (unsigned char)((mix + (u32)(x * 11u) + (u32)(y * 3u)) & 0xFFu);
            image[index + 2] = (unsigned char)(((mix >> 3u) ^ (u32)(x * 9u) ^ (u32)(y * 13u)) & 0xFFu);
            image[index + 3] = (unsigned char)(255u - ((x * 5u + y * 7u + seed) & 0x7Fu));
        }
    }
}

static int fold_bytes(const unsigned char *data, size_t size) {
    u32 hash = 0x811C9DC5u;
    size_t i = 0;

    for (i = 0; i < size; i++) {
        hash ^= (u32)data[i];
        hash *= 16777619u;
        hash = (hash << 5u) | (hash >> 27u);
    }

    return (int)hash;
}

static int run_roundtrip(unsigned width, unsigned height, u32 seed, int mode) {
    unsigned char *png = 0;
    size_t png_size = 0;
    unsigned char *decoded = 0;
    unsigned decoded_width = 0;
    unsigned decoded_height = 0;
    unsigned error = 0;
    size_t image_size = (size_t)width * (size_t)height * 4u;
    int hash = 0;

    shim_reset_heap();
    fill_image(image_a, width, height, seed);

    error = lodepng_encode32(&png, &png_size, image_a, width, height);
    if (error != 0u) {
        return -1000 - (int)error;
    }

    if (mode == 1) {
        free(png);
        return (int)png_size;
    }

    error = lodepng_decode32(&decoded, &decoded_width, &decoded_height, png, png_size);
    if (error != 0u) {
        free(png);
        return -2000 - (int)error;
    }

    if ((decoded_width != width) || (decoded_height != height)) {
        free(decoded);
        free(png);
        return -3000 - (int)(decoded_width ^ decoded_height);
    }

    if (memcmp(decoded, image_a, image_size) != 0) {
        free(decoded);
        free(png);
        return -4000;
    }

    if (mode == 2) {
        hash = fold_bytes(decoded, image_size);
        hash ^= (int)png_size;
        free(decoded);
        free(png);
        return hash;
    }

    fill_image(image_b, width, height, seed ^ 0x9E3779B9u);
    hash = fold_bytes(decoded, image_size);
    hash ^= fold_bytes(image_b, image_size);
    hash ^= (int)png_size;
    hash ^= (int)decoded_width;
    hash ^= (int)(decoded_height << 8u);

    free(decoded);
    free(png);

    return hash;
}

int lodepng_roundtrip_hash(int variant) {
    return run_roundtrip(choose_width(variant), choose_height(variant), 0x13579BDFu, 0);
}

int lodepng_probe_encoded_size(int variant) {
    return run_roundtrip(choose_width(variant), choose_height(variant), 0x13579BDFu, 1);
}

int lodepng_probe_decode_hash(int variant) {
    return run_roundtrip(choose_width(variant), choose_height(variant), 0x13579BDFu, 2);
}

int lodepng_probe_input_hash(int variant) {
    unsigned width = choose_width(variant);
    unsigned height = choose_height(variant);
    size_t image_size = (size_t)width * (size_t)height * 4u;

    fill_image(image_a, width, height, 0x13579BDFu);

    return fold_bytes(image_a, image_size);
}

int lodepng_probe_png_hash(int variant) {
    unsigned width = choose_width(variant);
    unsigned height = choose_height(variant);
    unsigned char *png = 0;
    size_t png_size = 0;
    unsigned error = 0;
    int hash = 0;

    shim_reset_heap();
    fill_image(image_a, width, height, 0x13579BDFu);

    error = lodepng_encode32(&png, &png_size, image_a, width, height);
    if (error != 0u) {
        return -5000 - (int)error;
    }

    hash = fold_bytes(png, png_size);
    hash ^= (int)png_size;
    free(png);

    return hash;
}

void lodepng_host_reset(void) {
    shim_reset_heap();
    host_decoded = 0;
    host_width = 0;
    host_height = 0;
    host_decoded_size = 0;
    host_encoded = 0;
    host_encoded_size = 0;
}

int lodepng_host_alloc(int size) {
    void *result = 0;
    if (size <= 0) {
        return 0;
    }

    result = malloc((size_t)size);
    if (!result) {
        return 0;
    }

    return (int)(uintptr_t)result;
}

int lodepng_host_decode_png(int png_ptr, int png_size) {
    unsigned error = 0;

    if ((png_ptr == 0) || (png_size <= 0)) {
        return 999u;
    }

    host_decoded = 0;
    host_width = 0;
    host_height = 0;
    host_decoded_size = 0;

    error = lodepng_decode32(
        &host_decoded,
        &host_width,
        &host_height,
        (const unsigned char *)(uintptr_t)png_ptr,
        (size_t)png_size
    );
    if (error != 0u) {
        return (int)error;
    }

    host_decoded_size = (size_t)host_width * (size_t)host_height * 4u;
    return 0;
}

int lodepng_host_apply_debug_overlay(void) {
    unsigned x = 0;
    unsigned y = 0;

    if (!host_decoded || host_width == 0u || host_height == 0u) {
        return -1;
    }

    for (y = 0; y < host_height; y++) {
        for (x = 0; x < host_width; x++) {
            size_t index = ((size_t)y * (size_t)host_width + (size_t)x) * 4u;
            int on_diagonal = (x == y) || (x + y + 1u == host_width);
            int on_border = (x < 3u) || (y < 3u) || (x + 3u >= host_width) || (y + 3u >= host_height);

            if (on_diagonal) {
                host_decoded[index + 0] = 255u;
                host_decoded[index + 1] = 32u;
                host_decoded[index + 2] = 32u;
                host_decoded[index + 3] = 255u;
            } else if (on_border) {
                host_decoded[index + 0] = (unsigned char)((host_decoded[index + 0] + 32u) & 0xFFu);
                host_decoded[index + 1] = (unsigned char)((host_decoded[index + 1] + 96u) & 0xFFu);
                host_decoded[index + 2] = (unsigned char)(host_decoded[index + 2] / 2u);
            }
        }
    }

    return 0;
}

int lodepng_host_apply_grayscale(void) {
    size_t index = 0;

    if (!host_decoded || host_width == 0u || host_height == 0u) {
        return -1;
    }

    for (index = 0; index < host_decoded_size; index += 4u) {
        unsigned r = host_decoded[index + 0];
        unsigned g = host_decoded[index + 1];
        unsigned b = host_decoded[index + 2];
        unsigned gray = (77u * r + 150u * g + 29u * b + 128u) >> 8u;

        host_decoded[index + 0] = (unsigned char)gray;
        host_decoded[index + 1] = (unsigned char)gray;
        host_decoded[index + 2] = (unsigned char)gray;
    }

    return 0;
}

int lodepng_host_encode_decoded(void) {
    LodePNGState state;
    unsigned error = 0;

    if (!host_decoded || host_width == 0u || host_height == 0u) {
        return -1;
    }

    host_encoded = 0;
    host_encoded_size = 0;

    lodepng_state_init(&state);
    state.info_raw.colortype = LCT_RGBA;
    state.info_raw.bitdepth = 8;
    state.info_png.color.colortype = LCT_RGBA;
    state.info_png.color.bitdepth = 8;
    state.encoder.auto_convert = 0;
    state.encoder.zlibsettings.btype = 0;
    state.encoder.zlibsettings.use_lz77 = 0;
    state.encoder.zlibsettings.windowsize = 2048;

    error = lodepng_encode(&host_encoded, &host_encoded_size, host_decoded, host_width, host_height, &state);
    lodepng_state_cleanup(&state);
    if (error != 0u) {
        return (int)error;
    }

    return 0;
}

int lodepng_host_width(void) {
    return (int)host_width;
}

int lodepng_host_height(void) {
    return (int)host_height;
}

int lodepng_host_decoded_ptr(void) {
    return (int)(uintptr_t)host_decoded;
}

int lodepng_host_decoded_size(void) {
    return (int)host_decoded_size;
}

int lodepng_host_encoded_ptr(void) {
    return (int)(uintptr_t)host_encoded;
}

int lodepng_host_encoded_size(void) {
    return (int)host_encoded_size;
}

int lodepng_host_heap_size(void) {
    return (int)shim_heap_size();
}

int lodepng_host_heap_offset(void) {
    return (int)shim_heap_offset();
}

int lodepng_host_heap_peak(void) {
    return (int)shim_heap_peak();
}

int lodepng_host_last_alloc_request(void) {
    return (int)shim_last_alloc_request();
}

int lodepng_host_last_alloc_total(void) {
    return (int)shim_last_alloc_total();
}

int lodepng_host_last_failed_request(void) {
    return (int)shim_last_failed_request();
}

int lodepng_host_last_failed_total(void) {
    return (int)shim_last_failed_total();
}

int lodepng_host_error86_pos(void) {
    return (int)spider_lodepng_last_error86_pos;
}

int lodepng_host_error86_wpos(void) {
    return (int)spider_lodepng_last_error86_wpos;
}

int lodepng_host_error86_hashpos(void) {
    return (int)spider_lodepng_last_error86_hashpos;
}

int lodepng_host_error86_current_offset(void) {
    return (int)spider_lodepng_last_error86_current_offset;
}

int lodepng_host_error86_prev_offset(void) {
    return (int)spider_lodepng_last_error86_prev_offset;
}

int lodepng_host_error86_windowsize(void) {
    return (int)spider_lodepng_last_error86_windowsize;
}

int lodepng_host_error86_length(void) {
    return (int)spider_lodepng_last_error86_length;
}

int lodepng_host_error86_offset(void) {
    return (int)spider_lodepng_last_error86_offset;
}
