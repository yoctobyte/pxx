/* _Generic on a struct-valued expression (`*(s)`, `h.a`) matches its `struct X:`
   association, as LinuxKPI seqlock.h needs.
   bug-c-generic-on-a-struct-expression-matches-no-association. Expected output is gcc's. */
#include <stdio.h>
struct sa { int x; }; struct sb { int y; };
struct holder { int pad; struct sa a; struct sb b; };
static int fa(int *p) { return 1; }
static int fb(int *p) { return 2; }
#define pick(s) _Generic(*(s), struct sa: 10, struct sb: 20)
#define call(s) _Generic(*(s), struct sa: fa, struct sb: fb)(&(s)->x)
int main(void) {
  struct sa a; struct sb b; struct holder h;
  printf("%d %d %d %d\n", pick(&a), pick(&b), pick(&h.a), pick(&h.b));
  printf("%d\n", call(&h.a));
  return 0;
}
