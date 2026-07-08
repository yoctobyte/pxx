/* Regression (bug-c-sizeof-widening-cast-expr): sizeof of a general expression
 * hardcoded 4 for every integer type, so `sizeof((long)1)` was 4 not 8 (and
 * short/char were 4 too). C sizeof does not promote its operand — the size is
 * that of the operand's own type. Fixed to use TypeSize for ordinals (keeping 4
 * for C's int-typed `!`/comparison results). Returns 42. */
#include <stdio.h>
int main(void) {
  int f = 0;
  if (sizeof((long)1)               != sizeof(long))      f++;
  if (sizeof((long long)1)          != sizeof(long long)) f++;
  if (sizeof((unsigned long)1)      != sizeof(long))      f++;
  if (sizeof((char)1)               != 1)                 f++;
  if (sizeof((short)1)              != 2)                 f++;
  if (sizeof((int)1)                != 4)                 f++;
  if (sizeof(1 == 1)                != 4)                 f++;   /* comparison -> int */
  if (sizeof(!f)                    != 4)                 f++;   /* logical-not -> int */
  if (sizeof((long)1 + 0)           != sizeof(long))      f++;   /* +0 keeps long here */
  if (f) { printf("f=%d\n", f); return f; }
  return 42;
}
