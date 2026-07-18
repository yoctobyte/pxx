/* Regression: a signed vs unsigned 64-bit comparison must follow C's usual
   arithmetic conversions — at equal rank the signed operand converts to
   unsigned, so the comparison is UNSIGNED. pxx compared signed and produced
   wrong results (csmith seeds 5038/5194/8020: `int64 > 0UL` etc). Exit 42. */
#include <stdint.h>
int main(void){
  int64_t n = -1;
  int64_t big = 0x8C66F5A9C4C8D3C8LL;   /* negative */
  uint64_t z = 0, one = 1;
  /* n as uint64 is huge, so > 0 and >= any small unsigned; < small is false */
  if ((n > z) == 1 && (big > z) == 1 && (n < one) == 0 &&
      (n > (int64_t)0) == 0 &&          /* both signed: -1 > 0 -> 0 (unchanged) */
      (big < z) == 0)
    return 42;
  return 0;
}
