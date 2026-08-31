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

/* THE TWO SHAPES THAT NEED A STACK ARGUMENT AREA. Both were absent from every
   subject in this family until 2026-08-31, not because they were uninteresting
   but because arm32 REFUSED them at compile time -- "argument block exceeds 4
   core registers" -- and one compile-time refusal takes every other shape in
   the file down with it on that target. So the shapes that exercise the part of
   the ABI with no implementation were exactly the shapes nothing tested.
   bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area

   mix4's block is 32 bytes on arm32 (an int, then a double forced to an even
   word, then an int, then another aligned double), so half of it is on the
   stack AND the alignment rule is live. eight is eight plain words with no float
   at all, weighted so that ANY permutation of the four stack arguments changes
   the answer -- i386's original divergence was argument order, and an unweighted
   sum would have reported it green.

   EIGHT and not nine, deliberately: aarch64 refuses a cdecl routine with more
   than 8 integer parameters, which is its own open ticket
   (bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds)
   and NOT part of what landed here. Nine params makes every other shape in this
   file unreachable on that target, for a gap this file does not fix; eight still
   spills four words on arm32 and all eight on i386. */
double cee_mix4(int i1, double d1, int i2, double d2)
{ return (double)i1*1000.0 + d1*100.0 + (double)i2*10.0 + d2; }
int cee_eight(int a, int b, int c, int d, int e, int f, int g, int h)
{ return a*1 + b*2 + c*3 + d*4 + e*5 + f*6 + g*7 + h*8; }

/* A STRUCT RETURNED BY VALUE ACROSS A C-ABI CALL. The inner call is the shape
   under test; the wrapper returns a plain double so all three subjects in this
   family can share one expected line.

   This is crtl's own `sin`: its kernels return a two-double `crtl_dd` by value,
   and the cdecl call arms on i386, arm32 and aarch64 never set the hidden
   destination register the callee prologue reads (ecx / r12 / x8) -- so
   `sin(2)` SEGFAULTED on three targets the moment a C function always used the
   C ABI, while `sqrt(4.0)` was fine. Nothing that returns a struct had ever
   come down that path before, so the arm had no code and no test.
   bug-c-a-c-function-s-calling-convention-depends-on-the-target */
struct cee_pair { double hi; double lo; };
static struct cee_pair cee_mkpair(double a, double b)
{ struct cee_pair p; p.hi = a; p.lo = b; return p; }
double cee_pairsum(double a, double b)
{ struct cee_pair p = cee_mkpair(a * 10.0, b); return p.hi + p.lo; }

