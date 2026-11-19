/* SysV x86-64 struct returns across a gcc object boundary: the CALLEE half.
   Linked against a gcc-built and a pxx-built caller (row csret_sysv): 8-byte
   INTEGER, 2-byte, (SSE,INTEGER), (SSE,SSE), 24-byte MEMORY, MEMORY with seven
   integer arguments (rdi shifts them, the last onto the stack), and a
   variadic MEMORY return (va_start must skip rdi).
   bug-c-a-struct-returned-by-value-across-a-gcc-object-boundary-crashes */
#include <stdarg.h>
struct pt { int x, y; };
struct big { long a, b, c; };
struct mix { double d; long l; };
struct dd { double a, b; };
struct sm { char c; short s; };
struct pt mkpt(int a, int b) { struct pt p = {a, b}; return p; }
struct big mkbig(long a) { struct big r = {a, a + 1, a + 2}; return r; }
struct mix mkmix(double d, long l) { struct mix m = {d, l}; return m; }
struct dd mkdd(double a, double b, int scale) { struct dd r = {a * scale, b * scale}; return r; }
struct sm mksm(int c) { struct sm r = {(char)c, (short)(c * 100)}; return r; }
struct big bigargs(long a, long b, long c, long d, long e, long f, long g) { struct big r = {a + b, c + d + e, f + g}; return r; }
struct big vsum(int n, ...) { va_list ap; struct big r = {0, 0, 0}; va_start(ap, n);
  for (int i = 0; i < n; i++) { long v = va_arg(ap, long); r.a += v; r.b += v * v; r.c = v; } va_end(ap); return r; }
