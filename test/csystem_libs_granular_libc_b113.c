/* Granular --system-libs=c: libc symbols are real imports, while math.h still
   uses PXX's bundled/Pascal math path. Structural DT_NEEDED test only: the
   whole-program C libc external-call runtime path predates this ticket and is
   not the behavior under test here. */
#include <math.h>
#include <stdlib.h>

int main(void) {
  return (int)sqrt(16.0) + abs(-3);
}
