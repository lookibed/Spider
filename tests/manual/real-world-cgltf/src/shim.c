#include <stddef.h>
#include <stdint.h>

static unsigned char heap[1024 * 1024 * 2];
static size_t heap_offset = 8;

typedef struct HeapHeader {
	size_t size;
} HeapHeader;

void shim_reset_heap(void) {
	heap_offset = 8;
}

void *malloc(size_t size) {
	const size_t aligned_header = (sizeof(HeapHeader) + 7u) & ~(size_t)7u;
	const size_t aligned_size = (size + 7u) & ~(size_t)7u;
	const size_t total = aligned_header + aligned_size;
	HeapHeader *header = 0;

	if (size == 0 || (heap_offset + total) > sizeof(heap)) {
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
	const size_t aligned_header = (sizeof(HeapHeader) + 7u) & ~(size_t)7u;

	if (result && ptr) {
		unsigned char *dst = (unsigned char *)result;
		const unsigned char *src = (const unsigned char *)ptr;
		const HeapHeader *header = (const HeapHeader *)(src - aligned_header);
		size_t old_size = header->size;
		size_t copy_size = old_size < size ? old_size : size;

		for (size_t i = 0; i < copy_size; i++) {
			dst[i] = src[i];
		}
	}

	return result;
}

void *calloc(size_t count, size_t size) {
	size_t total = count * size;
	void *result = malloc(total);

	if (result) {
		for (size_t i = 0; i < total; i++) {
			((unsigned char *)result)[i] = 0;
		}
	}

	return result;
}

int abs(int value) {
	return value < 0 ? -value : value;
}

void *memcpy(void *dest, const void *src, size_t count) {
	unsigned char *out = (unsigned char *)dest;
	const unsigned char *in = (const unsigned char *)src;

	for (size_t i = 0; i < count; i++) {
		out[i] = in[i];
	}

	return dest;
}

void *memmove(void *dest, const void *src, size_t count) {
	unsigned char *out = (unsigned char *)dest;
	const unsigned char *in = (const unsigned char *)src;

	if (out == in || count == 0) {
		return dest;
	}

	if (out < in) {
		for (size_t i = 0; i < count; i++) {
			out[i] = in[i];
		}
	} else {
		for (size_t i = count; i > 0; i--) {
			out[i - 1] = in[i - 1];
		}
	}

	return dest;
}

void *memset(void *dest, int value, size_t count) {
	unsigned char *bytes = (unsigned char *)dest;

	for (size_t i = 0; i < count; i++) {
		bytes[i] = (unsigned char)value;
	}

	return dest;
}

int memcmp(const void *lhs, const void *rhs, size_t count) {
	const unsigned char *left = (const unsigned char *)lhs;
	const unsigned char *right = (const unsigned char *)rhs;

	for (size_t i = 0; i < count; i++) {
		if (left[i] != right[i]) {
			return (int)left[i] - (int)right[i];
		}
	}

	return 0;
}

size_t strlen(const char *str) {
	size_t length = 0;

	while (str[length] != 0) {
		length++;
	}

	return length;
}

int strncmp(const char *lhs, const char *rhs, size_t count) {
	for (size_t i = 0; i < count; i++) {
		if (lhs[i] != rhs[i]) {
			return (unsigned char)lhs[i] - (unsigned char)rhs[i];
		}

		if (lhs[i] == 0) {
			return 0;
		}
	}

	return 0;
}

char *strncpy(char *dest, const char *src, size_t count) {
	size_t i = 0;

	for (i = 0; i < count && src[i] != 0; i++) {
		dest[i] = src[i];
	}

	for (; i < count; i++) {
		dest[i] = 0;
	}

	return dest;
}

char *strcpy(char *dest, const char *src) {
	size_t i = 0;

	do {
		dest[i] = src[i];
	} while (src[i++] != 0);

	return dest;
}

char *strchr(const char *str, int ch) {
	while (*str != 0) {
		if (*str == (char)ch) {
			return (char *)str;
		}

		str++;
	}

	return ch == 0 ? (char *)str : 0;
}

char *strrchr(const char *str, int ch) {
	const char *last = 0;

	while (*str != 0) {
		if (*str == (char)ch) {
			last = str;
		}

		str++;
	}

	if (ch == 0) {
		return (char *)str;
	}

	return (char *)last;
}

static int is_digit(int ch) {
	return ch >= '0' && ch <= '9';
}

double strtod(const char *str, char **endptr) {
	double result = 0.0;
	double sign = 1.0;
	double fraction = 0.0;
	double fraction_div = 1.0;
	int exponent_sign = 1;
	int exponent = 0;
	int has_digits = 0;

	while (*str == ' ' || *str == '\t' || *str == '\n' || *str == '\r') {
		str++;
	}

	if (*str == '-') {
		sign = -1.0;
		str++;
	} else if (*str == '+') {
		str++;
	}

	while (is_digit(*str)) {
		result = result * 10.0 + (double)(*str - '0');
		has_digits = 1;
		str++;
	}

	if (*str == '.') {
		str++;

		while (is_digit(*str)) {
			fraction = fraction * 10.0 + (double)(*str - '0');
			fraction_div *= 10.0;
			has_digits = 1;
			str++;
		}
	}

	if (!has_digits) {
		if (endptr) {
			*(const char **)endptr = str;
		}

		return 0.0;
	}

	result += fraction / fraction_div;

	if (*str == 'e' || *str == 'E') {
		str++;

		if (*str == '-') {
			exponent_sign = -1;
			str++;
		} else if (*str == '+') {
			str++;
		}

		if (!is_digit(*str)) {
			if (endptr) {
				*(const char **)endptr = (char *)str;
			}

			return sign * result;
		}

		while (is_digit(*str)) {
			exponent = exponent * 10 + (*str - '0');
			str++;
		}
	}

	if (endptr) {
		*(const char **)endptr = (char *)str;
	}

	while (exponent > 0) {
		result *= (exponent_sign > 0) ? 10.0 : 0.1;
		exponent--;
	}

	return sign * result;
}

int atoi(const char *str) {
	return (int)strtod(str, 0);
}

double atof(const char *str) {
	return strtod(str, 0);
}

struct CgltfFile *fopen(const char *path, const char *mode) {
	(void)path;
	(void)mode;
	return 0;
}

int fclose(struct CgltfFile *file) {
	(void)file;
	return 0;
}

size_t fread(void *ptr, size_t size, size_t count, struct CgltfFile *file) {
	(void)ptr;
	(void)size;
	(void)count;
	(void)file;
	return 0;
}

int fseek(struct CgltfFile *file, long offset, int origin) {
	(void)file;
	(void)offset;
	(void)origin;
	return -1;
}

long ftell(struct CgltfFile *file) {
	(void)file;
	return -1;
}

char *strstr(const char *haystack, const char *needle) {
	size_t needle_len = strlen(needle);

	if (needle_len == 0) {
		return (char *)haystack;
	}

	while (*haystack != 0) {
		if (strncmp(haystack, needle, needle_len) == 0) {
			return (char *)haystack;
		}

		haystack++;
	}

	return 0;
}

size_t strcspn(const char *str, const char *reject) {
	size_t count = 0;

	while (str[count] != 0) {
		for (const char *r = reject; *r != 0; r++) {
			if (str[count] == *r) {
				return count;
			}
		}

		count++;
	}

	return count;
}
