/* aligned(N) on a LOCAL, for N up to 16 (the x86-64 frame pointer's own
   alignment): an attribute after the name, after an array's brackets, on the
   specifiers, and an aligned typedef -- each between char locals that would
   otherwise pack it off the boundary. Prints one bit per case; gcc prints 31.
   Above 16 needs frame realignment and is still open on the ticket.
   feature-c-an-over-aligned-local-is-not-aligned */
#include <stdio.h>
#include <stdint.h>

typedef int al16_t __attribute__((aligned(16)));

static int on(void *p, int a) { return ((uintptr_t)p % (uintptr_t)a) == 0; }

static int probe(int k)
{
  char c1 = (char)k;
  int l8 __attribute__((aligned(8))) = 1;
  char c2 = (char)k;
  int l16 __attribute__((aligned(16))) = 2;
  char c3 = (char)k;
  al16_t t16 = 3;
  char c4 = (char)k;
  char buf[3] __attribute__((aligned(16)));
  char c5 = (char)k;
  __attribute__((aligned(16))) short s16 = 5;
  buf[0] = (char)(c1 + c2 + c3 + c4 + c5);
  return on(&l8, 8) + 2 * on(&l16, 16) + 4 * on(&t16, 16) + 8 * on(buf, 16) +
         16 * on(&s16, 16) + 0 * (l8 + l16 + t16 + buf[0] + s16);
}

static int deeper(int k) { char pad[3]; pad[0] = (char)k; return probe(k + pad[0]) & probe(k); }

int main(void)
{
  int i, all = 31;
  for (i = 0; i < 4; i++) all &= probe(i) & deeper(i);
  printf("%d\n", all);
  return 0;
}
