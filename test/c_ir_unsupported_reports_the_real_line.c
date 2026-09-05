/* IR_UNSUPPORTED must name the line the construct is ON.
 *
 * `&K` takes the address of an ENUM CONSTANT. That is not an lvalue, so the
 * argument is an AN_INT_LIT (AST node kind 1), which IRLowerAddress cannot
 * lower. Refusing is CORRECT -- this test is not about the refusal, it is
 * about WHERE the refusal says it happened.
 *
 * THE FIXTURE HAS BEEN WRONG TWICE, THE SAME WAY BOTH TIMES: it borrowed
 * somebody else's gap to manufacture the node. First `loff_t`, a real crtl
 * hole -- adding it to <sys/types.h> on 2026-09-04 made the fixture compile
 * and this test fail for a reason unrelated to the diagnostic. Then
 * `pxx_no_such_type_t`, chosen because crtl would never grow it -- and on
 * 2026-09-05 the ground moved the other way, when an undeclared identifier
 * used as a value became a hard error
 * (bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error).
 * The compile then stopped at the undeclared name and never reached IR
 * lowering at all, so the assertion below could not fire.
 *
 * An enum constant ends that: it is a construct the language DEFINES, declared
 * right here, depending on no gap in anything. Nobody can fix it out from
 * under this test, in either direction.
 *
 * The test asserts the LINE, not merely that it fails: a check that only
 * asserted "this refuses" would have passed throughout the two days this cost.
 * bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall
 */
extern int ioctl(int, unsigned long, ...);

enum { K = 7 };

int main(void)
{
	return ioctl(0, 1, &K);  /* line 33 -- the site, and the assertion */
}
