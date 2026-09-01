/* One operand, many spellings: sizeof must agree with itself.
 *
 * `sizeof(**p)` answered 8 while `sizeof **p` answered 16 -- the SAME operand,
 * wrong with parentheses and right without. The parenthesised form ran a walk
 * of token-pattern arms; the unparenthesised form ended in the general
 * expression path, which types the operand properly. Two mechanisms for one
 * concept, and the second one is the one that stayed broken.
 *
 * The arms were not a fast path over the expression code, they were a parallel
 * implementation: the fallback to the expression path required that NO arm had
 * consumed anything, so an arm that ate part of the operand and then failed to
 * recognise the rest left the pointer-size default in place and this never ran.
 * The `*`-arm consumed one star and required an identifier, so every operand
 * with two levels of indirection fell out of it holding 8.
 *
 * Measured against gcc before the fix, sizeof(struct Big) == 16: eleven of
 * seventeen spellings answered 8. Seven of them were this one shape in
 * different syntax, and they are the rows below. A wrong sizeof is not a wrong
 * number, it is a wrong allocation -- `malloc(sizeof(**p))` reserving 8 bytes
 * for a 16-byte struct writes past it later, three layers from the cause.
 *
 * NOT covered here, deliberately, because they are still wrong and have their
 * own ticket: subscript-through-pointer-to-pointer (`p2[0][0]`) and anything
 * involving a FILE-SCOPE pointer-to-array, which does not merely mis-size --
 * `gp[2][3]` on a global `int (*gp)[4]` SEGFAULTS where the identical local is
 * correct. See bug-c-a-file-scope-pointer-to-array-crashes-on-indexing. */
#include <stdio.h>
struct Big { long a, b; };          /* 16 */
struct Big  *p1;
struct Big **p2;
struct Big ***p3;

int main(void)
{
  int bad = 0;
#define CHK(e, want) do { \
    int got = (int)(e); \
    printf("%-20s %2d want %2d\n", #e, got, (int)(want)); \
    if (got != (int)(want)) bad++; \
  } while (0)

  /* the shape the arms handled */
  CHK(sizeof(*p1),        16);
  CHK(sizeof(p1[0]),      16);

  /* two or more levels: every one of these answered 8 */
  CHK(sizeof(**p2),       16);
  CHK(sizeof(***p3),      16);
  CHK(sizeof(*(*p2)),     16);
  CHK(sizeof(*p2[0]),     16);
  CHK(sizeof(**&p2[0]),   16);
  CHK(sizeof(*&*p1),      16);
  CHK(sizeof(*(p1+1)),    16);
  CHK(sizeof((*p2)[0]),   16);

  /* the parenthesised and unparenthesised spellings must not disagree: that
     disagreement IS the bug, and it is invisible to any test that writes only
     one of the two forms. */
  CHK(sizeof **p2,        16);
  CHK(sizeof ***p3,       16);
  if (sizeof(**p2) != sizeof **p2) { printf("FAIL: paren and no-paren disagree\n"); bad++; }

  /* controls: the pointer itself is still pointer-sized */
  CHK(sizeof(p1),         sizeof(void *));
  CHK(sizeof(p2),         sizeof(void *));

  printf(bad == 0 ? "SIZEOF OK\n" : "SIZEOF FAIL\n");
  return bad == 0 ? 0 : 1;
}
