/* An asm block inside a body the INLINER clones.

   -O3's non-leaf slice copies a whole procedure body into its caller, through
   CloneToInlineRegion (inline_expand.inc) and IRCloneInlineBody (ir.inc). Both
   are generic cloners: a few special kind arms, then

       ASTLeft[r] := Clone(ASTLeft[node]); ASTRight[r] := Clone(ASTRight[node])

   with no idea that those two slots are OVERLOADED PER KIND. CloneToInlineRegion
   guards with `if ASTLeft[node] >= 0`, which does NOT help -- an AsmBytes
   offset, a VMT slot, a record id and a 0/1 flag are all >= 0. The guard is
   aimed at an absent child, not at a payload.

   Measured 2026-09-02: at -O3 these two clone AN_CALL nodes in BULK (39k+ of
   them across test/), and every one carried ASTRight = -1, so the corpus never
   reached the corrupting case. The frontends that DO park a record id there
   are NilPy's; C and Pascal leave it -1. That is a reachability accident, not
   a guarantee, which is why the cloners now ask ast_arena.inc's overload table
   and copy a payload slot verbatim instead of cloning it.

   This test pins the ASM half, which is the one C can reach: an inline body
   whose AN_ASM would otherwise have its byte offset and length cloned as if
   they were subtrees. Run at -O3 (where the inliner fires) AND at the default,
   because a test that only ever exercises the non-inlining level is a test of
   the wrong population.

   bug-a-generic-astleft-astright-walkers-recurse-into-kinds-that-overload-those-fields */

int printf(const char *, ...);

static inline int addasm(int a, int b)
{
	int r;
	__asm__("nop\n\tnop\n\tnop\n\tnop");
	r = a + b;
	__asm__("nop");
	return r;
}

static inline int twice(int a)
{
	return addasm(a, a);            /* nested: the clone of a clone */
}

int main(void)
{
	int i, s = 0;
	for (i = 0; i < 5; i++)
		s += twice(i) + addasm(i, 1);
	printf("%d %d %d\n", s, twice(7), addasm(2, 3));
	return 0;
}
