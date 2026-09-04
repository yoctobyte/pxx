/* `offsetof` inside a STATIC ARRAY initializer.

   stddef.h defines offsetof as `((size_t)&(((type*)0)->member))`, and `->`
   lexes to tkDot (clexer.inc:790). CBraceFlatIntInitCountAt -- the token scan
   that decides whether a brace list is a flat integer init -- had no tkDot in
   its allowlist, so the element bailed to the `else Exit(-1)` arm.

   THE CONSEQUENCE WAS NOT A ZERO, WHICH IS WHY THE FIRST TWO DIAGNOSES WERE
   BOTH WRONG. Losing the flat path made the fallback size the array as ONE
   element, so `static int ofs[] = {5, offsetof(S,b), 9}` had sizeof 4 against
   gcc's 12 -- and `sizeof(a)/sizeof(a[0])`, the standard C table-length idiom,
   evaluated to 1. Every loop over such a table ran exactly one iteration.

   HOW THIS TEST IS BUILT, because the ordinary way of writing it cannot fail:

   1. IT ASSERTS THE SIZE BEFORE ANY ELEMENT. Reading ofs[1] and ofs[2] of a
      1-element array is out of bounds; it returns whatever static lives next
      door and never faults. A peer's first probe printed `0 4 0` that way and
      read it as "offsetof zeroed, literals fine" -- a coherent, wrong
      mechanism built from neighbouring memory. sizeof is the only quantity
      here that adjacent memory cannot answer.

   2. NO ROW EXPECTS 0, AND NO TWO ROWS EXPECT THE SAME NUMBER. The broken
      value was 0, so an `offsetof(S, a)` row -- a FIRST member, genuinely 0 --
      passes just as well broken. That is not hypothetical: in the busybox
      program that exposed this, `uname -s` printed the right answer all along
      because sysname is the first member of struct utsname, while `uname -a`
      printed `Linux` eight times. The offsets here are 8, 4 and 12: distinct
      from each other, from 0, and from the struct sizes, so no single wrong
      mechanism can satisfy two rows at once.

   3. THE NESTED ROW DISCRIMINATES A SECOND BUG. CEvalConstOffsetofAddress
      walked ONE member link, so `offsetof(outer, n.b)` returned the offset of
      `n` (4) and left `.b` unconsumed. 12 vs 4 separates a correct walk from
      the outer-field-only walk; a nested member at offset 0 would not.

   4. `sizeof` IN THE SAME SLOT IS THE POSITIVE CONTROL. It was always correct,
      so if this test ever goes red on BOTH arrays the fault is general
      constant folding, not offsetof.

   bug-c-offsetof-in-a-static-array-initializer-folds-to-zero-silently */
#include <stddef.h>
#include <stdio.h>

struct S     { char a[8]; char b[8]; };            /* b at 8              */
struct outer { char pad[4]; struct S n; };         /* n at 4, n.b at 12   */

static int            ofs[]  = { 5, offsetof(struct S, b), 9 };
static int            szo[]  = { 5, sizeof(struct S), 9 };          /* control */
static const unsigned nest[] = { 1, offsetof(struct outer, n.b), 3 };
static const unsigned long scalar_nested = offsetof(struct outer, n.a);

int main(void)
{
	int rc = 0;

	/* (1) lengths first -- every element read below is meaningless until these hold */
	if (sizeof(ofs)  / sizeof(ofs[0])  != 3) { printf("FAIL ofs  len %zu\n",  sizeof(ofs)  / sizeof(ofs[0]));  rc = 1; }
	if (sizeof(nest) / sizeof(nest[0]) != 3) { printf("FAIL nest len %zu\n",  sizeof(nest) / sizeof(nest[0])); rc = 1; }
	if (sizeof(szo)  / sizeof(szo[0])  != 3) { printf("FAIL szo  len %zu\n",  sizeof(szo)  / sizeof(szo[0]));  rc = 1; }
	if (rc) return rc;

	/* (2) the offsetof element, and the plain literals that shared its declaration */
	if (ofs[0] != 5 || ofs[1] != 8 || ofs[2] != 9) { printf("FAIL ofs %d %d %d\n", ofs[0], ofs[1], ofs[2]); rc = 1; }

	/* (3) nested member path: 12, not 4 */
	if (nest[0] != 1 || nest[1] != 12 || nest[2] != 3) { printf("FAIL nest %u %u %u\n", nest[0], nest[1], nest[2]); rc = 1; }
	if (scalar_nested != 4) { printf("FAIL scalar_nested %lu\n", scalar_nested); rc = 1; }

	/* (4) control */
	if (szo[1] != (int)sizeof(struct S)) { printf("FAIL szo %d\n", szo[1]); rc = 1; }

	if (!rc) printf("OFFSETOF STATIC OK %d %u %lu %d\n", ofs[1], nest[1], scalar_nested, szo[1]);
	return rc;
}
