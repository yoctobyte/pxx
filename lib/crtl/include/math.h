#ifndef PXX_CRTL_MATH_H
#define PXX_CRTL_MATH_H 1

/* Double-precision C math surface used by lua/sqlite. These resolve to libm/libc
   at link time via the external-symbol path; the declarations let the C frontend
   parse calls to them as functions rather than rejecting them as undeclared. */

extern double fabs(double x);
extern double floor(double x);
extern double ceil(double x);
extern double trunc(double x);
extern double round(double x);
extern double sqrt(double x);
extern double cbrt(double x);
extern double sin(double x);
extern double cos(double x);
extern double tan(double x);
extern double asin(double x);
extern double acos(double x);
extern double atan(double x);
extern double atan2(double y, double x);
extern double sinh(double x);
extern double cosh(double x);
extern double tanh(double x);
extern double exp(double x);
extern double exp2(double x);
extern double log(double x);
extern double log2(double x);
extern double log10(double x);
extern double pow(double x, double y);
extern double fmod(double x, double y);
extern double frexp(double x, int *e);
extern double ldexp(double x, int e);
extern double modf(double x, double *iptr);
extern double hypot(double x, double y);
extern double copysign(double x, double y);
extern double nextafter(double x, double y);

extern int isnan(double x);
extern int isinf(double x);

/* HUGE_VAL: positive double overflow value used by lua for range checks. */
#define HUGE_VAL (1e308 * 10.0)
#define INFINITY (1e308 * 10.0)
#define NAN      (0.0 / 0.0)

#endif
