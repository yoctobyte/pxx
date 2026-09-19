/* SPDX-License-Identifier: MPL-2.0 */
/* WHICH OPERATIONS ARE SIGNED, ASKED IN BOTH DIRECTIONS AT ONCE.
 *
 * A backend picks div_s or div_u, lt_s or lt_u, from a single answer to "is
 * this operation signed", and a rule that is wrong in EITHER direction
 * produces a plausible wrong number rather than a crash. The two directions
 * hide each other: a rule that makes an unsigned op signed is fixed by a rule
 * that makes a signed op unsigned, and a suite containing only one of them
 * certifies the replacement.
 *
 * Found 2026-09-19 on wasm32, the day hosted printf first ran there:
 * `printf("%llu", 18446744073709551615ULL)` printed `/`, ONE character, while
 * five other targets matched gcc exactly. `/` is '0' minus one -- a digit loop
 * running negative. The cause was a viral `signed if EITHER operand is signed`
 * rule: __crtl_utoa's `v % (unsigned long)base` lowers the cast as a mask
 * against a tyInt64 constant, so a provably non-negative zero-extension
 * reported itself signed and the modulo above it chose rem_s.
 *
 * THE FIRST REPAIR BROKE THE MIRROR, WHICH IS WHY ROWS 16 AND 32 ARE HERE:
 * making an unsigned operand at the operation's own width win outright turned
 * `n / (long long)q` -- an explicit cast TO signed -- unsigned, because the
 * cast node still carried the source's unsigned type. Rows 64 and 128 are the
 * third trap: `and` instead of `or` would pass everything above and make
 * `-7 / (int)w` four billion, since a narrow unsigned promotes to SIGNED int
 * in C and must not carry its unsignedness across.
 *
 * ROWS 256..4096 ARE THE COMPARISONS, and they are not decoration either: a
 * comparison's recorded result type is boolean, which is not a signed type, so
 * a fix that reads the result type without excluding compares turns every
 * signed `<` into lt_u.
 *
 * THE MASK IS PRINTED, NOT RETURNED. An exit status is 8 bits and this mask is
 * 13, so `100000 + bad` wraps: 100000 + 138 is 42 mod 256, and 138 is three
 * real failures wearing the all-pass answer. gcc is the oracle and the whole
 * line is diffed, so no expected value lives here.
 * bug-a-wasm32-picks-signed-division-for-an-unsigned-64-bit-value
 */
#include <stdio.h>
/* Signed and unsigned integer operations that a single viral signedness rule
   gets wrong in one direction or the other. Each bit is a distinct shape. */
int main(void)
{
	unsigned long long v = 18446744073709551615ULL;
	unsigned long long q = 3;
	unsigned short w = 3;
	unsigned int c = 3;
	long long n = -7;
	int base = 10;
	int bad = 0;

	/* unsigned 64 must stay unsigned through a width-narrowing cast operand */
	if (v % (unsigned long)base != 5ULL)                   bad |= 1;
	if (v / (unsigned long)base != 1844674407370955161ULL) bad |= 2;
	if (v % (unsigned int)base != 5ULL)                    bad |= 4;
	if (v % 10 != 5ULL)                                    bad |= 8;
	/* ...and a cast TO signed must be respected, the mirror failure */
	if (n / (long long)q != -2)                            bad |= 16;
	if (n % (long long)q != -1)                            bad |= 32;
	/* a narrow unsigned promotes to signed int: these must stay signed */
	if (-7 / (int)w != -2)                                 bad |= 64;
	if (-7 % (int)w != -1)                                 bad |= 128;
	/* signed comparisons must not become unsigned */
	if (!(-7 < 3))                                         bad |= 256;
	if (!(n < (long long)q))                               bad |= 512;
	if (!((long long)-1 < (long long)1))                   bad |= 1024;
	/* unsigned comparisons above 2^63 must not become signed */
	if (!(v > q))                                          bad |= 2048;
	if (v < c)                                             bad |= 4096;
	/* PRINTED, NOT RETURNED. An exit status is 8 bits, so `100000 + bad`
	   wraps and a 13-bit mask can alias onto the all-pass value: 100000+138
	   is 42 mod 256, and 138 is three real failures. Diff the line instead. */
	printf("signs bad=%d\n", bad);
	return 0;
}
