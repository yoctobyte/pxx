/* `sqrt` binds case-insensitively to the Pascal RTL `Sqrt`; that proc must keep
   its internal calling convention (double args in GP), not be re-marked cdecl by
   the C extern (which would pass them in XMM and feed the Pascal prologue garbage:
   sqrt(16)->0). pow goes via Exp/Ln, also Pascal routines. */
#include <math.h>
#include "math.c"
int main(void) {
  double s = sqrt(16.0);
  double p = pow(2.0, 10.0);
  return (s == 4.0 && p > 1023.0 && p < 1025.0) ? 42 : 1;
}
