/* `for (init; cond; post)` must run `post` on EVERY back edge, including the
   one that follows a `goto` INTO the body -- C's one legal way in.
 *
 * It used to desugar to `first = 1; while (1) { if (!first) post; first = 0;
 * if (!cond) break; body; }`, and the jump skips both writes to `first`, so the
 * first back edge read an uninitialised slot: non-zero, and `if (!first) post`
 * SKIPPED THE POST -- one extra pass with the induction variable unchanged.
 * Same defect as the do-while flag (cdo_while_goto_entry.c), found by grepping
 * for the sibling; this one is not cross-target-only, because the slot holds
 * whatever the previous call left at that offset.
 *
 * `dirty()` IS LOAD-BEARING and must be called from main, not from f: the point
 * is to leave non-zero bytes where f's frame will be. Without it the slot reads
 * zero, which is accidentally the CORRECT value, and the whole test passes on
 * every target while the bug is live.
 *
 * .expected is gcc's output. Rows: top entry, goto entry, `continue` (post must
 * still run, or this hangs), `break`, a two-expression post, and a post whose
 * left arm is a void call (the AN_COMMA arm that carries no value).
 * bug-a-i386-a-pointer-is-register-and-memory-resident-at-once-across-a-goto-entered-loop
 */
#include <stdio.h>

static void dirty(void)
{
	volatile char b[8192];
	int i;
	for (i = 0; i < 8192; i++) b[i] = 0x7f;
}

static int f(int jump)
{
	int i, n;
	n = 0;
	i = 0;
	if (jump) goto INSIDE;
	for (; i < 3; i++) {
INSIDE:
		n++;
		printf("  i=%d n=%d\n", i, n);
	}
	return n;
}

static int cont_runs_post(void)
{
	int i, n;
	n = 0;
	for (i = 0; i < 4; i++) {
		if (i == 1) continue;
		n++;
	}
	return n;
}

static int brk_skips_post(void)
{
	int i;
	for (i = 0; i < 9; i++) {
		if (i == 2) break;
	}
	return i;
}

static int two_expr_post(void)
{
	int i, j;
	j = 100;
	for (i = 0; i < 3; i++, j++)
		;
	return i * 1000 + j;
}

static int sideCount;
static void bump(void) { sideCount++; }

static int void_call_post(void)
{
	int i;
	sideCount = 0;
	for (i = 0; i < 5; bump())
		i++;
	return sideCount;
}

int main(void)
{
	dirty();
	printf("top entry:\n");
	printf("  passes=%d\n", f(0));
	dirty();
	printf("goto entry:\n");
	printf("  passes=%d\n", f(1));
	printf("continue: n=%d\n", cont_runs_post());
	printf("break: i=%d\n", brk_skips_post());
	printf("two-expr post: %d\n", two_expr_post());
	printf("void-call post: %d\n", void_call_post());
	return 0;
}
