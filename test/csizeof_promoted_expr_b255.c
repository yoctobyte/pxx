/* `sizeof(us + 0)` is 4, not 2: the integer promotions make `unsigned short + int`
   an int. ParseCSizeof had a fast path that sized an operand straight from its
   SYMBOL, and it fired on ANY leading identifier without checking that the operand
   ended there — so `sizeof(us + 0)` quietly measured `us` alone
   (bug-c-binary-op-no-integer-promotion-sizeof).

   `sizeof(-us)` was already right, but only because it does not begin with an
   identifier and so took the general expression path.

   The second half of this test is the part that matters: the fast path still has to
   handle everything it did before — struct fields, `->`, array members, deref, and
   the sizeof(arr)/sizeof(arr[0]) count idiom. Those are the cases the guard could
   have broken.

   exit 42 = all pass. */

struct Inner { int a; short b; };            /* 8 bytes */
struct Outer { struct Inner c[4]; struct Inner *head; int arr[10]; };

static int f(void) { return 1; }

int main(void)
{
	unsigned short us = 1;
	short ss = 1;
	unsigned char uc = 1;
	struct Outer o;
	struct Outer *p = &o;
	int a[10];
	int i = 2;

	/* promoted: anything narrower than int becomes int in an arithmetic expression */
	if (sizeof(us) != 2) return 1;            /* the operand ALONE is still 2 */
	if (sizeof(us + 0) != 4) return 2;
	if (sizeof(us + 1) != 4) return 3;
	if (sizeof(us * 1) != 4) return 4;
	if (sizeof(ss + 0) != 4) return 5;
	if (sizeof(uc + 0) != 4) return 6;
	if (sizeof(us + us) != 4) return 7;
	if (sizeof(-us) != 4) return 8;

	/* the symbol fast path must still size all of these correctly. Expectations are
	   composed rather than hard-coded, so the test is target-independent (a pointer
	   is 4 bytes on ILP32, 8 on LP64). */
	if (sizeof(o) != 4 * sizeof(struct Inner) + sizeof(void *) + 10 * sizeof(int)) return 9;
	if (sizeof(*p) != sizeof(o)) return 10;
	if (sizeof(o.arr) != 10 * sizeof(int)) return 11;
	if (sizeof(p->arr) != 10 * sizeof(int)) return 12;
	if (sizeof(p->c[0]) != sizeof(struct Inner)) return 13;
	if (sizeof(o.c) != 4 * sizeof(struct Inner)) return 14;
	if (sizeof(*p->head) != sizeof(struct Inner)) return 15;
	if (sizeof(a) != 10 * sizeof(int)) return 16;
	if (sizeof(a[0]) != sizeof(int)) return 17;
	if (sizeof(a[i + 1]) != sizeof(int)) return 18;  /* a '+' INSIDE brackets is still simple */
	if (sizeof(f()) != sizeof(int)) return 19;       /* a call is not a simple operand */

	/* the array-count idiom must keep working */
	if ((int)(sizeof(o.arr) / sizeof(o.arr[0])) != 10) return 20;
	if ((int)(sizeof(o.c) / sizeof(o.c[0])) != 4) return 21;

	return 42;
}
