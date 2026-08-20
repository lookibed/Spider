#ifndef REAL_WORLD_CGLTF_STDIO_H
#define REAL_WORLD_CGLTF_STDIO_H

#include <stddef.h>

#ifndef SEEK_SET
#define SEEK_SET 0
#endif
#ifndef SEEK_CUR
#define SEEK_CUR 1
#endif
#ifndef SEEK_END
#define SEEK_END 2
#endif

typedef struct CgltfFile CgltfFile;
#define FILE CgltfFile

struct CgltfFile;
struct CgltfFile *fopen(const char *path, const char *mode);
int fclose(struct CgltfFile *file);
size_t fread(void *ptr, size_t size, size_t count, struct CgltfFile *file);
int fseek(struct CgltfFile *file, long offset, int origin);
long ftell(struct CgltfFile *file);
int vsnprintf(char *buf, size_t size, const char *fmt, __builtin_va_list args);

#endif
