/* A `goto` INTO a do-while body: C's one legal way in, and the shape busybox's
 * `mv` uses (`goto DO_MOVE` past the first two statements of the do-body).
 *
 * WHAT IT PINS. pxx used to desugar `do body while (cond)` into a FLAG:
 * `first = 1; while (first || cond) { first = 0; body }`. Correct for every
 * entry through the top; wrong for the jump, which skips BOTH assignments and
 * leaves the flag holding whatever its stack slot contained. Non-zero, and the
 * back edge short-circuits `first || cond` true and takes an extra pass
 * WITHOUT EVALUATING cond -- so the `*++argv` in the condition never runs, the
 * body sees the same *argv twice, and busybox printed
 * `mv: can't stat 'NEW/A'` after a move that had already succeeded.
 *
 * DIRTY THE STACK FIRST OR THIS TEST CANNOT FAIL. The flag is an ordinary
 * uninitialised local, so in a small program its slot is usually zero and the
 * bug does not show: five earlier minimal programs missed it for exactly that
 * reason and the defect was filed as an i386 register-allocation bug. It is
 * neither i386 nor register allocation -- measured pre-fix, i386, aarch64,
 * arm32 and riscv32 all took the extra pass and x86-64 did not, because its
 * frame layout happened to leave that slot zero.
 *
 * The `passes` counts ARE the assertion; the printed `*argv` values are what
 * say the condition was skipped rather than merely mis-taken. Runs identically
 * under gcc, which is the oracle. */
#include <stdio.h>

static void dirty(void)
{
	volatile char buf[8192];
	int i;
	for (i = 0; i < 8192; i++) buf[i] = 0x7f;
}

static int passes;

static void f(char **argv, char *last, int viaGoto)
{
	passes = 0;
	if (viaGoto)
		goto INSIDE;
	do {
		printf("  top   *argv=%s\n", *argv);
 INSIDE:
		passes++;
		printf("  body  *argv=%s\n", *argv);
	} while (*++argv && *argv != last);
}

/* continue inside a do-while must re-test the CONDITION, not restart the body:
 * the desugar's flag used to carry that too, so it is asserted here rather than
 * left to the reader. */
static int cont_passes;

static void g(void)
{
	int i = 0;
	cont_passes = 0;
	do {
		i++;
		if (i == 2)
			continue;
		cont_passes++;
	} while (i < 4);
}

int main(void)
{
	char *a[3];
	a[0] = "A"; a[1] = "NEW"; a[2] = 0;
	dirty();
	printf("normal entry:\n"); f(a, a[1], 0); printf("  passes=%d\n", passes);
	dirty();
	printf("goto entry:\n");   f(a, a[1], 1); printf("  passes=%d\n", passes);
	dirty();
	g(); printf("continue: i-passes=%d\n", cont_passes);
	return 0;
}
