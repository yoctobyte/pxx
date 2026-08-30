/* Reached ONLY through test/unit_cabi_bridge.pas, whose implementation this is.
   That makes the caller Pascal-mode and the callee a bodied C function -- the
   one shape in which no `not CProgramMode` guard applies, so the C prologue and
   the Pascal call site must already agree on a convention.

   Every function's expected value is TARGET-INDEPENDENT arithmetic. That is the
   point: no cross-gcc oracle is needed (and none is installed), because
   f(2.5, 4) is 10.00 on every architecture and a target that disagrees is wrong
   by construction.

   NOTE the C names are deliberately NOT case-variants of the Pascal wrappers.
   `Mix4` calling `mix4` binds case-insensitively into infinite recursion and
   dies on the stack -- which reads exactly like an ABI crash on the targets
   that are actually correct.
   bug-c-a-c-function-s-calling-convention-depends-on-the-target */

double cee_dbl_first(double x, int n)      { return x * (double)n; }
double cee_int_first(int n, double x)      { return x * (double)n; }
int    cee_three_ints(int a, int b, int c) { return a*100 + b*10 + c; }
double cee_two_dbl(double a, double b)     { return a*10.0 + b; }
float  cee_flt(float f, int n)             { return f * (float)n; }
