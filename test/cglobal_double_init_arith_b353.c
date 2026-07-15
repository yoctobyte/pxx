/* Regression: compile-time arithmetic in a double/float global initializer
   must fold in Double, not silently become 0.0 (bug-a-double-global-
   initializer-arithmetic-folds-to-zero). A bare literal always worked; any
   binary op (+ - * /) on float leaves used to be skipped, leaving the global
   at its 0.0 bss default. */
static double b = 1.0 / 4.0;      /* 0.25   */
static double c = 1024.0 - 0.5;   /* 1023.5 */
static double f = 2.0 * 3.0;      /* 6.0    */
static double n = -1.0 / 4.0;     /* -0.25  */
static double m = 100.0 / 255.0;  /* 100/255 */
static double e = 3 + 0.5;        /* mixed int/float = 3.5 */
static float  s = 1.0f / 3.0f;    /* narrows to float 0.333... */

int main(void) {
  if (b != 0.25)      return 1;
  if (c != 1023.5)    return 2;
  if (f != 6.0)       return 3;
  if (n != -0.25)     return 4;
  if (m != 100.0/255.0) return 5;
  if (e != 3.5)       return 6;
  if (s <= 0.33f || s >= 0.34f) return 7;   /* float narrow of 1/3, not 0.0 */
  return 42;
}
