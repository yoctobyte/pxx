/* SPDX-License-Identifier: MPL-2.0 */
/* HOSTED C ON wasm32: the whole point of the three walls, exercised end to end.
 *
 * Until 2026-09-19 `#include <stdio.h>` could not produce a wasm32 module at
 * all. Three things stood in the way and each hid the next, which is why this
 * subject is one file rather than three:
 *
 *   va_arg     printf IS the variadic case, and the crtl that defines it
 *              refused at parse time. wasm32 now marshals its variadic tail
 *              into linear memory and hands it over as a trailing parameter.
 *   the ceiling MAX_WASM_BODY_VARS was 288 and one crtl stdio.c body needs
 *              more, so the module could not be ENCODED.
 *   fegetround the float formatter calls it, EmitCFenvStubs writes it as raw
 *              machine code, and wasm32 has none -- so with the ceiling raised
 *              the module BUILT and then failed to instantiate on one
 *              unresolved import. lib/crtl/src/fenv.c is that body.
 *
 * WHY THE FLOAT ROWS ARE NOT DECORATION: they are the only rows that reach
 * __crtl_round_carry, hence __pxx_fegetround, hence the third wall. A subject
 * that printed only integers would link and run with that body missing.
 *
 * WHY getenv IS HERE: `environ` on wasm32 is filled by WasmEmitEnvironFetch
 * from WASI, and that code had NEVER EXECUTED -- its own ticket says so and
 * says the first thing to do when the other walls fall is to run a program
 * that reads getenv and check the value. This is that program. It found a real
 * defect the day it was first run: environ was populated correctly and getenv
 * answered (null), because crtl's getenv read /proc/self/environ, which a WASI
 * module has no filesystem for.
 *
 * DIFFED WHOLE AGAINST gcc, so no expected value lives in this file and no row
 * can pass by agreeing with a stale constant. The environment variable is set
 * identically for both legs by the caller.
 */
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	const char *v;

	printf("d=%d s=%s c=%c x=%x o=%o\n", 42, "str", 'z', 255, 64);
	printf("lld=%lld llu=%llu u=%u\n",
	       1122334455667788LL, 18446744073709551615ULL, 4000000000u);
	printf("ld=%ld neg=%d wid=%5d pad=%-5d|\n", 123456L, -7, 42, 42);

	/* Every row below reaches the rounding decision at the cut. The tie is
	   deliberate: 1.005 is not representable, so the correct answer depends on
	   the expansion being exact rather than on a lucky comparison. */
	printf("f=%.2f g=%g e=%.3e\n", 3.14159, 0.5, 12345.678);
	printf("tie=%.2f half=%.1f zero=%.1f\n", 1.005, 0.25, -0.0);
	printf("big=%.0f small=%.6f\n", 1e15, 1.0 / 3.0);

	v = getenv("PXX_WASM_HOSTED_PROBE");
	printf("env=%s\n", v ? v : "(unset)");
	v = getenv("PXX_WASM_HOSTED_ABSENT");
	printf("absent=%s\n", v ? v : "(unset)");

	return 0;
}
