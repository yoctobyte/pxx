/* The gcc side of test-packrecords-c-gcc-oracle. {$PACKRECORDS C} promises "lay
   this record out the way the platform C compiler does", so the only instrument
   that can check it is the platform C compiler. Field widths are deliberately
   mixed and deliberately NOT all-4: the two targets must print DIFFERENT rows
   (x86-64 pads `b` to 8, i386 SysV to 4), so a run that measured the wrong
   target shows up as a mismatch instead of passing quietly.
   feature-p-packrecords-c-directive */
#include <stdio.h>
#include <stddef.h>
struct S { char a; double b; short c; int d; char e; };
int main(void) {
  printf("%d %d %d %d %d %d\n",
         (int)offsetof(struct S, a), (int)offsetof(struct S, b),
         (int)offsetof(struct S, c), (int)offsetof(struct S, d),
         (int)offsetof(struct S, e), (int)sizeof(struct S));
  return 0;
}
