/* SPDX-License-Identifier: Zlib */
/*
 * A branch on `opt & ZERO' where opt is UNSIGNED -- the feature-flag idiom, in
 * the shape real C produces it.
 *
 * WHY THE WIDTH MATTERS, and it is the whole reason this file exists beside the
 * existing const-branch tests: the C frontend wraps every unsigned-int result
 * in its width mask, so the condition reaches the IR as
 *
 *     and( and( load opt, 0 ), 0xFFFFFFFF )
 *
 * and the one-level `x and 0' identity looked at the OUTER node, whose operands
 * are a binop and a nonzero literal. Neither is a zero, so nothing folded, the
 * arm stayed live, and the call inside it became a REAL EXTERNAL REFERENCE to a
 * symbol the configuration defines nowhere. gcc drops it at every -O level,
 * -O0 included. Measured on busybox 2026-09-02: `if (opt & OPT_2COMMAND)' in
 * archival/tar.c kept data_extract_to_command, whose translation unit that
 * config leaves out of the build, and it was the only undefined symbol left in
 * the 141-applet link.
 *
 * ROWS 3 AND 4 ARE THE POSITIVE CONTROL AND THEY ASSERT WHAT MUST SURVIVE, not
 * what must vanish -- which is the row shape that caught the first cut of this
 * fold deleting a call the program was supposed to make. `bump() & 0' is still
 * false, so the arm is still dead, but the CALL IS NOT: C evaluates both
 * operands of `&', so the counter must reach 1. A fold that reasons only about
 * the branch and not about the operands passes every "the arm is gone" row and
 * fails these two.
 *
 * Row 5 is the other side: a longer chain, whose zero is two ANDs down, must
 * still fold. THE BOUNDARY IS NAMED RATHER THAN TESTED -- a chain with a CAST
 * in it, `(opt & OPT_OFF) & (unsigned)n', does NOT fold, because the discarded
 * sibling is a conversion node and the purity allowlist walks only ANDs. That
 * is deliberate conservatism, not an oversight: being wrong about what may be
 * discarded deletes a call the program was supposed to make, and no real code
 * has asked for it yet. It cannot be asserted here, because asserting that a
 * reference SURVIVES means shipping a program that will not start.
 *
 * If the fold does not fire, the missing symbol is what says so -- the program
 * either fails to link or dies before main -- so a clean run IS the assertion.
 *
 * Diffed against gcc by compiling this same file with it.
 * feature-c-corpus-busybox-multi-applet
 */
#include <stdio.h>

/* Declared, never defined, referenced only from arms that must not survive. */
extern int never_defined_dead_arm_a(void);
extern int never_defined_dead_arm_b(void);
extern int never_defined_dead_arm_c(void);

enum {
  OPT_OFF = 0,          /* the IF_FEATURE_X() expansion when X is off */
  OPT_ON  = 1 << 2
};

static int bumps = 0;
static unsigned bump(void) { bumps++; return 7u; }

int main(int argc, char **argv) {
  unsigned opt = (unsigned)argc;   /* unsigned: the width mask is the point */
  int wide;
  (void)argv;

  if (opt & OPT_OFF)
    printf("unreachable %d\n", never_defined_dead_arm_a());
  printf("1 %d\n", (int)(opt & OPT_ON ? 1 : 0));

  /* the same thing written as a plain int, which folded before this fix */
  wide = (int)argc;
  if (wide & OPT_OFF)
    printf("unreachable %d\n", never_defined_dead_arm_b());
  printf("2 %d\n", wide > 0);

  /* THE CONTROL: dead arm, live operand. */
  if (bump() & OPT_OFF)
    printf("unreachable\n");
  printf("3 %d\n", bumps);
  if (bump() & (unsigned)OPT_OFF)
    printf("unreachable\n");
  printf("4 %d\n", bumps);

  /* a longer chain, zero two ANDs down */
  if ((opt & OPT_OFF) & 0xF0u)
    printf("unreachable %d\n", never_defined_dead_arm_c());
  printf("5 done\n");
  return 0;
}
