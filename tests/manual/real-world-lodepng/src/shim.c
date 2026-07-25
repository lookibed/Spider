#include <stddef.h>
#include <stdint.h>

static unsigned char heap[1024 * 1024 * 16];
static size_t heap_offset = 0;
static size_t heap_peak = 0;
static size_t last_alloc_request = 0;
static size_t last_alloc_total = 0;
static size_t last_failed_request = 0;
static size_t last_failed_total = 0;

typedef struct HeapHeader {
    size_t size;
} HeapHeader;

void shim_reset_heap(void) {
    heap_offset = 0;
    heap_peak = 0;
    last_alloc_request = 0;
    last_alloc_total = 0;
    last_failed_request = 0;
    last_failed_total = 0;
}

void *malloc(size_t size) {
    size_t aligned_header = (sizeof(HeapHeader) + 7u) & ~(size_t)7u;
    size_t aligned_size = (size + 7u) & ~(size_t)7u;
    size_t total = aligned_header + aligned_size;
    HeapHeader *header = 0;

    last_alloc_request = size;
    last_alloc_total = total;

    if ((heap_offset + total) > sizeof(heap)) {
        last_failed_request = size;
        last_failed_total = total;
        return 0;
    }

    {
        header = (HeapHeader *)(heap + heap_offset);
        header->size = size;
        heap_offset += total;
        if (heap_offset > heap_peak) {
            heap_peak = heap_offset;
        }
        return (unsigned char *)header + aligned_header;
    }
}

void free(void *ptr) {
    (void)ptr;
}

void *realloc(void *ptr, size_t size) {
    void *result = malloc(size);
    size_t old_size = 0;
    size_t copy_size = 0;
    size_t i = 0;
    const size_t aligned_header = (sizeof(HeapHeader) + 7u) & ~(size_t)7u;

    if (!result) {
        return 0;
    }

    if (ptr) {
        unsigned char *dst = (unsigned char *)result;
        const unsigned char *src = (const unsigned char *)ptr;
        const HeapHeader *header = (const HeapHeader *)(src - aligned_header);

        old_size = header->size;
        copy_size = old_size < size ? old_size : size;

        for (i = 0; i < copy_size; i++) {
            dst[i] = src[i];
        }
    }

    return result;
}

void *calloc(size_t count, size_t size) {
    size_t total = count * size;
    void *result = malloc(total);
    if (result) {
        unsigned char *dst = (unsigned char *)result;
        size_t i = 0;
        for (i = 0; i < total; i++) {
            dst[i] = 0;
        }
    }

    return result;
}

void *memset(void *dest, int value, size_t count) {
    unsigned char *bytes = (unsigned char *)dest;
    size_t i = 0;
    for (i = 0; i < count; i++) {
        bytes[i] = (unsigned char)value;
    }
    return dest;
}

void *memcpy(void *dest, const void *src, size_t count) {
    unsigned char *out = (unsigned char *)dest;
    const unsigned char *in = (const unsigned char *)src;
    size_t i = 0;
    for (i = 0; i < count; i++) {
        out[i] = in[i];
    }
    return dest;
}

void *memmove(void *dest, const void *src, size_t count) {
    unsigned char *out = (unsigned char *)dest;
    const unsigned char *in = (const unsigned char *)src;
    size_t i = 0;

    if (out == in || count == 0) {
        return dest;
    }

    if (out < in) {
        for (i = 0; i < count; i++) {
            out[i] = in[i];
        }
    } else {
        for (i = count; i > 0; i--) {
            out[i - 1] = in[i - 1];
        }
    }

    return dest;
}

int memcmp(const void *lhs, const void *rhs, size_t count) {
    const unsigned char *left = (const unsigned char *)lhs;
    const unsigned char *right = (const unsigned char *)rhs;
    size_t i = 0;
    for (i = 0; i < count; i++) {
        if (left[i] != right[i]) {
            return (int)left[i] - (int)right[i];
        }
    }
    return 0;
}

size_t shim_heap_size(void) {
    return sizeof(heap);
}

size_t shim_heap_offset(void) {
    return heap_offset;
}

size_t shim_heap_peak(void) {
    return heap_peak;
}

size_t shim_last_alloc_request(void) {
    return last_alloc_request;
}

size_t shim_last_alloc_total(void) {
    return last_alloc_total;
}

size_t shim_last_failed_request(void) {
    return last_failed_request;
}

size_t shim_last_failed_total(void) {
    return last_failed_total;
}
