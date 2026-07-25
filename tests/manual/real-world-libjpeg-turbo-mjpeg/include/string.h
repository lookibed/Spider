#ifndef REAL_WORLD_LIBJPEG_TURBO_STRING_H
#define REAL_WORLD_LIBJPEG_TURBO_STRING_H

#include <stddef.h>

void *memset(void *dest, int value, size_t count);
void *memcpy(void *dest, const void *src, size_t count);
void *memmove(void *dest, const void *src, size_t count);
int memcmp(const void *lhs, const void *rhs, size_t count);
void *memchr(const void *src, int value, size_t count);
size_t strlen(const char *src);
char *strncpy(char *dest, const char *src, size_t count);

#endif
