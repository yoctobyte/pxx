/* _Generic must distinguish `long` from `int` and from `long long` even when the
   TARGET makes them the same width — the width is right, the C-level type identity
   was being lost (bug-c-generic-long-vs-int-ilp32):

     ILP32 (i386/arm32/riscv32): long is 32-bit, so it collapsed onto int
     LP64  (x86-64/aarch64):     long long is 64-bit, so it collapsed onto long

   Both directions silently selected the WRONG association, with no diagnostic. The
   answers below are target-independent: exercise this on every backend.

   Reordering the associations is deliberate: the old code got some of these "right"
   only because the first-listed association happened to be the one it collapsed to.

   exit 42 = all pass. */

int fail = 0;

static void want(int got, int expect, int id)
{
	if (got != expect)
		fail = id;
}

int main(void)
{
	int i = 1;
	long l = 2;
	unsigned long ul = 3;
	long long ll = 4;

	/* literals: the l/L suffix is the only thing that carries the type */
	want(_Generic(17, int : 1, long : 2, long long : 3), 1, 1);
	want(_Generic(17L, int : 1, long : 2, long long : 3), 2, 2);
	want(_Generic(17LL, int : 1, long : 2, long long : 3), 3, 3);

	/* variables — association order reversed, so a collapse cannot pass by luck */
	want(_Generic(i, long : 2, long long : 3, int : 1), 1, 4);
	want(_Generic(l, int : 1, long long : 3, long : 2), 2, 5);
	want(_Generic(ll, int : 1, long : 2, long long : 3), 3, 6);
	want(_Generic(ul, unsigned int : 1, unsigned long : 2), 2, 7);

	/* usual arithmetic conversions: the greater rank wins (C11 6.3.1.8) */
	want(_Generic(i + 2L, int : 1, long : 2, long long : 3), 2, 8);
	want(_Generic(i + 2LL, int : 1, long : 2, long long : 3), 3, 9);
	want(_Generic(i + 2, int : 1, long : 2, long long : 3), 1, 10);
	want(_Generic(l * i, int : 1, long : 2, long long : 3), 2, 11);

	/* a shift takes its type from the LEFT operand only */
	want(_Generic(1L << i, int : 1, long : 2, long long : 3), 2, 12);
	want(_Generic(1 << l, int : 1, long : 2, long long : 3), 1, 13);

	/* A comparison, `!`, and the logical operators all yield an INT in C (6.5.8p6,
	   6.5.3.3p5). The frontend tags them boolean internally, which used to match NO
	   association at all — a hard "no matching association" error on valid C. */
	want(_Generic(l < 2L, int : 1, long : 2), 1, 15);
	want(_Generic(!i, int : 1, long : 2), 1, 16);
	want(_Generic(i && 1, int : 1, long : 2), 1, 17);
	want(_Generic(i || 0, int : 1, long : 2), 1, 18);
	want(_Generic(ll > 0, int : 1, long : 2, long long : 3), 1, 19);

	if (fail != 0)
		return fail;
	return 42;
}
