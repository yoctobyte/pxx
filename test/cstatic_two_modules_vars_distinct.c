/* TWO SAME-NAMED FILE-SCOPE STATIC VARIABLES IN TWO C MODULES ARE TWO OBJECTS.
 *
 * The VARIABLE arm of the defect whose FUNCTION arm is
 * test/cstatic_two_modules_distinct.c. Same cause, one namespace over, and
 * this arm is the worse one.
 *
 * C 6.2.2 gives a file-scope `static` internal linkage, so `v` in
 * fixtures/cstatic_var_mod_a.c and `v` in cstatic_var_mod_b.c are two distinct
 * objects that merely share a spelling. pxx's preprocessor inlines every
 * module into ONE buffer and tells them apart by module attribution, which is
 * how it emulates separate translation units.
 *
 * BEFORE THE FIX both statics shared one Syms[] row, and one row is one
 * address is ONE object:
 *
 *      row        pxx (before)   gcc (3 TUs)
 *      1 a        2              1     <- module A READ module B's value
 *      2 b        2              2
 *      3 a=70     70             70
 *      4 b        70             2     <- a WRITE through A changed B's object
 *
 * WHY THIS ARM IS WORSE THAN THE FUNCTION ONE. Functions were saved by an
 * accident of the fixup machinery: every call site keeps a CallFixTarget
 * snapshot and stays BAKED, so calls reached the right body even while sharing
 * a row — which is why rows 1-2 of the function test pass either way. A
 * variable has no snapshot. Sharing the row IS sharing the storage.
 *
 * ROW 4 ASSERTS THE WRITE DIRECTION, and that is a different observation from
 * row 1 even though both fail together today. Row 1 catches a read bound to
 * the wrong object; row 4 catches a STORE through one object being visible
 * through another, which is the sharper statement and the one a size- or
 * read-only check cannot make.
 *
 * WHAT IT IS NOT: a discriminator between the two arms of the fix. The fix has
 * two — a `static` declaration must not seize another module's row, and a
 * reference must prefer its own module's row — and this comment first claimed
 * they fail this file differently. MEASURED, THEY DO NOT: reverting either arm
 * alone gives the identical `2 / 2 / 70 / 70`, because without the rung there
 * is one row for the lookup to prefer between, and without the lookup the two
 * rows exist but every reference still takes the first. Each arm is necessary
 * and neither alone moves a single row. The claim was written before the
 * ablation and the ablation corrected it.
 *
 * NO EXPECTED VALUES ARE WRITTEN DOWN. The Makefile row diffs this program's
 * output against gcc compiling the SAME three files as three translation units
 * (-DSEPARATE_TU). The numbers in the table above are documentation; the
 * assertion is the C standard's own answer.
 *
 * Do NOT run gcc the way pxx runs this file. A unity build really is one
 * translation unit and gcc correctly rejects it — two `static int v` at file
 * scope in one TU is a redefinition. That asymmetry is the whole reason the
 * oracle needs -DSEPARATE_TU, and it is the same note the function arm carries.
 * bug-c-two-same-named-file-scope-static-variables-share-one-syms-row-and-alias
 */
#include <stdio.h>

#ifdef SEPARATE_TU
/* The oracle's view: a.c and b.c are their own translation units, as they
   would be in any ordinary build. */
extern int  ma_get(void);
extern void ma_set(int);
extern int  ma_size(void);
extern int  mb_get(void);
extern int  mb_size(void);
#else
/* The path under test: one buffer, told apart by module attribution. */
#include "fixtures/cstatic_var_mod_a.c"
#include "fixtures/cstatic_var_mod_b.c"
#endif

int main(void)
{
	printf("1 a=%d\n", ma_get());
	printf("2 b=%d\n", mb_get());
	ma_set(70);
	printf("3 a=%d\n", ma_get());
	printf("4 b=%d\n", mb_get());
	/* THE SIZE ROW FAILS INDEPENDENTLY OF THE VALUE ROWS, which is the reason
	   it exists. sizeof reads the symbol's own ArrLen, not any value, so it is
	   resolved at a different set of call sites -- and when only the value path
	   was made module-aware, rows 1-4 were already correct while both modules
	   answered 24 here. Match the assertion class to the defect class: no read
	   or write assertion can observe a size taken from the wrong object. */
	printf("5 size a=%d b=%d\n", ma_size(), mb_size());
	return 0;
}
