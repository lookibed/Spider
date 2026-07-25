#include <stdio.h>

int tinyexpr_hash(int iterations);
int tinyexpr_error_code(void);

int main(void) {
    printf("tinyexpr_hash(256) = %d\n", tinyexpr_hash(256));
    printf("tinyexpr_error_code() = %d\n", tinyexpr_error_code());
    return 0;
}
