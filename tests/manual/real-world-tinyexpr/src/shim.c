#include <stddef.h>
#include <stdint.h>

static unsigned char heap[1024 * 256];
static size_t heap_offset = 0;

void *malloc(size_t size);
void *memset(void *dest, int value, size_t count);
int isspace(int c);
int isdigit(int c);
int isalpha(int c);

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

    void *result = heap + heap_offset;
    heap_offset += aligned;
    return result;
}

void free(void *ptr) {
    (void)ptr;
}

void *calloc(size_t count, size_t size) {
    size_t total = count * size;
    void *result = malloc(total);
    if (result != 0) {
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
    size_t len = 0;
    while (text[len] != '\0') {
        len++;
    }
    return len;
}

int strncmp(const char *lhs, const char *rhs, size_t count) {
    size_t i = 0;
    for (i = 0; i < count; i++) {
        const unsigned char left = (const unsigned char)lhs[i];
        const unsigned char right = (const unsigned char)rhs[i];
        if ((left != right) || (left == '\0') || (right == '\0')) {
            return (int)left - (int)right;
        }
    }
    return 0;
}

double strtod(const char *text, char **endptr) {
    const char *cursor = text;
    double sign = 1.0;
    double whole = 0.0;
    double fraction = 0.0;
    double scale = 1.0;
    int exponent_sign = 1;
    int exponent_value = 0;

    while (isspace((unsigned char)*cursor)) {
        cursor++;
    }

    if (*cursor == '+') {
        cursor++;
    } else if (*cursor == '-') {
        sign = -1.0;
        cursor++;
    }

    while (isdigit((unsigned char)*cursor)) {
        whole = (whole * 10.0) + (double)(*cursor - '0');
        cursor++;
    }

    if (*cursor == '.') {
        cursor++;
        while (isdigit((unsigned char)*cursor)) {
            fraction = (fraction * 10.0) + (double)(*cursor - '0');
            scale *= 10.0;
            cursor++;
        }
    }

    if ((*cursor == 'e') || (*cursor == 'E')) {
        const char *saved = cursor;
        cursor++;

        if (*cursor == '+') {
            cursor++;
        } else if (*cursor == '-') {
            exponent_sign = -1;
            cursor++;
        }

        if (!isdigit((unsigned char)*cursor)) {
            cursor = saved;
        } else {
            while (isdigit((unsigned char)*cursor)) {
                exponent_value = (exponent_value * 10) + (*cursor - '0');
                cursor++;
            }
        }
    }

    if (endptr != 0) {
        *endptr = (char *)cursor;
    }

    whole = sign * (whole + (fraction / scale));
    while (exponent_value > 0) {
        whole = exponent_sign > 0 ? (whole * 10.0) : (whole / 10.0);
        exponent_value--;
    }

    return whole;
}

int isspace(int c) {
    return (c == ' ') || (c == '\n') || (c == '\r') || (c == '\t') || (c == '\v') || (c == '\f');
}

int isdigit(int c) {
    return (c >= '0') && (c <= '9');
}

int isalpha(int c) {
    return ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z'));
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
    for (i = 1; i < 20; i += 2) {
        result += 2.0 * term / (double)i;
        term *= y2;
    }

    return result;
}

double log10(double value) {
    return log(value) / 2.30258509299404568402;
}

double sin(double value) {
    double x = wrap_pi(value);
    double x2 = x * x;
    return x * (1.0 - (x2 / 6.0) + (x2 * x2 / 120.0) - (x2 * x2 * x2 / 5040.0));
}

double cos(double value) {
    double x = wrap_pi(value);
    double x2 = x * x;
    return 1.0 - (x2 / 2.0) + (x2 * x2 / 24.0) - (x2 * x2 * x2 / 720.0);
}

double tan(double value) {
    double c = cos(value);
    if ((c < 0.000001) && (c > -0.000001)) {
        return 0.0;
    }
    return sin(value) / c;
}

double atan(double value) {
    double x = value;
    double x2 = 0.0;
    double result = 0.0;
    if (value > 1.0) {
        return 1.57079632679489661923 - atan(1.0 / value);
    }
    if (value < -1.0) {
        return -1.57079632679489661923 - atan(1.0 / value);
    }

    x2 = x * x;
    result = x;
    result -= (x * x2) / 3.0;
    result += (x * x2 * x2) / 5.0;
    result -= (x * x2 * x2 * x2) / 7.0;
    result += (x * x2 * x2 * x2 * x2) / 9.0;
    return result;
}

double atan2(double y, double x) {
    if (x > 0.0) {
        return atan(y / x);
    }
    if ((x < 0.0) && (y >= 0.0)) {
        return atan(y / x) + 3.14159265358979323846;
    }
    if ((x < 0.0) && (y < 0.0)) {
        return atan(y / x) - 3.14159265358979323846;
    }
    if (y > 0.0) {
        return 1.57079632679489661923;
    }
    if (y < 0.0) {
        return -1.57079632679489661923;
    }
    return 0.0;
}

double asin(double value) {
    return atan2(value, sqrt(1.0 - (value * value)));
}

double acos(double value) {
    return 1.57079632679489661923 - asin(value);
}

double sinh(double value) {
    double positive = exp(value);
    double negative = exp(-value);
    return (positive - negative) * 0.5;
}

double cosh(double value) {
    double positive = exp(value);
    double negative = exp(-value);
    return (positive + negative) * 0.5;
}

double tanh(double value) {
    double positive = exp(value);
    double negative = exp(-value);
    return (positive - negative) / (positive + negative);
}

double fmod(double numerator, double denominator) {
    double quotient = 0.0;
    if (denominator == 0.0) {
        return 0.0 / 0.0;
    }
    quotient = numerator / denominator;
    if (quotient >= 0.0) {
        quotient = floor(quotient);
    } else {
        quotient = ceil(quotient);
    }
    return numerator - (quotient * denominator);
}

double pow(double base, double exponent) {
    if (base <= 0.0) {
        int64_t whole = (int64_t)exponent;
        double result = 1.0;
        int64_t i = 0;
        if ((double)whole != exponent) {
            return 0.0 / 0.0;
        }
        if (whole < 0) {
            if (base == 0.0) {
                return 0.0 / 0.0;
            }
            for (i = 0; i < -whole; i++) {
                result /= base;
            }
            return result;
        }
        for (i = 0; i < whole; i++) {
            result *= base;
        }
        return result;
    }

    return exp(exponent * log(base));
}
