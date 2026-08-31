/* The THIRD cell of the calling-convention table, and the one nobody had drawn.
   The other two subjects are:
     test_c_abi_pascal_caller.pas   Pascal caller  -> C callee
     c_abi_pure_c_control.c         C caller -> C callee, gate OFF (a C program)
   This one is C caller -> C callee with the gate ON: the inner calls below
   happen INSIDE a C translation unit that a Pascal program uses, where
   CProgramMode is True and CUnitOfPascalProgram is True at once. Neither other
   subject can reach it by construction, which is how b4ff9adea passed two
   independent verifications while regressing this population 1000 -> 0 on
   aarch64 and i386.

   Pascal calls only the int-taking, int-returning `cee_*` wrappers, so the
   Pascal<->C boundary carries nothing that could mask an inner disagreement.
   Every inner call is the thing under test.

   SIX shapes, because three targets fail by three different mechanisms and no
   single shape finds them all -- the same lesson the bridge subject encodes.
   (int, double) is arm32's alone: AAPCS32 puts a 64-bit argument in an EVEN
   core-register pair while the word-based convention uses (r1,r2), and arm32 is
   green on the other five. i386 needs no float at all -- its divergence is
   argument ORDER. riscv32 is clean here by construction, its prologue is not
   gated.

   Two further shapes, mix4 and eight, USED to be absent for that reason: arm32
   refused an argument block over four core registers at compile time, and a
   compile-time refusal takes the other six down with it on that target. The
   refusal is gone (bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area) and they
   are the only shapes here that reach a stack argument -- so C-to-C stack
   arguments inside a Pascal-used unit were untested until 2026-08-31.

   bug-a-the-c-abi-gate-moved-the-callee-but-not-the-intra-c-call-sites
   bug-c-a-c-function-s-calling-convention-depends-on-the-target */

static double in_dbl_first(double x, int n)          { return x * (double)n; }
static double in_int_first(int n, double x)          { return x * (double)n; }
static int    in_three_ints(int a, int b, int c)     { return a*100 + b*10 + c; }
static double in_two_dbl(double a, double b)         { return a*10.0 + b; }
static float  in_flt(float f, int n)                 { return f * (float)n; }
static int    in_dbl_arg_int_ret(double x, int n)    { return (int)(x * (double)n * 100.0); }
static double in_mix4(int i1, double d1, int i2, double d2)
{ return (double)i1*1000.0 + d1*100.0 + (double)i2*10.0 + d2; }
static int    in_eight(int a, int b, int c, int d, int e, int f, int g, int h)
{ return a*1 + b*2 + c*3 + d*4 + e*5 + f*6 + g*7 + h*8; }
struct in_pair { double hi; double lo; };
static struct in_pair in_mkpair(double a, double b)
{ struct in_pair p; p.hi = a; p.lo = b; return p; }
static double in_pairsum(double a, double b)
{ struct in_pair p = in_mkpair(a * 10.0, b); return p.hi + p.lo; }

int cee_intra_dbl_first(int n)     { return (int)(in_dbl_first(2.5, n) * 100.0); }
int cee_intra_int_first(int n)     { return (int)(in_int_first(n, 2.5) * 100.0); }
int cee_intra_three_ints(void)     { return in_three_ints(1, 2, 3); }
int cee_intra_two_dbl(void)        { return (int)(in_two_dbl(1.5, 2.5) * 100.0); }
int cee_intra_flt(int n)           { return (int)(in_flt(2.5f, n) * 100.0); }
int cee_intra_dbl_arg_int_ret(int n) { return in_dbl_arg_int_ret(2.5, n); }
int cee_intra_mix4(void)           { return (int)(in_mix4(1, 2.0, 3, 4.0) * 100.0); }
int cee_intra_eight(void)          { return in_eight(1, 2, 3, 4, 5, 6, 7, 8); }
int cee_intra_pairsum(void)        { return (int)(in_pairsum(1.5, 2.5) * 100.0); }
