#ifndef REAL_WORLD_CGLTF_STDLIB_H
#define REAL_WORLD_CGLTF_STDLIB_H

#include <stddef.h>

void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);
void *calloc(size_t count, size_t size);
int abs(int value);
void abort(void);
unsigned long strtoul(const char *str, char **endptr, int base);
unsigned long long strtoull(const char *str, char **endptr, int base);

#endif
