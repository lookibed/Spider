#ifndef REAL_WORLD_LIBJPEG_TURBO_STDIO_H
#define REAL_WORLD_LIBJPEG_TURBO_STDIO_H

#include <stddef.h>
#include <stdarg.h>

typedef struct FILE {
    int _unused;
} FILE;

extern FILE *stderr;

size_t fread(void *buffer, size_t size, size_t count, FILE *stream);
int fprintf(FILE *stream, const char *format, ...);
int snprintf(char *buffer, size_t size, const char *format, ...);
int vsnprintf(char *buffer, size_t size, const char *format, va_list args);

#endif
