#include <stddef.h>
#include <stdint.h>

#include "../include/stdio.h"
#include "../include/sys/stat.h"

typedef struct allocation_header_s {
    size_t size;
} allocation_header;

typedef struct spider_vfile_s {
    char path[96];
    unsigned char data[262144];
    size_t size;
    int exists;
} spider_vfile;

struct spider_file {
    spider_vfile *file;
    size_t pos;
    int readable;
    int writable;
    int in_use;
};

static unsigned char heap[16 * 1024 * 1024];
static size_t heap_offset = 0;

static spider_vfile vfiles[16];
static struct spider_file handles[16];

static size_t min_size(size_t lhs, size_t rhs) {
    return lhs < rhs ? lhs : rhs;
}

void *memset(void *dest, int value, size_t count);
void *memcpy(void *dest, const void *src, size_t count);
void *memmove(void *dest, const void *src, size_t count);
int memcmp(const void *lhs, const void *rhs, size_t count);
size_t strlen(const char *text);
int strcmp(const char *lhs, const char *rhs);

void reset_heap(void) {
    heap_offset = 0;
}

static void reset_handles(void) {
    size_t i = 0;
    for (i = 0; i < sizeof(handles) / sizeof(handles[0]); i++) {
        handles[i].file = 0;
        handles[i].pos = 0;
        handles[i].readable = 0;
        handles[i].writable = 0;
        handles[i].in_use = 0;
    }
}

void spider_vfs_reset(void) {
    size_t i = 0;
    for (i = 0; i < sizeof(vfiles) / sizeof(vfiles[0]); i++) {
        vfiles[i].path[0] = '\0';
        vfiles[i].size = 0;
        vfiles[i].exists = 0;
    }
    reset_handles();
}

static int string_contains(const char *text, char needle) {
    size_t i = 0;
    while (text[i] != '\0') {
        if (text[i] == needle) {
            return 1;
        }
        i++;
    }
    return 0;
}

static spider_vfile *find_file(const char *path) {
    size_t i = 0;
    for (i = 0; i < sizeof(vfiles) / sizeof(vfiles[0]); i++) {
        if (vfiles[i].exists && strcmp(vfiles[i].path, path) == 0) {
            return &vfiles[i];
        }
    }
    return 0;
}

static spider_vfile *create_file(const char *path) {
    size_t i = 0;
    size_t length = strlen(path);
    if (length + 1 > sizeof(vfiles[0].path)) {
        return 0;
    }

    for (i = 0; i < sizeof(vfiles) / sizeof(vfiles[0]); i++) {
        if (!vfiles[i].exists) {
            memcpy(vfiles[i].path, path, length + 1);
            vfiles[i].size = 0;
            vfiles[i].exists = 1;
            return &vfiles[i];
        }
    }
    return 0;
}

static spider_vfile *ensure_file(const char *path) {
    spider_vfile *file = find_file(path);
    if (file) {
        return file;
    }
    return create_file(path);
}

static struct spider_file *allocate_handle(void) {
    size_t i = 0;
    for (i = 0; i < sizeof(handles) / sizeof(handles[0]); i++) {
        if (!handles[i].in_use) {
            handles[i].in_use = 1;
            handles[i].file = 0;
            handles[i].pos = 0;
            handles[i].readable = 0;
            handles[i].writable = 0;
            return &handles[i];
        }
    }
    return 0;
}

int spider_vfs_seed_file(const char *path, const void *data, size_t size) {
    spider_vfile *file = ensure_file(path);
    if (!file || size > sizeof(file->data)) {
        return 0;
    }
    memcpy(file->data, data, size);
    file->size = size;
    return 1;
}

const unsigned char *spider_vfs_get_file_data(const char *path) {
    spider_vfile *file = find_file(path);
    if (!file) {
        return 0;
    }
    return file->data;
}

int spider_vfs_get_file_size(const char *path) {
    spider_vfile *file = find_file(path);
    if (!file) {
        return -1;
    }
    return (int)file->size;
}

FILE *fopen(const char *path, const char *mode) {
    spider_vfile *file = 0;
    struct spider_file *handle = 0;
    int wants_write = string_contains(mode, 'w');
    int wants_read = string_contains(mode, 'r');
    int wants_plus = string_contains(mode, '+');

    if (wants_write) {
        file = ensure_file(path);
        if (!file) {
            return 0;
        }
        file->size = 0;
    } else {
        file = find_file(path);
        if (!file) {
            return 0;
        }
    }

    handle = allocate_handle();
    if (!handle) {
        return 0;
    }

    handle->file = file;
    handle->pos = 0;
    handle->readable = wants_read || wants_plus;
    handle->writable = wants_write || wants_plus;
    return (FILE *)handle;
}

FILE *freopen(const char *path, const char *mode, FILE *stream) {
    struct spider_file *handle = (struct spider_file *)stream;
    FILE *fresh = fopen(path, mode);
    if (!handle) {
        return fresh;
    }
    if (!fresh) {
        return 0;
    }
    *handle = *(struct spider_file *)fresh;
    ((struct spider_file *)fresh)->in_use = 0;
    return stream;
}

int fclose(FILE *stream) {
    struct spider_file *handle = (struct spider_file *)stream;
    if (!handle) {
        return -1;
    }
    handle->in_use = 0;
    handle->file = 0;
    handle->pos = 0;
    handle->readable = 0;
    handle->writable = 0;
    return 0;
}

size_t fread(void *ptr, size_t size, size_t count, FILE *stream) {
    struct spider_file *handle = (struct spider_file *)stream;
    size_t bytes = size * count;
    size_t available = 0;
    size_t read_bytes = 0;

    if (!handle || !handle->readable || !handle->file || size == 0) {
        return 0;
    }

    if (handle->pos >= handle->file->size) {
        return 0;
    }

    available = handle->file->size - handle->pos;
    read_bytes = min_size(bytes, available);
    memcpy(ptr, handle->file->data + handle->pos, read_bytes);
    handle->pos += read_bytes;
    return read_bytes / size;
}

size_t fwrite(const void *ptr, size_t size, size_t count, FILE *stream) {
    struct spider_file *handle = (struct spider_file *)stream;
    size_t bytes = size * count;
    size_t end = 0;

    if (!handle || !handle->writable || !handle->file || size == 0) {
        return 0;
    }

    end = handle->pos + bytes;
    if (end > sizeof(handle->file->data)) {
        return 0;
    }

    memcpy(handle->file->data + handle->pos, ptr, bytes);
    handle->pos = end;
    if (end > handle->file->size) {
        handle->file->size = end;
    }
    return count;
}

long long ftello(FILE *stream) {
    struct spider_file *handle = (struct spider_file *)stream;
    if (!handle) {
        return -1;
    }
    return (long long)handle->pos;
}

int fseeko(FILE *stream, long long offset, int whence) {
    struct spider_file *handle = (struct spider_file *)stream;
    long long base = 0;
    long long target = 0;

    if (!handle || !handle->file) {
        return -1;
    }

    if (whence == SEEK_CUR) {
        base = (long long)handle->pos;
    } else if (whence == SEEK_END) {
        base = (long long)handle->file->size;
    }

    target = base + offset;
    if (target < 0 || (size_t)target > sizeof(handle->file->data)) {
        return -1;
    }

    handle->pos = (size_t)target;
    return 0;
}

int fflush(FILE *stream) {
    (void)stream;
    return 0;
}

int remove(const char *path) {
    spider_vfile *file = find_file(path);
    if (!file) {
        return -1;
    }
    file->exists = 0;
    file->size = 0;
    file->path[0] = '\0';
    return 0;
}

int stat(const char *path, struct stat *buffer) {
    spider_vfile *file = find_file(path);
    if (!file || !buffer) {
        return -1;
    }
    buffer->st_size = (long long)file->size;
    return 0;
}

void *malloc(size_t size) {
    size_t total = sizeof(allocation_header) + size;
    size_t aligned = (total + 7u) & ~(size_t)7u;
    allocation_header *header = 0;

    if ((heap_offset + aligned) > sizeof(heap)) {
        return 0;
    }

    header = (allocation_header *)(heap + heap_offset);
    header->size = size;
    heap_offset += aligned;
    return (void *)(header + 1);
}

void free(void *ptr) {
    (void)ptr;
}

void *realloc(void *ptr, size_t size) {
    allocation_header *old_header = 0;
    void *result = 0;

    if (!ptr) {
        return malloc(size);
    }

    result = malloc(size);
    if (!result) {
        return 0;
    }

    old_header = ((allocation_header *)ptr) - 1;
    memcpy(result, ptr, min_size(old_header->size, size));
    return result;
}

void *calloc(size_t count, size_t size) {
    size_t total = count * size;
    void *result = malloc(total);
    if (result) {
        memset(result, 0, total);
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

size_t strlen(const char *text) {
    size_t length = 0;
    while (text[length] != '\0') {
        length++;
    }
    return length;
}

int strcmp(const char *lhs, const char *rhs) {
    size_t i = 0;
    while (lhs[i] != '\0' && rhs[i] != '\0') {
        if (lhs[i] != rhs[i]) {
            return (int)(unsigned char)lhs[i] - (int)(unsigned char)rhs[i];
        }
        i++;
    }
    return (int)(unsigned char)lhs[i] - (int)(unsigned char)rhs[i];
}
