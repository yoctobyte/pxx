/* gcc's __builtin_ spellings of library functions are the library call.
   bison's YYCOPY uses __builtin_memcpy whenever __GNUC__ is defined (pxx
   defines it), so every bison parser hit "undeclared function". .expected is
   gcc's output. */
#include <stdio.h>
#include <string.h>
int main(void) {
  char a[16], b[16] = "hello", c[16];
  __builtin_memcpy(a, b, 6);
  __builtin_memset(b, 'x', 3);
  __builtin_memmove(c, a, 6);
  __builtin_strcpy(c + 5, "!");
  printf("%s %s %s %d %d %d\n", a, b, c, (int)__builtin_strlen(c),
         __builtin_memcmp(a, "hello", 5), __builtin_strcmp(a, "hello"));
  return 0;
}
