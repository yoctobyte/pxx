/* SPDX-License-Identifier: MPL-2.0 */
/* GNU inline asm with a non-empty template, on i386.
 *
 * The i386 arms of busybox's networking/tls_sp_c32.c and
 * networking/tls_pstm_mul_comba.c, verbatim -- the files this feature exists
 * for. pxx answers __GNUC__ and __i386__ on this target, so those sources
 * SELECT these arms; refusing them is refusing code we told the preprocessor
 * to reach (bug-c-inline-asm-is-x86-64-only-so-five-busybox-tus-refuse-on-i386).
 *
 * WHY THE TWO BLOCKS ARE BOTH HERE AND NOT ONE. add8 is four "=r" outputs with
 * matching inputs and `(%N)` / `k*4(%N)` memory-through-a-pinned-register --
 * four of five pool entries. MULADD is the REGISTER-PRESSURE case: three "=rm"
 * outputs and two "m" inputs with %eax and %edx clobbered, which fits in
 * exactly the three registers a five-entry pool has left, and only because an
 * "m" operand is a frame slot rather than a pinned address. Drop either block
 * and the surviving one passes on a compiler that could not build busybox.
 *
 * The oracle is `gcc -m32` on this same source: the carries, the 64-bit
 * product split and the borrow are the machine's answers, not literals.
 * Inputs are chosen so a dropped carry cannot pass -- add8 adds 1 to a limb of
 * all-ones in every position, so every add must carry into the next.
 */
#include <stdio.h>

typedef unsigned int sp_digit;

/* --- sp_256_add_8's i386 arm, verbatim ----------------------------------- */
static int sp_256_add_8(sp_digit *r, const sp_digit *a, const sp_digit *b)
{
	sp_digit reg;
	asm volatile (
"\n		movl	(%0), %3"
"\n		addl	(%1), %3"
"\n		movl	%3, (%2)"
"\n"
"\n		movl	1*4(%0), %3"
"\n		adcl	1*4(%1), %3"
"\n		movl	%3, 1*4(%2)"
"\n"
"\n		movl	2*4(%0), %3"
"\n		adcl	2*4(%1), %3"
"\n		movl	%3, 2*4(%2)"
"\n"
"\n		movl	3*4(%0), %3"
"\n		adcl	3*4(%1), %3"
"\n		movl	%3, 3*4(%2)"
"\n"
"\n		movl	4*4(%0), %3"
"\n		adcl	4*4(%1), %3"
"\n		movl	%3, 4*4(%2)"
"\n"
"\n		movl	5*4(%0), %3"
"\n		adcl	5*4(%1), %3"
"\n		movl	%3, 5*4(%2)"
"\n"
"\n		movl	6*4(%0), %3"
"\n		adcl	6*4(%1), %3"
"\n		movl	%3, 6*4(%2)"
"\n"
"\n		movl	7*4(%0), %3"
"\n		adcl	7*4(%1), %3"
"\n		movl	%3, 7*4(%2)"
"\n"
"\n		sbbl	%3, %3"
"\n"
		: "=r" (a), "=r" (b), "=r" (r), "=r" (reg)
		: "0" (a), "1" (b), "2" (r)
		: "memory"
	);
	return reg;
}

/* --- tls_pstm_mul_comba.c's MULADD, PSTM_X86 arm, verbatim --------------- */
static void muladd(sp_digit i, sp_digit j,
                   sp_digit *pc0, sp_digit *pc1, sp_digit *pc2)
{
	sp_digit c0 = *pc0, c1 = *pc1, c2 = *pc2;
	asm(
	 "movl  %6,%%eax     \n\t"
	 "mull  %7           \n\t"
	 "addl  %%eax,%0     \n\t"
	 "adcl  %%edx,%1     \n\t"
	 "adcl  $0,%2        \n\t"
	 :"=rm"(c0), "=rm"(c1), "=rm"(c2)
	 :"0"(c0), "1"(c1), "2"(c2), "m"(i), "m"(j)
	 :"%eax","%edx","cc");
	*pc0 = c0; *pc1 = c1; *pc2 = c2;
}


/* --- tls_pstm_montgomery_reduce.c's INNERMUL and PROPCARRY, PSTM_X86 arm ---
 *
 * Three things at once, and each was a separate refusal before:
 *   "=g"   a class this frontend did not read -- a register is one of the
 *          choices `g` permits, so taking one honours it rather than
 *          approximating it. Five uses across these two blocks.
 *   "=&d"  earlyclobber. Every operand is pinned to a register of its own and
 *          the only sharing is an explicit matching constraint, so `&` holds
 *          by construction. This row is what says so out loud.
 *   _c[LO] an output that is a SUBSCRIPT, not a name. It is evaluated twice --
 *          once as the store target and once for the "0" input tied to it --
 *          which is a wrong answer only if evaluating it once changes
 *          something, and a subscript of two locals does not.
 */
#define LO 0
static void innermul(sp_digit *_c, sp_digit mu, const sp_digit *tmpm,
                     sp_digit *pcy)
{
	sp_digit cy = *pcy;
	asm(
	   "mull %4       \n\t"
	   "addl %3,%%eax \n\t"
	   "adcl $0,%%edx \n\t"
	   "addl %%eax,%0 \n\t"
	   "adcl $0,%%edx \n\t"
	:"=g"(_c[LO]), "=&d"(cy)
	:"0"(_c[LO]), "g"(cy), "g"(mu), "a"(*tmpm)
	:"cc");
	*pcy = cy;
}

static void propcarry(sp_digit *_c, sp_digit *pcy)
{
	sp_digit cy = *pcy;
	asm(
	   "addl   %1,%0    \n\t"
	   "sbb    %1,%1    \n\t"
	   "neg    %1       \n\t"
	:"=g"(_c[LO]), "=r"(cy)
	:"0"(_c[LO]), "1"(cy)
	:"cc");
	*pcy = cy;
}

/* --- powertop.c's cpuid, verbatim ----------------------------------------
 *
 * "=b" names ebx, which this backend PRESERVES (ir_codegen386.inc pushes and
 * pops it wherever it uses it), so the block gets a push/pop pair around it.
 * `cpuid` writes ebx and there is nothing for us to re-choose.
 *
 * The outputs are *eax, *ebx, ... -- dereferences, not names, which is the
 * same side-effect-free-lvalue rule the montgomery blocks need.
 *
 * WHAT THIS ROW CAN AND CANNOT SEE. The VALUES are diffed against gcc -m32 on
 * this same machine, so a mis-plumbed "=b" -- the output not actually coming
 * from ebx -- fails here. That ebx is RESTORED for the caller is not
 * observable from C: it would take a caller that keeps a value in ebx across
 * the block, which C gives no way to write. Asserted structurally instead
 * (the emitted block carries the 0x53/0x5b pair) and stated here rather than
 * left for a reader to assume from a passing row.
 */
static void cpuid(unsigned int *eax, unsigned int *ebx, unsigned int *ecx,
                  unsigned int *edx)
{
	asm (
		"	cpuid\n"
		: "=a"(*eax), "=b"(*ebx), "=c"(*ecx), "=d"(*edx)
		: "0"(*eax), "1"(*ebx), "2"(*ecx), "3"(*edx)
	);
}

int main(void)
{
	sp_digit a[8], b[8], r[8];
	sp_digit c0, c1, c2;
	int i, carry;

	for (i = 0; i < 8; i++) { a[i] = 0xFFFFFFFFu; b[i] = 0; }
	b[0] = 1;                       /* every limb must carry into the next */
	carry = sp_256_add_8(r, a, b);
	printf("add8");
	for (i = 0; i < 8; i++) printf(" %u", r[i]);
	printf(" carry=%d\n", carry);

	c0 = 0xFFFFFFFEu; c1 = 0xFFFFFFFFu; c2 = 5;
	muladd(0x10000003u, 0x20000005u, &c0, &c1, &c2);
	printf("muladd %u %u %u\n", c0, c1, c2);

	c0 = 0; c1 = 0; c2 = 0;
	muladd(3u, 5u, &c0, &c1, &c2);
	printf("muladd %u %u %u\n", c0, c1, c2);

	{
		sp_digit acc[2], mu, tmpm[1], cy;
		acc[0] = 0xFFFFFFF0u; acc[1] = 0; mu = 0x00010007u;
		tmpm[0] = 0x00020003u; cy = 9;
		innermul(acc, mu, tmpm, &cy);
		printf("innermul %u %u\n", acc[0], cy);

		acc[0] = 0xFFFFFFFEu; cy = 7;
		propcarry(acc, &cy);
		printf("propcarry %u %u\n", acc[0], cy);
	}

	{
		unsigned int ea = 0, eb = 0, ec = 0, ed = 0;
		cpuid(&ea, &eb, &ec, &ed);
		/* leaf 0: eax = max leaf, ebx/edx/ecx = the vendor string. Machine
		   facts, not portable ones -- which is why the oracle is gcc -m32 on
		   this same box rather than a literal. */
		printf("cpuid %u %08x %08x %08x\n", ea, eb, ec, ed);
	}
	return 0;
}
