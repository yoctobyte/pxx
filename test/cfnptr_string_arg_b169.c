/* Regression: a string literal passed through a function pointer must decay to
   char* (skip the Pascal length prefix), same as a direct C call. Before the fix
   `p("...")` passed the length word and the callee saw an empty string. Uses a
   crtl call whose result is observable: strlen of the passed string. */
#include <string.h>

int main(void) {
  unsigned long (*sl)(const char*) = strlen;
  /* "hello" via the function pointer must yield 5, not 0 (empty/prefix). */
  if (sl("hello") != 5) return 1;
  int (*cmp)(const char*, const char*) = strcmp;
  if (cmp("abc", "abc") != 0) return 2;
  if (cmp("abc", "abd") == 0) return 3;
  return 42;
}
