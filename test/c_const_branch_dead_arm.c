/* A constant `if` condition must not keep its dead arm.
 *
 * This is the pre-C11 static-assert idiom and it is everywhere in real C:
 * a helper that is DECLARED and never DEFINED, called only from a branch the
 * condition proves unreachable. gcc never references the symbol. We used to
 * emit the call, warn, link anyway -- and the binary died BEFORE main with
 * `symbol lookup error: undefined symbol`. So a regression here does not
 * produce a wrong number, it produces a program that will not START, which is
 * exactly why the undefined symbols below are load-bearing and must stay
 * undefined. Defining them would delete the test while leaving it green.
 *
 * busybox's include/xatonum.h uses the last shape verbatim, which is what
 * blocked feature-c-corpus-busybox-applet.
 * bug-a-a-constant-if-condition-keeps-its-dead-arm-and-the-binary-will-not-start */
#include <stdio.h>
#include <stdint.h>

int NEVER_stmt(void);      /* declared, never defined, anywhere */
int NEVER_if_true(void);
int NEVER_if_false(void);
int NEVER_sizeof(void);
uint32_t BUG_bb_strtou32_unimplemented(void);

/* the shape that already worked: statement-level unreachable */
static int a1(unsigned x) { return (int)x + 1; return NEVER_stmt(); }
/* the branch is never taken */
static int a2(unsigned x) { if (1) return (int)x + 1; return NEVER_if_true(); }
/* the branch is always taken */
static int a3(unsigned x) { if (0) return NEVER_if_false(); return (int)x + 1; }
/* the condition is a constant COMPARISON, not a literal -- both operands fold
   to const_int and the comparison around them did not */
static int a4(unsigned x) { if (sizeof(unsigned) == 4) return (int)x + 1; return NEVER_sizeof(); }

/* busybox's assert, verbatim in shape */
static uint32_t bb_strtou32(uint32_t v) {
  if (sizeof(uint32_t) == sizeof(unsigned)) return v + 1;
  if (sizeof(uint32_t) == sizeof(unsigned long)) return v + 2;
  return BUG_bb_strtou32_unimplemented();
}

/* NEGATIVE CONTROL: the same operators on a RUNTIME value must still branch.
   A fold that fires here would silently invert control flow, which is a worse
   defect than the one being fixed -- so these rows are the half of the test
   that says the pass is narrow rather than merely effective. */
static int r1(int x) { if (x == 4) return 100; return 200; }
static int r2(int x) { if (x != 4) return 300; return 400; }
static int r3(int x) { int n = 4; if (n == x) return 500; return 600; }

int main(void) {
  printf("%d %d %d %d %u\n", a1(41), a2(41), a3(41), a4(41), bb_strtou32(41));
  printf("%d %d %d %d %d %d\n", r1(4), r1(5), r2(4), r2(5), r3(4), r3(5));
  return 0;
}
