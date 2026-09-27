/* A FUNCTION RETURNING A POINTER TO AN ARRAY POINTS AT THE WHOLE ARRAY.
 *
 * `vec4 *f(void)`, `mat4 *f(void)`, `int (*f(void))[4]` and `PA *f(void)` for a
 * struct-array typedef returned the right address, but nothing recorded what it
 * pointed at: `sizeof *f()` was the element, `f() + 1` stepped one element,
 * `(*f())[i]` and `f()[0][i][j]` read the wrong one, and `float *r = *f()`
 * loaded through the pointer instead of decaying. The declarator form
 * `int (*f(void))[4]` was read as a function returning a FUNCTION pointer.
 * bug-c-a-function-returning-a-pointer-to-an-array-has-no-pointee-shape
 *
 * Found on the way, and pinned here: `typedef struct P PA[3];` (and the
 * struct-body form `typedef struct {..} QA[3];`) dropped its dims, so PA was
 * ONE struct -- `sizeof(PA)` was 8 where gcc says 24. `typedef P PA[3];`
 * was already right.
 *
 * Each row reads the LAST element of what it walks. Diffed against gcc's own
 * output, native and (test-i386) against gcc -m32, so no value is transcribed.
 */
#include <stdio.h>

typedef float vec4[4];
typedef vec4 mat4[4];
struct P { int a, b; };
typedef struct P PA[3];
typedef struct { int a, b; } QA[3];
typedef struct P PB[2][3];

vec4 gv = {1, 2, 3, 4};
mat4 gm = {{1, 2, 3, 4}, {5, 6, 7, 8}, {9, 10, 11, 12}, {13, 14, 15, 16}};
PA gp = {{1, 2}, {3, 4}, {5, 6}};
QA gq = {{7, 8}, {9, 10}, {11, 12}};
PB gb = {{{1, 2}, {3, 4}, {5, 6}}, {{7, 8}, {9, 10}, {11, 12}}};
int ga[2][4] = {{1, 2, 3, 4}, {5, 6, 7, 8}};

static mat4 *fm_proto(void);   /* declared first, defined below */

static vec4 *fv(void) { return &gv; }
static mat4 *fm(void) { return &gm; }
static PA *fp(void) { return &gp; }
static QA *fq(void) { return &gq; }
static PB *fb(void) { return &gb; }
static int (*fi(void))[4] { return &ga[1]; }
static int (*fi0(void))[4] { return ga; }
static struct P (*fs(int k))[3] { return k ? &gb[1] : &gb[0]; }
static int (*f2(void))[2][4] { return &ga; }

#define P(x) printf("%s = %ld\n", #x, (long)(x))
#define F(x) printf("%s = %g\n", #x, (double)(x))
#define D(p) ((long)((char *)((p) + 1) - (char *)(p)))

int main(void) {
  /* the typedefs themselves */
  P(sizeof(PA)); P(sizeof(QA)); P(sizeof(PB)); P(sizeof gp); P(sizeof gb[1]);

  /* sizeof what the result points at */
  P(sizeof *fv()); P(sizeof(*fm())); P(sizeof *fp()); P(sizeof *fq()); P(sizeof *fb());
  P(sizeof *fi()); P(sizeof *fs(0)); P(sizeof *f2()); P(sizeof((*fm())[3]));
  P(sizeof(fm()[0][3])); P(sizeof((*fb())[1])); P(sizeof *fm_proto());

  /* ...and what it steps by */
  P(D(fv())); P(D(fm())); P(D(fp())); P(D(fq())); P(D(fb())); P(D(fi())); P(D(fs(1)));
  P(D(f2())); P(D(fm_proto()));

  /* values, the last element each time */
  F((*fv())[3]); F(fv()[0][3]); F((*fm())[3][3]); F(fm()[0][2][3]); F((*fm_proto())[3][3]);
  P((*fp())[2].b); P(fp()[0][2].b); P((*fq())[2].b); P((*fb())[1][2].b); P(fb()[0][1][2].a);
  P((*fi())[3]); P(fi()[0][3]); P(fi0()[1][3]); P((*fs(1))[2].b); P(fs(0)[0][2].a);
  P((*f2())[1][3]); P(f2()[0][1][3]);

  /* `*f()` decays to the first element */
  { float *r = *fv(); F(r[3]); }
  { vec4 *row = *fm(); F(row[3][2]); }
  { int *e = *fi(); P(e[3]); }
  { struct P *s = *fp(); P(s[2].b); }
  { int (*r2)[4] = *f2(); P(r2[1][3]); }
  return 0;
}

static mat4 *fm_proto(void) { return &gm; }
