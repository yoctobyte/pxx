/* C at -O2 skips reloading a local the previous statement stored, when the
 * next statement reads it first. The value in rax is the wide one, so each
 * narrow type must still come out narrowed; against gcc.
 * feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc */
#include <stdio.h>
#include <stdbool.h>
static long wide(long v) { return v; }
static int g;
int main(void) {
  long big = wide(0x1234567890L);
  signed char sc; unsigned char uc; short ss; unsigned short us;
  int i; unsigned u; bool b; long l; int *p;
  sc = big; i = sc; printf("sc %d %d\n", sc, i);
  uc = big + 0x70; i = uc; printf("uc %d %d\n", uc, i);
  ss = big; l = ss; printf("ss %d %ld\n", ss, l);
  us = -big; l = us; printf("us %d %ld\n", us, l);
  i = big; l = i; printf("i %d %ld\n", i, l);
  u = -big; l = u; printf("u %u %ld\n", u, l);
  b = big; i = b + 1; printf("b %d %d\n", b, i);
  sc = 200; if (sc < 0) printf("neg %d\n", sc);
  uc = 300; while (uc > 40) uc = uc - 7; printf("uc2 %d\n", uc);
  p = &g; *p = 5; l = (long)(p == &g); printf("p %d %ld\n", g, l);
  i = wide(7); i = i * i; i = i - 1; printf("chain %d\n", i);
  g = 9; i = g; printf("g %d\n", i);
  return 0;
}
