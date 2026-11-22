/* Function-like macros defined on the command line, against gcc. The row
 * passes '-DSQ(x)=((x)*(x))' '-DADD(a,b)=((a)+(b))' -DPLAIN=5 '-DSTR(s)=#s'
 * '-DNOARGS()=3'. pxx took the whole `SQ(x)` as an object-like macro's NAME,
 * so SQ(7) was an undeclared function (micropython's harness defines
 * pthread_cancel(t) this way).
 * bug-c-a-function-like-macro-on-the-command-line-is-not-defined */
#include <stdio.h>
int main(void) {
  printf("%d %d %d %s\n", SQ(7), ADD(1, 2) + NOARGS() - 3, PLAIN, STR(hi));
#ifdef SQ
  puts("SQ defined");
#endif
  return 0;
}
