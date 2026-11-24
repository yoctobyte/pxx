/* Every call leaves rsp 16-aligned, as the SysV ABI requires: each callee
   checks a local declared aligned(16), which both gcc and pxx place by the
   frame pointer (entry rsp - 16, so 0 mod 16 only when the call was
   aligned), and counts misses. (__builtin_frame_address(0) is no probe in
   pxx: it is the address of a hidden local, by design.)

   pxx used to realign rsp around every C call (18 bytes each, ~186 KB of
   the Rainyday pc kernel). A C body now aligns rsp once after its prologue
   and the code generator counts the depth (X64DepthAdd, asmtext.inc); these
   are the shapes that move the depth inside a statement: nested calls in
   arguments, stack arguments, an __int128 pad slot, varargs with doubles,
   indirect calls, ?: and && / || in arguments, a struct by value, and a
   returns-twice body, whose indirect calls keep the old realignment.
   feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc */
#include <stdio.h>
#include <stdarg.h>
#include <setjmp.h>
#include <stdint.h>

static int misses;
static int calls;

#define CHECK() do { char probe[16] __attribute__((aligned(16))); calls++; \
    probe[0] = 0; if (((uintptr_t)probe & 15) != 0) misses++; } while (0)

typedef struct { double a, b; } P2;
typedef struct { long v[5]; } Big;

static int add2(int a, int b) { CHECK(); return a + b; }
static long many(long a, long b, long c, long d, long e, long f, long g, long h, long i) {
  CHECK(); return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8 + i * 9; }
static long many8(long a, long b, long c, long d, long e, long f, long g, long h) {
  CHECK(); return a + b + c + d + e + f + g * 10 + h * 100; }
static double dsum(P2 p, double x) { CHECK(); return p.a + p.b + x; }
static long bigsum(Big b) { long s = 0; int i; CHECK(); for (i = 0; i < 5; i++) s += b.v[i]; return s; }
static long i128s(long a, long b, long c, long d, long e, long f, __int128 x, long g) {
  CHECK(); return (long)(x >> 20) + a + g; }
static double vsum(int n, ...) {
  va_list ap; double s = 0; int i;
  CHECK();
  va_start(ap, n);
  for (i = 0; i < n; i++) s += va_arg(ap, double);
  va_end(ap);
  return s;
}
static jmp_buf jb;
static void jumper(int n) { CHECK(); if (n > 2) longjmp(jb, n); jumper(n + 1); }
static int (*fp)(int, int) = add2;
static long (*fmany)(long, long, long, long, long, long, long, long, long) = many;

static int with_setjmp(void) {
  volatile int r = setjmp(jb);
  if (r == 0) jumper(0);
  return add2(r, fp(r, fp(1, add2(2, 3))));
}

int main(void) {
  P2 p = { 1.5, 2.25 };
  Big b = { { 1, 2, 3, 4, 5 } };
  int x = 3;
  printf("%d\n", add2(add2(1, 2), add2(add2(3, 4), 5)));
  printf("%ld\n", many(1, 2, 3, add2(1, 3), 5, 6, 7, many(1, 1, 1, 1, 1, 1, 1, 1, 1), 9));
  printf("%ld\n", many8(1, 2, 3, 4, 5, 6, many8(1, 1, 1, 1, 1, 1, 1, add2(1, 1)), 8));
  printf("%ld\n", fmany(1, 2, 3, 4, 5, 6, fp(3, 4), 8, many8(1, 2, 3, 4, 5, 6, 7, 8)));
  printf("%.3f %.3f\n", dsum(p, 0.5), vsum(3, 1.0, dsum(p, vsum(2, 0.25, 0.25)), 2.0));
  printf("%ld %ld\n", bigsum(b), i128s(1, 2, 3, 4, 5, 6, (__int128)add2(1, 0) << 40, add2(3, 4)));
  printf("%d %d\n", x > 2 ? add2(x, 1) : fp(x, 2), (x && add2(0, 0)) || fp(1, 1));
  printf("%d\n", with_setjmp());
  printf("%d\n", fp(fp(fp(1, 1), add2(fp(2, 2), 2)), many8(0, 0, 0, 0, 0, 0, 0, 1) > 50));
  printf("calls %d misaligned %d\n", calls, misses);
  return misses != 0;
}
