/* A pointer to an array typedef whose elements are pointers, against gcc.
 * `typedef RecPtr Table[16]` (RecPtr a pointer typedef) or `typedef long *TQ[16]`
 * is an array of 16 pointers, and `Table *pt` is a pointer to that whole array,
 * exactly as `RecPtr (*pt)[16]` is. pxx read the depth 2 (one level from the
 * elements, one from the star) as `RecPtr *` over an array, so `(*pt)[3]`
 * crashed, `pt + 1` stepped the wrong distance and `(*pt)[i] = v` did not
 * compile. Found building libXt (Path B JWM desktop).
 * bug-c-a-pointer-to-an-array-typedef-of-pointers-has-no-shape */
#include <stdio.h>

typedef struct _Rec *RecPtr;
typedef struct _Rec { RecPtr next; long a[8]; } Rec;
typedef RecPtr Table[16];
typedef long *TQ[16];
typedef long *TM[3][4];

static Table gtab, gtab2[2];
static TQ gq;
static TM gm;
static Table *gpt = &gtab;
static TQ *gqp = &gq;

static long viaparam(Table *t, TQ *q) { return (*t)[5]->a[1] + *(*q)[2]; }
static int stride(Table *t) { return (int)((char *)(t + 1) - (char *)t); }

int main(void) {
  static Rec r1, r2;
  static long v = 42, w = 7;
  Table *pt = &gtab, *pt2 = gtab2;
  TQ *qp = &gq, *qp2 = &gq;
  TM *mp = &gm;
  Table **ppt = &pt;
  TQ **pq = &qp;
  int i;
  r1.a[0] = 11; r2.a[1] = 22;
  gtab[3] = &r1; gtab[5] = &r2; gq[2] = &v; gq[9] = &w; gm[2][3] = &w;
  gtab2[1][4] = &r2;

  printf("local     %ld %d %d\n", (*pt)[3]->a[0], (int)sizeof *pt, stride(pt));
  printf("global    %ld %d %ld\n", (*gpt)[3]->a[0], (int)sizeof *gpt, *(*gqp)[9]);
  printf("param     %ld\n", viaparam(&gtab, &gq));
  printf("direct    %ld %d %d\n", *(*qp)[2], (int)sizeof *qp, (int)((char *)(qp + 1) - (char *)qp));
  printf("sibling   %ld %ld\n", (*qp2)[9][0], pt2[1][4]->a[1]);
  printf("2-d       %ld %d %d\n", *(*mp)[2][3], (int)sizeof *mp, (int)sizeof (*mp)[1]);
  {
    /* `->` straight on (**ppt)[i] is not covered: pxx loses the record there
       (bug-c-a-pointer-to-a-pointer-to-an-array-typedef-of-pointers-loses-its-record) */
    RecPtr x = (**ppt)[5];
    printf("ptr-ptr   %ld %d %ld\n", x->a[1], (int)sizeof **ppt, *(**pq)[2]);
  }
  (*pt)[7] = &r2;
  (*qp)[1] = &w;
  printf("store     %ld %ld\n", gtab[7]->a[1], *gq[1]);
  {
    RecPtr *e = *pt;
    long sum = 0;
    for (i = 0; i < 16; i++) if ((*pt)[i]) sum += (*pt)[i]->a[0] + (*pt)[i]->a[1];
    printf("decay     %ld %ld\n", e[3]->a[0], sum);
  }
  return 0;
}
