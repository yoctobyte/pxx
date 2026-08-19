/* A C function DEFINITION whose name matches a Pascal routine only
   case-insensitively must NOT seize that routine's proc entry.

   `double sqrt(double)` with a body used to land on the RTL's `Sqrt` through
   the case-insensitive cross-namespace FindProc and overwrite its BodyAddr, so
   bare `Sqrt`, `math.Sqrt` and `cmath.sqrt` ALL returned this file's 42.0 and
   the RTL's square root became unreachable by any spelling — a silent wrong
   value out of the standard library.

   `tanh` is the control on the other side: its Pascal twin was never hijacked
   (no intrinsic entry to land on), so it must keep behaving exactly as before.
   bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine */

double sqrt(double x) { return 42.0; }
double exp(double x) { return 43.0; }
double tanh(double x) { return 55.0; }

int cube(int x) { return 999; }
