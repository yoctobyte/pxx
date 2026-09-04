/* IR_UNSUPPORTED must name the line the construct is ON.
 *
 * `pxx_no_such_type_t` is declared NOWHERE -- deliberately a name crtl will
 * never grow -- so this is not a declaration: it becomes an undeclared
 * identifier "treated as 0", and `&offset` on the next line is then the
 * address of an INTEGER LITERAL (AN_INT_LIT = kind 1), which IRLowerAddress
 * cannot lower. Refusing is CORRECT -- this test is not about the refusal, it
 * is about WHERE the refusal says it happened.
 *
 * IT USED TO SAY `loff_t`, and that was a fixture borrowed from a real crtl
 * gap. Adding `loff_t` to <sys/types.h> on 2026-09-04 made the fixture compile
 * and this test fail for a reason that had nothing to do with the diagnostic.
 * A test whose fixture is somebody else's bug passes until that bug is fixed.
 *
 * The test asserts the LINE, not merely that it fails: a check that only
 * asserted "this refuses" would have passed throughout the two days this cost.
 * bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall
 */
extern int ioctl(int, unsigned long, ...);

int main(void)
{
	pxx_no_such_type_t offset = 0;  /* line 23 -- the site, and the assertion */
	return ioctl(0, 1, &offset);
}
