/* `__aligned__(N)` (glibc's and busybox's spelling) parsed as alignment 0,
   which marked the struct body not simple: pxx kept the struct OPAQUE and every
   member access was refused (busybox tls_sp_c32's sp_point, wget's globals).
   Bare `aligned` did the same; gcc reads it as __BIGGEST_ALIGNMENT__ (16 on
   x86-64). Sizes and offsets below are gcc's. */
#include <stdio.h>
#include <stddef.h>

typedef struct sp_point {
	int x[8]
		__attribute__ ((__aligned__(8)))
	;
	int y[8];
	int infinity;
} sp_point;

struct plain_under { char c; int v __attribute__((__aligned__(16))); };
struct bare        { char c; int v __attribute__((aligned)); };
struct bare_under  { char c; int v __attribute__((__aligned__)); };
struct spaced      { char c; int v __attribute__ (( __aligned__ ( 8 ) )); };

static void use(int *a) { a[1] = 7; }

int main(void) {
	sp_point point[1];
	struct bare b;
	use(point->x);
	point->y[2] = 9;
	b.v = 5;
	printf("sp_point %d y@%d inf@%d x1=%d y2=%d\n", (int)sizeof(sp_point),
	       (int)offsetof(sp_point, y), (int)offsetof(sp_point, infinity), point[0].x[1], point[0].y[2]);
	printf("plain_under %d v@%d\n", (int)sizeof(struct plain_under), (int)offsetof(struct plain_under, v));
	printf("bare %d v@%d v=%d\n", (int)sizeof(struct bare), (int)offsetof(struct bare, v), b.v);
	printf("bare_under %d v@%d\n", (int)sizeof(struct bare_under), (int)offsetof(struct bare_under, v));
	printf("spaced %d v@%d\n", (int)sizeof(struct spaced), (int)offsetof(struct spaced, v));
	return 0;
}
