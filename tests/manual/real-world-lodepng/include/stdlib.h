#ifndef SPIDER_LODEPNG_STDLIB_H
#define SPIDER_LODEPNG_STDLIB_H

typedef __SIZE_TYPE__ size_t;

#ifndef NULL
#define NULL ((void *)0)
#endif

void *malloc(size_t size);
void *realloc(void *ptr, size_t size);
void *calloc(size_t count, size_t size);
void free(void *ptr);

#endif
