/* `sizeof(*p)` where p is a POINTER TO AN ARRAY -- `int (*p)[4]`.
 *
 * It answered the ELEMENT size: 4 where gcc says 16. Same shape as every other
 * reader that takes a pointer-to-array's element for the thing itself, and the
 * metadata was already recorded -- SymPtrElemArrLen, which holds the FLATTENED
 * product for a multi-dim pointee, so one multiply covers row M too.
 *
 * Pascal's SizeOf(p^) is correct on the identical construct, which is what says
 * this is the C reader alone rather than the metadata.
 *
 * Rows S, D and E are the controls and each rules out a different overreach: a
 * pointer to a SCALAR must stay at the element size (4, not 4*something), the
 * POINTER itself must stay 8, and a plain array must stay 16 -- an extent
 * multiply applied one level too widely moves exactly these.
 *
 * Oracle: gcc. Non-vacuous: rows A, B, C and M read 4, 8, 1 and 4 on pinned.
 * bug-c-sizeof-of-a-dereferenced-pointer-to-array-answers-the-element-size */
#include <stdio.h>

int main(void) {
  int a[4];       int (*p)[4] = &a;
  double d[3];    double (*q)[3] = &d;
  char c[7];      char (*r)[7] = &c;
  int m[3][4];    int (*mm)[3][4] = &m;
  int scal = 0;   int *sp = &scal;

  printf("A %d\n", (int)sizeof(*p));
  printf("B %d\n", (int)sizeof(*q));
  printf("C %d\n", (int)sizeof(*r));
  printf("M %d\n", (int)sizeof(*mm));
  printf("S %d\n", (int)sizeof(*sp));
  printf("D %d\n", (int)sizeof(p));
  printf("E %d\n", (int)sizeof(a));
  return 0;
}
