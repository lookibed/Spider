#ifndef REAL_WORLD_CGLTF_STRING_H
#define REAL_WORLD_CGLTF_STRING_H

#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t count);
void *memmove(void *dest, const void *src, size_t count);
void *memset(void *dest, int value, size_t count);
int memcmp(const void *lhs, const void *rhs, size_t count);

size_t strlen(const char *str);
int strcmp(const char *lhs, const char *rhs);
int strncmp(const char *lhs, const char *rhs, size_t count);
char *strncpy(char *dest, const char *src, size_t count);
char *strcpy(char *dest, const char *src);
char *strchr(const char *str, int ch);
char *strrchr(const char *str, int ch);
char *strstr(const char *haystack, const char *needle);
size_t strcspn(const char *str, const char *reject);
double strtod(const char *str, char **endptr);
int atoi(const char *str);
double atof(const char *str);

#endif
