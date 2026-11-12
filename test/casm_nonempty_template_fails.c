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
 * This asserts that ordering:
 *
 *   "+r"        -> read-write constraint, named
 *
 * There is no blanket refusal left behind it: every remaining refusal names a
 * construct. Two shapes lived here and graduated into acceptance tests when
 * their support landed: plain "=r"/"r" (now casm_gnu_operands.c) and the
 * symbolic spelling [a] "=r" (2026-11-12, now casm_kernel_user_mode_subset.c).
 *
 * feature-c-gnu-inline-asm-with-a-non-empty-template */
int printf(const char *, ...);

int main(void)
{
	int x = 0;
	asm volatile ("mov %0, %0" : "+r"(x));
	printf("%d\n", x);
	return 0;
}
