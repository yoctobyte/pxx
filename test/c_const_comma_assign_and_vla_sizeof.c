/* A comma or an assignment inside a constant-expression arm, and sizeof of a
   variable-length array in every spelling. gcc is the reference (both widths).

   git's MOVE_ARRAY checks its operands at compile time without __GNUC__ >= 3:
     BUILD_ASSERT_OR_ZERO(0 ? ((*(dst) = *(src)), 0) : sizeof(*(dst)) == sizeof(*(src)))
   The folder stopped at the `=` or `,`, read the arm as 0 and failed the
   assertion; in an else arm it was `expected ']'`. A live comma (`a[(1, 3)]`)
   is a VLA bound with gcc and now with pxx.
   bug-c-a-comma-or-assignment-in-a-constant-expression-arm-is-not-read

   `sizeof a` of a VLA, without parentheses, answered the pointer size, and
   `sizeof(a[1])` the whole array.
   bug-c-sizeof-of-a-vla-without-parentheses-is-the-pointer-size */
#include <stdio.h>
#include <string.h>

#define BUILD_ASSERT_OR_ZERO(cond) (sizeof(char [1 - 2*!(cond)]) - 1)
#define BARF_UNLESS_COPYABLE(dst, src) \
	BUILD_ASSERT_OR_ZERO(0 ? ((*(dst) = *(src)), 0) : \
				 sizeof(*(dst)) == sizeof(*(src)))
#define MOVE_ARRAY(dst, src, n) move_array((dst), (src), (n), sizeof(*(dst)) + \
	BARF_UNLESS_COPYABLE((dst), (src)))

static void move_array(void *dst, const void *src, size_t n, size_t size)
{
	if (n)
		memmove(dst, src, n * size);
}

struct line { size_t len; unsigned hash : 24; unsigned flag : 8; };
struct image { int pad; struct line *line; size_t line_nr; };
struct s3 { int a, b, c; };

int x;
static char file_scope[0 ? (1, 2) : 3];
static char file_scope2[1 ? 4 : (5, 6)];

static void remove_first(struct image *img)
{
	img->line_nr--;
	if (img->line_nr)
		MOVE_ARRAY(img->line, img->line + 1, img->line_nr);
}

static int dims(void)
{
	char a1[1 - 2 * !(0 ? (x = 1) : 1)];
	char a2[1 - 2 * !(0 ? (1, 0) : 1)];
	char a3[1 ? 2 : (x = 1, 0)];
	char a4[1 ? 3 : (1, 0)];
	char a5[0 ? ((x += 3), 0) : 5];
	return (int)(sizeof a1 * 1000 + sizeof a2 * 100 + sizeof a3 * 10 + sizeof a4) + (int)sizeof a5 * 10000;
}

static int live_comma(void) { char a[(1, 3)]; return (int)sizeof a; }
static int live_assign(void) { char a[(x = 4)]; return (int)sizeof a; }

static int vla_sizes(int n, int *out)
{
	char c[n];
	int i5[n + 1];
	struct s3 st[n];
	char *pp[n];
	char z[1 - 2 * !n];
	out[0] = (int)sizeof c;
	out[1] = (int)sizeof(c);
	out[2] = (int)(sizeof i5 / sizeof i5[0]);
	out[3] = (int)(sizeof(i5) / sizeof(i5[0]));
	out[4] = (int)sizeof st;
	out[5] = (int)sizeof st[0];
	out[6] = (int)sizeof(st[1]);
	out[7] = (int)sizeof st[1].b;
	out[8] = (int)sizeof pp;
	out[9] = (int)sizeof *pp;
	out[10] = (int)sizeof(*pp);
	out[11] = (int)sizeof z;
	out[12] = (int)(sizeof c + 1);
	return 13;
}

int main(void)
{
	struct line l[4] = { {1, 10, 1}, {2, 20, 0}, {3, 30, 1}, {4, 40, 0} };
	struct image im = { 0, l, 4 };
	int out[16], k, i;

	remove_first(&im);
	printf("move: %zu", im.line_nr);
	for (i = 0; i < (int)im.line_nr; i++)
		printf(" %zu/%u/%u", l[i].len, (unsigned)l[i].hash, (unsigned)l[i].flag);
	printf("\nbarf: %zu %zu\n", (size_t)BARF_UNLESS_COPYABLE(l, l + 1),
	       (size_t)(sizeof(*(l)) + BARF_UNLESS_COPYABLE(l, l + 1)));
	printf("file scope: %zu %zu\n", sizeof file_scope, sizeof file_scope2);
	k = dims();
	printf("dims: %d x=%d\n", k, x);
	k = live_comma();
	i = live_assign();   /* sets x: read after, not as a sibling argument */
	printf("live: %d %d x=%d\n", k, i, x);
	for (int n = 1; n <= 5; n += 2) {
		k = vla_sizes(n, out);
		printf("vla %d:", n);
		for (i = 0; i < k; i++) printf(" %d", out[i]);
		printf("\n");
	}
	return 0;
}
