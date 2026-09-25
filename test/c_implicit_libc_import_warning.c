/* The implicit-libc-import warning names the PROGRAM's symbols only. A program
   that imports from libc also gets compiler-made imports (libc$fflush, which
   flushes libc's stdio at exit), and the warning used to list those too:
   "crtl does not define ffsll, libc$fflush". Output is glibc's. */
#include <stdio.h>
extern int ffsll(long long v);
int main(void) {
  printf("ffsll %d\n", ffsll(0x100));
  return 0;
}
