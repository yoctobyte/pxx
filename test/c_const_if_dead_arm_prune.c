/* The C half of the constant-condition dead-arm prune (`if` and `while`), and the case that makes the
 * escape guard mandatory.
 *
 *     void *p = &&inside; if (0) { inside: N(); } goto *p;
 *
 * gcc, clang and tcc all KEEP `N` at every level: the label's address escaped,
 * so the arm is reachable and pruning on reachability alone silently breaks
 * computed-goto code.
 *
 * MEASURED against gcc on THIS FILE, and the -O0 row is the ruling's own claim:
 * gcc LINKS AND RUNS it at -O0 as well as -O2, printing exactly what pxx prints.
 * It could only link if gcc had already dropped the `never_arm_C` arms at -O0 —
 * i.e. gcc prunes here with no optimiser asked for, which is what makes this
 * lowering rather than an optimisation.
 *
 * MEASURED with the guard disabled: the compiler refuses this program with
 * `invalid IR label-address target (label not defined)`. So the guard can fail,
 * which is the only thing that makes its passing mean anything.
 *
 * never_arm_C is declared and never defined: the two constant-false guards
 * above it must prune, or this does not print the wrong thing, it fails to
 * start with `undefined symbol'.
 * feature-a-fold-the-consensus-dead-branch-core-at-every-level */
#include <stdio.h>
extern int never_arm_C(void);
static int hits = 0;
static void N(void) { hits++; printf("N ran\n"); }
int main(void) {
  void *p = &&inside;
  if (0) { printf("%d\n", never_arm_C()); }
  if (0 || 0 || !1) { printf("%d\n", never_arm_C()); }
  /* THE SIBLING SHAPE. The C frontend reaches the same shared AN_WHILE
   * lowering the Pascal side does, so `while (0)` must prune for exactly the
   * reason `if (0)` does -- and it did NOT until the AN_WHILE arm was added:
   * with only the AN_IF prune in place this line still died at -O0 with
   * `undefined symbol: never_arm_C` while the two `if` rows above it were
   * already clean. It prints nothing, so the oracle comparison is unchanged. */
  while (0) { printf("%d\n", never_arm_C()); }
  if (0) { inside: N(); goto after; }
  printf("skipped the arm\n");
  goto *p;
after:
  printf("hits=%d\n", hits);
  return 0;
}
