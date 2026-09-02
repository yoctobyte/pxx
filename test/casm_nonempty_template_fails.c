/* Inline asm with real instructions must be REFUSED, not silently dropped —
 * and the refusal must NAME what is unsupported.
 *
 * This file must NOT compile, in any of its three shapes. Accepting the
 * barrier form (casm_barrier.c beside this) is only safe because an empty
 * template emits nothing and means nothing to the machine. A template with
 * instructions in it does mean something, and parsing-then-discarding it would
 * silently miscompile exactly the code that cares most about what the machine
 * does — which is the failure class this project treats as its most expensive.
 *
 * WHY THREE SHAPES. The parser used to count the operand sections and skip
 * their tokens on paren depth, so every unimplemented corner produced the same
 * sentence: "inline asm with a non-empty template is not supported". That is
 * true and it is useless — a reader cannot tell from it whether the missing
 * piece is a constraint class, an operand spelling, or a whole feature. The
 * operand sections are now captured, and the refusals run most-specific-first.
 * These three assert that ordering, one compile each, selected by -d:
 *
 *   (default)       "+r"        -> read-write constraint, named
 *   SHAPE_SYMBOLIC  [a] "=r"    -> symbolic operand spelling, named
 *   SHAPE_PLAIN     "=r" / "r"  -> the constraints are fine; %N substitution
 *                                  is what does not exist yet
 *
 * There is no blanket refusal left behind these: a template with no operands
 * to substitute is now READ (compiler/asmatt.inc), so every remaining refusal
 * names a construct. SHAPE_PLAIN is the one with a lifecycle — it is the
 * vocabulary the busybox tls_sp_c32.c work is building towards, so when
 * "=r"/"r" bind to real operands this shape becomes an ACCEPTANCE test.
 *
 * feature-c-gnu-inline-asm-with-a-non-empty-template */
int printf(const char *, ...);

int main(void)
{
	int x = 0;
#if defined(SHAPE_SYMBOLIC)
	asm volatile ("mov %[a], %[a]" : [a] "=r"(x));
#elif defined(SHAPE_PLAIN)
	int y = 1;
	asm volatile ("mov %1, %0" : "=r"(x) : "r"(y));
#else
	asm volatile ("mov %0, %0" : "+r"(x));
#endif
	printf("%d\n", x);
	return 0;
}
