/* DCE must not delete a C program's `main`.
 *
 * The C entry stub emits its call to main as a forward with a zero
 * displacement -- main has no Procs[] row when the stub is emitted -- and
 * CPatchStubCall aims it afterwards with an ABSOLUTE body address, never
 * through CallFix. So the call graph contains no edge to main and never can,
 * and a reachability pass reading only CallFix concluded main was unreachable:
 * 43 of 792 bodies live and a SIGSEGV before anything printed.
 * bug-a-dce-on-a-c-program-drops-main-because-nothing-roots-the-c-entry-path
 *
 * WHY THIS FILE HAS A CALL CHAIN RATHER THAN JUST A main(). Rooting main is
 * not enough on its own and the two failures look identical from outside if
 * the program is one function: a range that DCE merely KEEPS (because it holds
 * a stub target) is never WALKED, so main can survive with everything it calls
 * deleted underneath it. `deep3` is four calls from main and prints part of the
 * answer, so a root that does not propagate fails here and cannot fail in a
 * one-function program.
 *
 * `unreachable_by_anything` is the negative control drawn from this same file:
 * DCE must be doing real work, or the row above passes on a pass that dropped
 * nothing. The Makefile asserts the -O3 image is SMALLER as well as equal.
 */
#include <stdio.h>

static int deep3(int n) { return n * 2; }
static int deep2(int n) { return deep3(n) + 1; }
static int deep1(int n) { return deep2(n) + 1; }

/* Never called, never addressed. */
int unreachable_by_anything(int n) { return n + 999; }

int main(void) {
  printf("chain %d\n", deep1(20));
  printf("done\n");
  return 0;
}
