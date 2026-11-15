/* An array declared `extern` (as a header does) and then defined with an
   initialiser is baked into .data like any other initialised global
   (--c-static-data, the default for x86-64 --emit-obj --function-sections).
   It used to keep the .bss slot its declaration took and run its stores in the
   init thunk, which kept every literal it named alive in every object
   (crtl's tzname). An unsized extern that the definition grows must carry
   the grown size (sizeof, the object symbol's st_size). */
#include <stdio.h>
#include <time.h>
extern char *a[2];
char *a[2] = { (char *)"ax", (char *)"ay" };
extern const char *u[];
const char *u[] = { "u0", "u1", "u2" };
extern int n[];
int n[] = { 7, 8, 9, 10 };
int main(void) {
  printf("%s %s %s %s %d %d %s %zu %zu\n", a[0], a[1], u[0], u[2], n[0], n[3],
         tzname[0], sizeof u, sizeof n);
  return 0;
}
