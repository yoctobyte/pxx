/* An undeclared identifier in a FILE-SCOPE initializer must be refused.
 *
 * All four shapes below produced NO DIAGNOSTIC AT ALL and folded to 0 until
 * 2026-09-05 — not a warning, nothing, and the object linked. The function-body
 * arm had been a hard error since a157e88ee, so the loud half was fixed while
 * the quiet half stayed; this is the quiet half.
 *
 * THIS IS THE ARM A crtl CONSTANT GAP ACTUALLY TRAVELS THROUGH.
 * `static const int f = O_NOFOLLOW;` is exactly row 4, and `bb0c9c1ff` found
 * eighteen such constants silently zero across eleven busybox translation
 * units — ETH_P_IP binding a packet socket to nothing, IPDEFTTL dropped by the
 * first router, O_NOFOLLOW as a security guard switched off. Every one of
 * those was found because it WARNED, which means it was in a function body.
 * Nothing could have found these: a census that counts diagnostics returns
 * zero for a silent arm whether it is clean or not.
 *
 * It was found by a positive control failing, not by a report — an undeclared
 * name injected into a real busybox TU compiled `ok:` with nothing to say.
 *
 * The COMPANION test is the one that matters more:
 * test/c_const_expr_legit_identifiers.c pins the population this must not
 * break — an identifier in a constant expression that is DECLARED but not
 * constant is a VLA, not a mistake, and `FindSym` is what separates them.
 *
 * gcc -std=gnu99 errors on every row.
 * bug-c-an-undeclared-identifier-in-a-file-scope-initializer-is-silent
 */
int a = NO_SUCH_A;                  /* scalar                        */
int b = NO_SUCH_B + 1;              /* scalar inside an expression   */
int arr[3] = { NO_SUCH_C, 2, 3 };   /* INTEGER element of an aggregate */
static int s = NO_SUCH_E;           /* file-scope static             */

int main(void) { return a + b + arr[0] + s; }
