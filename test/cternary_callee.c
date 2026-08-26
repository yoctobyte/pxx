/* A ternary may be the CALLEE of a call.
 *
 * `(*fp)(a)`, `(fp)(a)`, `(name)(a)`, `(a, fn)(x)`, `arr[i](a)` and
 * `s.f[i](a)` were all recognised; `(c ? f : g)(a)` was not, and the parse died
 * as `Expected: ), but got:` at the `?`. busybox opens copy_file.c with
 *
 *     if ((FLAGS_DEREF ? stat : lstat)(source, &source_stat) < 0)
 *
 * and coreutils/stat.c has the same shape.
 *
 * CNodeProcSig is a chain of arms, one per node shape, so the fix RECURSES the
 * way the AN_COMMA arm above it already does rather than adding another shape:
 * a ternary's arms are function-pointer expressions in their own right, and
 * every shape the chain knows is legal there. C requires the two arms to have
 * compatible types, so either supplies the signature.
 *
 * bug-c-a-ternary-cannot-be-the-callee-of-a-call
 * Oracle: gcc -O0, diffed. */
int printf(const char *, ...);

static int add(int a, int b) { return a + b; }
static int sub(int a, int b) { return a - b; }
static int mul(int a, int b) { return a * b; }

typedef int (*fn2)(int, int);

static int calls;
static int which(void) { calls++; return 0; }

int main(void)
{
	int p = 1, q = 0;
	fn2 fa = add, fb = sub;

	/* bare function names, both ways */
	printf("%d %d\n", (p ? add : sub)(7, 3), (q ? add : sub)(7, 3));
	/* function-POINTER variables, both ways */
	printf("%d %d\n", (p ? fa : fb)(7, 3), (q ? fa : fb)(7, 3));
	/* nested in the else-arm, so the recursion has to go more than one level */
	printf("%d\n", (p ? add : (q ? sub : mul))(7, 3));
	printf("%d\n", (q ? add : (q ? sub : mul))(7, 3));
	/* the condition is evaluated EXACTLY once. Sequenced across two statements
	   because argument evaluation order within one call is unspecified in C,
	   and gcc and pxx pick differently — a single printf tests the wrong thing. */
	printf("%d\n", (which() ? add : sub)(7, 3));
	printf("%d\n", calls);
	return 0;
}
