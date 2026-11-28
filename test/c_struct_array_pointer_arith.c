/* Pointer arithmetic on an ARRAY of structs: the array decays to a pointer,
   so `l + 1`, `(l + 1)->len`, `*(l + 2)`, `l + n - l` and `x.a + 1` are
   pointer operations gcc accepts. e17b4497b4 (struct operands to scalar
   operators refused) refused them all: an array's node carries its element
   kind, so it looked like a struct value. git's MOVE_ARRAY on a struct array
   hit it. Struct VALUES stay refused (c_structop26). gcc is the reference.
   bug-c-pointer-arithmetic-on-a-struct-array-is-refused-as-a-struct-operand */
#include <stdio.h>
#include <string.h>

struct line { unsigned long len; unsigned hash : 24; unsigned flag : 8; };
struct img { int pad; struct line rows[4]; };

static struct line g[3] = { { 10, 1, 0 }, { 20, 2, 1 }, { 30, 3, 0 } };

int main(void)
{
	struct line l[4] = { { 1, 11, 1 }, { 2, 22, 0 }, { 3, 33, 1 }, { 4, 44, 0 } };
	struct img im = { 7, { { 5, 1, 1 }, { 6, 2, 0 } } };
	struct line *p = l + 1, *e = l + 4;
	int n = 2;

	printf("%lu %lu %lu\n", p->len, (l + 2)->len, (*(l + 3)).len);
	printf("%d %d\n", (int)(e - l), (int)((l + n) - l));
	printf("%lu %lu\n", (g + 1)->len, (im.rows + 1)->len);
	printf("%zu %zu\n", sizeof(*(l + 1)), sizeof(*(im.rows + 1)));
	memmove(l, l + 1, 3 * sizeof *l);
	printf("%lu/%u %lu/%u %lu/%u\n", l[0].len, (unsigned)l[0].hash,
	       l[1].len, (unsigned)l[1].hash, l[2].len, (unsigned)l[2].hash);
	printf("%d %d\n", l + 1 > l, (g + 2) == &g[2]);
	return 0;
}
