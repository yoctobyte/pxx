/* A pointer to a pointer to an array of struct pointers, against gcc: through
 * `typedef struct R *Table[16]; Table **pp` (local, global, parameter) and the
 * explicit `struct R *(**pp)[16]`. pxx read `(**pp)[5]->b` at offset 0, crashed
 * on the global and parameter forms, typed `(*(*pt)[5])` as a pointer, and did
 * not parse `elem (**name)[N]`.
 * bug-c-a-pointer-to-a-pointer-to-an-array-typedef-of-pointers-loses-its-record */
#include <stdio.h>

typedef struct _Rec *RecPtr;
typedef struct _Rec { RecPtr next; long b; long a[8]; } Rec;
typedef RecPtr Table[16];

static Table gtab;
static Rec r2;
static Table *gpt = &gtab;
static Table **gppt = &gpt;

static long *lt[16];
static long v = 77;
static long *(*gq)[16] = &lt;
static long *(**gpq)[16] = &gq;
static struct _Rec *(*grq)[16] = &gtab;
static struct _Rec *(**gprq)[16] = &grq;

static long viaparam(Table **pp) { return (**pp)[5]->a[1]; }
static long viaparam1(Table *p) { return (*(*p)[5]).b; }
static long viaexplicit(long *(**pq)[16]) { return *(**pq)[5]; }
static long viaexplicitrec(struct _Rec *(**pq)[16]) { return (**pq)[5]->b; }

int main(void) {
  Table *pt = &gtab;
  Table **ppt = &pt;
  struct _Rec *(**prq)[16] = &grq;
  long *(**lpq)[16] = &gq;
  RecPtr x;

  r2.a[1] = 22; r2.b = 33; r2.next = &r2;
  gtab[5] = &r2;
  lt[5] = &v;

  x = (**ppt)[5];
  printf("temp %ld\n", x->a[1]);
  printf("depth1 %ld %ld %ld\n", (*pt)[5]->a[1], pt[0][5]->b, (*(*pt)[5]).b);
  printf("local %ld %ld %ld %ld\n", (**ppt)[5]->a[1], (*ppt)[0][5]->b,
         ppt[0][0][5]->b, (*(*ppt))[5]->a[1]);
  printf("deref %ld %ld\n", (*(**ppt)[5]).b, (*(**ppt)[5]).a[1]);
  printf("next %d\n", (**ppt)[5]->next == &r2);
  printf("global %ld %ld\n", (**gppt)[5]->a[1], (*(**gppt)[5]).b);
  printf("param %ld %ld %ld\n", viaparam(ppt), viaparam(gppt), viaparam1(pt));
  printf("explicit %ld %ld %ld %ld\n", *(**gpq)[5], *(**lpq)[5], (**lpq)[5][0],
         viaexplicit(&gq));
  printf("explicitrec %ld %ld %ld %ld\n", (**gprq)[5]->a[1], (**prq)[5]->b,
         (*(**prq)[5]).b, viaexplicitrec(gprq));
  printf("sizeof %d %d %d\n", (int)sizeof **ppt, (int)sizeof *ppt, (int)sizeof **gpq);
  return 0;
}
