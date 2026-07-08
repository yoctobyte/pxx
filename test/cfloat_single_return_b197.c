/* b197: C function returning `float` (single) returned 0 on x86-64
   (bug-c-float-single-return-zero). The cdecl callee epilogue widened the
   single Result to a double in xmm0, then the cdecl call site widened AGAIN
   (cvtss2sd), reinterpreting double bits as single -> garbage. Fixed: a cdecl
   tySingle return leaves a raw single in xmm0. Double returns and float params
   were always fine; this exercises single return direct + indirect. */

static int near(float a, float b) { float d = a - b; if (d < 0.0f) d = -d; return d < 0.001f; }

float pass(float x) { return x; }
float twice(float x) { return x + x; }
float getf(void) { return 3.5f; }
double getd(void) { return 3.5; }
typedef float (*ff)(float);

int main(void) {
    if (!near(pass(2.5f), 2.5f)) return 1;
    if (!near(twice(2.5f), 5.0f)) return 2;
    if (!near(getf(), 3.5f)) return 3;
    if (getd() != 3.5) return 4;                 /* double still fine */
    ff p = twice;
    if (!near(p(3.0f), 6.0f)) return 5;          /* indirect through fn pointer */
    { float acc = 0.0f; int i; for (i = 0; i < 4; i++) acc = pass(acc + 1.0f);
      if (!near(acc, 4.0f)) return 6; }          /* return inside a loop (rax clobber) */
    return 42;
}
