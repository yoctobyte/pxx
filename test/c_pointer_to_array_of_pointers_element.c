/* An element of a pointer to an array of pointers, against gcc. Over
 * `short *(*q)[16]`, `*(*q)[5]` loaded 8 bytes (the element's own pointee type
 * was recorded nowhere, so `pointer` was used), and `&(*q)[5] - arr` was 0
 * (the difference divided by the whole array). The typedef spellings and the
 * depth-2 forms took the same paths.
 * bug-c-an-element-of-a-pointer-to-an-array-of-pointers-has-no-pointee-type */
#include <stdio.h>

typedef short *STab[16];
typedef char *CTab[4];
struct P { int x, y; };

static short sv[3] = {77, 99, 11};
static short *lt[16];
static STab st;
static char *names[4] = { "zero", "one", "two", "three" };
static int it[16];
static int m3[2][3][4];
static struct P pts[4];

static short *(*gq)[16] = &lt;
static STab *gst = &st;
static STab **gpst = &gst;

static int viaparam(short *(*q)[16]) { return *(*q)[5]; }
static int viatd(STab *p) { return (*p)[5][1]; }
static int viatd2(STab **pp) { return *(**pp)[5]; }

int main(void) {
  short *(*q)[16] = &lt;
  short *(**pq)[16] = &q;
  STab *p = &st;
  STab **pp = &p;
  CTab *pc = &names;
  int (*qi)[16] = &it;
  int (*qm)[2][3][4] = &m3;
  struct P (*qp)[4] = &pts;

  lt[5] = sv; st[5] = sv + 1;
  printf("load %d %d %d %d\n", *(*q)[5], (*q)[5][1], *(**pq)[5], *(*gq)[5]);
  printf("typedef %d %d %d %d\n", *(*p)[5], *(**pp)[5], (*gst)[5][1], *(**gpst)[5]);
  printf("param %d %d %d %d\n", viaparam(q), viatd(p), viatd2(pp), viatd2(gpst));
  printf("char %c %c %s\n", *(*pc)[2], (*pc)[3][1], (*pc)[1]);
  printf("diff %d %d %d %d\n", (int)(&(*q)[5] - lt), (int)(&(*q)[5] - &(*q)[0]),
         (int)(&(*qi)[5] - it), (int)(&(*p)[7] - st));
  printf("diff3 %d %d\n", (int)(&(*qm)[1][2][3] - &(*qm)[0][0][0]),
         (int)(&(*qp)[3] - pts));
  printf("eq %d %d\n", &(*q)[5] == lt + 5, &(**pq)[3] == lt + 3);
  return 0;
}
