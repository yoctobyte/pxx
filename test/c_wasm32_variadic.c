/* SPDX-License-Identifier: MPL-2.0 */
/* THE wasm32 C VARIADIC CALLING CONVENTION, EXERCISED IN THE SHAPES THAT TELL
   A CORRECT LAYOUT FROM A LUCKY ONE.
 *
 * wasm32 is the only target where the callee cannot FIND its variadic tail:
 * there are no argument registers to spill and no addressable incoming frame
 * to anchor at, so the caller marshals the tail into linear memory and hands
 * over one trailing i32. The layout is the one __pxx_va_arg_cross32 already
 * walks for i386-cdecl -- packed 4-byte slots, an 8-byte scalar taking two,
 * no 8-byte alignment -- and getting it wrong is SILENT: the module still
 * validates and every argument after the mismatch reads half of its
 * neighbour.
 *
 * WHY `sum3(3, 10, 20, 12)` ALONE IS NOT ENOUGH, which is why there are five
 * checks and not one. Three same-width arguments after one named parameter
 * pass under a packed layout, under an 8-aligned one, and under a backend that
 * hard-coded the area's position -- the three arrangements that differ are the
 * other four rows.
 *
 * EVERY CHECK CONTRIBUTES A DISTINCT BIT, so a failure names which shape broke
 * rather than only that something did, and the all-pass answer is 42 rather
 * than 0: a wasm module that exports no `_start` is instantiated, runs
 * nothing, and exits 0, so 0 as the expected value would be a guard that
 * cannot fail. 0 here means the program never ran.
 *
 * Target-independent by construction -- gcc builds and runs it as the oracle,
 * so no expected value in this file is a per-target constant.
 * bug-c-hosted-c-on-wasm32-needs-environ-and-va-arg-so-stdio-programs-still-refuse
 */
#include <stdarg.h>

static int sum3(int n, ...)
{
	va_list ap; int t = 0; int i;
	va_start(ap, n);
	for (i = 0; i < n; i++) t += va_arg(ap, int);
	va_end(ap);
	return t;
}

/* 4, 8 and 8 byte slots interleaved, twice: the arrangement a packed walk gets
   right and an 8-aligned one does not, starting at the SECOND group. */
static long long mix(int n, ...)
{
	va_list ap; long long acc = 0; int i;
	va_start(ap, n);
	for (i = 0; i < n; i++)
	{
		int k = va_arg(ap, int);
		double d = va_arg(ap, double);
		long long q = va_arg(ap, long long);
		acc += (long long)k + (long long)d + q;
	}
	va_end(ap);
	return acc;
}

/* An EMPTY tail still has to receive an anchor: the callee's signature carries
   the parameter unconditionally, so a caller that skipped the push for a call
   with no variadic argument would hand va_start whatever sat below. */
static int nul(int n, ...)
{
	va_list ap;
	va_start(ap, n);
	va_end(ap);
	return n;
}

/* Five named parameters before the tail. The area's index is ParamCount, so a
   backend that pinned it to a fixed position passes sum3 above and fails
   here. */
static int many(int a, int b, int c, int d, int e, ...)
{
	va_list ap; int t = a + b + c + d + e; int i; int n;
	va_start(ap, e);
	n = va_arg(ap, int);
	for (i = 0; i < n; i++) t += va_arg(ap, int);
	va_end(ap);
	return t;
}

int main(void)
{
	int bad = 0;
	if (sum3(3, 10, 20, 12) != 42) bad |= 1;
	if (mix(2, 1, 2.5, 3LL, 4, 5.5, 6LL) != 21) bad |= 2;
	if (nul(7) != 7) bad |= 4;
	/* A variadic call INSIDE a variadic tail: the inner area is pushed while
	   the outer one is live, which one shared scratch local would corrupt. */
	if (sum3(2, sum3(2, 1, 2), 4) != 7) bad |= 8;
	if (many(1, 2, 3, 4, 5, 3, 100, 200, 300) != 615) bad |= 16;
	return bad ? 100 + bad : 42;
}
