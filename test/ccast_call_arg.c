/* Regression: a cast expression used directly as a call argument — both a
   vararg call (printf) and a plain call (g). Once failed with
   "expected C expression"; fixed pre-v171.
   bug-c-cast-as-call-arg-parse-error. */
#include <stdio.h>

int g(int x) { return x; }

int main(void) {
  double x = 20.9;
  long   t = 22;
  printf("v=%d s=%d\n", (int)x, g((int)t));   /* v=20 s=22 */
  return 0;
}
