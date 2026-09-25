/* The POSIX rand48 family (cglm's test harness calls drand48). One 48-bit LCG,
 * so the output is deterministic: diffed against glibc for fixed seeds.
 * drand48 is printed as drand48()*2^48, an exact integer, so the diff compares
 * the generator and not printf's float rounding.
 * Rows: the UNSEEDED global state (glibc starts at X=0), srand48, the
 * caller-state forms, seed48's returned previous state, and lcong48 changing
 * a and c. Values are gcc's. */
#include <stdio.h>
#include <stdlib.h>

static void row(const char *tag) {
  int i;
  printf("%s", tag);
  for (i = 0; i < 3; i++) printf(" %lld", (long long)(drand48() * 281474976710656.0));
  for (i = 0; i < 3; i++) printf(" %ld", lrand48());
  for (i = 0; i < 3; i++) printf(" %ld", mrand48());
  printf("\n");
}

int main(void) {
  unsigned short xs[3] = { 0x1234, 0xABCD, 0x0F0F };
  unsigned short s16[3] = { 1, 2, 3 };
  unsigned short lc[7] = { 5, 6, 7, 0x0005, 0, 0, 3 };
  unsigned short *old;
  int i;
  row("unseeded");
  srand48(42);
  row("srand48-42");
  srand48(-7);
  row("srand48-neg7");
  printf("caller-state");
  for (i = 0; i < 2; i++) printf(" %lld", (long long)(erand48(xs) * 281474976710656.0));
  for (i = 0; i < 2; i++) printf(" %ld", nrand48(xs));
  for (i = 0; i < 2; i++) printf(" %ld", jrand48(xs));
  printf(" x %u %u %u\n", xs[0], xs[1], xs[2]);
  old = seed48(s16);
  printf("seed48-old %u %u %u\n", old[0], old[1], old[2]);
  row("seed48");
  lcong48(lc);
  row("lcong48");
  srand48(1);
  row("srand48-resets-a-c");
  return 0;
}
