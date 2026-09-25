/* An executable that USES an `extern` variable nothing defines is refused,
 * as ld refuses it ("undefined reference") and as the Pascal frontend refuses
 * `var x: T; external;` in an executable. It used to compile, give the name a
 * private zero slot, and print "[] 0". The Makefile row asserts the
 * refusal names BOTH variables. */
#include <stdio.h>
extern const char ghost_str[];
extern int ghost_int;
int main(void) {
  printf("[%s] %d\n", ghost_str, ghost_int);
  return 0;
}
