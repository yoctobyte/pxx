/* The integer promotions apply to the operand of unary minus, so the RESULT for any
   type narrower than int is a SIGNED int: `-(unsigned short)1` is the int -1, not an
   unsigned 65535.

   cparser copied the operand's type onto the AN_NEG node, so the result stayed
   UNSIGNED and `-(us) < 0` compiled to an unsigned compare — always false
   (bug-c-unary-minus-no-integer-promotion). Unary `~` already promoted correctly;
   `-` was the sibling that never got it.

   c-testsuite 00200 (lshift-type.c) detects operand signedness with exactly this
   idiom -- `(M) < 0 || -(M) < 0` -- which is why it failed on aarch64.

   The value printed fine either way; only the TYPE was wrong, so this was a silent
   wrong-branch bug, not a wrong-arithmetic one.

   exit 42 = all pass. */

int main(void)
{
	unsigned short us = 1;
	unsigned char uc = 1;
	signed short ss = 1;
	unsigned int ui = 1;
	unsigned long long ull = 1;

	/* narrower than int -> promotes to SIGNED int, so the negation is < 0 */
	if (!(-(us) < 0)) return 1;
	if (!(-(uc) < 0)) return 2;
	if (!(-(ss) < 0)) return 3;

	/* ...and the value is still -1 */
	if (-(us) != -1) return 4;
	if (-(uc) != -1) return 5;

	/* int-or-wider unsigned types are NOT promoted: they stay unsigned, so the
	   negation wraps and is never < 0. Do not "fix" these into signed. */
	if (-(ui) < 0) return 6;
	if (-(ull) < 0) return 7;

	/* a signed int operand keeps its own type */
	{
		int si = 1;
		if (!(-(si) < 0)) return 8;
	}

	return 42;
}
