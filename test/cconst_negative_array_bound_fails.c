/* A BUILD_BUG_ON whose condition HOLDS must be refused.
 *
 * This file must NOT compile. It is the half that matters: once unary `!` was
 * folded, pxx accepted the negative bound the macro produces, so every
 * compile-time assertion in a source file compiled and reported success while
 * asserting nothing. gcc: `size of unnamed array is negative`.
 *
 * The positive half — everything that must keep compiling, including the
 * zero-length and unsized arrays a naive check also refuses — is
 * cconst_logical_not_array_bound.c beside this file.
 *
 * bug-c-logical-not-is-not-folded-in-a-constant-expression */
#define BUILD_BUG_ON(condition) ((void)sizeof(char[1 - 2*!!(condition)]))

enum { A = 1, C = 2 };

int main(void)
{
	BUILD_BUG_ON(A != C);   /* the condition holds: bound is -1 */
	return 0;
}
