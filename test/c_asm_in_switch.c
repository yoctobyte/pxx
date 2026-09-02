/* An asm block inside a SWITCH ARM, which is how AN_ASM reaches
   IRLowerCSwitchDispatchScan -- the scan walks the whole switch body looking
   for AN_CASE / AN_DEFAULT markers, and it is generic: it recurses through
   ASTLeft/ASTRight of every node it does not recognise.

   AN_ASM's ASTLeft is an AsmBytes OFFSET and its ASTRight a LENGTH, not node
   references, so the scan used to index ASTKind with a byte offset and walk an
   unrelated subtree. Measured 2026-09-02 with a probe in the scan: on
   `switch (x) { case 1: __asm__("nop"); ... }` it really does recurse into
   nodes 63 and 1 of a tree with 8918 of them. Nothing observable came out of
   it in 306 generated shapes diffed against gcc -- the subtrees it wanders
   into happen to contain no case marker -- but "the walk is wrong and today's
   trees are lucky" is not a property to rely on, and the sibling instance of
   the same walk (AN_PTR_CAST's signature index) SEGFAULTED the compiler with
   no diagnostic while building busybox's ash.

   WHAT THIS ASSERTS is that every arm still dispatches. A stolen or spurious
   label shows up as a wrong arm taken, a missing one, or `invalid IR
   conditional jump target` at compile time -- all three are visible here,
   because every case returns a value unique to itself and main prints the
   whole fan.

   THE SHAPES ARE CHOSEN, not sampled: a multi-instruction template (so the
   byte offset is large and lands far from the block's own node), an arm with
   asm and NOTHING else, a nested switch (which owns its own labels and must
   not have them stolen), an asm arm that falls through to the next, and the
   default arm. Two asm blocks precede the switch so the offsets inside it are
   nonzero -- offset 0 is the one value that reads back as node 0, whose own
   ASTLeft is 0, and that is the recursion fixed point the ash segfault hit.

   bug-a-generic-astleft-astright-walkers-recurse-into-kinds-that-overload-those-fields */

int printf(const char *, ...);

static void pad(void)
{
	__asm__("nop\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop");
	__asm__("nop\n\tnop\n\tnop\n\tnop");
}

static int inner(int x)
{
	int r = 0;
	switch (x) {
	case 0: r = 100; break;
	case 1: __asm__("nop"); r = 101; break;
	default: r = 109;
	}
	return r;
}

static int outer(int x)
{
	int r = 0;
	switch (x) {
	case 0:
		__asm__("nop\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop");
		r = 10;
		break;
	case 1:
		__asm__("nop");          /* an arm that is nothing BUT asm, then falls through */
	case 2:
		r += 20;
		break;
	case 3:
		r = inner(1);            /* a nested switch: its labels are its own */
		break;
	case 4:
		__asm__("nop\n\tnop");
		r = inner(0);
		break;
	default:
		__asm__("nop");
		r = 99;
	}
	return r;
}

int main(void)
{
	int i;
	pad();
	for (i = 0; i < 6; i++)
		printf(i ? " %d" : "%d", outer(i));
	printf("\n");
	return 0;
}
