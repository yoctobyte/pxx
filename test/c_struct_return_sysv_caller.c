/* The CALLER half of c_struct_return_sysv_callee.c, direct and through a
   function pointer. bug-c-a-struct-returned-by-value-across-a-gcc-object-boundary-crashes */
#include <stdio.h>
struct pt { int x, y; };
struct big { long a, b, c; };
struct mix { double d; long l; };
struct dd { double a, b; };
struct sm { char c; short s; };
struct pt mkpt(int a, int b);
struct big mkbig(long a);
struct mix mkmix(double d, long l);
struct dd mkdd(double a, double b, int scale);
struct sm mksm(int c);
struct big bigargs(long a, long b, long c, long d, long e, long f, long g);
struct big vsum(int n, ...);
int main(void) {
  struct pt p = mkpt(3, 4);
  struct big b = mkbig(10);
  struct mix m = mkmix(2.5, 7);
  struct dd d = mkdd(1.5, 2.5, 2);
  struct sm s = mksm(5);
  struct big g = bigargs(1, 2, 3, 4, 5, 6, 7);
  struct pt (*fp)(int, int) = mkpt;
  struct big (*fb)(long) = mkbig;
  struct pt q = fp(8, 9);
  struct big h = fb(20);
  printf("pt %d %d big %ld %ld %ld mix %g %ld dd %g %g sm %d %d args %ld %ld %ld ind %d %d %ld %ld\n",
         p.x, p.y, b.a, b.b, b.c, m.d, m.l, d.a, d.b, s.c, s.s, g.a, g.b, g.c, q.x, q.y, h.a, h.c);
  struct big v = vsum(3, 2L, 3L, 4L);
  printf("vsum %ld %ld %ld\n", v.a, v.b, v.c);
  return 0;
}
