/* Inline asm with real instructions must be REFUSED, not silently dropped.
 *
 * This file must NOT compile. Accepting the barrier form (casm_barrier.c
 * beside this) is only safe because an empty template emits nothing and means
 * nothing to the machine. A template with instructions in it does mean
 * something, and parsing-then-discarding it would silently miscompile exactly
 * the code that cares most about what the machine does — which is the
 * failure class this project treats as its most expensive.
 *
 * feature-c-gcc-extended-inline-asm */
int printf(const char *, ...);

int main(void)
{
	int x = 0;
	asm volatile ("mov %0, %0" : "+r"(x));
	printf("%d\n", x);
	return 0;
}
