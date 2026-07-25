#include <stddef.h>
#include <stdint.h>

#include <stdio.h>
#include "../upstream/src/jpeglib.h"
#include "sample_jpeg_data.h"

void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);
void *memcpy(void *dest, const void *src, size_t count);
void shim_reset_heap(void);

static unsigned char *host_bytes = 0;
static int host_length = 0;
static unsigned char *host_rgb = 0;
static int host_width = 0;
static int host_height = 0;
static int host_components = 0;
static int host_rgb_size = 0;

static uint32_t rotl32(uint32_t value, unsigned int shift) {
    return (value << shift) | (value >> (32u - shift));
}

static uint32_t fold_bytes(const unsigned char *bytes, int length) {
    uint32_t hash = 0x811C9DC5u;
    int index = 0;

    for (index = 0; index < length; index++) {
        hash ^= bytes[index];
        hash *= 16777619u;
        hash = rotl32(hash, 5u);
    }

    return hash;
}

static int decode_rgb(
    const unsigned char *bytes,
    unsigned long length,
    unsigned char **rgb_out,
    int *width_out,
    int *height_out,
    int *components_out
) {
    struct jpeg_decompress_struct cinfo;
    struct jpeg_error_mgr jerr;
    unsigned long row_stride = 0;
    unsigned long rgb_size = 0;
    unsigned char *rgb = 0;

    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_decompress(&cinfo);
    jpeg_mem_src(&cinfo, bytes, length);
    if (jpeg_read_header(&cinfo, TRUE) != JPEG_HEADER_OK) {
        jpeg_destroy_decompress(&cinfo);
        return 0;
    }

    cinfo.out_color_space = JCS_RGB;
    jpeg_start_decompress(&cinfo);

    row_stride = cinfo.output_width * cinfo.output_components;
    rgb_size = row_stride * cinfo.output_height;
    rgb = (unsigned char *)malloc(rgb_size);
    if (!rgb) {
        jpeg_destroy_decompress(&cinfo);
        return 0;
    }

    while (cinfo.output_scanline < cinfo.output_height) {
        JSAMPROW row_pointer[1];
        row_pointer[0] = rgb + (cinfo.output_scanline * row_stride);
        jpeg_read_scanlines(&cinfo, row_pointer, 1);
    }

    jpeg_finish_decompress(&cinfo);

    *rgb_out = rgb;
    *width_out = (int)cinfo.output_width;
    *height_out = (int)cinfo.output_height;
    *components_out = (int)cinfo.output_components;

    jpeg_destroy_decompress(&cinfo);
    return 1;
}

static int decode_host(void) {
    if (!host_bytes || host_length <= 0) {
        return 0;
    }

    host_rgb = 0;
    host_width = 0;
    host_height = 0;
    host_components = 0;
    host_rgb_size = 0;

    if (!decode_rgb(host_bytes, (unsigned long)host_length, &host_rgb, &host_width, &host_height, &host_components)) {
        return 0;
    }

    host_rgb_size = host_width * host_height * host_components;
    return 1;
}

int libjpeg_turbo_host_reset(void) {
    shim_reset_heap();
    host_bytes = 0;
    host_length = 0;
    host_rgb = 0;
    host_width = 0;
    host_height = 0;
    host_components = 0;
    host_rgb_size = 0;
    return 1;
}

int libjpeg_turbo_host_alloc(int size) {
    void *result = 0;

    if (size <= 0) {
        return 0;
    }

    result = malloc((size_t)size);
    return result ? (int)(uintptr_t)result : 0;
}

int libjpeg_turbo_host_load(int bytes_ptr, int bytes_len) {
    if (bytes_ptr == 0 || bytes_len <= 0) {
        return 0;
    }

    host_bytes = (unsigned char *)(uintptr_t)bytes_ptr;
    host_length = bytes_len;
    return 1;
}

int libjpeg_turbo_host_decode(void) {
    return decode_host();
}

int libjpeg_turbo_host_get_rgb_ptr(void) {
    return (int)(uintptr_t)host_rgb;
}

int libjpeg_turbo_host_get_rgb_size(void) {
    return host_rgb_size;
}

int libjpeg_turbo_host_get_width(void) {
    return host_width;
}

int libjpeg_turbo_host_get_height(void) {
    return host_height;
}

int libjpeg_turbo_host_get_components(void) {
    return host_components;
}

int libjpeg_turbo_decode_hash(void) {
    unsigned char *rgb = 0;
    int width = 0;
    int height = 0;
    int components = 0;

    shim_reset_heap();
    if (!decode_rgb(sample_jpeg_bytes, sample_jpeg_size, &rgb, &width, &height, &components)) {
        return -1;
    }

    return (int)fold_bytes(rgb, width * height * components);
}

int libjpeg_turbo_probe_width(void) {
    unsigned char *rgb = 0;
    int width = 0;
    int height = 0;
    int components = 0;

    shim_reset_heap();
    if (!decode_rgb(sample_jpeg_bytes, sample_jpeg_size, &rgb, &width, &height, &components)) {
        return -1;
    }

    return width;
}

int libjpeg_turbo_probe_height(void) {
    unsigned char *rgb = 0;
    int width = 0;
    int height = 0;
    int components = 0;

    shim_reset_heap();
    if (!decode_rgb(sample_jpeg_bytes, sample_jpeg_size, &rgb, &width, &height, &components)) {
        return -1;
    }

    return height;
}

int libjpeg_turbo_probe_components(void) {
    unsigned char *rgb = 0;
    int width = 0;
    int height = 0;
    int components = 0;

    shim_reset_heap();
    if (!decode_rgb(sample_jpeg_bytes, sample_jpeg_size, &rgb, &width, &height, &components)) {
        return -1;
    }

    return components;
}

int libjpeg_turbo_probe_input_hash(void) {
    return (int)fold_bytes(sample_jpeg_bytes, (int)sample_jpeg_size);
}

int libjpeg_turbo_probe_rgb_size(void) {
    unsigned char *rgb = 0;
    int width = 0;
    int height = 0;
    int components = 0;

    shim_reset_heap();
    if (!decode_rgb(sample_jpeg_bytes, sample_jpeg_size, &rgb, &width, &height, &components)) {
        return -1;
    }

    return width * height * components;
}
