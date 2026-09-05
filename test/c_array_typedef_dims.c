/* AN ARRAY TYPEDEF CARRIES ALL ITS DIMENSIONS, and `sizeof` of its NAME sees them.
 *
 * Two defects, one recording site, and the worse one was silent.
 *
 * 1. `sizeof` of the TYPE NAME answered the ELEMENT size — `typedef double
 *    TA[4]` gave 8 against gcc's 32. Rows 1-3 exist in THREE element widths on
 *    purpose: 8 is also `TypeSlotSize(tyUnknown)`, the signature of a different
 *    defect (bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown), and the
 *    `double` row alone cannot tell them apart. An unknown default answers 8
 *    for all three; the element size answers 8 / 1 / 4. **Do not reduce these
 *    three rows to one** — the collision is the whole reason the first reading
 *    of this went to the wrong walk.
 *    bug-c-sizeof-of-an-array-typedef-name-answers-the-element-size
 *
 * 2. A MULTI-DIMENSIONAL array typedef recorded only its FIRST dimension and
 *    the rest were eaten by the skip-to-semicolon loop. `typedef int T2[2][3]`
 *    allocated 2 elements instead of 6 and indexed with a 2-wide row, so an
 *    object of that type OVERWROTE THE LOCAL DECLARED BEFORE IT and read its
 *    own elements back aliased. Silent, rc=0.
 *    bug-c-a-multi-dimensional-array-typedef-is-half-modelled-and-corrupts-neighbouring-locals
 *
 * ROW 10 IS THE ONE THAT MATTERS AND IT IS NOT A SIZE. `before` and `after`
 * bracket a `T2` local: an under-allocated array writes through its end into
 * whichever neighbour the frame put there, and `sizeof` can be corrected
 * without the allocation being corrected. A size assertion cannot observe a
 * buffer overrun — match the assertion class to the defect class.
 *
 * Row 5 is cglm's `mat4`, spelled exactly as cglm spells it. The recording
 * site's own comment cited cglm as the reason the single-dim case was modelled,
 * while the shape cglm actually uses was the broken one.
 *
 * Row 7 is the guard on the fix: `TA*` is a POINTER, so its size must stay the
 * pointer's. It asserts that as a RELATION against `sizeof(void *)` rather than
 * as the number 8 -- 8 is right on x86-64 and aarch64 and wrong on i386, arm32
 * and riscv32, and the literal made this file's transcript differ from the
 * 64-bit gcc oracle on three targets for a reason unrelated to what it tests.
 * Fold the typedef's dims in without testing pointer depth and the relation
 * goes false on every target at once.
 *
 * Row 13 is the direct spelling, which always worked — the control that says a
 * failure here is about typedefs rather than about arrays.
 *
 * The Makefile row diffs the whole output against gcc rather than a
 * transcribed block, so adding a row needs no expected value re-derived.
 */
#include <stdio.h>

typedef double TA[4];
typedef char   TC[4];
typedef int    TI[4];
typedef int    T2[2][3];
typedef float  M4[4][4];   /* cglm's mat4, spelled as cglm spells it */

TA gplain;
TA gs[2];
T2 gv;

int main(void)
{
	TA v;
	T2 m;
	M4 mat;
	int before = 111;
	T2 w;                    /* between two locals ON PURPOSE -- see row 10 */
	int after = 222;
	int i, j;

	for (i = 0; i < 2; i++)
		for (j = 0; j < 3; j++)
			w[i][j] = 1000 + i * 10 + j;
	for (i = 0; i < 2; i++)
		for (j = 0; j < 3; j++)
			m[i][j] = i * 10 + j;
	mat[3][3] = 1.5f;

	printf("1 sizeof(TA)=%d\n", (int)sizeof(TA));
	printf("2 sizeof(TC)=%d\n", (int)sizeof(TC));
	printf("3 sizeof(TI)=%d\n", (int)sizeof(TI));
	printf("4 sizeof(T2)=%d\n", (int)sizeof(T2));
	printf("5 sizeof(M4)=%d\n", (int)sizeof(M4));
	printf("6 sizeof(TA[2])=%d\n", (int)sizeof(TA[2]));
	/* A RELATION, NOT A WIDTH. This was `sizeof(TA*)=%d` and asserted 8 --
	   correct on x86-64 and aarch64, and wrong on i386, arm32 and riscv32,
	   where a pointer is 4. The transcript then differed from the 64-bit gcc
	   oracle on three targets for a reason that had nothing to do with this
	   test. Asserted as a relation it carries no expected width, passes
	   everywhere, and still catches the thing it is here for: fold the
	   typedef dims in without testing pointer depth and this goes to 0. */
	printf("7 TA*-is-a-pointer=%d\n", (int)(sizeof(TA*) == sizeof(void *)));
	printf("8 sizeof(v)=%d sizeof(gplain)=%d sizeof(gs)=%d\n",
	       (int)sizeof(v), (int)sizeof(gplain), (int)sizeof(gs));
	printf("9 sizeof(m)=%d sizeof(gv)=%d sizeof(mat)=%d\n",
	       (int)sizeof(m), (int)sizeof(gv), (int)sizeof(mat));
	printf("10 before=%d after=%d\n", before, after);
	printf("11 w=%d %d %d %d %d %d\n",
	       w[0][0], w[0][1], w[0][2], w[1][0], w[1][1], w[1][2]);
	printf("12 m[1][2]=%d mat[3][3]=%.1f\n", m[1][2], (double)mat[3][3]);
	printf("13 sizeof(double[4])=%d sizeof(int[2][3])=%d\n",
	       (int)sizeof(double[4]), (int)sizeof(int[2][3]));
	return 0;
}
