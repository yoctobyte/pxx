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
 * WHY TWO SHAPES. The parser used to count the operand sections and skip their
 * tokens on paren depth, so every unimplemented corner produced the same
 * sentence: "inline asm with a non-empty template is not supported". That is
 * true and it is useless — a reader cannot tell from it whether the missing
 * piece is a constraint class, an operand spelling, or a whole feature. The
 * operand sections are now captured, and the refusals run most-specific-first.
 * These assert that ordering, one compile each, selected by -d:
 *
 *   (default)       "+r"        -> read-write constraint, named
 *   SHAPE_SYMBOLIC  [a] "=r"    -> symbolic operand spelling, named
 *
 * There is no blanket refusal left behind them: every remaining refusal names a
 * construct. A third shape, plain "=r"/"r", lived here until the operand
 * binding landed and now COMPILES — it moved to casm_gnu_operands.c, which is
 * what a refusal test graduating into an acceptance test looks like.
 *
 * feature-c-gnu-inline-asm-with-a-non-empty-template */
int printf(const char *, ...);

int main(void)
{
	int x = 0;
#if defined(SHAPE_SYMBOLIC)
	asm volatile ("mov %[a], %[a]" : [a] "=r"(x));
#else
	asm volatile ("mov %0, %0" : "+r"(x));
#endif
	printf("%d\n", x);
	return 0;
}
