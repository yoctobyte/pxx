/* SPDX-License-Identifier: Zlib */
/*
 * longjmp must be usable as a VALUE, not only as a call.
 *
 * C 7.13: setjmp may be a macro, but longjmp SHALL be an external function.
 * crtl had function-like macros only, and those do not expand when the name is
 * not followed by '(' — so a bare `longjmp` was an undeclared identifier. Real
 * code takes its address: tcc's
 *
 *     #define tcc_setjmp(s1,jb,f) setjmp(_tcc_setjmp(s1, jb, f, longjmp))
 *
 * passes it as a function pointer, and libtcc.c stopped there
 * (feature-crtl-implement-libc-assumptions, corpus step 3).
 *
 * Both spellings are checked: through a function POINTER (the tcc shape) and as
 * an ordinary call (which still takes the macro, skipping the struct copy).
 * Exit code only, so a varargs or printf bug cannot masquerade as a jump bug.
 */

#include <setjmp.h>

static jmp_buf jb1, jb2;
static void (*lj)(jmp_buf, int) = longjmp;   /* the address-taken form */

int main(void) {
  int a, b;

  a = setjmp(jb1);
  if (a == 0) lj(jb1, 7);          /* via the pointer */
  if (a != 7) return 1;

  b = setjmp(jb2);
  if (b == 0) longjmp(jb2, 9);     /* ordinary call -> the macro */
  if (b != 9) return 2;

  return 42;
}
