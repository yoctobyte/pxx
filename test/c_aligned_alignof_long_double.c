/* aligned(__alignof__(long double)) lays a struct out as gcc does on each
   target: x86-64 16 (gcc: "16 16 7 9 8 8"), i386 4 (gcc -m32: "8 4 7 9 8 8"),
   where __alignof__(long double) is 4 though double and long long are 8.
   The argument used to read as 0 and took the target's biggest alignment,
   16, which was wrong on i386. bug-c-aligned-alignof-long-double-on-i386 */
#include <stdio.h>
struct dropped { int a; int b; } __attribute__((aligned(__alignof__(long double))));
struct al8 { char c; } __attribute__((aligned(__alignof__(long long))));
int main(void)
{
  struct dropped v;
  v.a = 7; v.b = 9;
  printf("%d %d %d %d %d %d\n", (int)sizeof v, (int)_Alignof(struct dropped), v.a, v.b,
         (int)_Alignof(struct al8), (int)sizeof(struct al8));
  return 0;
}
