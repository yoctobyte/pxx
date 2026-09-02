/* The dead-arm prune (b8ee49996) drops a constant-false `if`/`while` body, and
   its escape guard ASTSubtreeHasLabel keeps any arm holding a label -- because
   a label is an entry point and the arm is only dead to a reader who ignores
   it. The guard enumerated AN_LABEL / AN_LABELADDR / AN_GOTO_INDIRECT and
   missed AN_CASE / AN_DEFAULT, so a `case` inside `if (0)` went with the arm
   while AN_SWITCH's dispatch still jumped to it:

       pascal26: error: invalid IR conditional jump target (label not defined)

   That took out c-testsuite 00213.c on all five conformance targets at once.
   The corpus is not in the quick tier, so this row is the probe that is.

   Rows 1-2 are the two pruning shapes, rows 3-4 are `default` and a nested
   `switch` inside a dead arm, and rows 5-6 are the CONTROL: `if (1)` and a
   bare block, which never pruned and must not start now. gcc prints the same
   six lines. Exit 42. */
extern int printf(const char *, ...);

static int r1(int i) { switch (i) { if (0) { case 41: return 1; case 42: return 2; } } return 0; }
static int r2(int i) { switch (i) { while (0) { case 41: return 1; } } return 0; }
static int r3(int i) { switch (i) { if (0) { default: return 9; case 42: return 2; } } return 0; }
static int r4(int i) { switch (i) { if (0) { case 41: switch (i) { if (0) { case 41: return 7; } } } } return 0; }
static int r5(int i) { switch (i) { if (1) { case 41: return 1; } } return 0; }
static int r6(int i) { switch (i) { { case 41: return 1; } } return 0; }

int main(void) {
  int f = 0;
  if (r1(41) != 1) f |= 1;
  if (r1(42) != 2) f |= 2;
  if (r2(41) != 1) f |= 4;
  if (r3(41) != 9) f |= 8;    /* 41 matches no case, so `default` takes it */
  if (r3(42) != 2) f |= 16;
  if (r4(41) != 7) f |= 32;
  if (r5(41) != 1) f |= 64;
  if (r6(41) != 1) f |= 128;
  printf("%d\n", f);
  return f ? f : 42;
}
