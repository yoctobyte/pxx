/* libtommath's mp_word pointer walks (s_mp_montgomery_reduce_fast): *_W++ += x
   once evaluated its lvalue twice for __int128 only, stepping _W by two.
   feature-c-int128-and-attribute-mode */
#include <stdio.h>
#include <stdint.h>
typedef uint64_t mp_digit;
typedef unsigned long mp_word __attribute__((mode(TI)));
static void p(const char *n, mp_word v){ printf("%s %016llx%016llx\n", n, (unsigned long long)(v >> 64), (unsigned long long)v); }
int main(void){
  mp_digit x[4] = { 0x0FFFFFFFFFFFFFFFull, 2, 3, 4 }, n[3] = { 0x0EEEEEEEEEEEEEEEull, 5, 6 }, out[4];
  mp_word W[8] = {0}; mp_word *_W = W, *_W1; mp_digit *tmpx = x, *tmpn = n; int ix, iy;
  for (ix = 0; ix < 4; ix++) { *_W++ = *tmpx++; }
  p("a", W[0]); p("b", W[3]); printf("d %d\n", (int)(_W - W));
  mp_digit mu = 0x0123456789ABCDEFull;
  _W = W + 1; for (iy = 0; iy < 3; iy++) { *_W++ += (mp_word)mu * (mp_word)*tmpn++; }
  p("c1", W[1]); p("c2", W[2]); p("c3", W[3]);
  ix = 1; _W1 = W + ix; _W = W + ++ix;
  for (; ix < 5; ix++) { *_W++ += *_W1++ >> (mp_word)60; }
  p("e3", W[3]); p("e4", W[4]);
  tmpx = out; _W = W + 1;
  for (ix = 0; ix < 4; ix++) { *tmpx++ = *_W++ & (mp_word)0x0FFFFFFFFFFFFFFFull; }
  printf("out %llx %llx %llx %llx\n", (unsigned long long)out[0], (unsigned long long)out[1], (unsigned long long)out[2], (unsigned long long)out[3]);
  return 0; }
