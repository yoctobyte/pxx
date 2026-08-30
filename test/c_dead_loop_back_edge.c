/* A LOOP in dead code must not keep itself alive through its own back edge.
 *
 * Same load-bearing shape as its sibling c_const_branch_dead_arm.c and the same
 * consequence: the undefined symbols below must STAY undefined, because a
 * regression here does not produce a wrong number, it produces a binary that
 * will not START (`symbol lookup error`). Defining them would delete the test
 * while leaving it green.
 *
 * What made this survive a pass that already pruned `return 0; stmt;` is that
 * a loop is ITS OWN WITNESS: the only predecessor of the loop's top label is
 * the loop's own back-jump, which sits inside the region whose fate is being
 * decided. A pass that asks "does some jump name this label" always finds one.
 * Only reachability FROM THE ENTRY can tell the two apart.
 * bug-a-a-loop-in-dead-code-keeps-itself-alive-through-its-own-back-edge */
#include <stdio.h>

int NEVER_while(void);        /* declared, never defined, anywhere */
int NEVER_for(void);
int NEVER_whilecond(void);
int NEVER_do(void);
int NEVER_backgoto(void);

/* the shape that ALREADY worked before the fix -- the boundary row. Its whole
   job is to sit next to d1 and show the difference is the loop, not the
   unreachability: strip the `while` from d1 and you have this. */
static int d0(int x) { return x + 1; return NEVER_while(); }

static int d1(int x) { return x + 1; while (1)     { return NEVER_while(); } }
static int d2(int x) { return x + 1; for (;;)      { return NEVER_for(); } }
static int d3(int x) { return x + 1; while (x < 3) { return NEVER_whilecond(); } }
static int d4(int x) { return x + 1; do { return NEVER_do(); } while (1); }

/* A BACKWARD GOTO INTO A DEAD REGION -- the same self-witnessing shape wearing
   different syntax, and the reason this is one fix and not two: `back` is named
   only by a goto that is itself unreachable. It was cited as already covered by
   c_const_branch_dead_arm.c; it was not in that file, so it is here. */
static int d5(int x) { return x + 1; back: (void)NEVER_backgoto(); goto back; }

/* NEGATIVE CONTROLS. Reachability-from-entry deletes strictly more than a
   reference count did, so the half of this test that matters is the half that
   proves it stops in the right place -- a pass that pruned these would be a
   miscompile, not a missed optimization. */

/* a live infinite loop, left only by a break */
static int l1(int x) { int n = 0; while (1) { n += x; if (n > 40) break; } return n; }
/* a live loop whose back edge IS a goto */
static int l2(int x) { int n = 0; loop: n++; if (n < x) goto loop; return n; }
/* a FORWARD goto over a return: `tail` sits after an unconditional transfer and
   survives ONLY because a reachable jump names it. The mirror image of d5. */
static int l3(int x) { if (x > 0) goto tail; return 100; tail: return 200; }
/* nested, with continue and break, and a switch (which lowers to a compare
   chain, so its arms are ordinary labels) */
static int l4(int x) {
  int n = 0, i;
  for (i = 0; i < 6; i++) {
    if (i == 2) continue;
    switch (i) { case 4: n += 10; break; case 5: n += 100; break; default: n += 1; }
    if (n > 200) break;
  }
  return n + x;
}

int main(void) {
  printf("%d %d %d %d %d %d\n", d0(41), d1(41), d2(41), d3(41), d4(41), d5(41));
  printf("%d %d %d %d %d %d\n", l1(7), l2(5), l3(1), l3(0), l4(0), l4(1));
  return 0;
}
