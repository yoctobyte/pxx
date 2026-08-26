/* The strict-ISO half of test/ccrtl_string_pulls_strings.c: with no
   _GNU_SOURCE / _DEFAULT_SOURCE / _BSD_SOURCE, <string.h> must NOT drag in
   <strings.h>. If it did, `index` as a local would collide with the function
   of that name — which is why glibc gates the include on __USE_MISC. */
#include <string.h>

int printf(const char *, ...);

int main(void) {
  int index = 7;          /* would be shadowed/conflicting if <strings.h> leaked */
  printf("%d %d\n", index, (int)strlen("abcd"));
  return 0;
}
