#ifndef REAL_WORLD_H264MP4_STDIO_H
#define REAL_WORLD_H264MP4_STDIO_H

typedef struct FILE FILE;

extern FILE *stderr;

#define SEEK_SET 0
#define SEEK_END 2

int printf(const char *format, ...);
int fprintf(FILE *stream, const char *format, ...);
int snprintf(char *buffer, unsigned long size, const char *format, ...);
int fseek(FILE *stream, long offset, int origin);
long ftell(FILE *stream);
FILE *fopen(const char *filename, const char *mode);
int fclose(FILE *stream);
unsigned long fread(void *buffer, unsigned long size, unsigned long count, FILE *stream);
unsigned long fwrite(const void *buffer, unsigned long size, unsigned long count, FILE *stream);

#endif
