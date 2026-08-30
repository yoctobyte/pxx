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

   A seventh shape, (double,int,double,int,double,int), is deliberately ABSENT:
   arm32 refuses it at compile time -- "argument block exceeds 4 core registers",
   bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area -- and a compile-time
   refusal would take the other six down with it on that target.

   bug-a-the-c-abi-gate-moved-the-callee-but-not-the-intra-c-call-sites
   bug-c-a-c-function-s-calling-convention-depends-on-the-target */

static double in_dbl_first(double x, int n)          { return x * (double)n; }
static double in_int_first(int n, double x)          { return x * (double)n; }
static int    in_three_ints(int a, int b, int c)     { return a*100 + b*10 + c; }
static double in_two_dbl(double a, double b)         { return a*10.0 + b; }
static float  in_flt(float f, int n)                 { return f * (float)n; }
static int    in_dbl_arg_int_ret(double x, int n)    { return (int)(x * (double)n * 100.0); }

int cee_intra_dbl_first(int n)     { return (int)(in_dbl_first(2.5, n) * 100.0); }
int cee_intra_int_first(int n)     { return (int)(in_int_first(n, 2.5) * 100.0); }
int cee_intra_three_ints(void)     { return in_three_ints(1, 2, 3); }
int cee_intra_two_dbl(void)        { return (int)(in_two_dbl(1.5, 2.5) * 100.0); }
int cee_intra_flt(int n)           { return (int)(in_flt(2.5f, n) * 100.0); }
int cee_intra_dbl_arg_int_ret(int n) { return in_dbl_arg_int_ret(2.5, n); }
