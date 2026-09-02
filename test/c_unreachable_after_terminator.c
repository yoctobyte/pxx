/* STATEMENTS BEHIND AN UNCONDITIONAL TRANSFER are not emitted, at every level.
   The C half of test_unreachable_after_terminator.pas: one shared lowering in
   ir.inc, so the two frontends must agree, and gcc is the oracle -- it drops
   these with no optimiser asked for, which is what makes this LOWERING rather
   than an optimisation.

   THE C SIDE IS NOT FREE AND THAT IS WHY THIS FILE EXISTS. The prune first
   landed in the AN_SEQ spine walk only. A C function body is an AN_BLOCK,
   whose lowering walks the same cons chain ITSELF rather than handing the seq
   node to IRLowerAST, so C inherited nothing: measured at 400 unreachable
   stores, -O0 and -OO both emitted 425752B while the Pascal shape was already
   down to 89880B against -OO's 93976B. The decision now lives in one function
   (ASTSeqTailUnreachable) that both walks call.

   THE SWITCH ROWS ARE THE POINT. `case` and `default` are jump targets that
   carry no AN_LABEL node, so the first version of the label guard did not see
   them, and a `case` arm ending in `return` made the prune delete every arm
   behind it. That rejected the compiler's OWN crtl (`invalid IR conditional
   jump target (label not defined)`, lib/crtl/src/stdio.c near vsnprintf) and a
   five-line switch besides. C's fallthrough switch bodies are the population
   the guard is about; AN_LABEL alone did not cover it.

   pick() returns out of every arm, which is the shape that broke. pick2()
   breaks out of every arm instead -- Break is a terminator too, so the arm
   behind each `break` is unreachable while the CASE LABEL behind it is not. */
#include <stdio.h>

extern int never_term_C(void);
int g;

/* after return */
static void after_return(void) { g++; return; g += 100; }

/* after break: the loop body's tail is unreachable, the loop is not */
static void after_break(void) { for (int i = 0; i < 3; i++) { g++; break; g += 100; } }

/* after continue: runs all three iterations, tail unreachable each time */
static void after_continue(void) { for (int i = 0; i < 3; i++) { g++; continue; g += 100; } }

/* THE GUARD, plain goto: a label behind a return, reached from before it */
static int label_behind_return(void) {
  int n = 0;
  goto fwd;
  return -1;
fwd:
  n = 7;
  return n;
}

/* THE GUARD, switch arms ending in return -- the shape that rejected crtl */
static int pick(int x) {
  switch (x) {
    case 1: return 10;
    case 2: return 20;
    default: return 99;
  }
}

/* THE GUARD, switch arms ending in break */
static int pick2(int x) {
  int r = -1;
  switch (x) {
    case 1: r = 10; break; r = 111;
    case 2: r = 20; break; r = 222;
    default: r = 99; break; r = 333;
  }
  return r;
}

int main(void) {
  g = 0;
  after_return();
  after_break();
  after_continue();
  printf("g=%d\n", g);                       /* 1 + 1 + 3 = 5 */
  printf("lbl=%d\n", label_behind_return());
  printf("pick=%d %d %d\n", pick(1), pick(2), pick(5));
  printf("pick2=%d %d %d\n", pick2(1), pick2(2), pick2(5));
  return 0;
}
