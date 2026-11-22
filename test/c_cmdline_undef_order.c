/* -D and -U apply in command-line order, as gcc applies them. pxx applied
 * every -U after every -D, so `-U__GNUC__ -D__GNUC__=8` left __GNUC__
 * undefined (micropython's py/nlrx64.c picks its naked nlr_push on
 * __GNUC__ >= 8). Built with: -U__GNUC__ -D__GNUC__=8 -DFOO=3 -UFOO -UBAR -DBAR=4
 * bug-c-command-line-undef-is-applied-after-every-define */
#include <stdio.h>

int main(void) {
#ifdef __GNUC__
  printf("__GNUC__ %d\n", __GNUC__);
#else
  printf("__GNUC__ undefined\n");
#endif
#ifdef FOO
  printf("FOO %d\n", FOO);
#else
  printf("FOO undefined\n");
#endif
#ifdef BAR
  printf("BAR %d\n", BAR);
#else
  printf("BAR undefined\n");
#endif
  return 0;
}
