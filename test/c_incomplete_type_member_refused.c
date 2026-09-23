/* Taking a MEMBER from a type whose layout is unknown must be refused.
 *
 * Every shape below compiled clean and produced a working binary until
 * 2026-09-24, and the generated code read a PLAUSIBLE WRONG VALUE rather than
 * trapping: RecFieldOffset answers 0 both for "this field is at offset 0" and
 * for "there is no such field", so an unknown member resolves to offset 0 and
 * aliases the first real one. `v.a=11; v.b=22; v.typo=99' printed a=99 b=22.
 *
 * THE TWO ARMS ARE ONE MECHANISM, which is why they are one test. An
 * undeclared tag does NOT leave the base unresolved -- the frontend allocates
 * an EMPTY record for it -- so `struct nosuchtype v; v.field' and a typo'd
 * member on a fully known struct arrive at the identical not-found path. Only
 * the size distinguishes them, and only for the wording.
 *
 * COUNTED PER ARM, NOT IN TOTAL. A single check that collapsed both arms into
 * one message would still produce six diagnostics for six accesses and pass a
 * total; it would fail here, because the incomplete-type wording carries
 * information the other does not (there is no definition to look at, so the
 * reader should go find the header, not check their spelling).
 *
 * HOW IT SURFACED: <sys/ioctl.h> declared TIOCGWINSZ but not `struct winsize',
 * so the canonical `struct winsize ws; ioctl(1, TIOCGWINSZ, &ws)' compiled,
 * the syscall SUCCEEDED (rc=0, the kernel really filled the struct), and
 * ws.ws_col printed 8650792 == 0x00840028 -- the correct 132 and 40 read as
 * one 32-bit field. Every signal the caller had said it worked.
 *
 * The COMPANION test is the one that matters more:
 * test/c_incomplete_type_legal_shapes.c pins the population this must not
 * break -- pointers to incomplete types and forward declarations are legal C
 * and this tree's own headers use them.
 *
 * gcc refuses every row.
 * bug-c-an-undeclared-struct-type-compiles-and-reads-garbage
 */
struct known { int a; int b; };

/* THE INCOMPLETE ARM -- the tag is never defined anywhere in this file. */
int inc_write(void)  { struct nosuchtype v; v.field = 3; return 0; }
int inc_read(void)   { struct nosuchtype v; return v.field; }
int inc_arrow(struct nosuchtype *p) { return p->field; }

/* THE TYPO ARM -- the struct is fully known and the member is not its. */
int typo_write(void) { struct known v; v.typo = 3; return 0; }
int typo_read(void)  { struct known v; return v.typo; }
int typo_arrow(struct known *p) { return p->typo; }

int main(void) { return 0; }
