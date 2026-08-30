/* The ONE `__has_include` row where pxx deliberately diverges from gcc, kept
 * out of chas_include.c so that file stays gcc-compilable and can be run
 * through tools/gcc_diff_probe.sh.
 *
 * gcc REJECTS an operand that does not expand to a header-name --
 * `error: operator '__has_include' requires a header-name` -- and pxx answers
 * 0. That is the "we accept a form the reference rejects" row of the compat
 * table (CLAUDE.md), not a defect: no program gcc accepts can observe the
 * difference, because gcc refuses to compile every program that contains one.
 *
 * It is asserted rather than merely allowed, because "answers 0", "errors" and
 * "loops forever" are indistinguishable from a test that never runs it -- and
 * the operand goes through the macro expander, which is where a loop would
 * live. */

#include <stdio.h>

#define CHAS_BAD_MACRO     12 + 3
#define CHAS_UNTERM_MACRO  <stdio.h

#if __has_include(CHAS_BAD_MACRO)
static const int macro_bad = 1;
#else
static const int macro_bad = 0;
#endif

/* an operand that STARTS like a header-name and never closes: the expander
   must not run to the end of the buffer and call it a name */
#if __has_include(CHAS_UNTERM_MACRO)
static const int macro_unterm = 1;
#else
static const int macro_unterm = 0;
#endif

int main(void) {
  printf("lax %d %d\n", macro_bad, macro_unterm);
  return 0;
}
