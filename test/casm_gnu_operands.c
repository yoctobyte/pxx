/* GNU extended inline asm with real operands, on x86-64.
 *
 * The blocks below are not miniatures: two of them are lifted verbatim from
 * busybox networking/tls_sp_c32.c, which is the whole reason this feature
 * exists — its x86-64 arms are taken because pxx announces __GNUC__, and their
 * refusal took a 400-object link down with `undefined reference to
 * curve_P256_compute_pubkey_and_premaster`.
 *
 * WHAT EACH BLOCK IS FOR
 *
 *   add3     the smallest thing that can work: one output, two inputs, all "r".
 *   add8     sp_256_add_8's x86-64 arm, verbatim. Four "=r" outputs, three
 *            MATCHING inputs ("0" "1" "2"), a memory clobber, and a carry chain
 *            through adcq. Tied constraints are the cheap case here rather than
 *            the dear one: operand N is pinned to a fixed register, so "0"(a)
 *            just means "load a into that same register".
 *   mul1     sp_256to512_mul_8's inner block, verbatim. "=rm" outputs, a fixed
 *            register constraint ("a", which mulq needs), a memory operand
 *            ("m", whose ADDRESS is what gets pinned), and a "dx" clobber that
 *            must keep rdx out of the pool — mulq writes rdx:rax implicitly.
 *   submod   sp_256_sub_8_p256_mod's x86-64 arm, verbatim. The odd one: `cmc`,
 *            an immediate tied to an output ("1" (0x00000000ffffffff), so the
 *            pinned register is loaded from a CONSTANT rather than a variable),
 *            and a template that writes through %0 into memory it was handed.
 *
 * Between them these are all four of the x86-64-reachable asm blocks in that
 * file — sp_256_sub_8's arm is add8's, with subq/sbbq for addq/adcq, and is the
 * one shape not repeated here.
 *
 * THE ORACLE IS gcc, not a remembered number. Every expected value below is
 * what `gcc -O0` prints for this same file, which compiles both arms from the
 * same source; the point of the exercise is that pxx's arm agrees with the
 * compiler whose dialect we are claiming to implement. The inputs are chosen so
 * a dropped carry cannot pass: add8 adds 1 to all-ones so the carry ripples
 * through all four 64-bit limbs and out, and every printed limb is 0 only if
 * every adcq propagated.
 *
 * feature-c-gnu-inline-asm-with-a-non-empty-template */

typedef unsigned int sp_digit;
typedef unsigned long long u64;
int printf(const char *, ...);

/* --- the smallest working shape ------------------------------------------ */
static long add3(long a, long b)
{
	long r;
	asm volatile ("movq %1, %0\n\taddq %2, %0"
		: "=r" (r)
		: "r" (a), "r" (b));
	return r;
}

/* --- sp_256_add_8, x86-64 arm, verbatim ---------------------------------- */
static int add8(sp_digit* r, const sp_digit* a, const sp_digit* b)
{
	u64 reg;
	asm volatile (
"\n		movq	(%0), %3"
"\n		addq	(%1), %3"
"\n		movq	%3, (%2)"
"\n"
"\n		movq	1*8(%0), %3"
"\n		adcq	1*8(%1), %3"
"\n		movq	%3, 1*8(%2)"
"\n"
"\n		movq	2*8(%0), %3"
"\n		adcq	2*8(%1), %3"
"\n		movq	%3, 2*8(%2)"
"\n"
"\n		movq	3*8(%0), %3"
"\n		adcq	3*8(%1), %3"
"\n		movq	%3, 3*8(%2)"
"\n"
"\n		sbbq	%3, %3"
"\n"
		: "=r" (a), "=r" (b), "=r" (r), "=r" (reg)
		: "0" (a), "1" (b), "2" (r)
		: "memory"
	);
	return reg != 0;
}

/* --- sp_256to512_mul_8's inner accumulate, x86-64 arm, verbatim ----------- */
static void mul1(const u64* aa, const u64* bb, int i, int j,
                 u64* out_lo, u64* out_hi, u64* out_x)
{
	u64 accl = *out_lo, acch = *out_hi, acc_hi = *out_x;
	asm volatile (
"\n			mulq	%7"
"\n			addq	%%rax, %0"
"\n			adcq	%%rdx, %1"
"\n			adcq	$0, %2"
		: "=rm" (accl), "=rm" (acch), "=rm" (acc_hi)
		: "0" (accl), "1" (acch), "2" (acc_hi), "a" (aa[i]), "m" (bb[j])
		: "cc", "dx"
	);
	*out_lo = accl; *out_hi = acch; *out_x = acc_hi;
}

/* --- sp_256_sub_8_p256_mod, x86-64 arm, verbatim -------------------------- */
static void submod(u64* r)
{
	u64 reg;
	u64 ooff;

	asm volatile (
"\n		addq	$1, (%0)"	/* adding 1 is the same as subtracting ffffffffffffffff */
"\n		cmc"			/* only carry bit needs inverting */
"\n"
"\n		sbbq	%1, 1*8(%0)"	/* %1 holds 00000000ffffffff */
"\n"
"\n		sbbq	$0, 2*8(%0)"
"\n"
"\n		movq	3*8(%0), %2"
"\n		sbbq	$0, %2"		/* adding 00000000ffffffff (in %1) */
"\n		addq	%1, %2"		/* is the same as subtracting ffffffff00000001 */
"\n		movq	%2, 3*8(%0)"
"\n"
		: "=r" (r), "=r" (ooff), "=r" (reg)
		: "0" (r), "1" (0x00000000ffffffffULL)
		: "memory"
	);
}

int main(void)
{
	sp_digit a[8], b[8], r[8];
	u64 aa[1], bb[1], lo, hi, x;
	int i;

	printf("add3 %ld\n", add3(7, 5));

	for (i = 0; i < 8; i++) { a[i] = 0xffffffffu; b[i] = 0; r[i] = 0; }
	b[0] = 1;                       /* ripples a carry through every limb */
	i = add8(r, a, b);
	printf("add8");
	{ int k; for (k = 0; k < 8; k++) printf(" %u", r[k]); }
	printf(" carry=%d\n", i);

	/* 2^64-1 squared, accumulated onto a nonzero running total: exercises
	 * both halves of mulq's result and the adcq chain above them. */
	aa[0] = 0xffffffffffffffffULL;
	bb[0] = 0xffffffffffffffffULL;
	lo = 3; hi = 0; x = 0;
	mul1(aa, bb, 0, 0, &lo, &hi, &x);
	printf("mul1 %llu %llu %llu\n", lo, hi, x);

	{
		u64 m[4];
		m[0] = 0; m[1] = 0; m[2] = 0; m[3] = 0;   /* 0 - p256 borrows through every limb */
		submod(m);
		printf("submod %llu %llu %llu %llu\n", m[0], m[1], m[2], m[3]);
	}
	return 0;
}
