#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

static unsigned char heap[1024 * 1024 * 4];
static size_t heap_offset = 0;

void shim_reset_heap(void) {
    heap_offset = 0;
}

static double abs_double(double value) {
    return value < 0.0 ? -value : value;
}

static double wrap_pi(double value) {
    const double two_pi = 6.28318530717958647692;

    while (value > 3.14159265358979323846) {
        value -= two_pi;
    }
    while (value < -3.14159265358979323846) {
        value += two_pi;
    }

    return value;
}

void *malloc(size_t size) {
    size_t aligned = (size + 7u) & ~(size_t)7u;
    if ((heap_offset + aligned) > sizeof(heap)) {
        return 0;
    }

    {
        void *result = heap + heap_offset;
        heap_offset += aligned;
        return result;
    }
}

void free(void *ptr) {
    (void)ptr;
}

void *realloc(void *ptr, size_t size) {
    void *result = malloc(size);
    if (!result) {
        return 0;
    }

    if (ptr) {
        size_t i = 0;
        unsigned char *dst = (unsigned char *)result;
        const unsigned char *src = (const unsigned char *)ptr;
        for (i = 0; i < size; i++) {
            dst[i] = src[i];
        }
    }

    return result;
}

void *calloc(size_t count, size_t size) {
    size_t total = count * size;
    void *result = malloc(total);
    if (result) {
        size_t i = 0;
        unsigned char *dst = (unsigned char *)result;
        for (i = 0; i < total; i++) {
            dst[i] = 0;
        }
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

static void swap_bytes(unsigned char *lhs, unsigned char *rhs, size_t size) {
    size_t i = 0;
    for (i = 0; i < size; i++) {
        unsigned char tmp = lhs[i];
        lhs[i] = rhs[i];
        rhs[i] = tmp;
    }
}

static void quicksort_bytes(
    unsigned char *base,
    int left,
    int right,
    size_t size,
    int (*compare)(const void *, const void *)
) {
    int i = left;
    int j = right;
    unsigned char *pivot = base + (((left + right) / 2) * (int)size);

    while (i <= j) {
        while (compare(base + (i * (int)size), pivot) < 0) {
            i++;
        }
        while (compare(base + (j * (int)size), pivot) > 0) {
            j--;
        }

        if (i <= j) {
            swap_bytes(base + (i * (int)size), base + (j * (int)size), size);
            i++;
            j--;
        }
    }

    if (left < j) {
        quicksort_bytes(base, left, j, size, compare);
    }
    if (i < right) {
        quicksort_bytes(base, i, right, size, compare);
    }
}

void qsort(void *base, size_t count, size_t size, int (*compare)(const void *, const void *)) {
    if (!base || count < 2 || size == 0 || !compare) {
        return;
    }

    quicksort_bytes((unsigned char *)base, 0, (int)count - 1, size, compare);
}

double fabs(double value) {
    return abs_double(value);
}

double floor(double value) {
    int64_t whole = (int64_t)value;
    if (((double)whole > value) && (value < 0.0)) {
        whole -= 1;
    }
    return (double)whole;
}

double ceil(double value) {
    int64_t whole = (int64_t)value;
    if (((double)whole < value) && (value > 0.0)) {
        whole += 1;
    }
    return (double)whole;
}

double fmod(double x, double y) {
    int64_t quotient = 0;
    if (y == 0.0) {
        return 0.0 / 0.0;
    }

    quotient = (int64_t)(x / y);
    return x - ((double)quotient * y);
}

double sqrt(double value) {
    double guess = 0.0;
    int i = 0;

    if (value < 0.0) {
        return 0.0 / 0.0;
    }
    if (value == 0.0) {
        return 0.0;
    }

    guess = value > 1.0 ? value : 1.0;
    for (i = 0; i < 24; i++) {
        guess = 0.5 * (guess + value / guess);
    }
    return guess;
}

double sin(double value) {
    double x = wrap_pi(value);
    double x2 = x * x;

    return x * (1.0 - (x2 / 6.0) + ((x2 * x2) / 120.0) - ((x2 * x2 * x2) / 5040.0));
}

double cos(double value) {
    double x = wrap_pi(value);
    double x2 = x * x;

    return 1.0 - (x2 / 2.0) + ((x2 * x2) / 24.0) - ((x2 * x2 * x2) / 720.0);
}

static double atan_approx(double value) {
    double abs_value = abs_double(value);
    if (abs_value > 1.0) {
        double inner = atan_approx(1.0 / abs_value);
        return value > 0.0
            ? 1.57079632679489661923 - inner
            : -1.57079632679489661923 + inner;
    }

    return value / (1.0 + 0.28 * value * value);
}

double atan2(double y, double x) {
    if (x > 0.0) {
        return atan_approx(y / x);
    }
    if (x < 0.0) {
        return y >= 0.0
            ? atan_approx(y / x) + 3.14159265358979323846
            : atan_approx(y / x) - 3.14159265358979323846;
    }
    if (y > 0.0) {
        return 1.57079632679489661923;
    }
    if (y < 0.0) {
        return -1.57079632679489661923;
    }
    return 0.0;
}

double acos(double value) {
    if (value >= 1.0) {
        return 0.0;
    }
    if (value <= -1.0) {
        return 3.14159265358979323846;
    }

    return atan2(sqrt(1.0 - value * value), value);
}

double exp(double value) {
    double sum = 1.0;
    double term = 1.0;
    int i = 0;

    if (value > 20.0) {
        value = 20.0;
    }
    if (value < -20.0) {
        value = -20.0;
    }

    for (i = 1; i <= 24; i++) {
        term *= value / (double)i;
        sum += term;
    }
    return sum;
}

double log(double value) {
    double scaled = value;
    double result = 0.0;
    double y = 0.0;
    double y2 = 0.0;
    double term = 0.0;
    int i = 0;

    if (value <= 0.0) {
        return 0.0 / 0.0;
    }

    while (scaled > 1.5) {
        scaled *= 0.5;
        result += 0.69314718055994530942;
    }
    while (scaled < 0.75) {
        scaled *= 2.0;
        result -= 0.69314718055994530942;
    }

    y = (scaled - 1.0) / (scaled + 1.0);
    y2 = y * y;
    term = y;

    for (i = 1; i < 32; i += 2) {
        result += (2.0 * term) / (double)i;
        term *= y2;
    }

    return result;
}

double pow(double base, double exponent) {
    if (base <= 0.0) {
        if (base == 0.0) {
            return exponent > 0.0 ? 0.0 : 1.0;
        }
        return 0.0 / 0.0;
    }

    return exp(log(base) * exponent);
}

#undef stderr
FILE *const stderr = (FILE *)0;

int fprintf(FILE *stream, const char *format, ...) {
    (void)stream;
    (void)format;
    return 0;
}

int vfprintf(FILE *stream, const char *format, va_list args) {
    (void)stream;
    (void)format;
    (void)args;
    return 0;
}

int fputc(int character, FILE *stream) {
    (void)character;
    (void)stream;
    return 0;
}

void abort(void) {
    for (;;) {
    }
}
