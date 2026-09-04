/* SPDX-License-Identifier: MPL-2.0 */
/* An `"m"` inline-asm operand must cost NO register.
 *
 * WHY THIS TEST EXISTS, and why it is not covered by casm_gnu_operands.c.
 * `"m"` used to be encoded as `[reg]` with the frontend pinning a register to
 * hold the operand's ADDRESS. That is correct and it spends a pool entry per
 * memory operand. On x86-64 the pool is nine registers and nothing real ran
 * out; on i386 it is five (ebx is callee-saved and pxx's prologue does not save
 * it), and busybox's tls_pstm_mul_comba.c wants three outputs and two `"m"`
 * inputs with %eax and %edx clobbered -- five wanted, three free. So a defect
 * that is invisible on the 64-bit host decides whether a whole architecture
 * can build, which is the asymmetry CLAUDE.md's "nothing observably differs"
 * section is about.
 *
 * THE ROW THAT MATTERS IS msum9: ten operands want a register under the old
 * scheme and one under the new, so on nine pool entries it is the difference
 * between `needs more registers than this frontend can pin` and an answer.
 * It is a POSITIVE CONTROL for the pressure claim rather than a re-test of
 * `"m"` itself -- a test that merely used one `"m"` passes either way, which
 * is exactly why casm_gnu_operands.c could not have caught this.
 *
 * The oracle is gcc on this same source: every value here is the machine's
 * answer, not a literal anyone typed.
 */
#include <stdio.h>

typedef unsigned long u64;

/* Nine `"m"` inputs plus one `"=r"` output. Ten register operands before,
   one after. */
static u64 msum9(const u64 *v)
{
	u64 acc = 1;
	asm volatile (
"\n		addq	%2, %0"
"\n		addq	%3, %0"
"\n		addq	%4, %0"
"\n		addq	%5, %0"
"\n		addq	%6, %0"
"\n		addq	%7, %0"
"\n		addq	%8, %0"
"\n		addq	%9, %0"
"\n		addq	%10, %0"
		: "=r" (acc)
		: "0" (acc), "m" (v[0]), "m" (v[1]), "m" (v[2]), "m" (v[3]),
		  "m" (v[4]), "m" (v[5]), "m" (v[6]), "m" (v[7]), "m" (v[8])
		: "cc"
	);
	return acc;
}

/* An `"m"` naming a plain local binds straight to that local's own slot --
   no carrier, no copy. The value must still be the one the C code just
   stored, which a stale carrier would get wrong. */
static u64 mlocal(u64 seed)
{
	u64 x = seed;
	u64 out = 0;
	x += 7;                       /* written AFTER the operand was named */
	asm volatile (
"\n		movq	%1, %0"
		: "=r" (out)
		: "m" (x)
	);
	return out;
}

/* Width: an `"m"` operand is read at the size the MNEMONIC's suffix names,
   not at the width of the slot it landed in. `mull` on an 8-byte slot must
   multiply the low dword only -- if the slot's own width reached the encoder
   this would be a `mulq` and the answer would be the full 64x64 product's low
   half, which for these inputs is a different number. */
static u64 mul32(u64 a, u64 b)
{
	u64 lo = 0, hi = 0;
	asm volatile (
"\n		mull	%3"
		: "=a" (lo), "=d" (hi)
		: "0" (a), "m" (b)
		: "cc"
	);
	return lo + (hi << 32);
}

int main(void)
{
	u64 v[9];
	int i;
	for (i = 0; i < 9; i++)
		v[i] = 1UL << (i * 7);
	printf("msum9 %lu\n", msum9(v));
	printf("mlocal %lu\n", mlocal(35));
	printf("mul32 %lu\n", mul32(0x100000003UL, 0x200000005UL));
	return 0;
}
