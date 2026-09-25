/* POSIX random/srandom share rand's generator and state, as in glibc. The
   sequence is not glibc's, so this asserts only relations: srandom(s) then
   random() gives what srand(s) then rand() gives, the range is [0, 2^31-1],
   and a reseed repeats. busybox kconfig's conf.c calls random(). */
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  int i, same = 1, inrange = 1, repeat = 1;
  long r[8];
  srandom(42);
  for (i = 0; i < 8; i++) { r[i] = random(); if (r[i] < 0 || r[i] > 2147483647L) inrange = 0; }
  srand(42);
  for (i = 0; i < 8; i++) if ((long)rand() != r[i]) same = 0;
  srandom(42);
  for (i = 0; i < 8; i++) if (random() != r[i]) repeat = 0;
  printf("same-as-rand %d in-range %d repeats %d\n", same, inrange, repeat);
  return 0;
}
