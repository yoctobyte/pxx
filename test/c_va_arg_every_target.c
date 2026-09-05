/* THE TRIGGER FOR THE 32-BIT `va_arg` SET, MADE EXECUTABLE.
 *
 * bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet
 * says the set at cparser.inc's four `TargetArch in [TARGET_I386, TARGET_ARM32,
 * TARGET_RISCV32, TARGET_XTENSA]' sites is complete and correct — and correct
 * for a reason that has nothing to do with the set: the members that would
 * falsify it CANNOT COMPILE A C PROGRAM AT ALL, so no test can reach them. The
 * ticket's defence against that is a written instruction to whoever implements
 * the missing entry stub. This file is the same instruction, enforced.
 *
 * A NEW C-CAPABLE TARGET THAT IS NOT ADDED TO THOSE FOUR SETS FALLS INTO THE
 * `TargetArch <> TARGET_X86_64' arm, which hands it aarch64's 8-byte two-bank
 * layout. Varargs then produce WRONG VALUES rather than a diagnostic, and the
 * wrongness starts at the second argument — so it is invisible to any test
 * that passes one. `%llx' first is deliberate: a 64-bit argument read at the
 * wrong slot width prints the wrong half, which is what
 * `printf("%llx", v)' answering 55667788 for 0x1122334455667788 looked like
 * when xtensa joined the set and was STILL wrong for two other reasons
 * (7574a5f8d). Membership is necessary and is not sufficient, which is why
 * this asserts VALUES and not membership.
 *
 * The three arguments are chosen so every classification the lowering makes is
 * exercised in one call: a 64-bit integer (slot width and, on the two-bank
 * targets, the GP region), a plain int after it (so a misread of the first
 * argument's size shifts everything following), and a double (the FP region on
 * aarch64, the same region on everything else). One argument would pass on a
 * target with a completely wrong slot model.
 *
 * The Makefile row takes the expected line from `gcc` rather than from here —
 * the answer is target-INDEPENDENT, which is the entire claim, so a per-target
 * constant table would be a second copy of knowledge this file already asserts
 * is the same everywhere.
 */
#include <stdio.h>
#include <stdarg.h>

static void f(int n, ...)
{
	va_list ap;
	long long a;
	int b;
	double c;

	va_start(ap, n);
	a = va_arg(ap, long long);
	b = va_arg(ap, int);
	c = va_arg(ap, double);
	printf("%llx %d %.2f\n", a, b, c);
	va_end(ap);
}

int main(void)
{
	f(3, 0x1122334455667788LL, 42, 2.5);
	return 0;
}
