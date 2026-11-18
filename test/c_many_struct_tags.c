/* A translation unit with more struct tags than the old 2048-slot record
   table (NetBSD syscallargs.h alone declares thousands), and a tag first
   named inside a block, completed later in the same block.
   rump-pxx g35, g38, g39. */
#include <stdio.h>

#define F1(n) struct f##n { struct f##n *self; int v; };
#define F10(n) F1(n##0) F1(n##1) F1(n##2) F1(n##3) F1(n##4) F1(n##5) F1(n##6) F1(n##7) F1(n##8) F1(n##9)
#define F100(n) F10(n##0) F10(n##1) F10(n##2) F10(n##3) F10(n##4) F10(n##5) F10(n##6) F10(n##7) F10(n##8) F10(n##9)
#define F1000(n) F100(n##0) F100(n##1) F100(n##2) F100(n##3) F100(n##4) F100(n##5) F100(n##6) F100(n##7) F100(n##8) F100(n##9)
F1000(1) F1000(2) F100(30)

/* past the old limit: a self-linked list member and a call through a
   function-pointer member inside ?: */
struct proc { struct { struct proc *le_next; struct proc **le_prev; } p_list; int p_flag; };
struct c { int n; int (*fn)(int); };
static int twice(int x) { return 2 * x; }
static int g(const struct c *cip) { return cip->n > 0 ? cip->fn(21) : 1; }

static int pend(void)
{
	static struct pend_head { struct pend_entry *slh_first; } pend_stack;
	struct pend_entry {
		struct { struct pend_entry *sle_next; } pe_entry;
		int pe_pending;
	} a = { { 0 }, 4 }, b = { { &a }, 6 };
	pend_stack.slh_first = &b;
	return pend_stack.slh_first->pe_pending * 10 + pend_stack.slh_first->pe_entry.sle_next->pe_pending;
}

int main(void)
{
	struct proc p1 = { { 0, 0 }, 1 }, p2 = { { &p1, 0 }, 2 };
	struct c cc = { 1, twice };
	struct f2999 last = { &last, 77 };
	printf("%d %d %d %d %d\n", p2.p_list.le_next->p_flag, g(&cc), pend(),
	       last.self->v, (int)sizeof(struct f1500));
	return 0;
}
