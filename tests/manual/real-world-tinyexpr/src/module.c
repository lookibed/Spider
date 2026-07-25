#include "../../real-world-tinyexpr/upstream/tinyexpr.h"

typedef unsigned int u32;
typedef unsigned long long u64;

double sqrt(double value);
int strncmp(const char *lhs, const char *rhs, unsigned int count);
int te_debug_builtin_count(void);
int te_debug_builtin_type(int index);
int te_debug_builtin_name_char(int index, int char_index);
int te_debug_builtin_name_pointer(int index);
int te_debug_builtin_address_pointer(int index);
int te_debug_find_builtin_index(const char *name, int len);
int te_debug_compare_builtin(const char *name, int len, int index);
int te_debug_find_builtin_trace_step(const char *name, int len, int step);

static u32 fold_double(double value) {
    union {
        double f64;
        u64 bits;
    } repr;

    repr.f64 = value;
    return (u32)(repr.bits ^ (repr.bits >> 32));
}

int tinyexpr_hash(int iterations) {
    static double x = 0.0;
    static double y = 0.0;
    static double z = 0.0;
    static const te_variable vars[] = {
        {"x", &x, TE_VARIABLE, 0},
        {"y", &y, TE_VARIABLE, 0},
        {"z", &z, TE_VARIABLE, 0},
    };
    static const char expr1[] = "sqrt(x*x + y*y) + sin(z/3) + cos(x/5)";
    static const char expr2[] = "log(z + 11) + abs(y - x/2) + tan((x + z)/19)";
    static const char expr3[] = "pow(x + 1.5, 1.25) / (1 + sqrt(y + 7)) + atan2(z, x + 1)";

    int error = 0;
    te_expr *compiled1 = te_compile(expr1, vars, 3, &error);
    if (!compiled1) {
        return -1000 - error;
    }

    te_expr *compiled2 = te_compile(expr2, vars, 3, &error);
    if (!compiled2) {
        te_free(compiled1);
        return -2000 - error;
    }

    te_expr *compiled3 = te_compile(expr3, vars, 3, &error);
    if (!compiled3) {
        te_free(compiled2);
        te_free(compiled1);
        return -3000 - error;
    }

    u32 hash = 0x9E3779B9u;
    int i = 0;
    for (i = 0; i < iterations; i++) {
        x = 1.0 + (double)((i * 37) % 251) / 9.0;
        y = 2.0 + (double)((i * 91 + 7) % 199) / 11.0;
        z = 3.0 + (double)((i * 53 + 17) % 173) / 13.0;

        hash = (hash << 5) | (hash >> 27);
        hash ^= fold_double(te_eval(compiled1));
        hash += 0x85EBCA6Bu;
        hash ^= fold_double(te_eval(compiled2));
        hash = (hash << 7) | (hash >> 25);
        hash += fold_double(te_eval(compiled3));
    }

    te_free(compiled3);
    te_free(compiled2);
    te_free(compiled1);

    return (int)hash;
}

int tinyexpr_error_code(void) {
    static const char broken[] = "sqrt(x + )";
    static const te_variable empty[] = {0};
    int error = 0;
    te_expr *compiled = te_compile(broken, empty, 0, &error);
    if (compiled) {
        te_free(compiled);
        return -1;
    }

    return error;
}

int tinyexpr_probe_number(void) {
    int error = 0;
    double value = te_interp("12.5", &error);
    if (error != 0) {
        return -error;
    }

    return (int)(value * 1000.0);
}

int tinyexpr_probe_builtin(void) {
    int error = 0;
    te_expr *compiled = te_compile("sqrt(4)", 0, 0, &error);
    double value = 0.0;
    if (!compiled) {
        return -error;
    }

    value = te_eval(compiled);
    te_free(compiled);
    return (int)(value * 1000.0);
}

int tinyexpr_probe_variable(void) {
    double x = 3.0;
    const te_variable vars[] = {
        {"x", &x, TE_VARIABLE, 0},
    };
    int error = 0;
    te_expr *compiled = te_compile("x+1", vars, 1, &error);
    double value = 0.0;
    if (!compiled) {
        return -error;
    }

    value = te_eval(compiled);
    te_free(compiled);
    return (int)(value * 1000.0);
}

int tinyexpr_probe_static_builtin(void) {
    static const te_variable vars[] = {
        {"sqrt", sqrt, TE_FUNCTION1 | TE_FLAG_PURE, 0},
    };
    int error = 0;
    te_expr *compiled = te_compile("sqrt(4)", vars, 1, &error);
    double value = 0.0;
    if (!compiled) {
        return -error;
    }

    value = te_eval(compiled);
    te_free(compiled);
    return (int)(value * 1000.0);
}

int tinyexpr_probe_compare_flags(void) {
    int c = strncmp("sqrt", "pi", 4);
    if (!c) {
        c = '\0' - "pi"[4];
    }

    return (c > 0 ? 1 : 0) | (c < 0 ? 2 : 0) | (c == 0 ? 4 : 0);
}

int tinyexpr_probe_mini_binary_search(void) {
    static const te_variable vars[] = {
        {"abs", sqrt, TE_FUNCTION1 | TE_FLAG_PURE, 0},
        {"atan", sqrt, TE_FUNCTION1 | TE_FLAG_PURE, 0},
        {"pow", sqrt, TE_FUNCTION1 | TE_FLAG_PURE, 0},
        {"sqrt", sqrt, TE_FUNCTION1 | TE_FLAG_PURE, 0},
        {"tanh", sqrt, TE_FUNCTION1 | TE_FLAG_PURE, 0},
    };
    int imin = 0;
    int imax = (int)(sizeof(vars) / sizeof(vars[0])) - 1;

    while (imax >= imin) {
        const int i = imin + ((imax - imin) / 2);
        int c = strncmp("sqrt", vars[i].name, 4);
        if (!c) {
            c = '\0' - vars[i].name[4];
        }

        if (c == 0) {
            return vars[i].type;
        }
        if (c > 0) {
            imin = i + 1;
        } else {
            imax = i - 1;
        }
    }

    return -1;
}

int tinyexpr_probe_builtin_count(void) {
    return te_debug_builtin_count();
}

int tinyexpr_probe_find_builtin_sqrt(void) {
    return te_debug_find_builtin_index("sqrt", 4);
}

int tinyexpr_probe_find_builtin_abs(void) {
    return te_debug_find_builtin_index("abs", 3);
}

int tinyexpr_probe_builtin_sqrt_type(void) {
    return te_debug_builtin_type(20);
}

int tinyexpr_probe_builtin_sqrt_name_prefix(void) {
    return te_debug_builtin_name_char(20, 0)
        | (te_debug_builtin_name_char(20, 1) << 8)
        | (te_debug_builtin_name_char(20, 2) << 16)
        | (te_debug_builtin_name_char(20, 3) << 24);
}

int tinyexpr_probe_builtin_sqrt_name_terminator(void) {
    return te_debug_builtin_name_char(20, 4);
}

int tinyexpr_probe_builtin_pointer_delta(void) {
    return te_debug_builtin_name_pointer(21) - te_debug_builtin_name_pointer(20);
}

int tinyexpr_probe_builtin_address_delta(void) {
    return te_debug_builtin_address_pointer(21) - te_debug_builtin_address_pointer(20);
}

int tinyexpr_probe_compare_sqrt_to(int index) {
    return te_debug_compare_builtin("sqrt", 4, index);
}

int tinyexpr_probe_find_builtin_trace_sqrt(int step) {
    return te_debug_find_builtin_trace_step("sqrt", 4, step);
}

int tinyexpr_probe_divide_s32(int value) {
    int numerator = value - 1;
    return numerator / 2;
}
