/* Rainyday's x86-64 gcc kernel CFLAGS, given to pxx unchanged:
     -std=c11 -O2 -Wall -Wextra -ffreestanding -fno-pic -mno-red-zone
     -mcmodel=kernel -mgeneral-regs-only -fno-asynchronous-unwind-tables
     -fno-builtin -c <src> -o <obj>
   The predefines must say what gcc's would, and the object must hold what
   the flags promise: no access below rsp, no SSE register, and only
   relocations valid in the top 2 GiB (the Makefile row disassembles it).
   feature-c-accept-rainydays-gcc-kernel-cflags */
#include <stdarg.h>
#include <stddef.h>

_Static_assert(__STDC_HOSTED__ == 0, "-ffreestanding: __STDC_HOSTED__ is 0");
_Static_assert(__STDC_VERSION__ == 201112L, "-std=c11");
#ifndef __STRICT_ANSI__
#error "-std=c11 (not gnu11) defines __STRICT_ANSI__"
#endif
#ifndef __code_model_kernel__
#error "-mcmodel=kernel defines __code_model_kernel__"
#endif

struct big { long a[9]; };
static struct big tmpl = { { 1, 2, 3, 4, 5, 6, 7, 8, 9 } };
long sink;

void *memcpy(void *d, const void *s, size_t n)   /* the kernel's own: -fno-builtin */
{
  char *dp = d; const char *sp = s;
  while (n--) *dp++ = *sp++;
  return d;
}

long sum_va(int n, ...)
{
  va_list ap; long t = 0;
  va_start(ap, n);
  while (n-- > 0) t += va_arg(ap, long);
  va_end(ap);
  return t;
}

long leaf(long x) { long buf[4]; buf[x & 3] = x; return buf[x & 3] * 3; }

long copy_and_sum(void)
{
  struct big b = tmpl;
  long t = 0;
  for (int i = 0; i < 9; i++) t += b.a[i];
  sink = t;
  memcpy(&b, &tmpl, sizeof b);
  return t + sum_va(3, 1L, 2L, 3L) + leaf(t);
}
