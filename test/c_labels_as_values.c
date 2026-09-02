/* GNU labels-as-values: `&&label' as a void*, and `goto *expr'.
 *
 * Lua 5.4 turns its whole interpreter loop on with a bare
 * `#if defined(__GNUC__)' and dispatches through `goto *disptab[x]', so this
 * construct is the entire distance between HEAD and a green `make test-lua'.
 *
 * The rows are chosen so a WRONG implementation cannot print the right answer:
 * every arm contributes a distinct decimal digit or bit, so a mis-dispatch
 * changes the number rather than cancelling out.  Rows 2 and 3 are the two
 * halves of the codegen: a BACKWARD `&&label' is resolved against
 * LabelPositions immediately, a FORWARD one goes on the fixup list, and those
 * are different lines of ir_codegen.inc.  Only testing one of them would leave
 * the other free to be wrong.
 */
#include <stdio.h>

/* row 4: the lua shape -- a function-local static table, indexed by an
   expression rather than by a plain variable, entered many times. */
static int dispatch(int n)
{
  static const void *const tab[4] = { &&A, &&B, &&C, &&D };
  int acc = 0;
  goto *tab[n & 3];
A: acc = 1; goto out;
B: acc = 2; goto out;
C: acc = 4; goto out;
D: acc = 8; goto out;
out:
  return acc;
}

int main(void)
{
  void *tab[3];
  void *p, *q;
  int i, sum;

  /* 1 -- automatic array, all three targets forward of the &&. */
  tab[0] = &&L0; tab[1] = &&L1; tab[2] = &&L2;
  sum = 0;
  for (i = 0; i < 3; i++) {
    p = tab[i];
    goto *p;
  L0: sum += 1;   continue;
  L1: sum += 10;  continue;
  L2: sum += 100; continue;
  }
  printf("1 %d\n", sum);

  /* 2 -- BACKWARD reference: the label is already emitted when && is taken,
     so its address is read straight out of LabelPositions. */
  sum = 0;
BACK:
  sum++;
  p = &&BACK;
  if (sum < 3) goto *p;
  printf("2 %d\n", sum);

  /* 3 -- FORWARD reference: the address is not known yet and must go through
     the fixup list, patched when the label is finally placed. */
  p = &&FWD;
  sum = 7;
  goto *p;
  sum = 999;            /* unreachable: a working jump skips this */
FWD:
  printf("3 %d\n", sum);

  /* 4 -- the lua dispatch shape, eight entries, two full cycles. */
  sum = 0;
  for (i = 0; i < 8; i++) sum = sum * 10 + dispatch(i);
  printf("4 %d\n", sum);

  /* 5 -- &&label is a value: two takings of the same label are equal, and two
     different labels are not.  This catches an implementation that returns a
     plausible-looking constant. */
  p = &&SAME; q = &&SAME;
  printf("5 %d\n", p == q);
  q = &&OTHER;
  printf("6 %d\n", p != q);
  goto *q;
SAME:
  printf("7 wrong-arm\n");
  return 1;
OTHER:
  printf("7 %d\n", 42);

  /* 8 -- a label reached BOTH by a plain goto and by a computed one.  The two
     paths must agree about where it is. */
  sum = 0;
  goto PLAIN;
COMPUTED:
  sum += 100;
  goto DONE;
PLAIN:
  sum += 5;
  p = &&COMPUTED;
  goto *p;
DONE:
  printf("8 %d\n", sum);
  return 0;
}
