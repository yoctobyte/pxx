/* Regression: C integer promotions — two sub-int operands promote to signed int
   before comparison, so `(int8)-57 >= (uint16)0` is a SIGNED compare (false), not
   unsigned. pxx compared unsigned via the wider-operand rule (csmith seed 31039).
   Exit 42. */
#include <stdint.h>
static int8_t a = -57;
static uint16_t b = 0;
static uint8_t c = 200;
static int16_t d = -1;
static uint16_t e = 300;
int main(void){
  if ((a >= b) == 0 &&      /* -57 >= 0 signed -> false */
      (c > d) == 1 &&       /* 200 > -1 signed -> true */
      (d < e) == 1 &&       /* -1 < 300 signed -> true */
      (a < b) == 1)         /* -57 < 0 -> true */
    return 42;
  return 0;
}
