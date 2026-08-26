/* GCC extended inline asm, the only form pxx accepts: a COMPILER BARRIER.
 *
 * It was not recognised at all — `asm` parsed as an ordinary call, so a bare
 * `asm("")` failed as `call to undeclared function: asm`, and with operand
 * sections as `Expected: ), but got:` at the first ':'. busybox reaches it
 * through libbb.h's
 *
 *     #define barrier() asm volatile ("":::"memory")
 *
 * which SET_PTR_TO_GLOBALS -> INIT_G() / INIT_S() expands, so coreutils/test.c,
 * editors/ed.c and util-linux/acpid.c each stopped on their function's FIRST
 * statement.
 *
 * An empty template with no output operands orders the COMPILER, not the
 * machine, and pxx does not reorder across a statement boundary — so compiling
 * it to nothing is correct, and it is the only case accepted. Everything else
 * is refused by name: parsing real instructions and dropping them would
 * silently miscompile exactly the code that cares most about what the machine
 * does. The refusals are asserted by casm_nonempty_template_fails.c beside this.
 *
 * feature-c-gcc-extended-inline-asm
 * Oracle: gcc -O0, diffed. */
int printf(const char *, ...);

#define barrier() asm volatile ("":::"memory")

static int counter;

static void bump(void)
{
	counter++;
	barrier();
	counter++;
}

int main(void)
{
	int x = 41;

	asm("");                              /* bare, no volatile, no sections */
	asm volatile ("");                    /* volatile */
	__asm__ volatile ("");                /* the reserved spelling */
	__asm ("");                           /* and the short one */
	asm volatile ("":::"memory");         /* clobbers, unspaced — busybox's */
	asm volatile ("" ::: "memory");       /* clobbers, spaced */
	asm volatile ("" : : : "memory");     /* all three sections, empty */
	asm volatile ("" "" ::: "memory");    /* adjacent template literals */

	x++;
	barrier();
	x++;

	bump();
	printf("%d %d\n", x, counter);
	return 0;
}
