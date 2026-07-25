#include <stddef.h>
#include <stdint.h>

#include <stdio.h>
#include "jpeglib.h"
#include "sample_mjpeg_data.h"

void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);
void *memcpy(void *dest, const void *src, size_t count);
void shim_reset_heap(void);

typedef struct MjpegFrame {
    const unsigned char *bytes;
    int length;
} MjpegFrame;

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

static uint32_t mix_hash(uint32_t accumulator, uint32_t value, int index) {
    accumulator ^= value + (uint32_t)(index * 97 + 17);
    accumulator *= 16777619u;
    accumulator = rotl32(accumulator, 7u);
    return accumulator;
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

static int next_frame(const unsigned char *bytes, int length, int *cursor, MjpegFrame *frame) {
    int start = -1;
    int index = *cursor;

    while ((index + 1) < length) {
        if (bytes[index] == 0xFFu && bytes[index + 1] == 0xD8u) {
            start = index;
            index += 2;
            break;
        }
        index += 1;
    }

    if (start < 0) {
        return 0;
    }

    while ((index + 1) < length) {
        if (bytes[index] == 0xFFu && bytes[index + 1] == 0xD9u) {
            frame->bytes = bytes + start;
            frame->length = (index + 2) - start;
            *cursor = index + 2;
            return 1;
        }
        index += 1;
    }

    return 0;
}

static int frame_at(const unsigned char *bytes, int length, int frame_index, MjpegFrame *frame) {
    int cursor = 0;
    int current = 0;

    while (next_frame(bytes, length, &cursor, frame)) {
        if (current == frame_index) {
            return 1;
        }
        current += 1;
    }

    return 0;
}

static int frame_count(const unsigned char *bytes, int length) {
    int cursor = 0;
    int count = 0;
    MjpegFrame frame;

    while (next_frame(bytes, length, &cursor, &frame)) {
        count += 1;
    }

    return count;
}

typedef struct DecodeSummary {
    uint32_t combined_hash;
    uint32_t first_hash;
    uint32_t last_hash;
    int frame_count;
    int width;
    int height;
    int components;
} DecodeSummary;

static int decode_summary(const unsigned char *bytes, int length, int frame_limit, DecodeSummary *summary) {
    int cursor = 0;
    int decoded = 0;
    MjpegFrame frame;

    summary->combined_hash = 0x811C9DC5u;
    summary->first_hash = 0u;
    summary->last_hash = 0u;
    summary->frame_count = 0;
    summary->width = 0;
    summary->height = 0;
    summary->components = 0;

    while (decoded < frame_limit && next_frame(bytes, length, &cursor, &frame)) {
        unsigned char *rgb = 0;
        int width = 0;
        int height = 0;
        int components = 0;
        uint32_t hash = 0;

        if (!decode_rgb(frame.bytes, (unsigned long)frame.length, &rgb, &width, &height, &components)) {
            return 0;
        }

        hash = fold_bytes(rgb, width * height * components);
        if (decoded == 0) {
            summary->first_hash = hash;
            summary->width = width;
            summary->height = height;
            summary->components = components;
        }
        summary->last_hash = hash;
        summary->combined_hash = mix_hash(summary->combined_hash, hash, decoded);
        summary->frame_count = decoded + 1;
        decoded += 1;
    }

    return summary->frame_count > 0;
}

int libjpeg_turbo_mjpeg_host_reset(void) {
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

int libjpeg_turbo_mjpeg_host_alloc(int size) {
    void *result = 0;

    if (size <= 0) {
        return 0;
    }

    result = malloc((size_t)size);
    return result ? (int)(uintptr_t)result : 0;
}

int libjpeg_turbo_mjpeg_host_load(int bytes_ptr, int bytes_len) {
    if (bytes_ptr == 0 || bytes_len <= 0) {
        return 0;
    }

    host_bytes = (unsigned char *)(uintptr_t)bytes_ptr;
    host_length = bytes_len;
    return 1;
}

int libjpeg_turbo_mjpeg_host_decode_frame(int frame_index) {
    MjpegFrame frame;

    host_rgb = 0;
    host_width = 0;
    host_height = 0;
    host_components = 0;
    host_rgb_size = 0;

    if (!host_bytes || host_length <= 0 || frame_index < 0) {
        return 0;
    }

    if (!frame_at(host_bytes, host_length, frame_index, &frame)) {
        return 0;
    }

    if (!decode_rgb(frame.bytes, (unsigned long)frame.length, &host_rgb, &host_width, &host_height, &host_components)) {
        return 0;
    }

    host_rgb_size = host_width * host_height * host_components;
    return 1;
}

int libjpeg_turbo_mjpeg_host_get_rgb_ptr(void) {
    return (int)(uintptr_t)host_rgb;
}

int libjpeg_turbo_mjpeg_host_get_rgb_size(void) {
    return host_rgb_size;
}

int libjpeg_turbo_mjpeg_host_get_width(void) {
    return host_width;
}

int libjpeg_turbo_mjpeg_host_get_height(void) {
    return host_height;
}

int libjpeg_turbo_mjpeg_host_get_components(void) {
    return host_components;
}

int libjpeg_turbo_mjpeg_host_get_frame_count(void) {
    if (!host_bytes || host_length <= 0) {
        return 0;
    }
    return frame_count(host_bytes, host_length);
}

int libjpeg_turbo_mjpeg_decode_hash(int frame_limit) {
    DecodeSummary summary;

    shim_reset_heap();
    if (frame_limit <= 0) {
        return -1;
    }
    if (!decode_summary(sample_mjpeg_bytes, (int)sample_mjpeg_size, frame_limit, &summary)) {
        return -1;
    }

    return (int)summary.combined_hash;
}

int libjpeg_turbo_mjpeg_probe_width(void) {
    DecodeSummary summary;

    shim_reset_heap();
    if (!decode_summary(sample_mjpeg_bytes, (int)sample_mjpeg_size, 1, &summary)) {
        return -1;
    }

    return summary.width;
}

int libjpeg_turbo_mjpeg_probe_height(void) {
    DecodeSummary summary;

    shim_reset_heap();
    if (!decode_summary(sample_mjpeg_bytes, (int)sample_mjpeg_size, 1, &summary)) {
        return -1;
    }

    return summary.height;
}

int libjpeg_turbo_mjpeg_probe_components(void) {
    DecodeSummary summary;

    shim_reset_heap();
    if (!decode_summary(sample_mjpeg_bytes, (int)sample_mjpeg_size, 1, &summary)) {
        return -1;
    }

    return summary.components;
}

int libjpeg_turbo_mjpeg_probe_frame_count(int frame_limit) {
    DecodeSummary summary;

    shim_reset_heap();
    if (frame_limit <= 0) {
        return -1;
    }
    if (!decode_summary(sample_mjpeg_bytes, (int)sample_mjpeg_size, frame_limit, &summary)) {
        return -1;
    }

    return summary.frame_count;
}

int libjpeg_turbo_mjpeg_probe_first_frame_hash(void) {
    DecodeSummary summary;

    shim_reset_heap();
    if (!decode_summary(sample_mjpeg_bytes, (int)sample_mjpeg_size, 1, &summary)) {
        return -1;
    }

    return (int)summary.first_hash;
}

int libjpeg_turbo_mjpeg_probe_last_frame_hash(int frame_limit) {
    DecodeSummary summary;

    shim_reset_heap();
    if (frame_limit <= 0) {
        return -1;
    }
    if (!decode_summary(sample_mjpeg_bytes, (int)sample_mjpeg_size, frame_limit, &summary)) {
        return -1;
    }

    return (int)summary.last_hash;
}

int libjpeg_turbo_mjpeg_probe_input_hash(void) {
    return (int)fold_bytes(sample_mjpeg_bytes, (int)sample_mjpeg_size);
}
