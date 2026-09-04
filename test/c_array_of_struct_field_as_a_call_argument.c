/* An ARRAY FIELD whose elements are structs, passed to a function by its bare
 * name: `f(s.arr)`. C says it decays to &s.arr[0]. pxx passed the address of a
 * one-element TEMP COPY instead, so everything the callee wrote was discarded.
 *
 * WHY IT WAS INVISIBLE FOR SO LONG. An array node carries its ELEMENT's type
 * tag -- there is nowhere else on the node to put a kind -- so the argument
 * lowering saw tyRecord and took the C struct-by-value path, which copies to a
 * temp and passes &temp. The guard that exists to stop exactly this asked only
 * about AN_IDENT: a bare `arr` was covered and `s.arr` was not. And the temp
 * path only triggers for a record element OVER 8 BYTES, so every non-struct
 * element type decayed correctly -- which is why rows 1-4 below are controls
 * and not filler.
 *
 * ROWS 5 AND 6 ARE THE ONES THAT MATTER, AND THEY WRITE. An address comparison
 * alone is a weaker instrument than it looks: the defect is not a wrong-looking
 * pointer, it is a pointer to different memory, so the failure mode is that the
 * callee's stores go somewhere the caller never reads. Row 5 checks identity,
 * row 6 checks that a write through the argument is VISIBLE to the caller --
 * that is the assertion class the bug is physically able to fail.
 *
 * WHERE IT LANDED: busybox's sed passes `G.regmatch` (ten regmatch_t) to
 * regexec, which filled a temp nobody read. do_subst_command then took its
 * match offsets from the untouched array, got 0/0 for a match at 14..18, and
 * either substituted at the wrong place or ran `line` off the end and SIGSEGV'd
 * -- three layers from the cause, with crtl's regexec correct in isolation and
 * every sizeof and offset in the program correct too. `&s.e[0]` and
 * `p = s.e` were both right: ONE SPELLING OF THE SAME ADDRESS was wrong.
 *
 * The element struct is 12 bytes ON PURPOSE -- over the 8-byte threshold that
 * selects the temp path, and not a size that coincides with a pointer.
 */
#include <stdio.h>

struct Big { int a, b, c; };          /* 12 bytes: over the by-value threshold */

struct S {
	int         pad;
	char        c[16];
	int         i[8];
	double      d[4];
	int         g[2][3];
	struct Big  e[5];
};

static struct S s;

static long delta(const void *p, const void *q)
{
	return (long)((const char *)p - (const char *)q);
}

/* Takes the decayed pointer and WRITES through it. */
static void fill(struct Big *p, int n)
{
	int k;
	for (k = 0; k < n; k++) { p[k].a = 100 + k; p[k].b = 200 + k; p[k].c = 300 + k; }
}

int main(void)
{
	printf("1 %ld\n", delta(s.c, &s.c[0]));
	printf("2 %ld\n", delta(s.i, &s.i[0]));
	printf("3 %ld\n", delta(s.d, &s.d[0]));
	printf("4 %ld\n", delta(s.g[0], &s.g[0][0]));
	printf("5 %ld\n", delta(s.e, &s.e[0]));

	fill(s.e, 5);
	printf("6 %d %d %d %d\n", s.e[0].a, s.e[0].b, s.e[4].a, s.e[4].c);

	/* A local aggregate takes a different storage path than a global one. */
	{
		struct S loc;
		printf("7 %ld\n", delta(loc.e, &loc.e[0]));
		fill(loc.e, 5);
		printf("8 %d %d\n", loc.e[0].a, loc.e[4].c);
	}
	/* And through a pointer base, which is how busybox spells it:
	   #define G (*(struct globals*)buf) */
	{
		struct S *sp = &s;
		printf("9 %ld %ld\n", delta(sp->e, &sp->e[0]), delta((*sp).e, &s.e[0]));
	}
	return 0;
}
