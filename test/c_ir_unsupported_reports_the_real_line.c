/* IR_UNSUPPORTED must name the line the construct is ON.
 *
 * `loff_t` is not declared by crtl, so this is not a declaration: `loff_t`
 * becomes an undeclared identifier "treated as 0", and `&offset` on the next
 * line is then the address of an INTEGER LITERAL (AN_INT_LIT = kind 1), which
 * IRLowerAddress cannot lower. Refusing is CORRECT -- this test is not about
 * the refusal, it is about WHERE the refusal says it happened.
 *
 * Before the fix (ir.inc, IR_UNSUPPORTED verify arm) this reported a position
 * in whichever builtin unit the LEXER had stopped in -- `unit builtinheap`
 * here, and `lib/crtl/src/sys/socket.c near cmsghdr` for busybox's
 * flash_eraseall. Both files compile cleanly on their own. Two sessions spent
 * two days in the files the message named.
 *
 * The test asserts the LINE, not merely that it fails: a check that only
 * asserted "this refuses" would have passed throughout the two days.
 * bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall
 */
extern int ioctl(int, unsigned long, ...);

int main(void)
{
	loff_t offset = 0;              /* line 23 -- the site, and the assertion */
	return ioctl(0, 1, &offset);
}
