/* __attribute__((weak)): a weak definition another object's strong one
   replaces, and a weak extern that is 0 when nothing defines it.
   bug-c-attribute-weak-was-ignored */
#include <stdio.h>
__attribute__((weak)) int wk(void) { return 2; }
extern int maybe(void) __attribute__((weak));
int __attribute__((weak)) wk2(void);
int wk2(void) { return 3; }
int main(void) { printf("%d %d %d %d\n", wk(), maybe ? maybe() : -1, wk2(), maybe == 0); return 0; }
