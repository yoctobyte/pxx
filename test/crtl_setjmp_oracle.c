/* setjmp/longjmp and fenv against gcc, which is the oracle for this surface
   (feature-crtl-implement-libc-assumptions).

   A SEPARATE file from crtl_libc_oracle.c on purpose: longjmp unwinds out of
   the middle of the enclosing function, so folding it into a large main() with
   many live locals would make the test about that main() rather than about
   longjmp.

   Nothing here was broken when it was written -- it all matched gcc first
   time. It is gated anyway because setjmp is codegen-sensitive in a way the
   rest of the C library is not: it saves and restores the frame, so a
   register-allocation or prologue change can break it while every other test
   stays green, and the failure mode is a wild jump rather than a wrong value.
   `crtl_header_smoke.c` only proves the header COMPILES.

   The cases are the ones with a rule attached: longjmp(0) must arrive as 1,
   the unwind must cross frames, and only VOLATILE locals are guaranteed to
   survive -- which is why `keep` is volatile and why that is the only local
   this asserts anything about. */
#include <stdio.h>
#include <setjmp.h>
#include <string.h>
#include <fenv.h>
#include <math.h>

static jmp_buf env;
static int depth = 0;

static void level2(void) { longjmp(env, 42); }
static void level1(void) { depth++; level2(); depth = 999; /* not reached */ }

/* longjmp with 0 must arrive as 1 -- the classic C99 rule */
static jmp_buf z;
static void jump_zero(void) { longjmp(z, 0); }

int main(void) {
  int r = setjmp(env);
  if (r == 0) {
    level1();
    printf("unreachable\n");
  } else {
    printf("longjmp r=%d depth=%d\n", r, depth);
  }

  r = setjmp(z);
  if (r == 0) jump_zero();
  else printf("longjmp0 arrives as %d\n", r);

  /* volatile locals survive; that is the only guarantee C makes */
  volatile int keep = 7;
  static jmp_buf e3;
  if (setjmp(e3) == 0) { keep = 9; longjmp(e3, 1); }
  printf("volatile kept=%d\n", keep);

  /* fenv: the rounding mode printf's float conversion is documented to honour */
  printf("fegetround-default-is-nearest=%d\n", fegetround() == FE_TONEAREST);
  fesetround(FE_TOWARDZERO);
  printf("after-set=%d\n", fegetround() == FE_TOWARDZERO);
  fesetround(FE_TONEAREST);
  printf("restored=%d\n", fegetround() == FE_TONEAREST);

  /* nearbyint follows the mode; rint/round do not all behave alike */
  printf("round %.1f %.1f %.1f %.1f\n", round(2.5), round(-2.5), round(2.4), round(-2.4));
  printf("trunc %.1f %.1f\n", trunc(2.7), trunc(-2.7));
  printf("nearbyint %.1f %.1f\n", nearbyint(2.5), nearbyint(3.5));
  return 0;
}
