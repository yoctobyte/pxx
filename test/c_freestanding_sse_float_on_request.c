/* --freestanding -msse2: SSE float on request (Linux CC_FLAGS_FPU; amdgpu DC/DML,
   Rainyday drivers/gpu run as processes). A variadic double is read back,
   so the XMM half of the va_list save is written.
   feature-c-freestanding-sse-float-on-request */
#include <stdarg.h>
double scale(double x, int n) { double r = x; for (int i = 0; i < n; i++) r = r * 1.5 + 0.25; return r; }
double vsum(int n, ...) { va_list ap; double s = 0; va_start(ap, n); for (int i = 0; i < n; i++) s += va_arg(ap, double); va_end(ap); return s; }
float half(float f) { return f / 2.0f; }
