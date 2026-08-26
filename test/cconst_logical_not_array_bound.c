/* Unary `!` in a C constant expression, and what it is FOR.
 *
 * CEvalConstPrimary's unary chain had `-`, `+`, `~` and `&` and not `!`, so a
 * constant expression containing one was not folded at all. An array DIMENSION
 * is where that shows, because the bracket then met a token the dimension
 * reader could not use and reported `Expected: ], but got:` with no mention of
 * `!` anywhere.
 *
 * The idiom that produces it is BUILD_BUG_ON, spelled the same way by busybox
 * and the Linux kernel:
 *
 *     #define BUILD_BUG_ON(cond) ((void)sizeof(char[1 - 2*!!(cond)]))
 *
 * The bound is 1 when the condition is false and -1 when it holds, so the
 * assertion IS a refusal of a negative array bound. Which was the second half:
 * once `!` folded, pxx ACCEPTED the negative bound, so the macro compiled and
 * never fired — every compile-time assertion in the source silently becoming a
 * no-op that reports success. The negative case is asserted by
 * cconst_negative_array_bound_fails.c beside this file.
 *
 * bug-c-logical-not-is-not-folded-in-a-constant-expression
 * Oracle: gcc -O0, diffed. */
int printf(const char *, ...);

#define BUILD_BUG_ON(condition) ((void)sizeof(char[1 - 2*!!(condition)]))

enum { A = 1, B = 1, C = 2 };

struct S { int n; char pad[0]; };      /* GNU zero-length array, still legal */
static const char msg[] = "hi";        /* unsized, sized from the initializer */

int main(void)
{
	BUILD_BUG_ON(A != B);          /* holds, so this must compile away */
	BUILD_BUG_ON(sizeof(int) < 2);

	printf("%d %d\n", !5, !0);
	printf("%d %d\n", (int)sizeof(char[!!(0)]), (int)sizeof(char[!!(7)]));
	printf("%d %d\n", (int)sizeof(char[!0]), (int)sizeof(char[!!!0]));
	printf("%d\n", (int)sizeof(char[1 - 2*!!(0)]));
	printf("%d\n", (int)sizeof(char[1 + !(A != B)]));
	/* the folder's other arms must still reach through the new one */
	printf("%d %d\n", (int)sizeof(char[!(A == C)]), (int)sizeof(char[2 * !!(C)]));
	printf("%d %d\n", (int)sizeof(char[~(-3)]), (int)sizeof(char[-(-4)]));
	/* zero-length and unsized arrays are NOT negative bounds */
	printf("%d %d %d\n", (int)sizeof(msg), (int)sizeof(struct S), (int)sizeof(char[0]));
	return 0;
}
