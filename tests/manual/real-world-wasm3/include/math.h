#ifndef REAL_WORLD_WASM3_MATH_H
#define REAL_WORLD_WASM3_MATH_H

#ifndef HUGE_VAL
#define HUGE_VAL (1.0 / 0.0)
#endif

#ifndef NAN
#define NAN (0.0 / 0.0)
#endif

#ifndef INFINITY
#define INFINITY (1.0 / 0.0)
#endif

#ifdef __cplusplus
extern "C" {
#endif

double fabs(double x);
float fabsf(float x);
double ceil(double x);
float ceilf(float x);
double floor(double x);
float floorf(float x);
double sqrt(double x);
float sqrtf(float x);
double trunc(double x);
float truncf(float x);
double copysign(double x, double y);
float copysignf(float x, float y);
double rint(double x);
float rintf(float x);
int isnan(double x);
int signbit(double x);

#ifdef __cplusplus
}
#endif

#endif
