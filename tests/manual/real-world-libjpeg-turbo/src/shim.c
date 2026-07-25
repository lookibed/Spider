#include <stddef.h>
#include <stdarg.h>

static unsigned char heap[1024 * 1024 * 16];
static size_t heap_offset = 8;

typedef struct FILE {
    int _unused;
} FILE;

typedef struct HeapHeader {
    size_t size;
} HeapHeader;

static FILE stderr_file = {0};
FILE *stderr = &stderr_file;

static size_t write_decimal(char *buffer, size_t size, size_t offset, unsigned long value, int negative) {
    char digits[32];
    size_t count = 0;
    size_t index = 0;

    if (negative && offset + 1 < size) {
        buffer[offset] = '-';
    }
    if (negative) {
        offset += 1;
    }

    if (value == 0) {
        if (offset + 1 < size) {
            buffer[offset] = '0';
        }
        return offset + 1;
    }

    while (value > 0 && count < sizeof(digits)) {
        digits[count] = (char)('0' + (value % 10u));
        value /= 10u;
        count += 1;
    }

    for (index = 0; index < count; index++) {
        if (offset + index + 1 < size) {
            buffer[offset + index] = digits[count - index - 1];
        }
    }

    return offset + count;
}

void shim_reset_heap(void) {
    heap_offset = 8;
}

void *malloc(size_t size) {
    const size_t aligned_header = (sizeof(HeapHeader) + 7u) & ~(size_t)7u;
    const size_t aligned_size = (size + 7u) & ~(size_t)7u;
    const size_t total = aligned_header + aligned_size;
    HeapHeader *header = 0;

    if ((heap_offset + total) > sizeof(heap)) {
        return 0;
    }

    header = (HeapHeader *)(heap + heap_offset);
    header->size = size;
    heap_offset += total;
    return (unsigned char *)header + aligned_header;
}

void free(void *ptr) {
    (void)ptr;
}

void *realloc(void *ptr, size_t size) {
    void *result = malloc(size);
    size_t old_size = 0;
    size_t copy_size = 0;
    size_t index = 0;
    const size_t aligned_header = (sizeof(HeapHeader) + 7u) & ~(size_t)7u;

    if (!result) {
        return 0;
    }

    if (!ptr) {
        return result;
    }

    old_size = ((HeapHeader *)((unsigned char *)ptr - aligned_header))->size;
    copy_size = old_size < size ? old_size : size;
    for (index = 0; index < copy_size; index++) {
        ((unsigned char *)result)[index] = ((unsigned char *)ptr)[index];
    }

    return result;
}

void *calloc(size_t count, size_t size) {
    size_t total = count * size;
    void *result = malloc(total);
    size_t index = 0;

    if (!result) {
        return 0;
    }

    for (index = 0; index < total; index++) {
        ((unsigned char *)result)[index] = 0;
    }

    return result;
}

int abs(int value) {
    return value < 0 ? -value : value;
}

void *memset(void *dest, int value, size_t count) {
    unsigned char *bytes = (unsigned char *)dest;
    size_t index = 0;

    for (index = 0; index < count; index++) {
        bytes[index] = (unsigned char)value;
    }

    return dest;
}

void *memcpy(void *dest, const void *src, size_t count) {
    unsigned char *out = (unsigned char *)dest;
    const unsigned char *in = (const unsigned char *)src;
    size_t index = 0;

    for (index = 0; index < count; index++) {
        out[index] = in[index];
    }

    return dest;
}

void *memmove(void *dest, const void *src, size_t count) {
    unsigned char *out = (unsigned char *)dest;
    const unsigned char *in = (const unsigned char *)src;
    size_t index = 0;

    if (out == in || count == 0) {
        return dest;
    }

    if (out < in) {
        for (index = 0; index < count; index++) {
            out[index] = in[index];
        }
    } else {
        for (index = count; index > 0; index--) {
            out[index - 1] = in[index - 1];
        }
    }

    return dest;
}

int memcmp(const void *lhs, const void *rhs, size_t count) {
    const unsigned char *left = (const unsigned char *)lhs;
    const unsigned char *right = (const unsigned char *)rhs;
    size_t index = 0;

    for (index = 0; index < count; index++) {
        if (left[index] != right[index]) {
            return (int)left[index] - (int)right[index];
        }
    }

    return 0;
}

void *memchr(const void *src, int value, size_t count) {
    const unsigned char *bytes = (const unsigned char *)src;
    size_t index = 0;

    for (index = 0; index < count; index++) {
        if (bytes[index] == (unsigned char)value) {
            return (void *)(bytes + index);
        }
    }

    return 0;
}

size_t strlen(const char *src) {
    size_t count = 0;

    while (src[count] != '\0') {
        count += 1;
    }

    return count;
}

char *strncpy(char *dest, const char *src, size_t count) {
    size_t index = 0;

    for (index = 0; index < count; index++) {
        dest[index] = src[index];
        if (src[index] == '\0') {
            break;
        }
    }

    for (; index < count; index++) {
        dest[index] = '\0';
    }

    return dest;
}

int vsnprintf(char *buffer, size_t size, const char *format, va_list args) {
    size_t offset = 0;
    size_t index = 0;

    if (size == 0) {
        return 0;
    }

    while (format[index] != '\0') {
        if (format[index] != '%') {
            if (offset + 1 < size) {
                buffer[offset] = format[index];
            }
            offset += 1;
            index += 1;
            continue;
        }

        index += 1;
        if (format[index] == '%') {
            if (offset + 1 < size) {
                buffer[offset] = '%';
            }
            offset += 1;
            index += 1;
            continue;
        }

        if (format[index] == 'l') {
            index += 1;
            if (format[index] == 'd') {
                long value = va_arg(args, long);
                unsigned long magnitude = (unsigned long)(value < 0 ? -value : value);
                offset = write_decimal(buffer, size, offset, magnitude, value < 0);
                index += 1;
                continue;
            }
            if (format[index] == 'u') {
                unsigned long value = va_arg(args, unsigned long);
                offset = write_decimal(buffer, size, offset, value, 0);
                index += 1;
                continue;
            }
        }

        if (format[index] == 'd') {
            int value = va_arg(args, int);
            unsigned long magnitude = (unsigned long)(value < 0 ? -value : value);
            offset = write_decimal(buffer, size, offset, magnitude, value < 0);
            index += 1;
            continue;
        }

        if (format[index] == 'u') {
            unsigned int value = va_arg(args, unsigned int);
            offset = write_decimal(buffer, size, offset, (unsigned long)value, 0);
            index += 1;
            continue;
        }

        if (format[index] == 's') {
            const char *text = va_arg(args, const char *);
            size_t text_index = 0;

            if (!text) {
                text = "(null)";
            }

            while (text[text_index] != '\0') {
                if (offset + 1 < size) {
                    buffer[offset] = text[text_index];
                }
                offset += 1;
                text_index += 1;
            }

            index += 1;
            continue;
        }

        if (offset + 1 < size) {
            buffer[offset] = '?';
        }
        offset += 1;
    }

    if (offset >= size) {
        buffer[size - 1] = '\0';
    } else {
        buffer[offset] = '\0';
    }

    return (int)offset;
}

int snprintf(char *buffer, size_t size, const char *format, ...) {
    int written = 0;
    va_list args;

    va_start(args, format);
    written = vsnprintf(buffer, size, format, args);
    va_end(args);
    return written;
}

int fprintf(FILE *stream, const char *format, ...) {
    char buffer[512];
    int written = 0;
    va_list args;

    (void)stream;
    va_start(args, format);
    written = vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    return written;
}

size_t fread(void *buffer, size_t size, size_t count, FILE *stream) {
    (void)buffer;
    (void)size;
    (void)count;
    (void)stream;
    return 0;
}

void exit(int status) {
    (void)status;
    __builtin_trap();
}
