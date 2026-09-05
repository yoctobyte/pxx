/* THE POPULATION THE FILE-SCOPE REFUSAL MUST NOT BREAK.
 *
 * `CEvalConstPrimary` folds an identifier in a constant expression, and until
 * 2026-09-05 it treated two different things as one: a name that is DECLARED
 * but not a compile-time constant, and a name that does not exist at all. Both
 * contributed 0 and set `CConstExprSawNonConst`.
 *
 * Only the second is a mistake. The first is how a VLA is built — `int v[n]`
 * is the flag doing its job, and the dimension reader is the caller that acts
 * on it. `FindSym` separates them exactly: >= 0 is this file, < 0 is
 * test/c_undeclared_in_file_scope_init_refused.c.
 *
 * So this is the positive control for that fix, drawn from the population the
 * question is about: every row here names an identifier from inside a constant
 * expression, legitimately, and every row must still compile and produce the
 * value gcc produces. A guard that refuses these would refuse the VLA, the
 * NARGS idiom and BUILD_BUG_ON — which is 7 of busybox's 307 libbb sources on
 * the last count (bug-c-logical-not-is-not-folded-in-a-constant-expression).
 *
 * The expected line is asserted against `gcc -std=gnu99` in the Makefile row,
 * not transcribed here, so nothing in this file has to be re-derived when a
 * row is added.
 */
#include <stdio.h>

enum { E1 = 3, E2 = E1 * 2 };
static int tbl[E2];
int glob = 7;

int main(void) {
	int n = 4;
	int vla[n];                                   /* declared, not constant     */
	int m[E1];                                    /* enum constant as a dim     */
	char buf[3 * sizeof(size_t)];                 /* sizeof inside a dim        */
	int cnt = sizeof(tbl) / sizeof(tbl[0]);       /* the NARGS idiom            */
	int cl = sizeof((int[]){1,2,3}) / sizeof(int);/* array compound literal     */
	int dd[E1] = { [0] = 1, [E1-1] = 9 };         /* designated, const subscript*/
	(void)sizeof(char[1 - 2*!!(0)]);              /* BUILD_BUG_ON idiom         */

	vla[0] = 1; m[0] = 2; buf[0] = 3;
	printf("%d %d %d %d %d %d\n",
	       cnt, cl, dd[0], dd[2], vla[0] + m[0] + buf[0], glob);
	return 0;
}
