/* An array typedef whose element is a pointer is an array of pointers.
   `typedef P T[16]` (P a pointer typedef) and `typedef struct R *T[16]` were
   one pointer: the dims were skipped for a pointer element, and a declaration
   with no star was then read as a pointer to the array. libXt's
   `typedef CachePtr CacheHashTable[256]` strode the 72-byte record and read
   off the table, so every Xt program crashed in XtDirectConvert.
   bug-c-an-array-typedef-of-pointers-is-read-as-a-pointer-to-the-array */
#include <stdio.h>
typedef struct _Rec *RecPtr;
typedef struct _Rec { RecPtr next; long a[8]; } Rec;
typedef RecPtr Table[16];
typedef struct _Rec *Table2[4];
typedef int *IP;
typedef IP IPA[3];
static Table gtab;
static Table2 gt2;
static IPA gipa;
struct H { int n; Table t; };
static long sum(Table t) { return t[2]->a[0] + t[3]->a[0]; }
int main(void)
{
  static Rec r1, r2;
  static struct H h;
  Table ltab;
  IPA lipa;
  RecPtr p;
  int x = 7, y = 8, h5 = 5;
  r1.a[0] = 11; r2.a[0] = 22; r1.next = &r2;
  gtab[h5 & 15] = &r1; gtab[2] = &r1; gtab[3] = &r2;
  ltab[2] = &r2;
  gt2[1] = &r2;
  h.t[5] = &r2;
  gipa[1] = &x; lipa[2] = &y;
  for (p = gtab[h5 & 15]; p; p = p->next) printf("%ld ", p->a[0]);
  printf("\n%ld %ld %ld %ld\n", gtab[2]->a[0], ltab[2]->a[0], gt2[1]->a[0], h.t[5]->a[0]);
  printf("%d %d %d %d\n", *gipa[1], *lipa[2], (int)sizeof(ltab), (int)sizeof(lipa));
  printf("%d %d %d %d %ld\n", (int)sizeof(Table), (int)sizeof(Table2), (int)sizeof(IPA),
         (int)sizeof(h), sum(gtab));
  printf("%d\n", (int)((char *)&gtab[1] - (char *)&gtab[0]));
  return 0;
}
